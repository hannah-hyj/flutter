// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// What a split of a span does to shaping, for text that is harder than
// Latin: joined scripts, combining marks, emoji sequences, surrogate pairs.
//
// A text plugin computes ranges from a string. A range can end anywhere,
// also inside something that the shaper treats as one unit. With a painter
// the text is not touched, so the worst case is a highlight in the wrong
// place. With the inline-span prototype the range becomes a span boundary.
// These tests record what the engine does then.
//
// The fonts are system fonts of macOS. A test is skipped where its font is
// missing.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle _red = TextStyle(color: Color(0xFFFF0000));

Future<bool> _load(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    return false;
  }
  try {
    final loader = FontLoader(family)
      ..addFont(file.readAsBytes().then((Uint8List bytes) => ByteData.sublistView(bytes)));
    await loader.load();
    return true;
  } on Object {
    return false;
  }
}

TextPainter _layout(InlineSpan span, {double maxWidth = double.infinity}) {
  final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
    ..layout(maxWidth: maxWidth);
  addTearDown(painter.dispose);
  return painter;
}

InlineSpan _split(TextSpan span, int start, int end, [TextStyle style = _red]) {
  return decorateTextSpan(span, <TextSpanDecoration>[
    TextSpanDecoration(
      range: TextRange(start: start, end: end),
      style: style,
    ),
  ]).span;
}

