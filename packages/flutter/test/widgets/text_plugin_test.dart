// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTextPlugin extends TextPlugin {
  final List<TextDelegate> activeDelegates = <TextDelegate>[];
  final List<String> log = <String>[];

  @override
  void didAddText(TextDelegate delegate) {
    activeDelegates.add(delegate);
    log.add('plugin:add:${delegate.text}');
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    log.add('plugin:update:${delegate.text}');
  }

  @override
  void didLayoutText(TextDelegate delegate) {
    log.add('plugin:layout:${delegate.text}');
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    activeDelegates.remove(delegate);
    log.add('plugin:remove:${delegate.text}');
  }
}

class _InnerRecordingTextPlugin extends _RecordingTextPlugin {}

class _CallbackCustomPainter extends CustomPainter {
  _CallbackCustomPainter(this.onPaint, {super.repaint});

  final void Function(Canvas canvas, Size size) onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _CallbackCustomPainter oldDelegate) => true;
}

class _HighlightPlugin extends TextPlugin {
  _HighlightPlugin({
    required this.name,
    required this.paintLog,
    this.paintForeground = false,
    this.paintOrder = 0,
  });

  final String name;
  final List<String> paintLog;
  final bool paintForeground;
  @override
  final int paintOrder;
  final List<TextDelegate> delegates = <TextDelegate>[];

  @override
  void didAddText(TextDelegate delegate) {
    delegates.add(delegate);
    delegate.backgroundPainter = _CallbackCustomPainter((Canvas canvas, Size size) {
      paintLog.add('$name:bg:${delegate.text}');
    });
    if (paintForeground) {
      delegate.foregroundPainter = _CallbackCustomPainter((Canvas canvas, Size size) {
        paintLog.add('$name:fg:${delegate.text}');
      });
    }
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegates.remove(delegate);
  }
}

class _OuterHighlightPlugin extends _HighlightPlugin {
  _OuterHighlightPlugin({
    required super.name,
    required super.paintLog,
    super.paintForeground,
    super.paintOrder,
  });
}

class _InnerHighlightPlugin extends _HighlightPlugin {
  _InnerHighlightPlugin({
    required super.name,
    required super.paintLog,
    super.paintForeground,
    super.paintOrder,
  });
}

