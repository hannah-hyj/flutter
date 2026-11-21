// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Stage 3 of the inline-span prototype: widgets on text, tried three ways.
//
//  * S1, inline replacement: a WidgetSpan takes the place of the range.
//  * S2, anchor: a WidgetSpan of no size is inserted at the start of the
//    range, and what it shows is placed relative to it.
//  * S3, positioned: the text is not changed. A host around the text places
//    widgets on ranges (TextWidgetPlugin and TextPositioned).
//
// The same three use cases are written in each way, as far as the way allows.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How a stage 3 plugin puts its widgets on the text.
enum Stage3Way {
  /// S1: a [WidgetSpan] replaces the range.
  inlineReplacement,

  /// S2: a [WidgetSpan] of no size is inserted at the start of the range.
  anchor,

  /// S3: a host around the text places a widget on the range.
  positioned,
}

/// A widget of no size in the line, whose [follower] is shown in the
/// [Overlay], with its top left corner at the anchor.
class _OverlayAnchor extends StatefulWidget {
  const _OverlayAnchor({required this.follower, this.offset = Offset.zero});

  final Widget? follower;
  final Offset offset;

  @override
  State<_OverlayAnchor> createState() => _OverlayAnchorState();
}

class _OverlayAnchorState extends State<_OverlayAnchor> {
  final LayerLink _link = LayerLink();
  // The portal is always shown, also without a follower: show() cannot be
  // called while a frame is being built, which is when the follower changes.
  final OverlayPortalController _controller = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (BuildContext context) {
        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: widget.offset,
            child: widget.follower ?? const SizedBox.shrink(),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: const SizedBox.shrink(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Use case 1: a mention chip.
// ---------------------------------------------------------------------------

/// A pill for one `@name`. It counts its taps, so that a test can see whether
/// its state survives.
class MentionChip extends StatefulWidget {
  /// Creates a chip.
  const MentionChip({
    super.key,
    required this.name,
    required this.onTap,
    this.selectable = true,
  });

  /// Whether the label of the chip can be selected in a [SelectionArea].
  ///
  /// A chip that replaces the name (S1) has to be selectable, or the name is
  /// missing from what is copied. A chip that lies on the name (S3) must not
  /// be, or the name is copied twice.
  final bool selectable;

  /// The name, without the `@`.
  final String name;

  /// Called when the chip is tapped.
  final ValueChanged<String> onTap;

  @override
  State<MentionChip> createState() => MentionChipState();
}

/// The state of a [MentionChip].
class MentionChipState extends State<MentionChip> {
  /// How often this chip was tapped.
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => taps += 1);
        widget.onTap(widget.name);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFBBDEFB),
          border: Border.all(color: const Color(0xFF1565C0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: TextPluginScope.none(
            child: widget.selectable
                ? Text(
                    '@${widget.name}${taps == 0 ? '' : ' $taps'}',
                    softWrap: false,
                  )
                : SelectionContainer.disabled(
                    child: Text(
                      '@${widget.name}${taps == 0 ? '' : ' $taps'}',
                      softWrap: false,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// How the chips of a [MentionPlugin] are keyed (S1 only).
enum MentionKeys {
  /// No key.
  none,

  /// A [ValueKey] of the name.
  value,

  /// A [GlobalObjectKey] of the name and the text.
  global,
}

/// Turns every `@name` into a [MentionChip].
class MentionPlugin extends TextPlugin with TextWidgetPlugin {
  /// Creates a mention plugin.
  MentionPlugin(this.way, {required this.onTap, this.keys = MentionKeys.none});

  /// The way the chip is put on the text.
  final Stage3Way way;

  /// Called with the name of a tapped chip.
  final ValueChanged<String> onTap;

  /// How the chips are keyed.
  final MentionKeys keys;

  static final RegExp _pattern = RegExp(r'@(\w+)');

  final Map<(TextDelegate, String), GlobalKey> _globalKeys =
      <(TextDelegate, String), GlobalKey>{};

  Key? _keyFor(TextDelegate delegate, String name) {
    return switch (keys) {
      MentionKeys.none => null,
      MentionKeys.value => ValueKey<String>(name),
      MentionKeys.global => _globalKeys[(delegate, name)] ??= GlobalKey(),
    };
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    if (way == Stage3Way.positioned) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      for (final RegExpMatch match in _pattern.allMatches(delegate.text))
        if (way == Stage3Way.inlineReplacement)
          TextSpanDecoration(
            range: TextRange(start: match.start, end: match.end),
            replacement: WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: MentionChip(
                key: _keyFor(delegate, match.group(1)!),
                name: match.group(1)!,
                onTap: onTap,
              ),
            ),
          )
        else
          // The anchor does not know how large the range is, so the chip
          // cannot cover the name exactly. It is shown over the start of it.
          TextSpanDecoration(
            range: TextRange.collapsed(match.start),
            replacement: WidgetSpan(
              child: _OverlayAnchor(
                offset: const Offset(0, -14),
                follower: MentionChip(
                  name: match.group(1)!,
                  onTap: onTap,
                  selectable: false,
                ),
              ),
            ),
          ),
    ];
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    if (way != Stage3Way.positioned || layer != TextWidgetLayer.foreground) {
      return const <Widget>[];
    }
    return <Widget>[
      for (final RegExpMatch match in _pattern.allMatches(delegate.text))
        TextPositioned.fill(
          range: TextRange(start: match.start, end: match.end),
          child: MentionChip(
            name: match.group(1)!,
            onTap: onTap,
            selectable: false,
          ),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Use case 2: a suggestion menu on a misspelled word.
// ---------------------------------------------------------------------------

/// The menu of a [SuggestionMenuPlugin].
class SuggestionMenu extends StatelessWidget {
  /// Creates a menu with one [suggestion].
  const SuggestionMenu({
    super.key,
    required this.suggestion,
    required this.onAccept,
  });

  /// The word that is suggested.
  final String suggestion;

  /// Called when the suggestion is tapped.
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAccept,
      child: Container(
        width: 160,
        height: 60,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: const Color(0xFF9E9E9E)),
        ),
        child: TextPluginScope.none(child: Text('Replace with "$suggestion"')),
      ),
    );
  }
}

/// Underlines `teh` and shows a menu with `the` when the word is tapped.
///
/// The tap is a stage 2 recognizer in every way. Only the menu differs.
class SuggestionMenuPlugin extends TextPlugin with TextWidgetPlugin {
  /// Creates a suggestion menu plugin.
  SuggestionMenuPlugin(this.way, {required this.onAccept});

  /// The way the menu is put on the text.
  final Stage3Way way;

  /// Called with the text and the range of the word whose suggestion was
  /// accepted.
  final void Function(TextDelegate delegate, TextRange range) onAccept;

  static final RegExp _pattern = RegExp(r'\bteh\b');

  final Map<TextDelegate, List<TapGestureRecognizer>> _recognizers =
      <TextDelegate, List<TapGestureRecognizer>>{};

  /// The delegate and the start of the word whose menu is open.
  (TextDelegate, int)? _open;

  /// How often [buildTextWidgets] ran, for each text.
  final Map<String, int> widgetBuilds = <String, int>{};

  /// Whether a menu is open.
  bool get isOpen => _open != null;

  /// Closes the menu.
  void close() {
    final (TextDelegate, int)? open = _open;
    _open = null;
    open?.$1.markNeedsDecoration();
  }

  void _toggle(TextDelegate delegate, int start) {
    final (TextDelegate, int)? previous = _open;
    _open = previous == (delegate, start) ? null : (delegate, start);
    previous?.$1.markNeedsDecoration();
    delegate.markNeedsDecoration();
  }

  final Set<TextDelegate> _delegates = <TextDelegate>{};

  @override
  void didAddText(TextDelegate delegate) => _delegates.add(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    _delegates.remove(delegate);
    for (final TapGestureRecognizer recognizer
        in _recognizers.remove(delegate) ?? const <TapGestureRecognizer>[]) {
      recognizer.dispose();
    }
    if (_open?.$1 == delegate) {
      _open = null;
    }
  }

  Widget _menu(TextDelegate delegate, TextRange range) {
    return SuggestionMenu(
      suggestion: 'the',
      onAccept: () {
        close();
        onAccept(delegate, range);
      },
    );
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final List<RegExpMatch> matches = _pattern
        .allMatches(delegate.text)
        .toList();
    final List<TapGestureRecognizer> recognizers = _recognizers[delegate] ??=
        <TapGestureRecognizer>[];
    while (recognizers.length < matches.length) {
      recognizers.add(TapGestureRecognizer());
    }
    final decorations = <TextSpanDecoration>[];
    // A recognizer is not allowed in a text field that can be edited.
    final bool tappable = !delegate.isEditable;
    for (var i = 0; i < matches.length; i += 1) {
      final range = TextRange(start: matches[i].start, end: matches[i].end);
      final bool open = _open == (delegate, range.start);
      recognizers[i].onTap = () => _toggle(delegate, range.start);
      if (way == Stage3Way.inlineReplacement) {
        // The word and its menu are one widget in the line.
        decorations.add(
          TextSpanDecoration(
            range: range,
            replacement: WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => _toggle(delegate, range.start),
                    child: TextPluginScope.none(
                      child: Text(
                        delegate.text.substring(range.start, range.end),
                        style: const TextStyle(
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.wavy,
                          decorationColor: Color(0xFFD32F2F),
                        ),
                      ),
                    ),
                  ),
                  if (open) _menu(delegate, range),
                ],
              ),
            ),
          ),
        );
        continue;
      }
      decorations.add(
        TextSpanDecoration(
          range: range,
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: Color(0xFFD32F2F),
          ),
          recognizer: tappable ? recognizers[i] : null,
        ),
      );
      if (way == Stage3Way.anchor) {
        decorations.add(
          TextSpanDecoration(
            range: TextRange.collapsed(range.start),
            replacement: WidgetSpan(
              child: _OverlayAnchor(
                offset: const Offset(0, 4),
                follower: open ? _menu(delegate, range) : null,
              ),
            ),
          ),
        );
      }
    }
    return decorations;
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    if (layer == TextWidgetLayer.overlay) {
      widgetBuilds[delegate.text] = (widgetBuilds[delegate.text] ?? 0) + 1;
    }
    final (TextDelegate, int)? open = _open;
    if (way != Stage3Way.positioned || open == null || open.$1 != delegate) {
      return const <Widget>[];
    }
    final range = TextRange(start: open.$2, end: open.$2 + 3);
    return switch (layer) {
      // In a text field the word has no recognizer, so a transparent widget
      // on the word takes the tap.
      TextWidgetLayer.foreground => const <Widget>[],
      TextWidgetLayer.overlay => <Widget>[
        TextPositioned(
          range: range,
          offset: const Offset(0, 4),
          child: _menu(delegate, range),
        ),
      ],
      TextWidgetLayer.background => const <Widget>[],
    };
  }

