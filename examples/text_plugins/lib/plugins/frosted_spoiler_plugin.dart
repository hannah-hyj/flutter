// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Category of hidden text span (spoiler tag or flashcard cloze).
enum SpoilerMaskKind {
  /// A forum/chat spoiler span (e.g. `||Darth Vader||`).
  spoiler('Spoiler'),

  /// A flashcard cloze-deletion study answer (e.g. `{{RenderParagraph}}`).
  cloze('Cloze Study');

  const SpoilerMaskKind(this.label);

  /// Human-readable label for the mask category.
  final String label;
}

/// Represents a detected spoiler or cloze-study text span within a [TextDelegate].
@immutable
class SpoilerMaskMatch {
  /// Creates a [SpoilerMaskMatch].
  const SpoilerMaskMatch({
    required this.delegate,
    required this.range,
    required this.kind,
    required this.rawValue,
  });

  /// The [TextDelegate] containing this masked span.
  final TextDelegate delegate;

  /// The character range of the masked span within [TextDelegate.text].
  final TextRange range;

  /// The category of masked span.
  final SpoilerMaskKind kind;

  /// The underlying masked text value.
  final String rawValue;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SpoilerMaskMatch &&
        other.delegate == delegate &&
        other.range == range &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(delegate, range, kind);
}

/// Callback signature invoked when a hidden span is shown or hidden.
typedef SpoilerMaskTapCallback = void Function(
  SpoilerMaskMatch match, {
  required bool isRevealed,
});

/// A [TextPlugin] that hides spoilers (`||...||`) and cloze answers
/// (`{{...}}`) behind frosted glass.
///
/// A painter-only plugin could cover the same spans with an opaque bar,
/// which a [CustomPainter] can draw, but it could not be tapped to show the
/// span. Frosted glass blurs what is already painted
/// behind it. That takes a compositing layer, and a painter cannot create
/// one. So this plugin has no painter: it puts a [BackdropFilter] on every
/// line of every span, in [TextWidgetLayer.foreground].
///
/// The plugin does not use [didAddText], [didUpdateText] or [didLayoutText]
/// either. The covers are derived from the [TextDelegate] each time they are
/// built.
///
///  * In text that cannot be edited, a cover is a button. Activating it shows
///    or hides the span, and the text below it does not receive the tap.
///  * In editable text, a cover lets pointer events through, so that the
///    caret can be placed inside the span. The span is shown while the
///    selection touches it.
///
/// The plugin is not a [Listenable]. If it were, every text widget in its
/// scope would rebuild its covers whenever one span is shown or hidden.
/// Instead, each cover listens for the change on its own.
class FrostedSpoilerPlugin extends TextPlugin with TextWidgetPlugin {
  /// Creates a [FrostedSpoilerPlugin].
  FrostedSpoilerPlugin({this.onMatchTapped});

  /// Called when the user shows or hides a span.
  final SpoilerMaskTapCallback? onMatchTapped;

  static final List<(SpoilerMaskKind, RegExp)> _patterns =
      <(SpoilerMaskKind, RegExp)>[
        (SpoilerMaskKind.spoiler, RegExp(r'\|\|[^|\n]+\|\|')),
        (SpoilerMaskKind.cloze, RegExp(r'\{\{[^}\n]+\}\}')),
      ];

  // The spans of a delegate, together with the text they were found in.
  final Expando<(String, List<SpoilerMaskMatch>)> _matches =
      Expando<(String, List<SpoilerMaskMatch>)>();

  final Set<SpoilerMaskMatch> _revealed = <SpoilerMaskMatch>{};

  // Changes whenever [_revealed] changes.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Whether [match] is currently shown.
  bool isRevealed(SpoilerMaskMatch match) => _revealed.contains(match);

  /// Shows [match] if it is hidden, and hides it if it is shown.
  void toggle(SpoilerMaskMatch match) {
    final bool nowRevealed = !_revealed.remove(match);
    if (nowRevealed) {
      _revealed.add(match);
    }
    _revision.value += 1;
    onMatchTapped?.call(match, isRevealed: nowRevealed);
  }

  /// Releases the resources of this plugin.
  void dispose() {
    _revision.dispose();
  }

