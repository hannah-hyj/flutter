// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The part of the benchmark that differs between the two prototypes.
//
// This is the inline-span version. The painter version of this file lives on
// the `text-plugin-mvp` branch only for the duration of a benchmark run; it
// is kept in `benchmark_compat_painter.dart.txt` next to this file.

import 'dart:ui' show PictureRecorder;

import 'package:flutter/widgets.dart';

import 'plugins/search_in_page_plugin.dart';

/// The name of the prototype, for the report.
const String branchLabel = 'span';

/// One way to run a plugin.
class Variant {
  const Variant(this.label, {this.layer, this.notify = false});

  final String label;
  final TextDecorationLayer? layer;

  /// Whether the search plugin notifies instead of naming the texts.
  final bool notify;
}

/// The ways to run a plugin on this branch.
const List<Variant> variants = <Variant>[
  Variant('A widget layer', layer: TextDecorationLayer.widget),
  Variant('B render layer', layer: TextDecorationLayer.render),
  Variant(
    'A widget layer, notify',
    layer: TextDecorationLayer.widget,
    notify: true,
  ),
  Variant(
    'B render layer, notify',
    layer: TextDecorationLayer.render,
    notify: true,
  ),
];

Widget wrapScope({
  required List<TextPlugin> plugins,
  required Variant variant,
  required Widget child,
}) {
  return TextPluginScope.multiple(
    plugins: plugins,
    decorationLayer: variant.layer,
    child: child,
  );
}

SearchInPagePlugin makeSearch(Variant variant) {
  return SearchInPagePlugin(notifyToRedecorate: variant.notify);
}

/// Highlights one word of a text and moves on with [step].
class KaraokePlugin extends TextPlugin {
  static final RegExp _word = RegExp(r'\S+');

  TextDelegate? _delegate;
  List<TextRange> _words = const <TextRange>[];
  int _index = 0;

  @override
  void didAddText(TextDelegate delegate) {
    _delegate = delegate;
    _words = <TextRange>[
      for (final Match match in _word.allMatches(delegate.text))
        TextRange(start: match.start, end: match.end),
    ];
  }

  void step() {
    _index = (_index + 1) % _words.length;
    _delegate!.markNeedsDecoration();
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    if (_words.isEmpty) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: _words[_index],
        style: const TextStyle(
          backgroundColor: Color(0x5500ACC1),
          decoration: TextDecoration.underline,
        ),
      ),
    ];
  }
}

int _decorate = 0;
int _buildDecorations = 0;
int _builderBuilds = 0;

/// What the framework did since the last call, for the report.
String counters() {
  final String result =
      'spans decorated ${TextDelegateSet.debugDecorateCount - _decorate}, '
      'buildDecorations ${TextDelegateSet.debugBuildDecorationsCount - _buildDecorations}, '
      'wrapper builds ${TextPluginSpanBuilder.debugBuildCount - _builderBuilds}';
  _decorate = TextDelegateSet.debugDecorateCount;
  _buildDecorations = TextDelegateSet.debugBuildDecorationsCount;
  _builderBuilds = TextPluginSpanBuilder.debugBuildCount;
  return result;
}

/// Highlights the first word of every text, with a color that changes on
/// every [tick]. This is an animated highlight, such as a fade or a pulse.
class PulsePlugin extends TextPlugin {
  final Set<TextDelegate> _delegates = <TextDelegate>{};
  int _tick = 0;

  @override
  void didAddText(TextDelegate delegate) => _delegates.add(delegate);

  @override
  void didRemoveText(TextDelegate delegate) => _delegates.remove(delegate);

  void tick() {
    _tick += 1;
    for (final TextDelegate delegate in _delegates) {
      delegate.markNeedsDecoration();
    }
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    final int end = delegate.text.indexOf(' ');
    if (end <= 0) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: TextRange(start: 0, end: end),
        style: TextStyle(
          backgroundColor: Color.fromARGB(40 + _tick % 200, 255, 152, 0),
        ),
      ),
    ];
  }
}

/// The ways to show the selection of static text on this branch.
final List<(String, VoidCallback)> selectionModes = <(String, VoidCallback)>[
  (
    'built-in highlight',
    () {
      debugSelectionHighlightAsTextPlugin = false;
    },
  ),
  (
    'span plugin, A widget layer',
    () {
      debugSelectionHighlightAsTextPlugin = true;
      debugDefaultTextDecorationLayer = TextDecorationLayer.widget;
    },
  ),
  (
    'span plugin, B render layer',
    () {
      debugSelectionHighlightAsTextPlugin = true;
      debugDefaultTextDecorationLayer = TextDecorationLayer.render;
    },
  ),
];

