// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'spellcheck_linter_plugin.dart';

/// Called after a [SpellcheckSuggestionsPlugin] has replaced the flagged word
/// of [issue] with [replacement] in a text field.
typedef SpellcheckReplaceCallback = void Function(
  SpellcheckIssue issue,
  String replacement,
);

/// A [SpellcheckLinterPlugin] that also shows a menu with the suggested
/// replacement when a flagged word is activated.
///
/// The squiggles are still painted by the base class, which is unchanged.
/// This class only adds widgets, in two layers:
///
///  * In [TextWidgetLayer.foreground], an invisible target on every flagged
///    word. It opens the menu when it is tapped, and makes the word reachable
///    with the keyboard and with a screen reader. The target does not take
///    pointer events away from the text, so a tap still places the caret in a
///    text field and a drag still selects text.
///  * In [TextWidgetLayer.overlay], the menu of the word that was activated.
///    It floats next to the word, so it can be larger than the text widget
///    and it is painted above whatever comes after the text.
///
/// In a text field the menu offers to replace the word, and the plugin makes
/// the replacement through the field. In other text the menu only shows the
/// suggestion. A plugin cannot change the text of a [Text] widget. Only the
/// code that built the widget can.
///
/// The plugin is a [Listenable], and it notifies its listeners when the menu
/// opens or closes. Every text widget in the scope of the plugin then builds
/// its widgets again, which is how the text widget of the open menu comes to
/// have something in its overlay layer.
class SpellcheckSuggestionsPlugin extends SpellcheckLinterPlugin
    with TextWidgetPlugin, ChangeNotifier {
  /// Creates a [SpellcheckSuggestionsPlugin].
  SpellcheckSuggestionsPlugin({super.onIssueTapped, this.onReplace});

  /// Called after the plugin has replaced a flagged word in a text field.
  final SpellcheckReplaceCallback? onReplace;

  static final RegExp _wordTokenizer = RegExp(r'\b[A-Za-z]+\b');

  static const double _menuWidth = 260;

  // Only used to decide on which side of the word the menu goes.
  static const double _menuHeightEstimate = 120;

  // The issues of a delegate, together with the text they were found in.
  final Expando<(String, List<SpellcheckIssue>)> _issues =
      Expando<(String, List<SpellcheckIssue>)>();

  /// The issue whose menu is showing, if any.
  SpellcheckIssue? get openIssue => _openIssue;
  SpellcheckIssue? _openIssue;

  /// Shows the menu for [issue], replacing any other menu.
  void open(SpellcheckIssue issue) {
    if (_isOpen(issue)) {
      return;
    }
    _openIssue = issue;
    notifyListeners();
  }

  /// Hides the menu.
  void close() {
    if (_openIssue == null) {
      return;
    }
    _openIssue = null;
    notifyListeners();
  }

  /// Shows the menu for [issue], or hides it if it is showing.
  void toggle(SpellcheckIssue issue) {
    if (_isOpen(issue)) {
      close();
    } else {
      open(issue);
    }
  }

  bool _isOpen(SpellcheckIssue issue) {
    final SpellcheckIssue? open = _openIssue;
    return open != null &&
        identical(open.delegate, issue.delegate) &&
        open.range == issue.range &&
        open.matchedText == issue.matchedText;
  }

  /// The replacement for [issue], with the capitalization of the flagged word.
  String replacementFor(SpellcheckIssue issue) {
    final String suggestion = issue.rule.suggestion;
    final String first = issue.matchedText.substring(0, 1);
    final bool isCapitalized =
        first == first.toUpperCase() && first != first.toLowerCase();
    return isCapitalized
        ? suggestion[0].toUpperCase() + suggestion.substring(1)
        : suggestion;
  }

  // Finds the issues in the text of the delegate.
  //
  // The base class collects its issues in didAddText and didUpdateText. Those
  // callbacks run after layout, and the widgets of a frame are built during
  // layout. In the frame in which the text changes, the issues that the base
  // class has are therefore still those of the old text. So the widgets are
  // derived from the text itself.
  List<SpellcheckIssue> _issuesIn(TextDelegate delegate) {
    final String text = delegate.text;
    final (String, List<SpellcheckIssue>)? cached = _issues[delegate];
    if (cached != null && cached.$1 == text) {
      return cached.$2;
    }
    final issues = <SpellcheckIssue>[
      for (final RegExpMatch match in _wordTokenizer.allMatches(text))
        if (SpellcheckLinterPlugin.defaultRules[match.group(0)!.toLowerCase()]
            case final SpellcheckRule rule)
          SpellcheckIssue(
            delegate: delegate,
            range: TextRange(start: match.start, end: match.end),
            matchedText: match.group(0)!,
            rule: rule,
          ),
    ];
    _issues[delegate] = (text, issues);
    return issues;
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    super.didUpdateText(delegate);
    if (identical(_openIssue?.delegate, delegate) &&
        !_issuesIn(delegate).any(_isOpen)) {
      // The word was fixed, removed or moved. Its menu was not built in this
      // frame (see buildTextWidgets). This tells the listeners.
      close();
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    super.didRemoveText(delegate);
    if (identical(_openIssue?.delegate, delegate)) {
      // The text widget is gone, and its menu with it. The listeners are not
      // told, because this can be called while the widget tree is being
      // built.
      _openIssue = null;
    }
  }

  @override
  Set<TextWidgetLayer> get widgetLayers => const <TextWidgetLayer>{
    TextWidgetLayer.foreground,
    TextWidgetLayer.overlay,
  };

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    final List<SpellcheckIssue> issues = _issuesIn(delegate);
    final bool isEditable = delegate.renderObject is RenderEditable;
    switch (layer) {
      case TextWidgetLayer.background:
        return const <Widget>[];
      case TextWidgetLayer.foreground:
        return <Widget>[
          for (final (int index, SpellcheckIssue issue) in issues.indexed)
            TextPositioned.fill(
              key: ValueKey<int>(index),
              delegate: delegate,
              range: issue.range,
              child: _IssueTarget(
                plugin: this,
                issue: issue,
                isEditable: isEditable,
              ),
            ),
        ];
      case TextWidgetLayer.overlay:
        final SpellcheckIssue? open = _openIssue;
        if (open == null ||
            !identical(open.delegate, delegate) ||
            !issues.any(_isOpen)) {
          return const <Widget>[];
        }
        final (
          Alignment targetAnchor,
          Alignment followerAnchor,
          Offset offset,
        ) = _menuPlacement(
          context,
          delegate,
          open.range,
        );
        return <Widget>[
          TextPositioned(
            // A new menu for every word, so that each one starts out fresh.
            key: ValueKey<TextRange>(open.range),
            delegate: delegate,
            range: open.range,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: _SuggestionMenu(
              plugin: this,
              issue: open,
              isEditable: isEditable,
            ),
          ),
        ];
    }
  }

  // Decides where the menu goes: below the word and lined up with its left
  // edge, or on the other side when there is no room there.
  //
  // The overlay layer places a widget relative to the text and keeps it there
  // when the text moves, but it does not know where the text is on the
  // screen. So the side is chosen here, from where the text is at this
  // moment. That is where the text was painted last, which is right when the
  // menu opens while nothing else changes.
  static (Alignment, Alignment, Offset) _menuPlacement(
    BuildContext context,
    TextDelegate delegate,
    TextRange range,
  ) {
    var above = false;
    var alignRight = false;
    final RenderObject? overlay = Overlay.maybeOf(context)?.context
        .findRenderObject();
    final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    if (overlay is RenderBox && overlay.hasSize && boxes.isNotEmpty) {
      Rect word = boxes.first.toRect();
      for (final ui.TextBox box in boxes.skip(1)) {
        word = word.expandToInclude(box.toRect());
      }
      word = MatrixUtils.transformRect(delegate.getTransformTo(overlay), word);
      final Size available = overlay.size;
      above =
          word.bottom + _menuHeightEstimate > available.height &&
          word.top >= _menuHeightEstimate;
      alignRight =
          word.left + _menuWidth > available.width && word.right >= _menuWidth;
    }
    return (
      switch ((above, alignRight)) {
        (false, false) => Alignment.bottomLeft,
        (false, true) => Alignment.bottomRight,
        (true, false) => Alignment.topLeft,
        (true, true) => Alignment.topRight,
      },
      switch ((above, alignRight)) {
        (false, false) => Alignment.topLeft,
        (false, true) => Alignment.topRight,
        (true, false) => Alignment.bottomLeft,
        (true, true) => Alignment.bottomRight,
      },
      Offset(0, above ? -4 : 4),
    );
  }

  // Replaces the flagged word of a text field.
  //
  // The menu is a widget below the text field in the widget tree, so it can
  // find the field and change the text through it, like the built-in spell
  // check menu does. There is no such way into a Text widget, which is why
  // the menu has no action there.
  void _replace(BuildContext context, SpellcheckIssue issue) {
    final String replacement = replacementFor(issue);
    final EditableTextState? editable = context
        .findAncestorStateOfType<EditableTextState>();
    var isReplaced = false;
    if (editable != null) {
      final TextEditingValue value = editable.textEditingValue;
      final TextRange range = issue.range;
      // The text may have changed since the menu was built.
      if (range.end <= value.text.length &&
          range.textInside(value.text) == issue.matchedText) {
        editable.userUpdateTextEditingValue(
          value.replaced(range, replacement),
          SelectionChangedCause.toolbar,
        );
        isReplaced = true;
      }
    }
    close();
    if (isReplaced) {
      onReplace?.call(issue, replacement);
    }
  }
}

