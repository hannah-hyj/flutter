// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Tests for the inline-span prototype of text plugins. Every test runs once
// for each TextDecorationLayer: widget (Option A) and render (Option B).

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _yellow = Color(0xFFFFFF00);
const Color _orange = Color(0xFFFF8800);

/// Highlights every occurrence of [word].
class _WordPlugin extends TextPlugin {
  _WordPlugin(this.word, {this.order = 0, this.color = _yellow});

  String word;
  final int order;
  final Color color;
  final List<String> log = <String>[];
  final Set<TextDelegate> delegates = <TextDelegate>{};

  @override
  int get paintOrder => order;

  @override
  void didAddText(TextDelegate delegate) {
    delegates.add(delegate);
    log.add('add:${delegate.text}');
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    log.add('update:${delegate.text}');
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegates.remove(delegate);
    log.add('remove:${delegate.text}');
  }

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    log.add('build:${delegate.text}');
    if (word.isEmpty) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      for (final Match match in word.allMatches(delegate.text))
        TextSpanDecoration(
          range: TextRange(start: match.start, end: match.end),
          style: TextStyle(backgroundColor: color),
        ),
    ];
  }

  /// Changes the word and updates only the texts whose matches can change.
  void setWord(String value) {
    final String old = word;
    word = value;
    for (final TextDelegate delegate in delegates.toList()) {
      if ((old.isNotEmpty && delegate.text.contains(old)) ||
          (value.isNotEmpty && delegate.text.contains(value))) {
        delegate.markNeedsDecoration();
      }
    }
  }

  List<String> get texts => delegates.map((TextDelegate d) => d.text).toList()..sort();
}

class _OtherWordPlugin extends _WordPlugin {
  _OtherWordPlugin(super.word, {super.order, super.color});
}

