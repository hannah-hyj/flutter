// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Tests for an experiment on the inline-span prototype of text plugins: a
// decoration that only sets a background color is painted by the render
// object and is not put into the span (debugPaintHighlightsInFramework).

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _yellow = Color(0xFFFFFF00);

class _WordPlugin extends TextPlugin {
  _WordPlugin(this.word, {this.style = const TextStyle(backgroundColor: _yellow)});

  String word;
  TextStyle style;
  final Set<TextDelegate> delegates = <TextDelegate>{};

  @override
  void didAddText(TextDelegate delegate) => delegates.add(delegate);

  @override
  void didRemoveText(TextDelegate delegate) => delegates.remove(delegate);

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    return <TextSpanDecoration>[
      if (word.isNotEmpty)
        for (final Match match in word.allMatches(delegate.text))
          TextSpanDecoration(
            range: TextRange(start: match.start, end: match.end),
            style: style,
          ),
    ];
  }

  void setWord(String value) {
    word = value;
    for (final TextDelegate delegate in delegates.toList()) {
      delegate.markNeedsDecoration();
    }
  }
}

bool _hasBackground(InlineSpan root) {
  var found = false;
  root.visitChildren((InlineSpan span) {
    if (span.style?.backgroundColor != null) {
      found = true;
    }
    return !found;
  });
  return found;
}

Widget _app(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: child),
  );
}

void main() {
  setUp(() {
    debugPaintHighlightsInFramework = true;
  });

  tearDown(() {
    debugPaintHighlightsInFramework = false;
    debugDefaultTextDecorationLayer = TextDecorationLayer.widget;
  });

  for (final TextDecorationLayer layer in TextDecorationLayer.values) {
    group('$layer', () {
      setUp(() {
        debugDefaultTextDecorationLayer = layer;
      });

      testWidgets('a background color is painted by the render object, the span is not split', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('fox');
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('the quick fox jumps'))),
        );
        final RenderParagraph paragraph = tester.renderObject(find.byType(RichText));
        final InlineSpan painted = paragraph.debugDecoratedText;
        expect(_hasBackground(painted), isFalse);
        expect(painted.toPlainText(), 'the quick fox jumps');
        // One piece: nothing was cut out of the text.
        var leaves = 0;
        painted.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.text != null) {
            leaves += 1;
          }
          return true;
        });
        expect(leaves, 1);

        final Rect box = paragraph
            .getBoxesForSelection(const TextSelection(baseOffset: 10, extentOffset: 13))
            .single
            .toRect();
        expect(paragraph, paints..rect(rect: box, color: _yellow));
      });

      testWidgets('a new range repaints and does not build a new span', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('fox');
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('the quick fox jumps'))),
        );
        final RenderParagraph paragraph = tester.renderObject(find.byType(RichText));
        final InlineSpan before = paragraph.debugDecoratedText;
        final int decorated = TextDelegateSet.debugDecorateCount;
        final int changed = TextDelegateSet.debugFrameworkHighlightChangeCount;

        plugin.setWord('quick');
        await tester.pump();

        expect(TextDelegateSet.debugFrameworkHighlightChangeCount, changed + 1);
        expect(TextDelegateSet.debugDecorateCount, decorated);
        // The same span object: the text painter was not given a new text, so
        // it keeps its paragraph.
        expect(paragraph.debugDecoratedText.compareTo(before), RenderComparison.identical);
        final Rect box = paragraph
            .getBoxesForSelection(const TextSelection(baseOffset: 4, extentOffset: 9))
            .single
            .toRect();
        expect(paragraph, paints..rect(rect: box, color: _yellow));

        plugin.setWord('');
        await tester.pump();
        expect(paragraph, isNot(paints..rect(color: _yellow)));
      });

      testWidgets('a decoration with more than a background color still goes into the span', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin(
          'fox',
          style: const TextStyle(backgroundColor: _yellow, fontWeight: FontWeight.bold),
        );
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('the quick fox jumps'))),
        );
        final RenderParagraph paragraph = tester.renderObject(find.byType(RichText));
        expect(_hasBackground(paragraph.debugDecoratedText), isTrue);
        expect(
          tester
              .renderObject<RenderParagraph>(find.byType(RichText))
              .debugDecoratedText
              .toPlainText(),
          'the quick fox jumps',
        );
      });

      testWidgets('a match across two lines is one rectangle for each line', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('quick fox');
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: const SizedBox(
                width: 150,
                child: Text('the quick fox jumps', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        );
        final RenderParagraph paragraph = tester.renderObject(find.byType(RichText));
        final List<Rect> boxes = paragraph
            .getBoxesForSelection(const TextSelection(baseOffset: 4, extentOffset: 13))
            .map((TextBox box) => box.toRect())
            .toList();
        expect(boxes.length, 2);
        expect(
          paragraph,
          paints
            ..rect(rect: boxes[0], color: _yellow)
            ..rect(rect: boxes[1], color: _yellow),
        );
      });

      testWidgets('in a text field', (WidgetTester tester) async {
        final plugin = _WordPlugin('fox');
        final controller = TextEditingController(text: 'the quick fox jumps');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: SizedBox(
                width: 400,
                child: EditableText(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
                  cursorColor: const Color(0xFF000000),
                  backgroundCursorColor: const Color(0xFF888888),
                ),
              ),
            ),
          ),
        );
        final RenderEditable editable = tester.allRenderObjects
            .whereType<RenderEditable>()
            .toSet()
            .single;
        expect(_hasBackground(editable.debugDecoratedText!), isFalse);
        final Rect box = editable
            .getBoxesForSelection(const TextSelection(baseOffset: 10, extentOffset: 13))
            .single
            .toRect();
        expect(editable, paints..rect(rect: box, color: _yellow));
      });
    });
  }
}
