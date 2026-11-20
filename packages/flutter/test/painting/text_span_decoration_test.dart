// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle _yellow = TextStyle(backgroundColor: Color(0xFFFFFF00));
const TextStyle _red = TextStyle(color: Color(0xFFFF0000));

TextSpanDecoration _style(int start, int end, TextStyle style) {
  return TextSpanDecoration(
    range: TextRange(start: start, end: end),
    style: style,
  );
}

/// The leaf pieces of a tree, as (text, effective style) in order.
List<(String, TextStyle?)> _leaves(InlineSpan root) {
  final result = <(String, TextStyle?)>[];
  void visit(InlineSpan span, TextStyle? inherited) {
    if (span is TextSpan) {
      final TextStyle? style = inherited?.merge(span.style) ?? span.style;
      if (span.text != null) {
        result.add((span.text!, style));
      }
      span.children?.forEach((InlineSpan child) => visit(child, style));
    } else {
      result.add(('\uFFFC', inherited));
    }
  }

  visit(root, null);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decorateTextSpan', () {
    test('returns the same span when there is nothing to do', () {
      const span = TextSpan(text: 'hello world');
      expect(decorateTextSpan(span, const <TextSpanDecoration>[]).span, same(span));
      // A decoration outside of the text.
      expect(decorateTextSpan(span, <TextSpanDecoration>[_style(50, 60, _yellow)]).span, same(span));
      // A collapsed range without a replacement, and an invalid range.
      expect(
        decorateTextSpan(span, <TextSpanDecoration>[
          _style(3, 3, _yellow),
          const TextSpanDecoration(range: TextRange.empty, style: _yellow),
        ]).span,
        same(span),
      );
    });

    test('splits a span around a range and keeps the plain text', () {
      const span = TextSpan(text: 'hello world', style: TextStyle(fontSize: 20));
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(6, 11, _yellow),
      ]);
      expect(result.changesText, isFalse);
      expect(result.span.toPlainText(), 'hello world');
      expect(_leaves(result.span), <(String, TextStyle?)>[
        ('hello ', const TextStyle(fontSize: 20)),
        ('world', const TextStyle(fontSize: 20, backgroundColor: Color(0xFFFFFF00))),
      ]);
    });

    test('a later decoration wins where two overlap', () {
      const span = TextSpan(text: '0123456789');
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(0, 6, const TextStyle(color: Color(0xFF00FF00), fontSize: 10)),
        _style(4, 8, _red),
      ]);
      expect(_leaves(result.span), <(String, TextStyle?)>[
        ('0123', const TextStyle(color: Color(0xFF00FF00), fontSize: 10)),
        ('45', const TextStyle(color: Color(0xFFFF0000), fontSize: 10)),
        ('67', _red),
        ('89', null),
      ]);
    });

    test('keeps the nesting of the tree, so styles are inherited as before', () {
      const bold = TextStyle(fontWeight: FontWeight.bold);
      const span = TextSpan(
        text: 'ab',
        style: TextStyle(fontSize: 20),
        children: <InlineSpan>[
          TextSpan(text: 'cd', style: bold),
          TextSpan(text: 'ef'),
        ],
      );
      // The range crosses all three spans.
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(1, 5, _yellow),
      ]);
      expect(result.span.toPlainText(), 'abcdef');
      const TextStyle base = TextStyle(fontSize: 20);
      expect(_leaves(result.span), <(String, TextStyle?)>[
        ('a', base),
        ('b', base.merge(_yellow)),
        ('cd', base.merge(bold).merge(_yellow)),
        ('e', base.merge(_yellow)),
        ('f', base),
      ]);
    });

    test('a child that is not touched is kept by identity', () {
      const untouched = TextSpan(text: 'world');
      const span = TextSpan(text: 'hello ', children: <InlineSpan>[untouched]);
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(0, 5, _yellow),
      ]);
      final root = result.span as TextSpan;
      expect(root.children!.last, same(untouched));
    });

    test('the recognizer of the app is copied to every piece (H3)', () {
      final tap = TapGestureRecognizer();
      addTearDown(tap.dispose);
      final span = TextSpan(
        text: 'click here',
        recognizer: tap,
        mouseCursor: SystemMouseCursors.help,
      );
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(3, 7, _yellow),
      ]);
      final List<InlineSpan> pieces = (result.span as TextSpan).children!;
      expect(pieces, hasLength(3));
      for (final piece in pieces.cast<TextSpan>()) {
        expect(piece.recognizer, same(tap));
        expect(piece.mouseCursor, SystemMouseCursors.help);
      }
      for (var offset = 0; offset < 10; offset += 1) {
        final InlineSpan? hit = result.span.getSpanForPosition(TextPosition(offset: offset));
        expect((hit! as TextSpan).recognizer, same(tap), reason: 'offset $offset');
      }
    });

    test('the recognizer of a decoration replaces the one of the app', () {
      final appTap = TapGestureRecognizer();
      final pluginTap = TapGestureRecognizer();
      addTearDown(appTap.dispose);
      addTearDown(pluginTap.dispose);
      final span = TextSpan(text: '0123456789', recognizer: appTap);
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        TextSpanDecoration(range: const TextRange(start: 2, end: 4), recognizer: pluginTap),
      ]);
      final List<TextSpan> pieces = (result.span as TextSpan).children!.cast<TextSpan>();
      expect(pieces.map((TextSpan s) => s.recognizer), <GestureRecognizer>[
        appTap,
        pluginTap,
        appTap,
      ]);
      expect(pieces[1].mouseCursor, SystemMouseCursors.click);
    });

    test('a span with a semantics label is never split (H4)', () {
      const span = TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'Buy '),
          TextSpan(text: 'GOOG', semanticsLabel: 'Alphabet'),
          TextSpan(text: ' now'),
        ],
      );
      // Covers "y GO": half of the labelled span.
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(2, 6, _yellow),
      ]);
      expect(result.span.toPlainText(includeSemanticsLabels: false), 'Buy GOOG now');
      expect(result.span.toPlainText(), 'Buy Alphabet now');
      // The whole labelled span has the style.
      expect(_leaves(result.span), <(String, TextStyle?)>[
        ('Bu', null),
        ('y ', _yellow),
        ('GOOG', _yellow),
        (' now', null),
      ]);
    });

    test('a semantics label of a decoration is spoken once', () {
      const span = TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'see http://a'),
          TextSpan(text: '.com now', style: TextStyle(fontSize: 20)),
        ],
      );
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        const TextSpanDecoration(range: TextRange(start: 4, end: 16), semanticsLabel: 'link'),
      ]);
      expect(result.span.toPlainText(includeSemanticsLabels: false), 'see http://a.com now');
      expect(result.span.toPlainText(), 'see link now');
    });

    test('a placeholder is one code unit and is not styled', () {
      const placeholder = WidgetSpan(child: SizedBox());
      const span = TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'Buy '),
          placeholder,
          TextSpan(text: ' GOOG today'),
        ],
      );
      final String text = span.toPlainText(includeSemanticsLabels: false);
      final int start = text.indexOf('GOOG');
      expect(start, 6);
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        _style(2, start + 4, _yellow),
      ]);
      final root = result.span as TextSpan;
      expect(root.children![1], same(placeholder));
      expect(_leaves(result.span), <(String, TextStyle?)>[
        ('Bu', null),
        ('y ', _yellow),
        ('\uFFFC', null),
        (' GOOG', _yellow),
        (' today', null),
      ]);
    });

    test('a replacement takes the place of its range, across spans', () {
      const chip = WidgetSpan(child: SizedBox());
      const span = TextSpan(
        text: 'hi @al',
        children: <InlineSpan>[TextSpan(text: 'ice, bye')],
      );
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        const TextSpanDecoration(range: TextRange(start: 3, end: 9), replacement: chip),
        // Computed against the original text, after the replacement.
        _style(11, 14, _yellow),
      ]);
      expect(result.changesText, isTrue);
      expect(result.span.toPlainText(), 'hi \uFFFC, bye');
      expect(_leaves(result.span), <(String, TextStyle?)>[
        ('hi ', null),
        ('\uFFFC', null),
        (', ', null),
        ('bye', _yellow),
      ]);
      expect(result.toDecoratedOffset(0), 0);
      expect(result.toDecoratedOffset(3), 3);
      expect(result.toDecoratedOffset(5), 3);
      expect(result.toDecoratedOffset(9), 4);
      expect(result.toDecoratedOffset(11), 6);
      expect(result.toOriginalOffset(3), 3);
      expect(result.toOriginalOffset(4), 9);
      expect(result.toOriginalOffset(6), 11);
    });

    test('a collapsed replacement is inserted without removing text', () {
      const anchor = WidgetSpan(child: SizedBox());
      const end = WidgetSpan(child: SizedBox(width: 1));
      const span = TextSpan(text: 'hello world');
      final DecoratedTextSpan result = decorateTextSpan(span, <TextSpanDecoration>[
        const TextSpanDecoration(range: TextRange.collapsed(6), replacement: anchor),
        const TextSpanDecoration(range: TextRange.collapsed(11), replacement: end),
        _style(6, 11, _yellow),
      ]);
      expect(result.span.toPlainText(), 'hello \uFFFCworld\uFFFC');
      expect(result.toDecoratedOffset(5), 5);
      expect(result.toDecoratedOffset(6), 7);
      expect(result.toOriginalOffset(7), 6);
      expect(result.toOriginalOffset(6), 6);
      expect(result.toOriginalOffset(12), 11);
    });

    test('a style-only change compares as paint, a new split as layout (F1, F2)', () {
      const span = TextSpan(text: 'hello world');
      final InlineSpan yellow = decorateTextSpan(span, <TextSpanDecoration>[
        _style(6, 11, _yellow),
      ]).span;
      final InlineSpan orange = decorateTextSpan(span, <TextSpanDecoration>[
        _style(6, 11, const TextStyle(backgroundColor: Color(0xFFFF8800))),
      ]).span;
      final InlineSpan moved = decorateTextSpan(span, <TextSpanDecoration>[
        _style(0, 5, _yellow),
      ]).span;
      expect(span.compareTo(yellow), RenderComparison.layout);
      expect(yellow.compareTo(orange), RenderComparison.paint);
      expect(yellow.compareTo(moved), RenderComparison.layout);
    });
  });

  group('shaping (H1)', () {
    setUpAll(() async {
      final String root = Platform.environment['FLUTTER_ROOT']!;
      final file = File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      final loader = FontLoader('Roboto')
        ..addFont(file.readAsBytes().then((Uint8List bytes) => ByteData.sublistView(bytes)));
      await loader.load();
    });

    double widthOf(InlineSpan span) {
      final painter = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      addTearDown(painter.dispose);
      return painter.width;
    }

    const style = TextStyle(fontFamily: 'Roboto', fontSize: 100);

    test('a colour-only split inside a kerning pair does not change the layout', () {
      const whole = TextSpan(text: 'AV', style: style);
      final double separate =
          widthOf(const TextSpan(text: 'A', style: style)) +
          widthOf(const TextSpan(text: 'V', style: style));
      final double kerned = widthOf(whole);
      // The font really kerns this pair, so the test can fail.
      expect(kerned, lessThan(separate));

      for (final decoration in <TextStyle>[
        _yellow,
        _red,
        const TextStyle(decoration: TextDecoration.underline),
      ]) {
        final InlineSpan split = decorateTextSpan(whole, <TextSpanDecoration>[
          _style(1, 2, decoration),
        ]).span;
        expect(widthOf(split), kerned, reason: '$decoration');
      }
    });

    test('a colour-only split inside a ligature', () {
      const whole = TextSpan(text: 'fi', style: style);
      final double separate =
          widthOf(const TextSpan(text: 'f', style: style)) +
          widthOf(const TextSpan(text: 'i', style: style));
      final double joined = widthOf(whole);
      final InlineSpan split = decorateTextSpan(whole, <TextSpanDecoration>[
        _style(1, 2, _yellow),
      ]).span;
      // Report what the engine does, whatever it is.
      // ignore: avoid_print
      print('fi: separate=$separate joined=$joined split=${widthOf(split)}');
      expect(widthOf(split), joined);
    });
  });
}