/// The texts of the leaf spans that have [color] as background.
List<String> _highlighted(InlineSpan root, [Color color = _yellow]) {
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

RenderParagraph _paragraph(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(
    find.byWidgetPredicate(
      (Widget widget) => widget is RichText && widget.text.toPlainText() == text,
      skipOffstage: false,
    ),
  );
}

List<String> _highlightedIn(WidgetTester tester, String text, [Color color = _yellow]) {
  return _highlighted(_paragraph(tester, text).debugDecoratedText, color);
}

Widget _app(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

void main() {
  for (final TextDecorationLayer layer in TextDecorationLayer.values) {
    group('$layer', () {
      setUp(() {
        debugDefaultTextDecorationLayer = layer;
      });
      tearDown(() {
        debugDefaultTextDecorationLayer = TextDecorationLayer.widget;
      });

      testWidgets('a plugin decorates the text, and the lifecycle runs before buildDecorations', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('world');
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('hello world'))),
        );
        expect(_highlightedIn(tester, 'hello world'), <String>['world']);
        expect(_paragraph(tester, 'hello world').text.toPlainText(), 'hello world');
        expect(plugin.log, <String>['add:hello world', 'build:hello world']);

        plugin.log.clear();
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('a new world'))),
        );
        expect(plugin.log, <String>['update:a new world', 'build:a new world']);
        expect(_highlightedIn(tester, 'a new world'), <String>['world']);

        plugin.log.clear();
        await tester.pumpWidget(_app(const SizedBox()));
        expect(plugin.log, <String>['remove:a new world']);
        expect(plugin.delegates, isEmpty);
      });

      testWidgets('H6: a text without decorations is laid out with its own span', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('zzz');
        Widget build() => _app(TextPluginScope(plugin: plugin, child: const Text('hello world')));
        await tester.pumpWidget(build());
        final RenderParagraph paragraph = _paragraph(tester, 'hello world');
        expect(paragraph.debugDecoratedText, same(paragraph.text));

        // The scope is rebuilt with an equal text: nothing is dirty.
        await tester.pumpWidget(build());
        expect(paragraph.debugNeedsLayout, isFalse);
        expect(paragraph.debugNeedsPaint, isFalse);
      });

      testWidgets('markNeedsDecoration updates only the texts that it is called on', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('');
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: const Column(
                children: <Widget>[Text('one apple'), Text('two pears'), Text('three apples')],
              ),
            ),
          ),
        );
        expect(_highlightedIn(tester, 'one apple'), isEmpty);
        final RenderParagraph pears = _paragraph(tester, 'two pears');

        plugin.log.clear();
        final int builds = TextPluginSpanBuilder.debugBuildCount;
        plugin.setWord('apple');
        expect(pears.debugNeedsLayout, isFalse);
        await tester.pump();
        expect(_highlightedIn(tester, 'one apple'), <String>['apple']);
        expect(_highlightedIn(tester, 'three apples'), <String>['apple']);
        expect(_highlightedIn(tester, 'two pears'), isEmpty);
        expect(plugin.log, unorderedEquals(<String>['build:one apple', 'build:three apples']));
        // Option A rebuilds one widget for each of the two texts. Option B
        // builds no widget.
        expect(
          TextPluginSpanBuilder.debugBuildCount - builds,
          layer == TextDecorationLayer.widget ? 2 : 0,
        );
      });

      testWidgets('a color-only change of a decoration does not lay the text out again', (
        WidgetTester tester,
      ) async {
        final plugin = _ColorPlugin();
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('hello world'))),
        );
        final RenderParagraph paragraph = _paragraph(tester, 'hello world');
        expect(_highlighted(paragraph.debugDecoratedText), <String>['world']);

        plugin.color = _orange;
        plugin.delegate!.markNeedsDecoration();
        await tester.pump(null, EnginePhase.build);
        expect(paragraph.debugNeedsLayout, isFalse);
        expect(paragraph.debugNeedsPaint, isTrue);
        await tester.pump();
        expect(_highlighted(paragraph.debugDecoratedText, _orange), <String>['world']);
      });

      testWidgets('notifiesDecorationChanges: a notification asks every text again', (
        WidgetTester tester,
      ) async {
        final plugin = _NotifyingPlugin();
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: const Column(children: <Widget>[Text('one apple'), Text('two pears')]),
            ),
          ),
        );
        plugin.buildCount = 0;
        plugin.word = 'apple';
        plugin.notify();
        await tester.pump();
        expect(_highlightedIn(tester, 'one apple'), <String>['apple']);
        expect(plugin.buildCount, 2);
      });

      testWidgets('two plugins: the higher paintOrder wins an overlap', (WidgetTester tester) async {
        final low = _WordPlugin('hello world');
        final high = _OtherWordPlugin('lo wo', order: 1, color: _orange);
        await tester.pumpWidget(
          _app(
            TextPluginScope.multiple(
              plugins: <TextPlugin>[high, low],
              child: const Text('hello world'),
            ),
          ),
        );
        expect(_highlightedIn(tester, 'hello world'), <String>['hel', 'rld']);
        expect(_highlightedIn(tester, 'hello world', _orange), <String>['lo wo']);
      });

      testWidgets('H2: a selection survives a decoration change', (WidgetTester tester) async {
        final plugin = _WordPlugin('');
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await tester.pumpWidget(
          _app(
            Overlay(
              initialEntries: <OverlayEntry>[
                OverlayEntry(
                  builder: (BuildContext context) => TextPluginScope(
                    plugin: plugin,
                    child: SelectableRegion(
                      focusNode: focusNode,
                      selectionControls: emptyTextSelectionControls,
                      child: const Align(alignment: Alignment.topLeft, child: Text('hello world')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        final RenderParagraph paragraph = _paragraph(tester, 'hello world');
        final TestGesture gesture = await tester.startGesture(
          tester.getTopLeft(find.text('hello world')) + const Offset(1, 5),
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveTo(tester.getTopLeft(find.text('hello world')) + const Offset(60, 5));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        final List<TextSelection> before = paragraph.selections;
        expect(before, hasLength(1));
        expect(before.single.isCollapsed, isFalse);

        plugin.setWord('world');
        await tester.pump();
        expect(_highlighted(paragraph.debugDecoratedText), <String>['world']);
        expect(paragraph.selections, before);
      });

      testWidgets('the selection highlight as a text plugin', (WidgetTester tester) async {
        debugSelectionHighlightAsTextPlugin = true;
        addTearDown(() => debugSelectionHighlightAsTextPlugin = false);
        const selectionColor = Color(0xFF0000FF);
        final plugin = _WordPlugin('world');
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await tester.pumpWidget(
          _app(
            DefaultSelectionStyle(
              selectionColor: selectionColor,
              child: Overlay(
                initialEntries: <OverlayEntry>[
                  OverlayEntry(
                    builder: (BuildContext context) => TextPluginScope(
                      plugin: plugin,
                      child: SelectableRegion(
                        focusNode: focusNode,
                        selectionControls: emptyTextSelectionControls,
                        child: const Align(
                          alignment: Alignment.topLeft,
                          child: Text('hello world', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final RenderParagraph paragraph = _paragraph(tester, 'hello world');
        expect(_highlighted(paragraph.debugDecoratedText, selectionColor), isEmpty);

        final Offset origin = tester.getTopLeft(find.text('hello world'));
        final TestGesture gesture = await tester.startGesture(
          origin + const Offset(1, 5),
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);
        await tester.pump();
        final int decorated = TextDelegateSet.debugDecorateCount;
        // Every move of the pointer that changes the selection builds a new
        // span for the text.
        await gesture.moveTo(origin + const Offset(31, 5));
        await tester.pump();
        expect(_highlighted(paragraph.debugDecoratedText, selectionColor), <String>['hel']);
        await gesture.moveTo(origin + const Offset(81, 5));
        await tester.pump();
        // The selection is on top of the match of the other plugin.
        expect(_highlighted(paragraph.debugDecoratedText, selectionColor), <String>['hello ', 'wo']);
        expect(_highlighted(paragraph.debugDecoratedText), <String>['rld']);
        expect(TextDelegateSet.debugDecorateCount - decorated, 2);
        await gesture.up();
        await tester.pump();
        // The selection survived its own decoration.
        expect(paragraph.selections.single, const TextSelection(baseOffset: 0, extentOffset: 8));
      });

      testWidgets('H3: the recognizer of the app still works around a decoration', (
        WidgetTester tester,
      ) async {
        var taps = 0;
        final tap = TapGestureRecognizer()..onTap = () => taps += 1;
        addTearDown(tap.dispose);
        final plugin = _WordPlugin('bbbb');
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text.rich(
                  TextSpan(text: 'aaaabbbbcccc', recognizer: tap),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        );
        expect(_highlightedIn(tester, 'aaaabbbbcccc'), <String>['bbbb']);
        final Offset origin = tester.getTopLeft(find.byType(RichText));
        await tester.tapAt(origin + const Offset(15, 5));
        await tester.tapAt(origin + const Offset(55, 5));
        await tester.tapAt(origin + const Offset(105, 5));
        expect(taps, 3);
      });

      testWidgets('H7: a decoration that depends on state set in didAddText is in the first frame', (
        WidgetTester tester,
      ) async {
        final plugin = _SeenPlugin();
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: ListView.builder(
                controller: controller,
                itemExtent: 100,
                itemCount: 100,
                itemBuilder: (BuildContext context, int index) => Text('item $index'),
              ),
            ),
          ),
        );
        expect(find.text('item 50', skipOffstage: false), findsNothing);
        controller.jumpTo(5000);
        // One frame. The item is built during layout of this frame.
        await tester.pump();
        expect(plugin.seen.any((TextDelegate d) => d.text == 'item 50'), isTrue);
        expect(_highlightedIn(tester, 'item 50'), <String>['item 50']);
      });

      testWidgets('H8: a match in the part that maxLines cuts off', (WidgetTester tester) async {
        final plugin = _WordPlugin('');
        const text = 'one two three four five six seven eight nine ten';
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: const Center(
                child: SizedBox(
                  width: 120,
                  child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        );
        final Size before = tester.getSize(find.byType(RichText));
        plugin.setWord('nine');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(RichText)), before);
        expect(_highlightedIn(tester, text), <String>['nine']);
      });

      testWidgets('H9: a decoration in a text field keeps the text, the caret and the composing '
          'underline', (WidgetTester tester) async {
        final plugin = _WordPlugin('');
        final controller = TextEditingController(text: 'hello world');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: EditableText(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(fontSize: 14),
                    cursorColor: const Color(0xFF000000),
                    backgroundCursorColor: const Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ),
        );
        final RenderEditable editable = tester.renderObject<RenderEditable>(
          find.byWidgetPredicate((Widget widget) => widget.runtimeType.toString() == '_Editable'),
        );
        Rect caretAt(int offset) => editable.getLocalRectForCaret(TextPosition(offset: offset));
        final caretsBefore = <Rect>[for (var i = 0; i <= 11; i += 1) caretAt(i)];

        focusNode.requestFocus();
        await tester.pump();
        controller.value = const TextEditingValue(
          text: 'hello world',
          selection: TextSelection.collapsed(offset: 11),
          composing: TextRange(start: 4, end: 8),
        );
        plugin.setWord('world');
        await tester.pump();

        final InlineSpan decorated = editable.debugDecoratedText!;
        expect(editable.plainText, 'hello world');
        expect(decorated.toPlainText(), 'hello world');
        expect(_highlighted(decorated), <String>['wo', 'rld']);
        // The composing underline of "o wo" is still there, on both sides of
        // the split that the plugin added.
        final underlined = <String>[];
        void visit(InlineSpan span, TextDecoration? inherited) {
          if (span is TextSpan) {
            final TextDecoration? decoration = span.style?.decoration ?? inherited;
            if (span.text != null && decoration == TextDecoration.underline) {
              underlined.add(span.text!);
            }
            span.children?.forEach((InlineSpan child) => visit(child, decoration));
          }
        }

        visit(decorated, null);
        expect(underlined.join(), 'o wo');
        expect(<Rect>[for (var i = 0; i <= 11; i += 1) caretAt(i)], caretsBefore);
        expect(plugin.delegates.single.isEditable, isTrue);
      });

      testWidgets('H10: obscured text is not given to a plugin', (WidgetTester tester) async {
        final plugin = _WordPlugin('secret');
        final controller = TextEditingController(text: 'secret');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: EditableText(
                controller: controller,
                focusNode: focusNode,
                obscureText: true,
                style: const TextStyle(fontSize: 14),
                cursorColor: const Color(0xFF000000),
                backgroundCursorColor: const Color(0xFF000000),
              ),
            ),
          ),
        );
        expect(plugin.log, isEmpty);
        expect(plugin.delegates, isEmpty);
      });

      testWidgets('H10: TextPluginScope.none and exclude', (WidgetTester tester) async {
        final plugin = _WordPlugin('a');
        final other = _OtherWordPlugin('a', color: _orange);
        await tester.pumpWidget(
          _app(
            TextPluginScope.multiple(
              plugins: <TextPlugin>[plugin, other],
              child: const Column(
                children: <Widget>[
                  Text('a both'),
                  TextPluginScope.none(child: Text('a none')),
                  TextPluginScope.exclude(types: <Type>{_OtherWordPlugin}, child: Text('a first')),
                ],
              ),
            ),
          ),
        );
        expect(plugin.texts, <String>['a both', 'a first']);
        expect(other.texts, <String>['a both']);
        expect(_highlightedIn(tester, 'a none'), isEmpty);
        expect(_highlightedIn(tester, 'a first'), <String>['a']);
      });

      testWidgets('H10: text in a route covered by an opaque route is not given to plugins', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('page');
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: Navigator(
                key: navigatorKey,
                onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
                  pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) =>
                      const Text('First page'),
                ),
              ),
            ),
          ),
        );
        expect(plugin.texts, <String>['First page']);

        navigatorKey.currentState!.push(
          PageRouteBuilder<void>(
            pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) =>
                const Text('Second page'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('First page', skipOffstage: false), findsOneWidget);
        expect(plugin.texts, <String>['Second page']);
        expect(plugin.log, contains('remove:First page'));

        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(plugin.texts, <String>['First page']);
        expect(_highlightedIn(tester, 'First page'), <String>['page']);
      });

      testWidgets('H12: a decoration does not change the semantics tree', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final plugin = _WordPlugin('');
        const text = 'one two three two one';
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text(text))),
        );
        String describe() => tester
            .getSemantics(find.byType(RichText))
            .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder)
            .replaceAll(RegExp(r'#\d+'), '');
        final String none = describe();
        expect(none, contains(text));

        plugin.setWord('three');
        await tester.pump();
        expect(_highlightedIn(tester, text), <String>['three']);
        expect(describe(), none);

        plugin.setWord('o');
        await tester.pump();
        expect(_highlightedIn(tester, text), hasLength(4));
        expect(describe(), none);
        handle.dispose();
      });

      testWidgets('H13: a plugin notifies from a build-time callback through deferToEndOfFrame', (
        WidgetTester tester,
      ) async {
        final plugin = _CountingPlugin();
        final counts = <int>[];
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: Column(
                children: <Widget>[
                  ListenableBuilder(
                    listenable: plugin,
                    builder: (BuildContext context, Widget? child) {
                      counts.add(plugin.count);
                      return const SizedBox();
                    },
                  ),
                  const Text('one'),
                  const Text('two'),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(plugin.count, 2);
        // The counter is built again in the next frame, with the right value.
        await tester.pump();
        expect(counts.last, 2);
      });

      testWidgets('H13: a notification during build is reported with the name of the helper', (
        WidgetTester tester,
      ) async {
        final plugin = _CountingPlugin()
          ..defer = false
          ..redecorate = true;
        await tester.pumpWidget(
          _app(TextPluginScope(plugin: plugin, child: const Text('one'))),
        );
        final Object? exception = tester.takeException();
        expect(exception, isFlutterError);
        expect(exception.toString(), contains('TextPlugin.deferToEndOfFrame'));
      });

      testWidgets('H14: document order is right after the frame, also for a list scrolled upward', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('');
        final controller = ScrollController(initialScrollOffset: 3000);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: ListView.builder(
                controller: controller,
                itemExtent: 100,
                itemCount: 100,
                itemBuilder: (BuildContext context, int index) =>
                    Text('item ${index.toString().padLeft(3, '0')}'),
              ),
            ),
          ),
        );
        // Scroll upward: the new items come before the ones that exist.
        controller.jumpTo(2500);
        await tester.pump();
        final List<TextDelegate> sorted = plugin.delegates.toList()..shuffle();
        TextDelegate.sortInDocumentOrder(sorted);
        final List<String> texts = sorted.map((TextDelegate d) => d.text).toList();
        expect(texts, texts.toList()..sort());
        final List<TextDelegate> compared = plugin.delegates.toList()..sort();
        expect(compared.map((TextDelegate d) => d.text).toList(), texts);
      });

      testWidgets('H15: adding the first plugin to a scope', (WidgetTester tester) async {
        final plugin = _WordPlugin('hello');
        Widget build(List<TextPlugin> plugins) => _app(
          TextPluginScope.multiple(
            plugins: plugins,
            child: const Text('hello world'),
          ),
        );
        await tester.pumpWidget(build(const <TextPlugin>[]));
        final RenderParagraph before = _paragraph(tester, 'hello world');
        await tester.pumpWidget(build(<TextPlugin>[plugin]));
        final RenderParagraph after = _paragraph(tester, 'hello world');
        expect(_highlighted(after.debugDecoratedText), <String>['hello']);
        // Option A puts a widget around the text, so the text is created
        // again. Option B keeps the render object.
        expect(identical(before, after), layer == TextDecorationLayer.render);
      });

      testWidgets('H16: a RichText that is created directly', (WidgetTester tester) async {
        final plugin = _WordPlugin('hello');
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: RichText(text: const TextSpan(text: 'hello world')),
            ),
          ),
        );
        // Option A decorates in Text and EditableText. RichText has no build
        // method, so it is left out.
        expect(
          _highlightedIn(tester, 'hello world'),
          layer == TextDecorationLayer.render ? <String>['hello'] : isEmpty,
        );
      });

      testWidgets('ensureVisible scrolls a range of an offscreen text into view', (
        WidgetTester tester,
      ) async {
        final plugin = _WordPlugin('');
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            TextPluginScope(
              plugin: plugin,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: <Widget>[
                    for (var i = 0; i < 50; i += 1) SizedBox(height: 100, child: Text('item $i')),
                  ],
                ),
              ),
            ),
          ),
        );
        final TextDelegate target = plugin.delegates.firstWhere(
          (TextDelegate d) => d.text == 'item 30',
        );
        target.ensureVisible(const TextRange(start: 0, end: 4));
        await tester.pump();
        expect(controller.offset, greaterThan(2000));
      });
    });
  }

  testWidgets('with post-layout callbacks, a decoration from a callback is one frame late', (
    WidgetTester tester,
  ) async {
    // This is the reason why the lifecycle moved to build time. The plugin
    // learns about a text after layout, as the painter prototype does, and
    // only then can ask for a decoration.
    debugDefaultTextDecorationLayer = TextDecorationLayer.render;
    addTearDown(() => debugDefaultTextDecorationLayer = TextDecorationLayer.widget);
    final plugin = _LatePlugin();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        TextPluginScope(
          plugin: plugin,
          child: ListView.builder(
            controller: controller,
            itemExtent: 100,
            itemCount: 100,
            itemBuilder: (BuildContext context, int index) => Text('item $index'),
          ),
        ),
      ),
    );
    controller.jumpTo(5000);
    await tester.pump();
    // The text was painted in this frame without its highlight: the request
    // for the decoration came after the frame.
    expect(_highlightedIn(tester, 'item 50'), isEmpty);
    await tester.pump();
    expect(_highlightedIn(tester, 'item 50'), <String>['item 50']);
  });
}