/// A search plugin that gives new decorations to at most [perFrame] texts in
/// one frame.
SearchInPagePlugin makeBatchedSearch(int perFrame) {
  return SearchInPagePlugin(decorationsPerFrame: perFrame);
}

/// Where the time of one decoration change goes, for one text, outside of any
/// widget or render object. Returns lines for the report.
List<String> runBreakdown(String text) {
  const iterations = 3000;
  const base = TextStyle(fontSize: 14, color: Color(0xFF000000));
  const width = 780.0;
  final plain = TextSpan(text: text, style: base);
  List<TextSpanDecoration> decorations(String word, Color color) =>
      <TextSpanDecoration>[
        for (final Match match in word.allMatches(text))
          TextSpanDecoration(
            range: TextRange(start: match.start, end: match.end),
            style: TextStyle(backgroundColor: color),
          ),
      ];
  final List<TextSpanDecoration> foxYellow = decorations(
    'fox',
    const Color(0x66FFEB3B),
  );
  final InlineSpan spanFoxYellow = decorateTextSpan(plain, foxYellow).span;
  final InlineSpan spanFoxOrange = decorateTextSpan(
    plain,
    decorations('fox', const Color(0x99FF9800)),
  ).span;
  final InlineSpan spanFoYellow = decorateTextSpan(
    plain,
    decorations('fo', const Color(0x66FFEB3B)),
  ).span;

  double time(void Function(int i) body) {
    // Warm up.
    for (var i = 0; i < 200; i++) {
      body(i);
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body(i);
    }
    watch.stop();
    return watch.elapsedMicroseconds / iterations;
  }

  final painter = TextPainter(
    text: spanFoxYellow,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  void paintOnce() {
    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    recorder.endRecording().dispose();
  }

  final lines = <String>[];
  String us(double value) => '${value.toStringAsFixed(1)} us';
  lines.add(
    'BREAKDOWN one text of ${text.length} characters with ${foxYellow.length} matches, '
    '$iterations iterations each',
  );
  lines.add(
    'BREAKDOWN merge (decorateTextSpan, Dart only): '
    '${us(time((int i) => decorateTextSpan(plain, foxYellow)))}',
  );
  lines.add(
    'BREAKDOWN paint, nothing changed: ${us(time((int i) => paintOnce()))}',
  );
  final double boxes = time((int i) {
    for (final TextSpanDecoration decoration in foxYellow) {
      painter.getBoxesForSelection(
        TextSelection(
          baseOffset: decoration.range.start,
          extentOffset: decoration.range.end,
        ),
      );
    }
  });
  lines.add(
    'BREAKDOWN getBoxesForSelection for every match (what a painter plugin asks): ${us(boxes)}',
  );
  lines.add(
    'BREAKDOWN color-only change (compareTo says paint), then paint: '
    '${us(time((int i) {
      painter.text = i.isEven ? spanFoxOrange : spanFoxYellow;
      paintOnce();
    }))}',
  );
  lines.add(
    'BREAKDOWN range change (compareTo says layout), then layout and paint: '
    '${us(time((int i) {
      painter.text = i.isEven ? spanFoYellow : spanFoxYellow;
      painter.layout(maxWidth: width);
      paintOnce();
    }))}',
  );
  lines.add(
    'BREAKDOWN layout only, of a text that was marked as needing layout: '
    '${us(time((int i) {
      painter.markNeedsLayout();
      painter.layout(maxWidth: width);
    }))}',
  );
  final plainPainter = TextPainter(
    text: plain,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  lines.add(
    'BREAKDOWN layout only, same text without any decoration: '
    '${us(time((int i) {
      plainPainter.markNeedsLayout();
      plainPainter.layout(maxWidth: width);
    }))}',
  );
  lines.add(
    'BREAKDOWN compareTo of the two spans that differ in color: '
    '${spanFoxYellow.compareTo(spanFoxOrange)}, in range: ${spanFoxYellow.compareTo(spanFoYellow)}',
  );
  painter.dispose();
  plainPainter.dispose();
  return lines;
}
