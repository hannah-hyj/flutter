// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// A minimal reproduction, with dart:ui only: a paragraph is shaped again when
// a background color moves to a different range of the same text, although
// the text and the fonts are the same.
//
//     flutter run --profile -d macos -t lib/paragraph_cache_repro.dart

// ignore_for_file: avoid_print

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

const int paragraphCount = 50; // Fewer than the 128 entries of the cache.
const int rounds = 40;
const double width = 600;

const List<String> vocabulary = <String>[
  'time',
  'people',
  'water',
  'music',
  'garden',
  'window',
  'river',
  'bright',
  'small',
  'quiet',
  'market',
  'letter',
  'summer',
  'winter',
  'forest',
  'silver',
  'yellow',
  'simple',
  'travel',
  'listen',
  'moment',
  'number',
  'family',
  'friend',
  'school',
  'street',
  'animal',
  'plant',
  'light',
  'sound',
  'paper',
  'stone',
  'cloud',
  'ocean',
  'bridge',
  'castle',
  'orange',
  'purple',
  'mirror',
]; // dart format off

/// 80 words, about 500 characters, different for every [seed], so that no two
/// paragraphs begin or end with the same 40 characters.
List<String> words(int seed) {
  int state = (seed * 2654435761 + 97) & 0x7fffffff;
  return <String>[
    for (var i = 0; i < 80; i++)
      vocabulary[((state = (state * 1103515245 + 12345) & 0x7fffffff) >> 8) % vocabulary.length],
  ];
}

/// Builds the paragraph of [seed]. If [highlighted] is not null, that word
/// gets [background] as its background color. Nothing else differs.
ui.Paragraph build(int seed, {int? highlighted, ui.Color? background}) {
  final List<String> text = words(seed);
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
    ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)));
  for (var i = 0; i < text.length; i++) {
    if (i == highlighted) {
      builder
        ..pushStyle(ui.TextStyle(background: ui.Paint()..color = background!))
        ..addText(text[i])
        ..pop();
    } else {
      builder.addText(text[i]);
    }
    builder.addText(' ');
  }
  return builder.build();
}

/// Microseconds of `Paragraph.layout` for one paragraph, averaged over every
/// paragraph and every round after the first.
double measure(ui.Paragraph Function(int seed, int round) make) {
  final watch = Stopwatch();
  var count = 0;
  for (var round = 0; round < rounds; round++) {
    for (var seed = 0; seed < paragraphCount; seed++) {
      final ui.Paragraph paragraph = make(seed, round);
      if (round > 0) {
        watch.start();
      }
      paragraph.layout(const ui.ParagraphConstraints(width: width));
      watch.stop();
      if (round > 0) {
        count += 1;
      }
      paragraph.dispose();
    }
  }
  return watch.elapsedMicroseconds / count;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. The same paragraph, built again.
  final double same = measure((int seed, int round) => build(seed));

  // 2. One word has a background color. The word stays, the color changes.
  final double color = measure(
    (int seed, int round) =>
        build(seed, highlighted: 10, background: ui.Color(0xFF000000 | (round * 4001))),
  );

  // 3. One word has a background color. The color stays, the word changes.
  final double moved = measure(
    (int seed, int round) =>
        build(seed, highlighted: round, background: const ui.Color(0xFFFFFF00)),
  );

  // 4. A text that was never laid out, for comparison.
  var fresh = 1000;
  final double first = measure((int seed, int round) => build(fresh++));

  final report =
      'Paragraph.layout, microseconds for one paragraph of about 500 characters\n'
      '1. the same paragraph again:                      ${same.toStringAsFixed(1)}\n'
      '2. same word highlighted, another color:          ${color.toStringAsFixed(1)}\n'
      '3. same color, another word highlighted:          ${moved.toStringAsFixed(1)}\n'
      '4. a text that was never laid out:                ${first.toStringAsFixed(1)}';
  print(report);
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Center(
          child: Text(
            report,
            style: const TextStyle(color: Color(0xFF000000), fontSize: 14, fontFamily: 'Menlo'),
          ),
        ),
      ),
    ),
  );
}