/// One highlight whose color can change.
class _ColorPlugin extends TextPlugin {
  Color color = _yellow;
  TextDelegate? delegate;

  @override
  void didAddText(TextDelegate delegate) => this.delegate = delegate;

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: const TextRange(start: 6, end: 11),
        style: TextStyle(backgroundColor: color),
      ),
    ];
  }
}

/// Changes its decorations by notifying.
class _NotifyingPlugin extends TextPlugin with ChangeNotifier {
  String word = '';
  int buildCount = 0;

  @override
  bool get notifiesDecorationChanges => true;

  void notify() => notifyListeners();

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    buildCount += 1;
    if (word.isEmpty) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      for (final Match match in word.allMatches(delegate.text))
        TextSpanDecoration(
          range: TextRange(start: match.start, end: match.end),
          style: const TextStyle(backgroundColor: _yellow),
        ),
    ];
  }
}

/// Highlights a text only if it has seen the text in [didAddText].
class _SeenPlugin extends TextPlugin {
  final Set<TextDelegate> seen = <TextDelegate>{};

  @override
  void didAddText(TextDelegate delegate) => seen.add(delegate);

  @override
  void didRemoveText(TextDelegate delegate) => seen.remove(delegate);

  @override
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) {
    if (!seen.contains(delegate)) {
      return const <TextSpanDecoration>[];
    }
    return <TextSpanDecoration>[
      TextSpanDecoration(
        range: TextRange(start: 0, end: delegate.text.length),
        style: const TextStyle(backgroundColor: _yellow),
      ),
    ];
  }
}

/// Like [_SeenPlugin], but it learns about a text after layout, the way a
/// plugin of the painter prototype does.
class _LatePlugin extends _SeenPlugin {
  @override
  void didAddText(TextDelegate delegate) {
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      seen.add(delegate);
      delegate.markNeedsDecoration();
    });
  }
}

/// Counts the texts and tells its listeners.
class _CountingPlugin extends TextPlugin with ChangeNotifier {
  int count = 0;
  bool defer = true;
  bool redecorate = false;

  @override
  bool get notifiesDecorationChanges => redecorate;

  @override
  void didAddText(TextDelegate delegate) {
    count += 1;
    if (defer) {
      TextPlugin.deferToEndOfFrame(notifyListeners);
    } else {
      notifyListeners();
    }
  }
}
