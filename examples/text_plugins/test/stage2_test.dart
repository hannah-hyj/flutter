// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Stage 2 of the inline-span prototype: gestures, hover, cursors and
// semantics through the properties that a TextSpan already has.
//
// Each test is one row of the table in section 4 of
// text_plugins_inline_span_plan.md, and runs on both decoration layers.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/plugins/linkify_plugin.dart';
import 'package:text_plugins/plugins/search_in_page_plugin.dart';
import 'package:text_plugins/plugins/spoiler_mask_plugin.dart';

/// The offset of the middle of [substring] in the text that contains it.
Offset _centerOf(WidgetTester tester, String text, String substring) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText &&
          widget.text.toPlainText(includeSemanticsLabels: false) == text,
    ),
  );
  final int start = text.indexOf(substring);
  final List<TextBox> boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + substring.length),
  );
  return paragraph.localToGlobal(boxes.first.toRect().center);
}

Offset _centerInField(WidgetTester tester, String substring) {
  final EditableTextState state = tester.state<EditableTextState>(
    find.byType(EditableText),
  );
  final int start = state.textEditingValue.text.indexOf(substring);
  final RenderEditable editable = state.renderEditable;
  final List<TextBox> boxes = editable.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + substring.length),
  );
  return editable.localToGlobal(boxes.first.toRect().center);
}