void main() {
  testWidgets('TextPlugin tracks lifecycle of Text and RichText widgets in subtree', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: plugin,
          child: const Column(
            children: <Widget>[
              Text('Hello'),
              Text.rich(
                TextSpan(
                  text: 'Rich ',
                  children: <InlineSpan>[TextSpan(text: 'World')],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(plugin.activeDelegates, hasLength(2));
    expect(plugin.activeDelegates[0].text, 'Hello');
    expect(plugin.activeDelegates[1].text, 'Rich World');
    expect(
      plugin.log,
      containsAllInOrder(<String>[
        'plugin:add:Hello',
        'plugin:layout:Hello',
        'plugin:add:Rich World',
        'plugin:layout:Rich World',
      ]),
    );

    plugin.log.clear();

    // Update the first Text widget and remove the second one.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: plugin,
          child: const Column(children: <Widget>[Text('Hello Flutter')]),
        ),
      ),
    );

    expect(plugin.activeDelegates, hasLength(1));
    expect(plugin.activeDelegates.single.text, 'Hello Flutter');
    expect(plugin.log, contains('plugin:update:Hello Flutter'));
    expect(plugin.log, contains('plugin:layout:Hello Flutter'));
    expect(plugin.log, contains('plugin:remove:Rich World'));

    plugin.log.clear();

    // Unmount everything.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(plugin.activeDelegates, isEmpty);
    expect(plugin.log, <String>['plugin:remove:Hello Flutter']);
  });

  testWidgets('TextDelegate queries layout boxes and positions accurately', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: plugin,
          child: const Align(alignment: Alignment.topLeft, child: Text('Buy GOOG and AAPL today')),
        ),
      ),
    );

    final TextDelegate delegate = plugin.activeDelegates.single;
    expect(delegate.hasLayout, isTrue);
    expect(delegate.hasSize, isTrue);
    expect(delegate.size.width, greaterThan(0));
    expect(delegate.size.height, greaterThan(0));

    final int googStart = delegate.text.indexOf('GOOG');
    final List<TextBox> googBoxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: googStart, extentOffset: googStart + 4),
    );
    expect(googBoxes, isNotEmpty);
    final Rect googRect = googBoxes.first.toRect();
    expect(googRect.width, greaterThan(0));
    expect(googRect.height, greaterThan(0));

    final TextPosition centerPos = delegate.getPositionForOffset(googRect.center);
    final TextRange wordRange = delegate.getWordBoundary(centerPos);
    expect(delegate.text.substring(wordRange.start, wordRange.end), 'GOOG');
  });

  testWidgets('Multiple TextPlugins compose and paint in installation order (root first)', (
    WidgetTester tester,
  ) async {
    final paintLog = <String>[];
    final outerPlugin = _OuterHighlightPlugin(
      name: 'outer',
      paintLog: paintLog,
      paintForeground: true,
    );
    final innerPlugin = _InnerHighlightPlugin(
      name: 'inner',
      paintLog: paintLog,
      paintForeground: true,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: outerPlugin,
          child: TextPluginScope(plugin: innerPlugin, child: const Text('Composable Text')),
        ),
      ),
    );

    expect(paintLog, <String>[
      'outer:bg:Composable Text',
      'inner:bg:Composable Text',
      'outer:fg:Composable Text',
      'inner:fg:Composable Text',
    ]);
  });

  testWidgets('CustomPainter repaint listenable triggers paragraph repaint', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();
    final repaintNotifier = ValueNotifier<int>(0);
    addTearDown(repaintNotifier.dispose);
    var paintCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(plugin: plugin, child: const Text('Repaint Test')),
      ),
    );

    final TextDelegate delegate = plugin.activeDelegates.single;
    delegate.backgroundPainter = _CallbackCustomPainter((Canvas canvas, Size size) {
      paintCount += 1;
    }, repaint: repaintNotifier);

    await tester.pump();
    expect(paintCount, 1);

    repaintNotifier.value += 1;
    await tester.pump();
    expect(paintCount, 2);
  });

  testWidgets('TextPluginScope.none disables ancestor plugins for subtree', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: plugin,
          child: const Column(
            children: <Widget>[
              Text('Included'),
              TextPluginScope.none(child: Text('Excluded')),
            ],
          ),
        ),
      ),
    );

    expect(plugin.activeDelegates, hasLength(1));
    expect(plugin.activeDelegates.single.text, 'Included');
  });

  testWidgets('TextPluginScope works alongside SelectionArea', (WidgetTester tester) async {
    final plugin = _RecordingTextPlugin();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextPluginScope(
            plugin: plugin,
            child: const SelectionArea(
              child: Column(
                children: <Widget>[
                  Text('First selectable paragraph'),
                  Text('Second selectable paragraph'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(plugin.activeDelegates, hasLength(2));
    expect(
      plugin.activeDelegates.map((TextDelegate d) => d.text),
      containsAll(<String>['First selectable paragraph', 'Second selectable paragraph']),
    );
  });

  testWidgets('TextDelegate.ensureVisible scrolls offscreen text range into view', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: plugin,
          child: Center(
            child: SizedBox(
              height: 200,
              width: 400,
              child: SingleChildScrollView(
                controller: scrollController,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Top Paragraph'),
                    SizedBox(height: 600),
                    Text('Bottom Target Paragraph with KEYWORD inside'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(scrollController.offset, 0.0);
    final TextDelegate bottomDelegate = plugin.activeDelegates.last;
    expect(bottomDelegate.text, contains('KEYWORD'));

    final int keywordStart = bottomDelegate.text.indexOf('KEYWORD');
    bottomDelegate.ensureVisible(TextRange(start: keywordStart, end: keywordStart + 7));
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(400.0));
  });

  testWidgets(
    'TextDelegate.compareTo sorts delegates in document order when mounted out of order',
    (WidgetTester tester) async {
      final plugin = _RecordingTextPlugin();
      final scrollController = ScrollController(initialScrollOffset: 800.0);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: Center(
              child: SizedBox(
                height: 200,
                width: 400,
                child: ListView.builder(
                  controller: scrollController,
                  itemExtent: 100.0,
                  itemCount: 15,
                  itemBuilder: (BuildContext context, int index) => Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      // Scroll upward so earlier items are mounted after later items.
      scrollController.jumpTo(400.0);
      await tester.pump();

      final List<TextDelegate> sorted = plugin.activeDelegates.toList()..sort();
      final List<int> indices = sorted
          .map((TextDelegate d) => int.parse(d.text.split(' ').last))
          .toList();
      for (var i = 1; i < indices.length; i += 1) {
        expect(indices[i], greaterThan(indices[i - 1]));
      }
    },
  );

  testWidgets(
    'TextPlugin.needsOffscreenContent configures OffscreenContentRenderingStrategy in ListView.builder',
    (WidgetTester tester) async {
      final plugin = _EagerToggleTextPlugin();
      addTearDown(plugin.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: Center(
              child: SizedBox(
                height: 200,
                width: 400,
                child: ListView.builder(
                  controller: scrollController,
                  itemExtent: 100.0,
                  itemCount: 30,
                  itemBuilder: (BuildContext context, int index) => Text('Lazy Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      // With needsOffscreenContent == false (default), only visible + cacheExtent items are mounted (< 30).
      expect(plugin.activeDelegates.length, lessThan(10));
      expect(plugin.activeDelegates.any((TextDelegate d) => d.text == 'Lazy Item 29'), isFalse);

      // Simulate Ctrl+F switching needsOffscreenContent to true on the plugin.
      plugin.needsOffscreenContent = true;
      await tester.pump();

      // All 30 items in the ListView.builder are now rendered and registered!
      expect(plugin.activeDelegates, hasLength(30));
      final TextDelegate lastItem = plugin.activeDelegates.firstWhere(
        (TextDelegate d) => d.text == 'Lazy Item 29',
      );
      expect(lastItem.hasLayout, isTrue);

      // And we can scroll directly to the previously offscreen item 29 via ensureVisible!
      lastItem.ensureVisible(const TextRange(start: 0, end: 12));
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(2500.0));
    },
  );

  testWidgets(
    'OffscreenContentRenderingStrategy can override policy or bound cacheExtent for a subtree',
    (WidgetTester tester) async {
      final plugin = _EagerToggleTextPlugin()..needsOffscreenContent = true;
      addTearDown(plugin.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: OffscreenContentRenderingStrategy(
              policy: const OffscreenRenderingPolicy.lazy(),
              child: Center(
                child: SizedBox(
                  height: 200,
                  width: 400,
                  child: ListView.builder(
                    itemExtent: 100.0,
                    itemCount: 30,
                    itemBuilder: (BuildContext context, int index) => Text('OptOut Item $index'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Because the inner OffscreenContentRenderingStrategy explicitly sets lazy,
      // offscreen items beyond the normal cache extent remain unmounted even though
      // the enclosing plugin has needsOffscreenContent == true.
      expect(plugin.activeDelegates.length, lessThan(10));
      expect(plugin.activeDelegates.any((TextDelegate d) => d.text == 'OptOut Item 29'), isFalse);

      // Now test OffscreenRenderingPolicy.eager with a custom bounded cacheExtent (600px -> ~8 items).
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: const OffscreenContentRenderingStrategy(
              policy: OffscreenRenderingPolicy.eager(cacheExtent: ScrollCacheExtent.pixels(600.0)),
              child: Center(
                child: SizedBox(height: 200, width: 400, child: _BoundedListTestWidget()),
              ),
            ),
          ),
        ),
      );

      expect(plugin.activeDelegates.length, greaterThanOrEqualTo(8));
      expect(plugin.activeDelegates.length, lessThan(15));
    },
  );

  testWidgets('TextPluginScope deduplicates by Type and orders by paintOrder', (
    WidgetTester tester,
  ) async {
    final paintLog = <String>[];
    final outerSameType = _OuterHighlightPlugin(name: 'outer-v1', paintLog: paintLog);
    final innerSameType = _OuterHighlightPlugin(
      name: 'inner-v2',
      paintLog: paintLog,
      paintOrder: 10,
    );
    final innerLowOrder = _InnerHighlightPlugin(
      name: 'inner-low-order',
      paintLog: paintLog,
      paintOrder: -5,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: outerSameType,
          child: TextPluginScope.multiple(
            plugins: <TextPlugin>[innerSameType, innerLowOrder],
            child: const Text('Ordered Text'),
          ),
        ),
      ),
    );

    // 1. innerSameType overrides outerSameType because both have runtimeType _OuterHighlightPlugin.
    expect(outerSameType.delegates, isEmpty);
    expect(innerSameType.delegates, hasLength(1));

    // 2. innerLowOrder (paintOrder: -5) paints before innerSameType (paintOrder: 10).
    expect(paintLog, <String>['inner-low-order:bg:Ordered Text', 'inner-v2:bg:Ordered Text']);
  });

  testWidgets('TextPlugin tracks lifecycle and typing updates of EditableText in subtree', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();
    final controller = TextEditingController(text: 'Initial Editable');
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextPluginScope(
            plugin: plugin,
            child: EditableText(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(),
              cursorColor: Colors.red,
              backgroundCursorColor: Colors.black,
            ),
          ),
        ),
      ),
    );

    expect(plugin.activeDelegates, hasLength(1));
    final TextDelegate delegate = plugin.activeDelegates.single;
    expect(delegate.text, 'Initial Editable');
    expect(plugin.log, contains('plugin:add:Initial Editable'));
    expect(plugin.log, contains('plugin:layout:Initial Editable'));

    plugin.log.clear();

    // Type new text into controller
    controller.text = 'Updated Editable';
    await tester.pump();

    expect(delegate.text, 'Updated Editable');
    expect(plugin.log, contains('plugin:update:Updated Editable'));
    expect(plugin.log, contains('plugin:layout:Updated Editable'));

    plugin.log.clear();

    // Unmount widget
    await tester.pumpWidget(const SizedBox.shrink());
    expect(plugin.activeDelegates, isEmpty);
    expect(plugin.log, contains('plugin:remove:Updated Editable'));
  });

  testWidgets('An obscured EditableText is not registered with any TextPlugin', (
    WidgetTester tester,
  ) async {
    final scopePlugin = _RecordingTextPlugin();
    final explicitPlugin = _RecordingTextPlugin();
    final controller = TextEditingController(text: 'hunter2');
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    Widget build({required bool obscureText, List<TextPlugin>? textPlugins}) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: TextPluginScope(
            plugin: scopePlugin,
            child: EditableText(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              textPlugins: textPlugins,
              style: const TextStyle(),
              cursorColor: const Color(0xFFFF0000),
              backgroundCursorColor: const Color(0xFF000000),
            ),
          ),
        ),
      );
    }

    RenderEditable findRenderEditable() {
      return tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    }

    // Obscured from the start: the plugin of the scope never sees the field.
    await tester.pumpWidget(build(obscureText: true));
    expect(findRenderEditable().textPlugins, isNull);
    expect(scopePlugin.activeDelegates, isEmpty);
    expect(scopePlugin.log, isEmpty);

    // Plugins passed to the field directly are skipped as well.
    await tester.pumpWidget(build(obscureText: true, textPlugins: <TextPlugin>[explicitPlugin]));
    expect(findRenderEditable().textPlugins, isNull);
    expect(explicitPlugin.activeDelegates, isEmpty);
    expect(explicitPlugin.log, isEmpty);

    // No longer obscured: the plugin of the scope is told about the field.
    await tester.pumpWidget(build(obscureText: false));
    expect(findRenderEditable().textPlugins, <TextPlugin>[scopePlugin]);
    expect(scopePlugin.activeDelegates, hasLength(1));
    expect(scopePlugin.log, contains('plugin:add:hunter2'));

    // Obscured again: the plugin loses the field.
    scopePlugin.log.clear();
    await tester.pumpWidget(build(obscureText: true));
    expect(findRenderEditable().textPlugins, isNull);
    expect(scopePlugin.activeDelegates, isEmpty);
    expect(scopePlugin.log, hasLength(1));
    expect(scopePlugin.log.single, startsWith('plugin:remove:'));
  });

  testWidgets(
    'SelectableRegion installs _SelectionHighlightTextPlugin and exposes selections and selectionColor on TextDelegate',
    (WidgetTester tester) async {
      final plugin = _RecordingTextPlugin();
      final GlobalKey key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: TextPluginScope(
                plugin: plugin,
                child: Column(
                  key: key,
                  children: const <Widget>[
                    Text('Custom Color Paragraph', selectionColor: Color(0xFFFF5722)),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(text: 'Before '),
                          WidgetSpan(child: SizedBox(width: 10, height: 10)),
                          TextSpan(text: ' After'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(plugin.activeDelegates, hasLength(2));
      final TextDelegate firstDelegate = plugin.activeDelegates[0];
      final TextDelegate secondDelegate = plugin.activeDelegates[1];

      // Verify _SelectionHighlightTextPlugin is installed on the RenderParagraph alongside our plugin.
      final firstParagraph = firstDelegate.renderObject as RenderParagraph;
      expect(firstParagraph.textPlugins, hasLength(2));
      expect(
        firstParagraph.textPlugins!.any((TextPlugin p) => p.handlesSelectionHighlight),
        isTrue,
      );

      expect(firstDelegate.selectionColor, const Color(0xFFFF5722));
      expect(firstDelegate.selections, isEmpty);
      expect(secondDelegate.selections, isEmpty);

      // Select all text across the SelectionArea.
      Actions.invoke(
        key.currentContext!,
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();

      expect(firstDelegate.selections, <TextSelection>[
        const TextSelection(baseOffset: 0, extentOffset: 22),
      ]);
      // The second paragraph has a WidgetSpan placeholder at index 7, so it has two selectable fragments.
      expect(secondDelegate.selections, <TextSelection>[
        const TextSelection(baseOffset: 0, extentOffset: 7),
        const TextSelection(baseOffset: 8, extentOffset: 14),
      ]);
    },
  );

  testWidgets(
    'TextPluginScope.exclude filters out feature plugins while preserving _SelectionHighlightTextPlugin',
    (WidgetTester tester) async {
      final plugin = _RecordingTextPlugin();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: TextPluginScope(
                plugin: plugin,
                child: const Column(
                  children: <Widget>[
                    Text('Body Text'),
                    TextPluginScope.exclude(
                      types: <Type>{_RecordingTextPlugin},
                      child: Text('Toolbar Text'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(plugin.activeDelegates, hasLength(1));
      expect(plugin.activeDelegates.single.text, 'Body Text');

      // Toolbar Text excluded _RecordingTextPlugin but still keeps _SelectionHighlightTextPlugin.
      final RenderParagraph toolbarParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text('Toolbar Text'), matching: find.byType(RichText)),
      );
      expect(toolbarParagraph.textPlugins, hasLength(1));
      expect(toolbarParagraph.textPlugins!.single.handlesSelectionHighlight, isTrue);
    },
  );

  testWidgets('Lifecycle callbacks (didAddText, didUpdateText, didLayoutText) have valid layout', (
    WidgetTester tester,
  ) async {
    final plugin = _GeometryCheckingTextPlugin();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(plugin: plugin, child: const Text('Hello Geometry')),
      ),
    );

    expect(plugin.events, containsAll(<String>['add:boxes=1', 'layout:boxes=1']));
    plugin.events.clear();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(plugin: plugin, child: const Text('Updated Geometry')),
      ),
    );

    expect(plugin.events, containsAll(<String>['update:boxes=1', 'layout:boxes=1']));
  });

  testWidgets(
    'Custom RenderBox using TextPainter and non-text RenderBox participate via TextDelegateHostMixin',
    (WidgetTester tester) async {
      final plugin = _RecordingTextPlugin();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: const Column(
              children: <Widget>[
                CustomBadgeText(label: 'Badge v1', style: TextStyle(fontSize: 16)),
                LabeledColorBox(
                  label: 'Chart Thumbnail',
                  color: Color(0xFF2196F3),
                  boxSize: Size(80, 40),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        plugin.log,
        containsAll(<String>['plugin:add:Badge v1', 'plugin:add:Chart Thumbnail']),
      );
      expect(plugin.activeDelegates.length, 2);

      final RenderCustomBadgeText badgeRenderObject = tester.renderObject<RenderCustomBadgeText>(
        find.byType(CustomBadgeText),
      );
      expect(badgeRenderObject.label, 'Badge v1');
      expect(badgeRenderObject.style, const TextStyle(fontSize: 16));

      final RenderLabeledColorBox boxRenderObject = tester.renderObject<RenderLabeledColorBox>(
        find.byType(LabeledColorBox),
      );
      expect(boxRenderObject.label, 'Chart Thumbnail');
      expect(boxRenderObject.color, const Color(0xFF2196F3));
      expect(boxRenderObject.boxSize, const Size(80, 40));

      final List<TextBox> badgeBoxes = plugin.activeDelegates[0].getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(badgeBoxes, isNotEmpty);

      final List<TextBox> boxWidgetBoxes = plugin.activeDelegates[1].getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(boxWidgetBoxes.length, 1);
      expect(boxWidgetBoxes.single.toRect(), const Rect.fromLTWH(0, 0, 80, 40));

      plugin.log.clear();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: const Column(
              children: <Widget>[
                CustomBadgeText(label: 'Badge v2', style: TextStyle(fontSize: 16)),
                LabeledColorBox(
                  label: 'Updated Thumbnail',
                  color: Color(0xFF2196F3),
                  boxSize: Size(80, 40),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        plugin.log,
        containsAll(<String>['plugin:update:Badge v2', 'plugin:update:Updated Thumbnail']),
      );
    },
  );

  // A minimal stack of pages: a Navigator below the scope, so that the scope
  // sees the texts of every route.
  Widget buildNavigatorUnderScope({
    required GlobalKey<NavigatorState> navigatorKey,
    required TextPlugin plugin,
    required Widget firstPage,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextPluginScope(
        plugin: plugin,
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (RouteSettings settings) {
            return PageRouteBuilder<void>(
              pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) {
                return firstPage;
              },
            );
          },
        ),
      ),
    );
  }

  List<String> textsOf(_RecordingTextPlugin plugin) {
    return plugin.activeDelegates.map((TextDelegate delegate) => delegate.text).toList()..sort();
  }

  testWidgets('Text in a route covered by an opaque route is not given to plugins', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      buildNavigatorUnderScope(
        navigatorKey: navigatorKey,
        plugin: plugin,
        firstPage: const Text('First page'),
      ),
    );
    expect(textsOf(plugin), <String>['First page']);

    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) {
          return const Text('Second page');
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // During the transition both routes are on stage.
    expect(textsOf(plugin), <String>['First page', 'Second page']);

    await tester.pumpAndSettle();
    // The first route is still mounted, and its text is taken from the plugin.
    expect(find.text('First page', skipOffstage: false), findsOneWidget);
    expect(textsOf(plugin), <String>['Second page']);
    expect(plugin.log, contains('plugin:remove:First page'));

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    // Uncovered again: the text is given back, with a valid layout.
    expect(textsOf(plugin), <String>['First page']);
    expect(plugin.activeDelegates.single.hasLayout, isTrue);
  });

  testWidgets('Text in a route below a non-opaque route stays with its plugins', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      buildNavigatorUnderScope(
        navigatorKey: navigatorKey,
        plugin: plugin,
        firstPage: const Text('First page'),
      ),
    );

    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) {
          return const Text('Dialog');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(textsOf(plugin), <String>['Dialog', 'First page']);
    expect(plugin.log, isNot(contains('plugin:remove:First page')));
  });

  testWidgets('A TextPluginScope inside a covered route does not install its plugins', (
    WidgetTester tester,
  ) async {
    final outer = _RecordingTextPlugin();
    final inner = _InnerRecordingTextPlugin();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      buildNavigatorUnderScope(
        navigatorKey: navigatorKey,
        plugin: outer,
        firstPage: TextPluginScope(plugin: inner, child: const Text('First page')),
      ),
    );
    expect(textsOf(outer), <String>['First page']);
    expect(textsOf(inner), <String>['First page']);

    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) {
          return const Text('Second page');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(textsOf(outer), <String>['Second page']);
    expect(textsOf(inner), isEmpty);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(textsOf(outer), <String>['First page']);
    expect(textsOf(inner), <String>['First page']);
  });
}

class CustomBadgeText extends LeafRenderObjectWidget {
  const CustomBadgeText({super.key, required this.label, required this.style, this.textPlugins});

  final String label;
  final TextStyle style;
  final List<TextPlugin>? textPlugins;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderCustomBadgeText(
      label: label,
      style: style,
      textDirection: Directionality.of(context),
      textPlugins: textPlugins ?? TextPluginScope.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderCustomBadgeText renderObject) {
    renderObject
      ..label = label
      ..style = style
      ..textDirection = Directionality.of(context)
      ..textPlugins = textPlugins ?? TextPluginScope.maybeOf(context);
  }
}

class RenderCustomBadgeText extends RenderBox with TextDelegateHostMixin {
  RenderCustomBadgeText({
    required String label,
    required TextStyle style,
    required TextDirection textDirection,
    List<TextPlugin>? textPlugins,
  }) : _label = label,
       _style = style,
       _textDirection = textDirection,
       _textPainter = TextPainter(
         text: TextSpan(text: label, style: style),
         textDirection: textDirection,
       ) {
    this.textPlugins = textPlugins;
  }

  final TextPainter _textPainter;

  String get label => _label;
  String _label;
  set label(String value) {
    if (_label == value) {
      return;
    }
    _label = value;
    _textPainter.text = TextSpan(text: _label, style: _style);
    markNeedsTextDelegateUpdate();
    markNeedsLayout();
  }

  TextStyle get style => _style;
  TextStyle _style;
  set style(TextStyle value) {
    if (_style == value) {
      return;
    }
    _style = value;
    _textPainter.text = TextSpan(text: _label, style: _style);
    markNeedsLayout();
  }

  @override
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    _textPainter.textDirection = value;
    markNeedsLayout();
  }

  @override
  String get plainText => _textPainter.plainText;

  @override
  InlineSpan get textSpan => _textPainter.text!;

  @override
  List<TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    return _textPainter.getBoxesForSelection(
      selection,
      boxHeightStyle: boxHeightStyle,
      boxWidthStyle: boxWidthStyle,
    );
  }

  @override
  TextPosition getPositionForOffset(Offset offset) => _textPainter.getPositionForOffset(offset);

  @override
  TextRange getWordBoundary(TextPosition position) => _textPainter.getWordBoundary(position);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    _textPainter.layout(maxWidth: constraints.maxWidth);
    size = constraints.constrain(_textPainter.size);
    didLayoutTextDelegates();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintTextPluginBackgrounds(context, offset);
    _textPainter.paint(context.canvas, offset);
    paintTextPluginForegrounds(context, offset);
  }

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }
}

class LabeledColorBox extends LeafRenderObjectWidget {
  const LabeledColorBox({
    super.key,
    required this.label,
    required this.color,
    this.boxSize = const Size(100, 48),
    this.textPlugins,
  });

  final String label;
  final Color color;
  final Size boxSize;
  final List<TextPlugin>? textPlugins;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLabeledColorBox(
      label: label,
      color: color,
      boxSize: boxSize,
      textDirection: Directionality.of(context),
      textPlugins: textPlugins ?? TextPluginScope.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderLabeledColorBox renderObject) {
    renderObject
      ..label = label
      ..color = color
      ..boxSize = boxSize
      ..textDirection = Directionality.of(context)
      ..textPlugins = textPlugins ?? TextPluginScope.maybeOf(context);
  }
}

class RenderLabeledColorBox extends RenderBox with TextDelegateHostMixin {
  RenderLabeledColorBox({
    required String label,
    required Color color,
    required Size boxSize,
    required TextDirection textDirection,
    List<TextPlugin>? textPlugins,
  }) {
    this.label = label;
    this.color = color;
    this.boxSize = boxSize;
    this.textDirection = textDirection;
    this.textPlugins = textPlugins;
  }

  String get label => _label;
  String _label = '';
  set label(String value) {
    if (_label == value) {
      return;
    }
    _label = value;
    markNeedsTextDelegateUpdate();
    markNeedsPaint();
  }

  Color get color => _color;
  Color _color = const Color(0x00000000);
  set color(Color value) {
    if (_color == value) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  Size get boxSize => _boxSize;
  Size _boxSize = Size.zero;
  set boxSize(Size value) {
    if (_boxSize == value) {
      return;
    }
    _boxSize = value;
    markNeedsLayout();
  }

  @override
  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection = TextDirection.ltr;
  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  String get plainText => _label;

  @override
  List<TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    if (!selection.isValid || selection.isCollapsed) {
      return const <TextBox>[];
    }
    final int start = selection.start.clamp(0, _label.length);
    final int end = selection.end.clamp(0, _label.length);
    if (start >= end) {
      return const <TextBox>[];
    }
    return <TextBox>[TextBox.fromLTRBD(0, 0, size.width, size.height, textDirection)];
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
    didLayoutTextDelegates();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintTextPluginBackgrounds(context, offset);
    context.canvas.drawRect(offset & size, Paint()..color = _color);
    paintTextPluginForegrounds(context, offset);
  }
}

class _BoundedListTestWidget extends StatelessWidget {
  const _BoundedListTestWidget();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemExtent: 100.0,
      itemCount: 30,
      itemBuilder: (BuildContext context, int index) => Text('Bounded Item $index'),
    );
  }
}

class _GeometryCheckingTextPlugin extends TextPlugin {
  final List<String> events = <String>[];

  void _checkGeometry(String hook, TextDelegate delegate) {
    expect(delegate.hasLayout, isTrue, reason: '$hook should have valid layout');
    expect(delegate.size.width, greaterThan(0), reason: '$hook should have non-zero width');
    final List<TextBox> boxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: delegate.text.length),
    );
    events.add('$hook:boxes=${boxes.length}');
  }

  @override
  void didAddText(TextDelegate delegate) => _checkGeometry('add', delegate);

  @override
  void didUpdateText(TextDelegate delegate) => _checkGeometry('update', delegate);

  @override
  void didLayoutText(TextDelegate delegate) => _checkGeometry('layout', delegate);
}

class _EagerToggleTextPlugin extends TextPlugin with ChangeNotifier {
  final List<TextDelegate> activeDelegates = <TextDelegate>[];

  bool _needsOffscreenContent = false;
  @override
  bool get needsOffscreenContent => _needsOffscreenContent;
  set needsOffscreenContent(bool value) {
    if (_needsOffscreenContent == value) {
      return;
    }
    _needsOffscreenContent = value;
    notifyListeners();
  }

  @override
  void didAddText(TextDelegate delegate) {
    activeDelegates.add(delegate);
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    activeDelegates.remove(delegate);
  }
}