  List<SpoilerMaskMatch> _matchesIn(TextDelegate delegate) {
    final String text = delegate.text;
    final (String, List<SpoilerMaskMatch>)? cached = _matches[delegate];
    if (cached != null && cached.$1 == text) {
      return cached.$2;
    }
    final found = <SpoilerMaskMatch>[
      for (final (SpoilerMaskKind kind, RegExp pattern) in _patterns)
        for (final RegExpMatch match in pattern.allMatches(text))
          SpoilerMaskMatch(
            delegate: delegate,
            range: TextRange(start: match.start, end: match.end),
            kind: kind,
            rawValue: match.group(0)!,
          ),
    ];
    _matches[delegate] = (text, found);
    return found;
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    _revealed.removeWhere(
      (SpoilerMaskMatch match) => identical(match.delegate, delegate),
    );
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    final bool isEditable = delegate.renderObject is RenderEditable;
    final List<TextSelection> selections = delegate.selections;
    final covers = <Widget>[];
    for (final (int matchIndex, SpoilerMaskMatch match) in _matchesIn(
      delegate,
    ).indexed) {
      final TextRange range = match.range;
      final List<ui.TextBox> boxes = delegate.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      for (final (int boxIndex, ui.TextBox box) in boxes.indexed) {
        final Widget cover;
        if (isEditable) {
          cover = _FrostedCover(
            label: match.kind.label,
            isRevealed: selections.any(
              (TextSelection selection) =>
                  selection.start <= range.end && selection.end >= range.start,
            ),
          );
        } else {
          cover = ListenableBuilder(
            listenable: _revision,
            builder: (BuildContext context, Widget? child) {
              return _FrostedCover(
                label: match.kind.label,
                isRevealed: isRevealed(match),
                onPressed: () => toggle(match),
                // One button for the span, not one for each of its lines.
                isButton: boxIndex == 0,
              );
            },
          );
        }
        covers.add(
          TextPositioned.fromRect(
            key: ValueKey<(int, int)>((matchIndex, boxIndex)),
            rect: box.toRect().inflate(1.5),
            child: cover,
          ),
        );
      }
    }
    return covers;
  }
}

/// Frosted glass over one line of a hidden span.
class _FrostedCover extends StatefulWidget {
  const _FrostedCover({
    required this.label,
    required this.isRevealed,
    this.onPressed,
    this.isButton = false,
  });

  final String label;
  final bool isRevealed;

  /// Null in editable text, where the cover does not react to pointers.
  final VoidCallback? onPressed;

  /// Whether this cover is the one that can be focused and that assistive
  /// technology sees.
  final bool isButton;

  @override
  State<_FrostedCover> createState() => _FrostedCoverState();
}

class _FrostedCoverState extends State<_FrostedCover> {
  static const double _sigma = 5;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(4));

  // The plugin does not rely on an app to provide these.
  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  bool _showFocus = false;

  @override
  Widget build(BuildContext context) {
    final Widget glass = TweenAnimationBuilder<double>(
      // Starts at its end value, and animates when the end value changes.
      tween: Tween<double>(end: widget.isRevealed ? 0 : 1),
      duration: const Duration(milliseconds: 250),
      builder: (BuildContext context, double amount, Widget? child) {
        // A light tint stays when the span is shown, to mark it as something
        // that can be hidden again.
        final Widget tint = DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF607D8B)
                .withValues(alpha: 0.08 + 0.2 * amount),
            borderRadius: _radius,
            border: _showFocus
                ? Border.all(color: const Color(0xFF1A73E8), width: 2)
                : null,
          ),
          child: const SizedBox.expand(),
        );
        if (amount == 0) {
          // Shown. A backdrop filter needs compositing layers even while it
          // is disabled, so it is left out.
          return tint;
        }
        // A backdrop filter covers everything inside the nearest clip.
        return ClipRRect(
          borderRadius: _radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: _sigma * amount,
              sigmaY: _sigma * amount,
            ),
            child: tint,
          ),
        );
      },
    );

    final VoidCallback? onPressed = widget.onPressed;
    if (onPressed == null) {
      return IgnorePointer(child: ExcludeSemantics(child: glass));
    }
    final Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: !widget.isButton,
      onTap: onPressed,
      child: glass,
    );
    if (!widget.isButton) {
      return MouseRegion(cursor: SystemMouseCursors.click, child: tappable);
    }
    return Semantics(
      button: true,
      label: widget.label,
      value: widget.isRevealed ? 'Shown' : 'Hidden',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: _shortcuts,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent intent) => onPressed(),
          ),
        },
        onShowFocusHighlight: (bool value) {
          setState(() => _showFocus = value);
        },
        child: tappable,
      ),
    );
  }
}
