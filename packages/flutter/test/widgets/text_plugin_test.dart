// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTextPlugin extends TextPlugin {
  final List<TextDelegate> activeDelegates = <TextDelegate>[];
  final List<String> log = <String>[];
  final List<PointerEvent> pointerEvents = <PointerEvent>[];

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

  @override
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {
    pointerEvents.add(event);
    log.add('plugin:pointer:${event.runtimeType}:${delegate.text}');
  }
}

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
  _HighlightPlugin({required this.name, required this.paintLog, this.paintForeground = false});

  final String name;
  final List<String> paintLog;
  final bool paintForeground;
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
        'plugin:add:Rich World',
        'plugin:layout:Hello',
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
    final outerPlugin = _HighlightPlugin(name: 'outer', paintLog: paintLog, paintForeground: true);
    final innerPlugin = _HighlightPlugin(name: 'inner', paintLog: paintLog, paintForeground: true);

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

  testWidgets('TextPlugin and TextDelegate receive pointer events on Text', (
    WidgetTester tester,
  ) async {
    final plugin = _RecordingTextPlugin();
    final delegateEvents = <PointerEvent>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TextPluginScope(
          plugin: plugin,
          child: const Center(child: Text('Tap Me')),
        ),
      ),
    );

    final TextDelegate delegate = plugin.activeDelegates.single;
    delegate.onPointerEvent = delegateEvents.add;

    await tester.tap(find.text('Tap Me'));
    await tester.pump();

    expect(plugin.pointerEvents, isNotEmpty);
    expect(plugin.pointerEvents.whereType<PointerDownEvent>(), hasLength(1));
    expect(plugin.pointerEvents.whereType<PointerUpEvent>(), hasLength(1));
    expect(delegateEvents.whereType<PointerDownEvent>(), hasLength(1));
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
}