void main() {
  for (final TextDecorationLayer layer in TextDecorationLayer.values) {
    group('$layer', () {
      late List<String> opened;
      late LinkifyPlugin linkify;

      setUp(() {
        debugDefaultTextDecorationLayer = layer;
        opened = <String>[];
        linkify = LinkifyPlugin(onOpen: opened.add);
      });
      tearDown(() {
        linkify.dispose();
        debugDefaultTextDecorationLayer = TextDecorationLayer.widget;
      });

      const text = 'See https://flutter.dev for more.';

      testWidgets('tap: a tap on a link opens it, a tap next to it does not', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TextPluginScope(
              plugin: linkify,
              child: const Center(child: Text(text)),
            ),
          ),
        );
        await tester.tapAt(_centerOf(tester, text, 'See'));
        expect(opened, isEmpty);
        await tester.tapAt(_centerOf(tester, text, 'flutter.dev'));
        expect(opened, <String>['https://flutter.dev']);
      });

      testWidgets(
        'arena: a drag that starts on a link scrolls and opens nothing',
        (WidgetTester tester) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope(
                plugin: linkify,
                child: ListView(
                  controller: controller,
                  children: const <Widget>[Text(text), SizedBox(height: 2000)],
                ),
              ),
            ),
          );
          await tester.dragFrom(
            _centerOf(tester, text, 'flutter.dev'),
            const Offset(0, -200),
          );
          await tester.pump();
          expect(controller.offset, greaterThan(100));
          expect(opened, isEmpty);
        },
      );

      testWidgets('hover: cursor and enter/exit callbacks', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TextPluginScope(
              plugin: linkify,
              child: const Center(child: Text(text)),
            ),
          ),
        );
        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: _centerOf(tester, text, 'See'));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.basic,
        );
        expect(linkify.hoveredUrl.value, isNull);

        await mouse.moveTo(_centerOf(tester, text, 'flutter.dev'));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );
        expect(linkify.hoveredUrl.value, 'https://flutter.dev');

        await mouse.moveTo(_centerOf(tester, text, 'more'));
        await tester.pump();
        expect(linkify.hoveredUrl.value, isNull);
      });

      testWidgets(
        'hover: a link that another plugin splits reports enter and exit for each piece',
        (WidgetTester tester) async {
          final search = SearchInPagePlugin();
          addTearDown(search.dispose);
          var enters = 0;
          var exits = 0;
          final counting = _HoverCountPlugin(
            const TextRange(start: 4, end: 23),
            () => enters += 1,
            () => exits += 1,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope.multiple(
                plugins: <TextPlugin>[counting, search],
                child: const Center(child: Text(text)),
              ),
            ),
          );
          // The search match "flutter" is in the middle of the range.
          search.query = 'flutter';
          await tester.pump();
          final TestGesture mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: _centerOf(tester, text, 'https'));
          await tester.pump();
          await mouse.moveTo(_centerOf(tester, text, 'flutter'));
          await tester.pump();
          await mouse.moveTo(_centerOf(tester, text, 'dev'));
          await tester.pump();
          await mouse.moveTo(_centerOf(tester, text, 'more'));
          await tester.pump();
          // One range, but three spans: the pointer entered and left each.
          expect(enters, 3);
          expect(exits, 3);
        },
      );

      testWidgets(
        'semantics: a link is its own node with a tap action and the link flag, without a URL',
        (WidgetTester tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope(
                plugin: linkify,
                child: const Center(child: Text(text)),
              ),
            ),
          );
          final SemanticsNode root = tester.getSemantics(find.byType(RichText));
          final children = <SemanticsNode>[];
          root.visitChildren((SemanticsNode node) {
            children.add(node);
            return true;
          });
          expect(children.map((SemanticsNode node) => node.label), <String>[
            'See ',
            'https://flutter.dev',
            ' for more.',
          ]);
          final SemanticsData link = children[1].getSemanticsData();
          expect(link.hasAction(SemanticsAction.tap), isTrue);
          // A span with a recognizer is announced as a link. It cannot say
          // which URL it has.
          expect(link.flagsCollection.isLink, isTrue);
          expect(link.linkUrl, isNull);

          children[1].owner!.performAction(children[1].id, SemanticsAction.tap);
          expect(opened, <String>['https://flutter.dev']);
          handle.dispose();
        },
      );

      testWidgets('focus: Tab does not reach a link', (
        WidgetTester tester,
      ) async {
        final before = FocusNode();
        final after = FocusNode();
        addTearDown(before.dispose);
        addTearDown(after.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: TextPluginScope(
              plugin: linkify,
              child: Column(
                children: <Widget>[
                  Focus(
                    focusNode: before,
                    child: const SizedBox(width: 10, height: 10),
                  ),
                  const Text(text),
                  Focus(
                    focusNode: after,
                    child: const SizedBox(width: 10, height: 10),
                  ),
                ],
              ),
            ),
          ),
        );
        before.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        // The focus goes from the widget before the text to the widget after
        // it. A span has no focus node, so the link is skipped.
        expect(after.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(opened, isEmpty);
      });

      testWidgets(
        'two plugins on one range: only the one on top gets the tap',
        (WidgetTester tester) async {
          var low = 0;
          var high = 0;
          final lowPlugin = _TapPlugin(
            const TextRange(start: 0, end: 3),
            () => low += 1,
          );
          final highPlugin = _HighTapPlugin(
            const TextRange(start: 0, end: 3),
            () => high += 1,
          );
          addTearDown(lowPlugin.dispose);
          addTearDown(highPlugin.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope.multiple(
                plugins: <TextPlugin>[lowPlugin, highPlugin],
                child: const Center(child: Text(text)),
              ),
            ),
          );
          await tester.tapAt(_centerOf(tester, text, 'See'));
          // There is one recognizer on a span. The lower plugin is not in the
          // arena at all.
          expect(high, 1);
          expect(low, 0);
        },
      );

      testWidgets(
        'a spoiler over a link: the first tap reveals, the second opens',
        (WidgetTester tester) async {
          final spoiler = SpoilerMaskPlugin();
          addTearDown(spoiler.dispose);
          const hidden = 'Answer: ||https://flutter.dev|| ok';
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope.multiple(
                plugins: <TextPlugin>[linkify, spoiler],
                child: const Center(child: Text(hidden)),
              ),
            ),
          );
          await tester.tapAt(_centerOf(tester, hidden, 'flutter.dev'));
          await tester.pump();
          expect(opened, isEmpty);
          await tester.tapAt(_centerOf(tester, hidden, 'flutter.dev'));
          await tester.pump();
          expect(opened, <String>['https://flutter.dev']);
        },
      );

      testWidgets(
        'a spoiler: a screen reader hears the label until it is revealed',
        (WidgetTester tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final spoiler = SpoilerMaskPlugin();
          addTearDown(spoiler.dispose);
          const hidden = 'The butler ||did it|| again';
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope(
                plugin: spoiler,
                child: const Center(child: Text(hidden)),
              ),
            ),
          );
          String spoken() {
            final labels = <String>[];
            final SemanticsNode root = tester.getSemantics(
              find.byType(RichText),
            );
            if (root.childrenCount == 0) {
              return root.label;
            }
            root.visitChildren((SemanticsNode node) {
              labels.add(node.label);
              return true;
            });
            return labels.join();
          }

          expect(spoken(), 'The butler Spoiler, hidden again');
          await tester.tapAt(_centerOf(tester, hidden, 'did it'));
          await tester.pump();
          expect(spoken(), 'The butler did it again');
          handle.dispose();
        },
      );

      testWidgets(
        'a spoiler: the delimiters take no room, which changes the layout',
        (WidgetTester tester) async {
          const hidden = 'The butler ||did it|| again';
          const plain = 'The butler did it again';
          final spoiler = SpoilerMaskPlugin();
          addTearDown(spoiler.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Column(
                children: <Widget>[
                  TextPluginScope(plugin: spoiler, child: const Text(hidden)),
                  const Text(plain),
                ],
              ),
            ),
          );
          final double withSpoiler = tester.getSize(find.text(hidden)).width;
          final double withoutDelimiters = tester
              .getSize(find.text(plain))
              .width;
          expect(tester.takeException(), isNull);
          expect(withSpoiler, closeTo(withoutDelimiters, 0.5));
        },
      );

      testWidgets('a plugin over a recognizer of the app', (
        WidgetTester tester,
      ) async {
        var appTaps = 0;
        final appTap = TapGestureRecognizer()..onTap = () => appTaps += 1;
        addTearDown(appTap.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: TextPluginScope(
              plugin: linkify,
              child: Center(
                child: Text.rich(TextSpan(text: text, recognizer: appTap)),
              ),
            ),
          ),
        );
        await tester.tapAt(_centerOf(tester, text, 'See'));
        await tester.tapAt(_centerOf(tester, text, 'more'));
        expect(appTaps, 2);
        expect(opened, isEmpty);
        // On the link the plugin wins, and the app does not get the tap.
        await tester.tapAt(_centerOf(tester, text, 'flutter.dev'));
        expect(appTaps, 2);
        expect(opened, <String>['https://flutter.dev']);
      });

      testWidgets(
        'a link in a text field that can be edited is styled but cannot be opened',
        (WidgetTester tester) async {
          final controller = TextEditingController(text: text);
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: TextPluginScope(
                  plugin: linkify,
                  child: Center(child: TextField(controller: controller)),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.tapAt(_centerInField(tester, 'flutter.dev'));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          expect(opened, isEmpty);
          expect(controller.text, text);
        },
      );

      for (final (String name, bool readOnly, TargetPlatform platform)
          in <(String, bool, TargetPlatform)>[
            ('read-only field', true, TargetPlatform.android),
            ('editable field on macOS', false, TargetPlatform.macOS),
          ]) {
        testWidgets(
          'a link in a $name: a click places the caret, a modifier click opens',
          (WidgetTester tester) async {
            debugDefaultTargetPlatformOverride = platform;
            final controller = TextEditingController(text: text);
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                home: Material(
                  child: TextPluginScope(
                    plugin: linkify,
                    child: Center(
                      child: TextField(
                        controller: controller,
                        readOnly: readOnly,
                      ),
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final Offset link = _centerInField(tester, 'flutter.dev');
            final TestGesture mouse = await tester.startGesture(
              link,
              kind: PointerDeviceKind.mouse,
            );
            addTearDown(mouse.removePointer);
            await mouse.up();
            await tester.pump();
            expect(opened, isEmpty);
            // The click still did what a click in a field does.
            expect(controller.selection.isValid, isTrue);
            expect(controller.selection.baseOffset, inInclusiveRange(4, 23));

            await tester.pump(kDoubleTapTimeout);
            await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
            await mouse.down(link);
            await mouse.up();
            await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
            await tester.pump();
            expect(opened, <String>['https://flutter.dev']);
            // The text of the field is not changed by the decoration.
            expect(controller.text, text);
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }

      testWidgets(
        'a link in a SelectionArea: a click does not open, a double click selects',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope(
                plugin: linkify,
                child: const SelectionArea(child: Center(child: Text(text))),
              ),
            ),
          );
          final Offset link = _centerOf(tester, text, 'flutter');
          final TestGesture mouse = await tester.startGesture(
            link,
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.up();
          await tester.pump();
          expect(opened, isEmpty);

          await tester.pump(const Duration(milliseconds: 50));
          await mouse.down(link);
          await tester.pump();
          await mouse.up();
          await tester.pump();
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(find.byType(RichText));
          expect(paragraph.selections, isNotEmpty);
          expect(paragraph.selections.first.isCollapsed, isFalse);
          expect(opened, isEmpty);

          await tester.pump(kDoubleTapTimeout);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await mouse.down(link);
          await mouse.up();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          expect(opened, <String>['https://flutter.dev']);
        },
      );

      testWidgets(
        'an ordinary tap recognizer on a span takes the double click from the selection',
        (WidgetTester tester) async {
          var taps = 0;
          final plugin = _TapPlugin(
            const TextRange(start: 4, end: 23),
            () => taps += 1,
          );
          addTearDown(plugin.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: TextPluginScope(
                plugin: plugin,
                child: const SelectionArea(child: Center(child: Text(text))),
              ),
            ),
          );
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(find.byType(RichText));
          // A double click next to the range selects a word.
          final Offset outside = _centerOf(tester, text, 'more');
          final TestGesture mouse = await tester.startGesture(
            outside,
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.up();
          await tester.pump(const Duration(milliseconds: 50));
          await mouse.down(outside);
          await tester.pump();
          await mouse.up();
          await tester.pump();
          expect(paragraph.selections.first.isCollapsed, isFalse);
          final List<TextSelection> before = paragraph.selections;

          // A double click on the range does not: the recognizer of the span is
          // the first in the arena and wins both taps.
          await tester.pump(kDoubleTapTimeout);
          final Offset inside = _centerOf(tester, text, 'flutter');
          await mouse.down(inside);
          await mouse.up();
          await tester.pump(const Duration(milliseconds: 50));
          await mouse.down(inside);
          await tester.pump();
          await mouse.up();
          await tester.pump();
          expect(taps, 2);
          expect(paragraph.selections, before);
        },
      );
    });
  }

  test('a recognizer in a text field that can be edited is rejected by RenderEditable', () {
    // This is why a link plugin cannot make a link tappable in an editable
    // field by giving the span a recognizer. The check is in the framework,
    // not in the prototype.
    final tap = TapGestureRecognizer();
    addTearDown(tap.dispose);
    RenderEditable editable({required bool readOnly}) => RenderEditable(
      text: TextSpan(text: 'a link', recognizer: tap),
      readOnly: readOnly,
      textDirection: TextDirection.ltr,
      offset: ViewportOffset.zero(),
      startHandleLayerLink: LayerLink(),
      endHandleLayerLink: LayerLink(),
      textSelectionDelegate: _FakeTextSelectionDelegate(),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      () =>
          editable(readOnly: false)
              .describeSemanticsConfiguration(SemanticsConfiguration()),
      throwsAssertionError,
    );
    editable(readOnly: true)
        .describeSemanticsConfiguration(SemanticsConfiguration());
    // macOS is the exception: there the recognizer is ignored for semantics.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    editable(readOnly: false)
        .describeSemanticsConfiguration(SemanticsConfiguration());
    debugDefaultTargetPlatformOverride = null;
  });
}

class _FakeTextSelectionDelegate extends Fake
    implements TextSelectionDelegate {}

class _TapPlugin extends TextPlugin {
  _TapPlugin(this.range, VoidCallback onTap) {
    _recognizer.onTap = onTap;
  }

  final TextRange range;
  final TapGestureRecognizer _recognizer = TapGestureRecognizer();

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    return <TextSpanDecoration>[
      TextSpanDecoration(range: range, recognizer: _recognizer),
    ];
  }

  void dispose() => _recognizer.dispose();
}

class _HighTapPlugin extends _TapPlugin {
  _HighTapPlugin(super.range, super.onTap);

  @override
  int get paintOrder => 1;
}

class _HoverCountPlugin extends TextPlugin {
  _HoverCountPlugin(this.range, this.onEnter, this.onExit);

  final TextRange range;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: range,
        onEnter: (PointerEnterEvent event) => onEnter(),
        onExit: (PointerExitEvent event) => onExit(),
      ),
    ];
  }
}