/// An invisible target over a flagged word.
///
/// Every render object in here lets pointer events through to the text. A
/// [Listener] sees the events without taking part in the gesture arena, so it
/// does not compete with the gestures of a text field or of a selection area.
/// The price is that it has to tell a tap from a drag or a long press itself.
class _IssueTarget extends StatefulWidget {
  const _IssueTarget({
    required this.plugin,
    required this.issue,
    required this.isEditable,
  });

  final SpellcheckSuggestionsPlugin plugin;
  final SpellcheckIssue issue;

  /// Whether the word is in a text field, which keeps the keyboard focus and
  /// shows its own mouse cursor.
  final bool isEditable;

  @override
  State<_IssueTarget> createState() => _IssueTargetState();
}

class _IssueTargetState extends State<_IssueTarget> {
  int? _pointer;
  Offset _downPosition = Offset.zero;
  Duration _downTime = Duration.zero;
  bool _isFocused = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kPrimaryButton) {
      _pointer = event.pointer;
      _downPosition = event.position;
      _downTime = event.timeStamp;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    final bool isTap =
        (event.position - _downPosition).distance <=
            computeHitSlop(event.kind, null) &&
        event.timeStamp - _downTime < kLongPressTimeout;
    if (isTap) {
      widget.plugin.toggle(widget.issue);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      widget.plugin.toggle(widget.issue);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        widget.plugin._isOpen(widget.issue)) {
      widget.plugin.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final SpellcheckIssue issue = widget.issue;
    final bool isEditable = widget.isEditable;
    final String kind = issue.rule.severity == LintSeverity.spellingError
        ? 'Misspelled'
        : 'Style suggestion';
    Widget result = Semantics(
      button: true,
      label: '$kind: ${issue.matchedText}',
      onTap: () => widget.plugin.toggle(issue),
      // A decorated box is hit by a pointer, which would stop the event from
      // reaching the text.
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            border: _isFocused
                ? Border.all(color: const Color(0xFF1A73E8), width: 2)
                : null,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    result = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (PointerCancelEvent event) => _pointer = null,
      child: result,
    );
    if (!isEditable) {
      // Shows that the word can be clicked. A text field has its own cursor.
      result = MouseRegion(
        cursor: SystemMouseCursors.click,
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        child: result,
      );
    }
    return Focus(
      canRequestFocus: !isEditable,
      skipTraversal: isEditable,
      onFocusChange: (bool value) => setState(() => _isFocused = value),
      onKeyEvent: _handleKeyEvent,
      // A tap on the word is not a tap outside its menu.
      child: TapRegion(
        groupId: widget.plugin,
        behavior: HitTestBehavior.translucent,
        child: result,
      ),
    );
  }
}