  /// Opens the menu of the first misspelled word in the scope.
  void openFirst() {
    for (final TextDelegate delegate in _delegates) {
      final RegExpMatch? match = _pattern.firstMatch(delegate.text);
      if (match != null) {
        _toggle(delegate, match.start);
        return;
      }
    }
  }

  /// Disposes the recognizers.
  void dispose() {
    for (final List<TapGestureRecognizer> recognizers in _recognizers.values) {
      for (final recognizer in recognizers) {
        recognizer.dispose();
      }
    }
    _recognizers.clear();
  }
}

// ---------------------------------------------------------------------------
// Use case 3: a frosted-glass spoiler.
// ---------------------------------------------------------------------------

/// Blurs `{{spoiler}}` text until it is tapped.
///
/// A blur of what is behind it is something a widget can do and a text style
/// cannot.
class FrostedSpoilerPlugin extends TextPlugin with TextWidgetPlugin {
  /// Creates a frosted spoiler plugin.
  FrostedSpoilerPlugin(this.way);

  /// The way the cover is put on the text.
  final Stage3Way way;

  static final RegExp _pattern = RegExp(r'\{\{(.+?)\}\}');

  final Set<(TextDelegate, String)> _revealed = <(TextDelegate, String)>{};

  void _reveal(TextDelegate delegate, String content) {
    _revealed.add((delegate, content));
    delegate.markNeedsDecoration();
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    _revealed.removeWhere(
      ((TextDelegate, String) entry) => entry.$1 == delegate,
    );
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    if (way != Stage3Way.inlineReplacement) {
      // S2 cannot do this use case: an anchor has no size, and the cover has
      // to have the size of the range, on every line that the range is on.
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      for (final RegExpMatch match in _pattern.allMatches(delegate.text))
        if (!_revealed.contains((delegate, match.group(1)!)))
          // The words are taken out of the paragraph and drawn, blurred, by a
          // widget of their own. They are one box now and do not wrap with
          // the line.
          TextSpanDecoration(
            range: TextRange(start: match.start, end: match.end),
            replacement: WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                key: ValueKey<String>('spoiler ${match.group(1)}'),
                onTap: () => _reveal(delegate, match.group(1)!),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: TextPluginScope.none(child: Text(match.group(1)!)),
                ),
              ),
            ),
          ),
    ];
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    if (way != Stage3Way.positioned || layer != TextWidgetLayer.foreground) {
      return const <Widget>[];
    }
    return <Widget>[
      for (final RegExpMatch match in _pattern.allMatches(delegate.text))
        if (!_revealed.contains((delegate, match.group(1)!)))
          // One widget on the bounding box of the range. If the range is on
          // two lines, the box also covers words that are not in the range.
          TextPositioned.fill(
            range: TextRange(start: match.start, end: match.end),
            child: GestureDetector(
              key: ValueKey<String>('spoiler ${match.group(1)}'),
              onTap: () => _reveal(delegate, match.group(1)!),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: const ColoredBox(color: Color(0x22000000)),
                ),
              ),
            ),
          ),
    ];
  }
}
