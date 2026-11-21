// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class _Spoiler {
  _Spoiler(this.range, this.content, this.recognizer);

  /// The whole spoiler, with the `||` on both sides.
  TextRange range;
  final String content;
  final TapGestureRecognizer recognizer;
  bool revealed = false;
}

/// Stage 2 of the inline-span prototype: hides `||spoiler||` text until it is
/// tapped.
///
/// Everything is a [TextSpanDecoration]:
///
///  * The cover is a style whose text color and background color are the
///    same.
///  * The tap is a recognizer.
///  * A screen reader hears [hiddenLabel] instead of the text, through a
///    semantics label.
///  * The `||` are made invisible with a style, and with [collapseDelimiters]
///    they also take no room. A painter cannot do that, because it cannot
///    change the layout of the text.
class SpoilerMaskPlugin extends TextPlugin {
  /// Creates a spoiler plugin.
  SpoilerMaskPlugin({
    this.coverColor = const Color(0xFF424242),
    this.hiddenLabel = 'Spoiler, hidden',
    this.collapseDelimiters = true,
  });

  /// The color of the cover.
  final Color coverColor;

  /// What a screen reader says for a hidden spoiler.
  final String hiddenLabel;

  /// Whether the `||` take no room in the line.
  final bool collapseDelimiters;

  static final RegExp _pattern = RegExp(r'\|\|(.+?)\|\|');

  final Map<TextDelegate, List<_Spoiler>> _spoilers =
      <TextDelegate, List<_Spoiler>>{};

  // The paint order is above a link plugin, so that a hidden link cannot be
  // opened.
  @override
  int get paintOrder => 10;

  @override
  void didAddText(TextDelegate delegate) => _scan(delegate);

  @override
  void didUpdateText(TextDelegate delegate) => _scan(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    for (final _Spoiler spoiler
        in _spoilers.remove(delegate) ?? const <_Spoiler>[]) {
      spoiler.recognizer.dispose();
    }
  }

  void _scan(TextDelegate delegate) {
    final List<_Spoiler> old = _spoilers[delegate] ?? <_Spoiler>[];
    final spoilers = <_Spoiler>[];
    for (final RegExpMatch match in _pattern.allMatches(delegate.text)) {
      final String content = match.group(1)!;
      final range = TextRange(start: match.start, end: match.end);
      final int reuse = old.indexWhere(
        (_Spoiler spoiler) => spoiler.content == content,
      );
      if (reuse != -1) {
        spoilers.add(old.removeAt(reuse)..range = range);
      } else {
        final recognizer = TapGestureRecognizer();
        final spoiler = _Spoiler(range, content, recognizer);
        recognizer.onTap = () {
          spoiler.revealed = true;
          delegate.markNeedsDecoration();
        };
        spoilers.add(spoiler);
      }
    }
    for (final spoiler in old) {
      spoiler.recognizer.dispose();
    }
    if (spoilers.isEmpty) {
      _spoilers.remove(delegate);
    } else {
      _spoilers[delegate] = spoilers;
    }
  }

  /// Hides every spoiler again.
  void hideAll() {
    for (final MapEntry<TextDelegate, List<_Spoiler>> entry
        in _spoilers.entries) {
      for (final _Spoiler spoiler in entry.value) {
        spoiler.revealed = false;
      }
      entry.key.markNeedsDecoration();
    }
  }

  static const TextStyle _collapsed = TextStyle(
    fontSize: 0.01,
    letterSpacing: 0,
    color: Color(0x00000000),
  );
  static const TextStyle _invisible = TextStyle(color: Color(0x00000000));

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final List<_Spoiler>? spoilers = _spoilers[delegate];
    if (spoilers == null) {
      return const <TextSpanDecoration>[];
    }
    final TextStyle delimiter = collapseDelimiters ? _collapsed : _invisible;
    return <TextSpanDecoration>[
      for (final _Spoiler spoiler in spoilers) ...<TextSpanDecoration>[
        TextSpanDecoration(
          range: TextRange(
            start: spoiler.range.start,
            end: spoiler.range.start + 2,
          ),
          style: delimiter,
          semanticsLabel: '',
        ),
        TextSpanDecoration(
          range: TextRange(
            start: spoiler.range.end - 2,
            end: spoiler.range.end,
          ),
          style: delimiter,
          semanticsLabel: '',
        ),
        if (!spoiler.revealed)
          TextSpanDecoration(
            range: TextRange(
              start: spoiler.range.start + 2,
              end: spoiler.range.end - 2,
            ),
            style: TextStyle(color: coverColor, backgroundColor: coverColor),
            recognizer: spoiler.recognizer,
            semanticsLabel: hiddenLabel,
          ),
      ],
    ];
  }

  /// Disposes the recognizers.
  void dispose() {
    for (final List<_Spoiler> spoilers in _spoilers.values) {
      for (final spoiler in spoilers) {
        spoiler.recognizer.dispose();
      }
    }
    _spoilers.clear();
  }
}