/// The menu of a flagged word.
///
/// [TextWidgetLayer.overlay] puts the menu next to the word and keeps it
/// there. Everything else that makes it a menu is done here: closing on a tap
/// outside, on Escape and on scrolling.
///
/// The menu does not take the keyboard focus when it opens. A text field
/// keeps the focus, so that typing can continue. In other text the menu has
/// nothing to focus. The word keeps the focus, if it has it, and handles the
/// keys.
class _SuggestionMenu extends StatefulWidget {
  const _SuggestionMenu({
    required this.plugin,
    required this.issue,
    required this.isEditable,
  });

  final SpellcheckSuggestionsPlugin plugin;
  final SpellcheckIssue issue;

  /// Whether the word is in a text field.
  ///
  /// Only there does the menu offer to replace the word. In other text it
  /// shows the suggestion.
  final bool isEditable;

  @override
  State<_SuggestionMenu> createState() => _SuggestionMenuState();
}

class _SuggestionMenuState extends State<_SuggestionMenu> {
  List<ScrollPosition> _scrollPositions = const <ScrollPosition>[];

  // Whether the action of the menu has had the keyboard focus.
  bool _hadFocus = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Close when something scrolls, like a context menu does. The overlay
    // layer follows the text, but it is not clipped by the viewports that the
    // text is in, so the menu would stay visible after its word scrolled out
    // of sight.
    final positions = <ScrollPosition>[];
    ScrollableState? scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      positions.add(scrollable.position);
      scrollable = scrollable.context
          .findAncestorStateOfType<ScrollableState>();
    }
    for (final ScrollPosition position in _scrollPositions) {
      position.removeListener(_close);
    }
    for (final position in positions) {
      position.addListener(_close);
    }
    _scrollPositions = positions;
  }

  @override
  void dispose() {
    for (final ScrollPosition position in _scrollPositions) {
      position.removeListener(_close);
    }
    super.dispose();
  }

  // Closes this menu. By the time this is called, the plugin may already be
  // showing the menu of another word, which must stay open.
  void _close() {
    if (widget.plugin._isOpen(widget.issue)) {
      widget.plugin.close();
    }
  }

  void _replace() {
    widget.plugin._replace(context, widget.issue);
  }

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus) {
      _hadFocus = true;
    } else if (_hadFocus) {
      // The focus moved on, for example with the Tab key.
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SpellcheckSuggestionsPlugin plugin = widget.plugin;
    final SpellcheckIssue issue = widget.issue;
    final String replacement = plugin.replacementFor(issue);
    Widget result = TapRegion(
      groupId: plugin,
      onTapOutside: (PointerDownEvent event) => _close(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border: Border.fromBorderSide(BorderSide(color: Color(0x33000000))),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: SpellcheckSuggestionsPlugin._menuWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            // The menu is below the text widget in the widget tree, so it
            // inherits the text style of the place where the text is. Keep
            // the font, and set everything that should look the same in every
            // place.
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
                color: Color(0xFF1F1F1F),
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.normal,
                letterSpacing: 0,
                decoration: TextDecoration.none,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(issue.rule.message),
                  const SizedBox(height: 6),
                  if (widget.isEditable)
                    _MenuAction(
                      label: 'Replace with \u201C$replacement\u201D',
                      onPressed: _replace,
                    )
                  else
                    Text(
                      'Suggestion: \u201C$replacement\u201D',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.isEditable) {
      // A tap on the menu is not a tap outside the text field, so the field
      // keeps the focus.
      result = TextFieldTapRegion(child: result);
    }
    // These two only do something while the action of the menu has the
    // keyboard focus.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: _handleFocusChange,
        child: result,
      ),
    );
  }
}

class _MenuAction extends StatefulWidget {
  const _MenuAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_MenuAction> createState() => _MenuActionState();
}

class _MenuActionState extends State<_MenuAction> {
  // The plugin does not rely on an app to provide these.
  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  bool _showFocus = false;
  bool _showHover = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      shortcuts: _shortcuts,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) => widget.onPressed(),
        ),
      },
      onShowFocusHighlight: (bool value) {
        setState(() => _showFocus = value);
      },
      onShowHoverHighlight: (bool value) {
        setState(() => _showHover = value);
      },
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _showFocus || _showHover ? const Color(0x1F1A73E8) : null,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              border: Border.all(
                color: _showFocus
                    ? const Color(0xFF1A73E8)
                    : const Color(0x00000000),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Color(0xFF1A73E8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