double _separate(String text, int at, TextStyle style) {
  return _layout(TextSpan(text: text.substring(0, at), style: style)).width +
      _layout(TextSpan(text: text.substring(at), style: style)).width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool hasRoboto;
  late bool hasArabic;
  late bool hasEmoji;

  setUpAll(() async {
    final String root = Platform.environment['FLUTTER_ROOT']!;
    hasRoboto = await _load(
      'Roboto',
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    hasArabic = await _load('ArialUnicode', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    hasEmoji = await _load('AppleEmoji', '/System/Library/Fonts/Apple Color Emoji.ttc');
  });

  test('Arabic: a color split inside a word keeps the letters joined', () {
    if (!hasArabic) {
      markTestSkipped('Arial Unicode is not installed');
      return;
    }
    const style = TextStyle(fontFamily: 'ArialUnicode', fontSize: 100);
    const word = '\u0645\u0631\u062D\u0628\u0627'; // marhaba
    const whole = TextSpan(text: word, style: style);
    final double joined = _layout(whole).width;
    final double apart = _separate(word, 3, style);
    final double split = _layout(_split(whole, 3, 5)).width;
    // ignore: avoid_print
    print('SHAPING arabic: joined=$joined, two separate words=$apart, color split=$split');
    // The font really joins, so the test can fail.
    expect(joined, isNot(apart));
    expect(split, joined);
  });

  test('Arabic: a split that changes the font size inside a word breaks the joining', () {
    if (!hasArabic) {
      markTestSkipped('Arial Unicode is not installed');
      return;
    }
    const style = TextStyle(fontFamily: 'ArialUnicode', fontSize: 100);
    const word = '\u0645\u0631\u062D\u0628\u0627';
    const whole = TextSpan(text: word, style: style);
    final double joined = _layout(whole).width;
    final double split = _layout(_split(whole, 3, 5, const TextStyle(fontSize: 101))).width;
    // ignore: avoid_print
    print('SHAPING arabic, size split: joined=$joined, split=$split');
    // A decoration that changes the font (size, weight, family) starts a new
    // shaping run. The letters on both sides of it are no longer joined.
    expect(split, isNot(joined));
  });

  test('a combining mark: a split between the letter and its mark', () {
    if (!hasRoboto) {
      markTestSkipped('Roboto is not in the cache');
      return;
    }
    const style = TextStyle(fontFamily: 'Roboto', fontSize: 100);
    const text = 'e\u0301x';
    const whole = TextSpan(text: text, style: style);
    final TextPainter plain = _layout(whole);
    final TextPainter split = _layout(_split(whole, 1, 2));
    final List<TextBox> plainBoxes = plain.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    final List<TextBox> splitBoxes = split.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    // ignore: avoid_print
    print(
      'SHAPING combining mark: width plain=${plain.width} split=${split.width}, '
      'boxes plain=$plainBoxes split=$splitBoxes',
    );
    expect(split.width, plain.width);
  });

  test('an emoji sequence: a split inside a family emoji', () {
    if (!hasEmoji) {
      markTestSkipped('Apple Color Emoji could not be loaded');
      return;
    }
    const style = TextStyle(fontFamily: 'AppleEmoji', fontSize: 100);
    // man, zero width joiner, woman, zero width joiner, girl.
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
    const whole = TextSpan(text: family, style: style);
    final double one = _layout(whole).width;
    final double man = _layout(const TextSpan(text: '\u{1F468}', style: style)).width;
    // The range ends after the man: offsets are UTF-16, the man is two code
    // units.
    final double split = _layout(_split(whole, 0, 2)).width;
    // ignore: avoid_print
    print('SHAPING emoji family: one glyph=$one, a single man=$man, color split=$split');
    // The family is one glyph, and a color split inside it keeps it one.
    expect(one, man);
    expect(split, one);
  });

  test('a surrogate pair: a range that ends in the middle of it', () {
    if (!hasEmoji) {
      markTestSkipped('Apple Color Emoji could not be loaded');
      return;
    }
    const style = TextStyle(fontFamily: 'AppleEmoji', fontSize: 100);
    const text = 'a\u{1F600}b';
    const whole = TextSpan(text: text, style: style);
    final double plain = _layout(whole).width;

    // What a span boundary inside the pair does, without the merge: the two
    // halves are two broken characters, and the emoji is gone. There is no
    // error, and the plain text is the same string.
    const broken = TextSpan(
      style: style,
      children: <InlineSpan>[
        TextSpan(text: 'a\uD83D', style: _red),
        TextSpan(text: '\uDE00b'),
      ],
    );
    expect(broken.toPlainText(), text);
    final double brokenWidth = _layout(broken).width;
    // ignore: avoid_print
    print('SHAPING surrogate pair: plain=$plain, a span boundary inside the pair=$brokenWidth');
    expect(brokenWidth, isNot(plain));

    // The merge moves such a cut to after the pair.
    final InlineSpan span = _split(whole, 0, 2);
    expect(_layout(span).width, plain);
    final texts = <String>[];
    span.visitChildren((InlineSpan child) {
      if (child is TextSpan && child.text != null) {
        texts.add(child.text!);
      }
      return true;
    });
    expect(texts, <String>['a\u{1F600}', 'b']);
  });

  test('a split inside a word does not add a place where the line can break', () {
    if (!hasRoboto) {
      markTestSkipped('Roboto is not in the cache');
      return;
    }
    const style = TextStyle(fontFamily: 'Roboto', fontSize: 20);
    const text = 'aaaa unbreakableword bbbb';
    const whole = TextSpan(text: text, style: style);
    for (final maxWidth in <double>[80, 120, 160, 200]) {
      final List<LineMetrics> plain = _layout(whole, maxWidth: maxWidth).computeLineMetrics();
      final List<LineMetrics> split = _layout(
        _split(whole, 8, 12),
        maxWidth: maxWidth,
      ).computeLineMetrics();
      expect(split.length, plain.length, reason: 'maxWidth $maxWidth');
      for (var i = 0; i < plain.length; i += 1) {
        expect(split[i].width, plain[i].width, reason: 'maxWidth $maxWidth, line $i');
      }
    }
  });

  test('mixed directions: a split inside the right-to-left run', () {
    if (!hasArabic) {
      markTestSkipped('Arial Unicode is not installed');
      return;
    }
    const style = TextStyle(fontFamily: 'ArialUnicode', fontSize: 40);
    const text = 'abc \u05D0\u05D1\u05D2\u05D3 def';
    const whole = TextSpan(text: text, style: style);
    final TextPainter plain = _layout(whole);
    final TextPainter split = _layout(_split(whole, 5, 7));
    expect(split.width, plain.width);
    // The caret positions are where they were.
    for (var offset = 0; offset <= text.length; offset += 1) {
      expect(
        split.getOffsetForCaret(TextPosition(offset: offset), Rect.zero),
        plain.getOffsetForCaret(TextPosition(offset: offset), Rect.zero),
        reason: 'offset $offset',
      );
    }
  });

  test('a subclass of TextSpan is not kept for the pieces of a split', () {
    const span = _TaggedSpan(text: 'hello world', tag: 'greeting');
    final InlineSpan decorated = _split(span, 6, 11);
    final found = <Type>[];
    decorated.visitChildren((InlineSpan child) {
      found.add(child.runtimeType);
      return true;
    });
    // ignore: avoid_print
    print('SHAPING subclass: the decorated tree has $found');
    // The merge builds plain TextSpans. An app that finds its own spans by
    // type, or overrides a method of TextSpan, loses that for a text that a
    // plugin decorated.
    expect(found, isNot(contains(_TaggedSpan)));
    // A span that no decoration touches is kept as it is.
    const parent = TextSpan(
      children: <InlineSpan>[
        _TaggedSpan(text: 'kept', tag: 'a'),
        TextSpan(text: ' and split'),
      ],
    );
    final root = _split(parent, 9, 14) as TextSpan;
    expect(root.children!.first, isA<_TaggedSpan>());
  });
}

class _TaggedSpan extends TextSpan {
  const _TaggedSpan({super.text, required this.tag});

  final String tag;
}
