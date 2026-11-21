// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Stage 3 of the inline-span prototype: widgets on text, three ways.
//
//  * S1: a WidgetSpan replaces the range.
//  * S2: a WidgetSpan of no size is inserted at the start of the range.
//  * S3: a host around the text places a widget on the range.
//
// Each test is one cell of the tables in section 5 of
// text_plugins_inline_span_plan.md. A test that is named "cannot" shows a
// limit, and passes when the limit is there.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/plugins/search_in_page_plugin.dart';
import 'package:text_plugins/plugins/stage3_plugins.dart';

const String _placeholder = '\uFFFC';

Widget _app(Widget child) {
  return MaterialApp(
    home: Material(
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// The paragraph whose text, without placeholders, is [text].
RenderParagraph _paragraph(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(
    find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText &&
          widget.text
                  .toPlainText(includeSemanticsLabels: false)
                  .replaceAll(_placeholder, '') ==
              text,
    ),
  );
}

String _laidOutText(RenderParagraph paragraph) {
  return paragraph.debugDecoratedText.toPlainText(
    includeSemanticsLabels: false,
  );
}

/// The boxes of [substring] in the text that is laid out, in global
/// coordinates.
List<Rect> _boxesOf(RenderParagraph paragraph, String substring) {
  final int start = _laidOutText(paragraph).indexOf(substring);
  return <Rect>[
    for (final TextBox box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + substring.length),
    ))
      MatrixUtils.transformRect(paragraph.getTransformTo(null), box.toRect()),
  ];
}

Rect _boundsOf(RenderParagraph paragraph, String substring) {
  return _boxesOf(
    paragraph,
    substring,
  ).reduce((Rect a, Rect b) => a.expandToInclude(b));
}

List<String> _highlighted(InlineSpan root, Color color) {
  final out = <String>[];
  void visit(InlineSpan span, Color? inherited) {
    if (span is TextSpan) {
      final Color? background = span.style?.backgroundColor ?? inherited;
      if (span.text != null && background == color) {
        out.add(span.text!);
      }
      span.children?.forEach((InlineSpan child) => visit(child, background));
    }
  }

  visit(root, null);
  return out;
}

/// Drags a mouse over the whole of [finder] and returns what was selected.
Future<String?> _selectAcross(
  WidgetTester tester,
  Finder finder,
  ValueGetter<String?> content,
) async {
  final Rect rect = tester.getRect(finder);
  final TestGesture mouse = await tester.startGesture(
    rect.centerLeft + const Offset(1, 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await mouse.moveTo(rect.center);
  await tester.pump();
  await mouse.moveTo(rect.centerRight - const Offset(1, 0));
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
  return content();
}

void main() {
  setUp(() {
    debugDefaultTextDecorationLayer = TextDecorationLayer.widget;
  });

  group('mention chip', () {
    const text = 'hi @alice, bye';

    testWidgets('S1: the chip replaces the name and can be tapped', (
      WidgetTester tester,
    ) async {
      final tapped = <String>[];
      final plugin = MentionPlugin(
        Stage3Way.inlineReplacement,
        onTap: tapped.add,
      );
      late TextDelegate delegate;
      final recorder = _DelegateRecorder((TextDelegate d) => delegate = d);
      await tester.pumpWidget(
        _app(
          TextPluginScope.multiple(
            plugins: <TextPlugin>[plugin, recorder],
            child: const Text(text),
          ),
        ),
      );
      final RenderParagraph paragraph = _paragraph(tester, 'hi , bye');
      // The text that is laid out is a different string: the name is one
      // placeholder. The plugins still see the original.
      expect(_laidOutText(paragraph), 'hi $_placeholder, bye');
      expect(delegate.text, text);
      await tester.tap(find.byType(MentionChip));
      expect(tapped, <String>['alice']);
    });

    testWidgets(
      'S1, H5: the range of another plugin, after the chip, is on the right characters',
      (WidgetTester tester) async {
        final search = SearchInPagePlugin()..query = 'bye';
        addTearDown(search.dispose);
        final plugin = MentionPlugin(
          Stage3Way.inlineReplacement,
          onTap: (String name) {},
        );
        await tester.pumpWidget(
          _app(
            TextPluginScope.multiple(
              plugins: <TextPlugin>[plugin, search],
              child: const Text(text),
            ),
          ),
        );
        await tester.pump();
        final RenderParagraph paragraph = _paragraph(tester, 'hi , bye');
        // The search plugin computed 11..14 in "hi @alice, bye". In the text
        // that is laid out, "bye" is at 6..9. The framework did the mapping.
        expect(
          _highlighted(
            paragraph.debugDecoratedText,
            search.activeMatchBackgroundColor,
          ),
          <String>['bye'],
        );
        // ensureVisible and selections map through the same table.
        expect(
          search.matches.single.range,
          const TextRange(start: 11, end: 14),
        );
      },
    );

    for (final (MentionKeys keys, int alice, int bob, String what)
        in <(MentionKeys, int, int, String)>[
          (MentionKeys.none, 1, 0, 'the state moves to the wrong chip'),
          (MentionKeys.value, 0, 0, 'the state is lost'),
          (MentionKeys.global, 0, 1, 'the state is kept'),
        ]) {
      testWidgets(
        'S1, H11: a chip is added before a chip with state, ${keys.name} key: $what',
        (WidgetTester tester) async {
          final plugin = MentionPlugin(
            Stage3Way.inlineReplacement,
            onTap: (String name) {},
            keys: keys,
          );
          Widget build(String value) =>
              _app(TextPluginScope(plugin: plugin, child: Text(value)));
          await tester.pumpWidget(build('hi @bob'));
          await tester.tap(find.byType(MentionChip));
          await tester.pump();
          expect(
            tester.state<MentionChipState>(find.byType(MentionChip)).taps,
            1,
          );

          await tester.pumpWidget(build('@alice hi @bob'));
          MentionChipState chip(String name) => tester.state<MentionChipState>(
            find.byWidgetPredicate(
              (Widget w) => w is MentionChip && w.name == name,
            ),
          );
          expect(chip('alice').taps, alice);
          expect(chip('bob').taps, bob);
        },
      );
    }

    testWidgets('S1: what a selection across the chip copies', (
      WidgetTester tester,
    ) async {
      final plugin = MentionPlugin(
        Stage3Way.inlineReplacement,
        onTap: (String name) {},
      );
      String? content;
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SelectionArea(
              onSelectionChanged: (SelectedContent? value) =>
                  content = value?.plainText,
              child: const Text(text),
            ),
          ),
        ),
      );
      final String? selected = await _selectAcross(
        tester,
        find.byType(RichText).first,
        () => content,
      );
      debugPrint('STAGE3 S1 selection across a chip copies: "$selected"');
      // The paragraph is two fragments now, around the placeholder. What is
      // copied for the name is the label of the chip, which is a selectable
      // of its own. Here the label happens to be the name.
      expect(selected, text);
    });

    testWidgets('S1 cannot: in a text field the chip is not used', (
      WidgetTester tester,
    ) async {
      final plugin = MentionPlugin(
        Stage3Way.inlineReplacement,
        onTap: (String name) {},
      );
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SizedBox(
              width: 300,
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // A replacement would make the text of the field a different string,
      // so the framework drops it.
      expect(find.byType(MentionChip), findsNothing);
      final RenderEditable editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(editable.debugDecoratedText!.toPlainText(), text);
    });

    testWidgets('S1 cannot: in the render layer a replacement is rejected', (
      WidgetTester tester,
    ) async {
      debugDefaultTextDecorationLayer = TextDecorationLayer.render;
      final plugin = MentionPlugin(
        Stage3Way.inlineReplacement,
        onTap: (String name) {},
      );
      await tester.pumpWidget(
        _app(TextPluginScope(plugin: plugin, child: const Text(text))),
      );
      final Object? exception = tester.takeException();
      expect(exception, isAssertionError);
      expect(exception.toString(), contains('TextDecorationLayer.widget'));
      expect(find.byType(MentionChip), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'S2: the chip floats at the start of the name and can be tapped',
      (WidgetTester tester) async {
        final tapped = <String>[];
        final plugin = MentionPlugin(Stage3Way.anchor, onTap: tapped.add);
        await tester.pumpWidget(
          _app(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 40),
                TextPluginScope(plugin: plugin, child: const Text(text)),
                const Text(text),
              ],
            ),
          ),
        );
        await tester.pump();
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText).first,
        );
        // The name is still text. The anchor is one more code unit before it.
        expect(_laidOutText(paragraph), 'hi $_placeholder@alice, bye');
        // An anchor of no size does not change the size of the text.
        final RenderParagraph plain = tester.renderObject<RenderParagraph>(
          find.byType(RichText).last,
        );
        expect(paragraph.size, plain.size);

        final Rect name = _boundsOf(paragraph, '@alice');
        final Rect chip = tester.getRect(find.byType(MentionChip));
        expect(chip.left, closeTo(name.left, 0.5));
        // The chip has its own size. It does not know the size of the name.
        debugPrint('STAGE3 S2 chip $chip over name $name');
        await tester.tap(find.byType(MentionChip));
        expect(tapped, <String>['alice']);
      },
    );

    testWidgets('S2 cannot: in a text field the anchor is not used', (
      WidgetTester tester,
    ) async {
      final plugin = MentionPlugin(Stage3Way.anchor, onTap: (String name) {});
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SizedBox(
              width: 300,
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MentionChip), findsNothing);
    });

    testWidgets('S3: the chip covers the name, the text is not changed', (
      WidgetTester tester,
    ) async {
      final tapped = <String>[];
      final plugin = MentionPlugin(Stage3Way.positioned, onTap: tapped.add);
      String? content;
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SelectionArea(
              onSelectionChanged: (SelectedContent? value) =>
                  content = value?.plainText,
              child: const Text(text),
            ),
          ),
        ),
      );
      final RenderParagraph paragraph = _paragraph(tester, text);
      expect(_laidOutText(paragraph), text);
      final Rect name = _boundsOf(paragraph, '@alice');
      final Rect chip = tester.getRect(find.byType(MentionChip));
      expect(chip.left, closeTo(name.left, 0.01));
      expect(chip.top, closeTo(name.top, 0.01));
      expect(chip.size.width, closeTo(name.width, 0.01));
      expect(chip.size.height, closeTo(name.height, 0.01));
      await tester.tap(find.byType(MentionChip));
      expect(tapped, <String>['alice']);

      // A selection across the chip copies the whole text.
      final String? selected = await _selectAcross(
        tester,
        find.byType(RichText).first,
        () => content,
      );
      // The chip is not selectable. If it were, the name would be copied
      // twice: once from the text and once from the label of the chip.
      expect(selected, text);
    });

    testWidgets('S3: the chip is also on a name in a text field', (
      WidgetTester tester,
    ) async {
      final tapped = <String>[];
      final plugin = MentionPlugin(Stage3Way.positioned, onTap: tapped.add);
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SizedBox(
              width: 300,
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MentionChip), findsOneWidget);
      final RenderEditable editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final Rect name = MatrixUtils.transformRect(
        editable.getTransformTo(null),
        editable
            .getBoxesForSelection(
              const TextSelection(baseOffset: 3, extentOffset: 9),
            )
            .first
            .toRect(),
      );
      final Rect chip = tester.getRect(find.byType(MentionChip));
      expect(chip.left, closeTo(name.left, 0.01));
      expect(chip.width, closeTo(name.width, 0.01));
      await tester.tap(find.byType(MentionChip));
      expect(tapped, <String>['alice']);
      expect(controller.text, text);

      // Typing before the name moves the chip with it.
      controller.text = 'oh hi @alice, bye';
      await tester.pump();
      expect(
        tester.getRect(find.byType(MentionChip)).left,
        greaterThan(chip.left),
      );
    });

    testWidgets('S3 cannot: in the render layer no widget is built', (
      WidgetTester tester,
    ) async {
      debugDefaultTextDecorationLayer = TextDecorationLayer.render;
      final plugin = MentionPlugin(
        Stage3Way.positioned,
        onTap: (String name) {},
      );
      await tester.pumpWidget(
        _app(TextPluginScope(plugin: plugin, child: const Text(text))),
      );
      // The host of the widgets is the widget that owns the delegates, and
      // the render layer has no such widget.
      expect(find.byType(MentionChip), findsNothing);
    });
  });

  group('suggestion menu', () {
    const text = 'Fix teh typo here.';

    Future<(SuggestionMenuPlugin, List<String>, List<String>)> pump(
      WidgetTester tester,
      Stage3Way way,
    ) async {
      final accepted = <String>[];
      final below = <String>[];
      final plugin = SuggestionMenuPlugin(
        way,
        onAccept: (TextDelegate delegate, TextRange range) =>
            accepted.add(range.textInside(text)),
      );
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextPluginScope(plugin: plugin, child: const Text(text)),
              GestureDetector(
                key: const Key('below'),
                onTap: () => below.add('tap'),
                child: Container(
                  width: 300,
                  height: 100,
                  color: const Color(0xFFEEEEEE),
                ),
              ),
            ],
          ),
        ),
      );
      return (plugin, accepted, below);
    }

    testWidgets(
      'S1 cannot: the menu is in the line, so it pushes the content below it down',
      (WidgetTester tester) async {
        final (SuggestionMenuPlugin plugin, List<String> accepted, _) =
            await pump(tester, Stage3Way.inlineReplacement);
        final double belowBefore = tester
            .getTopLeft(find.byKey(const Key('below')))
            .dy;
        await tester.tap(find.text('teh'));
        await tester.pump();
        expect(find.byType(SuggestionMenu), findsOneWidget);
        final double belowAfter = tester
            .getTopLeft(find.byKey(const Key('below')))
            .dy;
        // The line grew by the height of the menu. The menu does not float.
        expect(belowAfter - belowBefore, greaterThan(50));
        expect(
          tester.getRect(find.byType(SuggestionMenu)).bottom,
          lessThanOrEqualTo(belowAfter + 0.01),
        );
        await tester.tap(find.byType(SuggestionMenu));
        expect(accepted, <String>['teh']);
        expect(plugin.isOpen, isFalse);
      },
    );

    for (final way in <Stage3Way>[Stage3Way.anchor, Stage3Way.positioned]) {
      testWidgets(
        '${way.name}: the menu floats over the content below and takes its tap',
        (WidgetTester tester) async {
          final (
            SuggestionMenuPlugin plugin,
            List<String> accepted,
            List<String> below,
          ) = await pump(
            tester,
            way,
          );
          final RenderParagraph paragraph = _paragraph(tester, text);
          final Size sizeBefore = paragraph.size;
          final double belowBefore = tester
              .getTopLeft(find.byKey(const Key('below')))
              .dy;
          await tester.tapAt(_boundsOf(paragraph, 'teh').center);
          await tester.pump();
          await tester.pump();
          expect(find.byType(SuggestionMenu), findsOneWidget);
          // Nothing moved.
          expect(paragraph.size, sizeBefore);
          expect(
            tester.getTopLeft(find.byKey(const Key('below'))).dy,
            belowBefore,
          );
          // The menu is under the word, over the content below the text.
          final Rect word = _boundsOf(paragraph, 'teh');
          final Rect menu = tester.getRect(find.byType(SuggestionMenu));
          expect(menu.left, closeTo(word.left, 0.5));
          expect(menu.top, greaterThanOrEqualTo(word.top));
          expect(menu.bottom, greaterThan(belowBefore + 20));
          await tester.tapAt(menu.bottomLeft + const Offset(10, -10));
          await tester.pump();
          expect(accepted, <String>['teh']);
          expect(below, isEmpty);
          expect(plugin.isOpen, isFalse);
          await tester.pump();
          expect(find.byType(SuggestionMenu), findsNothing);
        },
      );
    }

    for (final (Stage3Way way, bool works) in <(Stage3Way, bool)>[
      (Stage3Way.anchor, false),
      (Stage3Way.positioned, true),
    ]) {
      testWidgets(
        '${way.name}: a menu in a text field ${works ? 'works' : 'cannot be shown'}',
        (WidgetTester tester) async {
          final accepted = <String>[];
          final plugin = SuggestionMenuPlugin(
            way,
            onAccept: (TextDelegate delegate, TextRange range) =>
                accepted.add(range.textInside(text)),
          );
          addTearDown(plugin.dispose);
          final controller = TextEditingController(text: text);
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _app(
              TextPluginScope(
                plugin: plugin,
                child: SizedBox(
                  width: 300,
                  child: TextField(controller: controller),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          plugin.openFirst();
          await tester.pump();
          await tester.pump();
          expect(
            find.byType(SuggestionMenu),
            works ? findsOneWidget : findsNothing,
          );
          if (works) {
            await tester.tap(find.byType(SuggestionMenu));
            expect(accepted, <String>['teh']);
          }
          expect(controller.text, text);
        },
      );
    }

    testWidgets('S3: opening a menu builds the widgets of that text only', (
      WidgetTester tester,
    ) async {
      final plugin = SuggestionMenuPlugin(
        Stage3Way.positioned,
        onAccept: (TextDelegate delegate, TextRange range) {},
      );
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Fix teh first.'),
                Text('And teh second.'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final Map<String, int> before = Map<String, int>.of(plugin.widgetBuilds);
      final RenderParagraph first = _paragraph(tester, 'Fix teh first.');
      await tester.tapAt(_boundsOf(first, 'teh').center);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SuggestionMenu), findsOneWidget);
      // On the stage 3 branch, opening one menu built the widgets of every
      // text again. Here only the text that asked is built again.
      expect(plugin.widgetBuilds['And teh second.'], before['And teh second.']);
      expect(
        plugin.widgetBuilds['Fix teh first.'],
        greaterThan(before['Fix teh first.']!),
      );
    });
  });

  group('frosted spoiler', () {
    const short = 'He said {{boo}} then.';
    const long = 'The ending: {{one two three four five six seven}} and more.';

    testWidgets(
      'S1: the words are blurred by a widget, and a tap puts the text back',
      (WidgetTester tester) async {
        final plugin = FrostedSpoilerPlugin(Stage3Way.inlineReplacement);
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text(short))),
        );
        expect(find.byType(ImageFiltered), findsOneWidget);
        expect(
          _laidOutText(_paragraph(tester, 'He said  then.')),
          'He said $_placeholder then.',
        );
        await tester.tap(find.byKey(const ValueKey<String>('spoiler boo')));
        await tester.pump();
        expect(find.byType(ImageFiltered), findsNothing);
        expect(_laidOutText(_paragraph(tester, short)), short);
      },
    );

    testWidgets(
      'S1 cannot: a spoiler that is longer than the line does not wrap with the line',
      (WidgetTester tester) async {
        final plugin = FrostedSpoilerPlugin(Stage3Way.inlineReplacement);
        await tester.pumpWidget(
          _app(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: TextPluginScope(
                    plugin: plugin,
                    child: const Text(long),
                  ),
                ),
                const SizedBox(width: 300, child: Text(long)),
              ],
            ),
          ),
        );
        final Size withSpoiler = tester.getSize(find.byType(RichText).first);
        final Size plain = tester.getSize(find.byType(RichText).last);
        final Rect block = tester.getRect(
          find.byKey(
            const ValueKey<String>('spoiler one two three four five six seven'),
          ),
        );
        final Rect line = tester.getRect(find.byType(RichText).first);
        debugPrint(
          'STAGE3 S1 wrapped spoiler: text $withSpoiler, plain $plain, block $block',
        );
        // The spoiler is one box. In the plain text it starts on the first
        // line, after "The ending:". As a box it does not fit there, so it
        // starts on the next line, at the left edge.
        final RenderParagraph plainParagraph = tester
            .renderObject<RenderParagraph>(find.byType(RichText).last);
        expect(
          _boxesOf(plainParagraph, '{{one').first.top,
          tester.getRect(find.byType(RichText).last).top,
        );
        expect(block.left, closeTo(line.left, 0.5));
        expect(block.top, greaterThan(line.top));
        expect(withSpoiler, isNot(plain));
      },
    );

    testWidgets(
      'S3: the cover is on the range, the text is not changed, and a tap reveals',
      (WidgetTester tester) async {
        final plugin = FrostedSpoilerPlugin(Stage3Way.positioned);
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text(short))),
        );
        final RenderParagraph paragraph = _paragraph(tester, short);
        expect(_laidOutText(paragraph), short);
        expect(find.byType(BackdropFilter), findsOneWidget);
        final Rect cover = tester.getRect(find.byType(BackdropFilter));
        final Rect range = _boundsOf(paragraph, '{{boo}}');
        expect(cover.left, closeTo(range.left, 0.01));
        expect(cover.width, closeTo(range.width, 0.01));
        await tester.tapAt(cover.center);
        await tester.pump();
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );

    testWidgets(
      'S3: a spoiler on two lines is covered by one box, which also covers other words',
      (WidgetTester tester) async {
        final plugin = FrostedSpoilerPlugin(Stage3Way.positioned);
        await tester.pumpWidget(
          _app(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 200,
                  child: TextPluginScope(
                    plugin: plugin,
                    child: const Text(long),
                  ),
                ),
                const SizedBox(width: 200, child: Text(long)),
              ],
            ),
          ),
        );
        // The text wraps exactly as it does without the plugin.
        expect(
          tester.getSize(find.byType(RichText).first),
          tester.getSize(find.byType(RichText).last),
        );
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText).first,
        );
        final List<Rect> boxes = _boxesOf(
          paragraph,
          '{{one two three four five six seven}}',
        );
        expect(boxes.length, greaterThan(1));
        final double rangeArea = boxes.fold(
          0,
          (double sum, Rect box) => sum + box.width * box.height,
        );
        final Rect cover = tester.getRect(find.byType(BackdropFilter));
        // The stage 3 branch gives the plugin the layout, so that it can put
        // one cover on each line. This small host has the bounding box only.
        expect(cover.width * cover.height, greaterThan(rangeArea));
      },
    );

    testWidgets('S3: the cover is also on a range in a text field', (
      WidgetTester tester,
    ) async {
      final plugin = FrostedSpoilerPlugin(Stage3Way.positioned);
      final controller = TextEditingController(text: short);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SizedBox(
              width: 300,
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(controller.text, short);
    });

    testWidgets('S1 cannot: in a text field the spoiler is not covered', (
      WidgetTester tester,
    ) async {
      final plugin = FrostedSpoilerPlugin(Stage3Way.inlineReplacement);
      final controller = TextEditingController(text: short);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          TextPluginScope(
            plugin: plugin,
            child: SizedBox(
              width: 300,
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ImageFiltered), findsNothing);
    });
  });
}

/// Hands the delegate of the last text that was added to [onDelegate].
class _DelegateRecorder extends TextPlugin {
  _DelegateRecorder(this.onDelegate);

  final ValueChanged<TextDelegate> onDelegate;

  @override
  void didAddText(TextDelegate delegate) => onDelegate(delegate);
}
