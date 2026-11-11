// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _TextWidgetsBuilder = Iterable<Widget> Function(
  BuildContext context,
  TextDelegate delegate,
  TextWidgetLayer layer,
);

const Set<TextWidgetLayer> _foregroundOnly = <TextWidgetLayer>{TextWidgetLayer.foreground};
const Set<TextWidgetLayer> _allLayers = <TextWidgetLayer>{
  TextWidgetLayer.background,
  TextWidgetLayer.foreground,
  TextWidgetLayer.overlay,
};

/// A widget plugin whose widgets are built by the test.
class _TestPlugin extends TextPlugin with TextWidgetPlugin {
  _TestPlugin(this.builder, {this.layers = _foregroundOnly});

  final _TextWidgetsBuilder builder;
  final Set<TextWidgetLayer> layers;
  final List<String> log = <String>[];

  Iterable<String> get builds => log.where((String entry) => entry.startsWith('build'));

  @override
  Set<TextWidgetLayer> get widgetLayers => layers;

  @override
  void didAddText(TextDelegate delegate) => log.add('didAddText');

  @override
  void didUpdateText(TextDelegate delegate) => log.add('didUpdateText');

  @override
  void didLayoutText(TextDelegate delegate) => log.add('didLayoutText');

  @override
  void didRemoveText(TextDelegate delegate) => log.add('didRemoveText');

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    log.add('build ${layer.name} "${delegate.text}" hasLayout: ${delegate.hasLayout}');
    return builder(context, delegate, layer);
  }
}

// TextPluginScope keeps one plugin per type, so a second plugin needs its own
// type.
class _SecondTestPlugin extends _TestPlugin {
  _SecondTestPlugin(super.builder);
}

class _PainterOnlyPlugin extends TextPlugin {
  const _PainterOnlyPlugin();
}

/// Shows a label below the text and rebuilds it when [increment] is called.
class _CounterPlugin extends TextPlugin with TextWidgetPlugin, ChangeNotifier {
  int count = 0;
  int builds = 0;

  void increment() {
    count += 1;
    notifyListeners();
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    builds += 1;
    return <Widget>[
      TextPositioned(
        delegate: delegate,
        range: const TextRange(start: 0, end: 1),
        targetAnchor: Alignment.bottomLeft,
        child: Text('count: $count'),
      ),
    ];
  }
}

/// Shows the length that it saw in [didLayoutText], which is called after the
/// widgets of that frame have been built.
class _LengthPlugin extends TextPlugin with TextWidgetPlugin, ChangeNotifier {
  int length = 0;

  @override
  void didLayoutText(TextDelegate delegate) {
    if (delegate.text.length != length) {
      length = delegate.text.length;
      notifyListeners();
    }
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    return <Widget>[
      TextPositioned(
        delegate: delegate,
        range: const TextRange(start: 0, end: 1),
        targetAnchor: Alignment.bottomLeft,
        child: Text('length: $length'),
      ),
    ];
  }
}

ValueKey<String> _marker(TextWidgetLayer layer) => ValueKey<String>('marker ${layer.name}');

/// Covers the first X of the text with an empty box.
Iterable<Widget> _markX(BuildContext context, TextDelegate delegate, TextWidgetLayer layer) {
  final int index = delegate.text.indexOf('X');
  return <Widget>[
    if (index >= 0)
      TextPositioned.fill(
        delegate: delegate,
        range: TextRange(start: index, end: index + 1),
        child: SizedBox.expand(key: _marker(layer)),
      ),
  ];
}

/// Puts [child] in the top left corner of an app in which [plugins] are
/// installed.
///
/// The tests use the test font, in which every glyph is a square with the
/// size of the font, 14 by default.
Widget _app(Widget child, {required List<TextPlugin> plugins}) {
  return TestWidgetsApp(
    home: TextPluginScope.multiple(
      plugins: plugins,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

/// The paragraph that contains an X, which is the text under test.
RenderParagraph _paragraph(WidgetTester tester) {
  return tester.allRenderObjects.whereType<RenderParagraph>().firstWhere(
    (RenderParagraph paragraph) => paragraph.text.toPlainText().contains('X'),
  );
}

/// Where the first X of the text under test is on screen.
Rect _rectOfX(WidgetTester tester) {
  final RenderParagraph paragraph = _paragraph(tester);
  final int index = paragraph.text.toPlainText(includeSemanticsLabels: false).indexOf('X');
  final Rect local = paragraph
      .getBoxesForSelection(TextSelection(baseOffset: index, extentOffset: index + 1))
      .single
      .toRect();
  return MatrixUtils.transformRect(paragraph.getTransformTo(null), local);
}

RenderObject _host(WidgetTester tester) {
  return tester.renderObject(find.byType(TextPluginWidgetHost));
}

bool _isRenderDescendant(RenderObject node, RenderObject ancestor) {
  for (RenderObject? current = node.parent; current != null; current = current.parent) {
    if (identical(current, ancestor)) {
      return true;
    }
  }
  return false;
}

/// Checks that the plugin built every layer in [layers] from a valid layout of
/// [text], and logged exactly [then] afterwards.
///
/// The layers have no fixed order among themselves.
void _expectBuiltThen(
  _TestPlugin plugin,
  String text, {
  required Set<TextWidgetLayer> layers,
  required List<String> then,
}) {
  final builds = <String>{
    for (final TextWidgetLayer layer in layers) 'build ${layer.name} "$text" hasLayout: true',
  };
  expect(plugin.log.take(builds.length).toSet(), builds);
  expect(plugin.log.skip(builds.length), then);
}

class _Stateful extends StatefulWidget {
  const _Stateful({super.key});

  @override
  State<_Stateful> createState() => _StatefulState();
}

class _StatefulState extends State<_Stateful> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Resizable extends StatefulWidget {
  const _Resizable({super.key});

  @override
  State<_Resizable> createState() => _ResizableState();
}

class _ResizableState extends State<_Resizable> {
  double _width = 10;

  void resize(double value) => setState(() => _width = value);

  @override
  Widget build(BuildContext context) => SizedBox(width: _width, height: 10);
}

class _Tick extends InheritedWidget {
  const _Tick({required this.value, required super.child});

  final int value;

  static int of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_Tick>()!.value;
  }

  @override
  bool updateShouldNotify(_Tick oldWidget) => value != oldWidget.value;
}

/// A widget that shows a popup below itself, in the overlay, when it is
/// tapped.
class _Popup extends StatefulWidget {
  const _Popup();

  @override
  State<_Popup> createState() => _PopupState();
}

class _PopupState extends State<_Popup> {
  final OverlayPortalController _controller = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _controller,
      overlayChildBuilder: (BuildContext context, OverlayChildLayoutInfo info) {
        final Offset origin = MatrixUtils.transformPoint(
          info.childPaintTransform,
          info.childSize.bottomLeft(Offset.zero),
        );
        return Positioned(
          left: origin.dx,
          top: origin.dy,
          child: const SizedBox(key: ValueKey<String>('popup'), width: 50, height: 20),
        );
      },
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _controller.toggle),
    );
  }
}

void main() {
  group('TextWidgetPlugin', () {
    testWidgets('Text is only wrapped in a host when a widget plugin is in scope', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(plugins: const <TextPlugin>[_PainterOnlyPlugin()], const Text('aX')),
      );
      expect(find.byType(TextPluginWidgetHost), findsNothing);

      final plugin = _TestPlugin(_markX);
      await tester.pumpWidget(
        _app(plugins: <TextPlugin>[const _PainterOnlyPlugin(), plugin], const Text('aX')),
      );
      expect(find.byType(TextPluginWidgetHost), findsOneWidget);
      expect(find.byKey(_marker(TextWidgetLayer.foreground)), findsOneWidget);

      await tester.pumpWidget(
        _app(plugins: const <TextPlugin>[_PainterOnlyPlugin()], const Text('aX')),
      );
      expect(find.byType(TextPluginWidgetHost), findsNothing);
      expect(find.byKey(_marker(TextWidgetLayer.foreground)), findsNothing);
      expect(plugin.log.last, 'didRemoveText');
    });

    for (final tight in <bool>[false, true]) {
      final constraints = tight ? 'tight' : 'loose';
      testWidgets('widgets are built from the new layout in the frame in which the text changes '
          '($constraints constraints)', (WidgetTester tester) async {
        final plugin = _TestPlugin(_markX, layers: _allLayers);
        // With tight constraints the text render object is a relayout
        // boundary: it is laid out on its own, not by the host.
        Widget build(String text) {
          return _app(
            plugins: <TextPlugin>[plugin],
            tight ? SizedBox(width: 300, height: 50, child: Text(text)) : Text(text),
          );
        }

        await tester.pumpWidget(build('aX'));
        _expectBuiltThen(
          plugin,
          'aX',
          layers: _allLayers,
          then: <String>['didAddText', 'didLayoutText'],
        );
        for (final TextWidgetLayer layer in _allLayers) {
          expect(
            tester.getRect(find.byKey(_marker(layer))),
            const Rect.fromLTWH(14, 0, 14, 14),
            reason: layer.name,
          );
        }

        // Let the app settle; it schedules a second frame when it starts.
        await tester.pump();
        plugin.log.clear();

        await tester.pumpWidget(build('aaaaX'));
        _expectBuiltThen(
          plugin,
          'aaaaX',
          layers: _allLayers,
          then: <String>['didUpdateText', 'didLayoutText'],
        );
        for (final TextWidgetLayer layer in _allLayers) {
          expect(
            tester.getRect(find.byKey(_marker(layer))),
            const Rect.fromLTWH(56, 0, 14, 14),
            reason: layer.name,
          );
        }
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }

    testWidgets('widgets are rebuilt in the same frame when the text is laid out on its own', (
      WidgetTester tester,
    ) async {
      final plugin = _TestPlugin(_markX, layers: _allLayers);
      final resizable = GlobalKey<_ResizableState>();
      // The text has tight constraints, so its render object is a relayout
      // boundary. When the inline widget changes its size, only that render
      // object is marked as needing layout. The Text is not rebuilt and its
      // host is not laid out.
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          SizedBox(
            width: 300,
            height: 50,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  WidgetSpan(child: _Resizable(key: resizable)),
                  const TextSpan(text: 'aX'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_rectOfX(tester).left, 24);
      plugin.log.clear();

      resizable.currentState!.resize(60);
      await tester.pump();

      expect(_rectOfX(tester).left, 74);
      _expectBuiltThen(plugin, '\uFFFCaX', layers: _allLayers, then: <String>['didLayoutText']);
      for (final TextWidgetLayer layer in _allLayers) {
        expect(tester.getRect(find.byKey(_marker(layer))), _rectOfX(tester), reason: layer.name);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('widgets are rebuilt in the same frame when the constraints of the text change', (
      WidgetTester tester,
    ) async {
      final plugin = _TestPlugin(_markX, layers: _allLayers);
      // The same widget in both frames, so the Text is not rebuilt. Its render
      // object is laid out again because its constraints change; it is never
      // marked as needing layout.
      const Widget text = Text('aaa X');
      Widget build(double width) {
        return _app(
          plugins: <TextPlugin>[plugin],
          SizedBox(width: width, child: text),
        );
      }

      await tester.pumpWidget(build(300));
      await tester.pump();
      expect(_rectOfX(tester), const Rect.fromLTWH(56, 0, 14, 14));
      plugin.log.clear();

      // Four glyphs fit, so the X moves to the second line.
      await tester.pumpWidget(build(56));
      expect(_rectOfX(tester), const Rect.fromLTWH(0, 14, 14, 14));
      _expectBuiltThen(plugin, 'aaa X', layers: _allLayers, then: <String>['didLayoutText']);
      for (final TextWidgetLayer layer in _allLayers) {
        expect(tester.getRect(find.byKey(_marker(layer))), _rectOfX(tester), reason: layer.name);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('widgets are rebuilt when the selection of a Text changes', (
      WidgetTester tester,
    ) async {
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          for (final TextSelection selection in delegate.selections)
            if (!selection.isCollapsed)
              TextPositioned.fill(
                delegate: delegate,
                range: selection,
                child: SizedBox.expand(key: _marker(layer)),
              ),
        ],
      );
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          SelectableRegion(
            selectionControls: emptyTextSelectionControls,
            child: const Text('abcdXf'),
          ),
        ),
      );
      await tester.pump();
      final Finder marker = find.byKey(_marker(TextWidgetLayer.foreground));
      expect(marker, findsNothing);

      // Drag from the "b" to the "c".
      final TestGesture gesture = await tester.startGesture(
        const Offset(15, 7),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(const Offset(41, 7));
      // The frame that paints the new selection also has the new widgets.
      await tester.pump();
      expect(
        _paragraph(tester).selections.single,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );
      expect(tester.getRect(marker), const Rect.fromLTWH(14, 0, 28, 14));

      await gesture.moveTo(const Offset(69, 7));
      await tester.pump();
      expect(
        _paragraph(tester).selections.single,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      expect(tester.getRect(marker), const Rect.fromLTWH(14, 0, 56, 14));

      await gesture.up();
      await tester.pump();
      expect(tester.getRect(marker), const Rect.fromLTWH(14, 0, 56, 14));
    });

    testWidgets('the text is laid out before a layer that is rebuilt on its own', (
      WidgetTester tester,
    ) async {
      final ticks = <int>[];
      final plugin = _TestPlugin((
        BuildContext context,
        TextDelegate delegate,
        TextWidgetLayer layer,
      ) {
        // Makes the layer depend on the inherited widget.
        ticks.add(_Tick.of(context));
        return _markX(context, delegate, layer);
      });
      final resizable = GlobalKey<_ResizableState>();
      // The same widget in every frame, so that the Text is never rebuilt.
      final Widget text = SizedBox(
        width: 300,
        height: 50,
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              WidgetSpan(child: _Resizable(key: resizable)),
              const TextSpan(text: 'aX'),
            ],
          ),
        ),
      );
      Widget build(int tick) {
        return _app(
          plugins: <TextPlugin>[plugin],
          _Tick(value: tick, child: text),
        );
      }

      await tester.pumpWidget(build(0));
      await tester.pump();
      plugin.log.clear();
      ticks.clear();

      // Only the layer is dirty.
      await tester.pumpWidget(build(1));
      expect(ticks, <int>[1]);
      expect(plugin.log, <String>['build foreground "\uFFFCaX" hasLayout: true']);
      plugin.log.clear();
      ticks.clear();

      // The layer and the text are dirty, and the host is not.
      resizable.currentState!.resize(60);
      await tester.pumpWidget(build(2));
      expect(ticks, <int>[2]);
      expect(plugin.log, <String>['build foreground "\uFFFCaX" hasLayout: true', 'didLayoutText']);
      expect(_rectOfX(tester).left, 74);
      expect(tester.getRect(find.byKey(_marker(TextWidgetLayer.foreground))), _rectOfX(tester));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the background layer paints behind the text and the foreground layer in front', (
      WidgetTester tester,
    ) async {
      const background = Color(0xFF111111);
      const foreground = Color(0xFF222222);
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          // Not wrapped in a TextPositioned, so it covers the text.
          ColoredBox(color: layer == TextWidgetLayer.background ? background : foreground),
        ],
        layers: const <TextWidgetLayer>{TextWidgetLayer.background, TextWidgetLayer.foreground},
      );
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aX')));

      expect(
        _host(tester),
        paints
          ..rect(color: background, rect: const Rect.fromLTWH(0, 0, 28, 14))
          ..paragraph()
          ..rect(color: foreground, rect: const Rect.fromLTWH(0, 0, 28, 14)),
      );
    });

    testWidgets('foreground widgets are hit before the text and background widgets are not hit', (
      WidgetTester tester,
    ) async {
      final taps = <String>[];
      final recognizer = TapGestureRecognizer()..onTap = () => taps.add('text');
      addTearDown(recognizer.dispose);

      Iterable<Widget> detectorOnX(
        BuildContext context,
        TextDelegate delegate,
        TextWidgetLayer layer,
      ) {
        return <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 1, end: 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps.add(layer.name),
            ),
          ),
        ];
      }

      final text = Text.rich(TextSpan(text: 'aXb', recognizer: recognizer));
      const onA = Offset(7, 7);
      const onX = Offset(21, 7);

      await tester.pumpWidget(_app(plugins: <TextPlugin>[_TestPlugin(detectorOnX)], text));
      await tester.tapAt(onX);
      expect(taps, <String>['foreground']);
      taps.clear();
      await tester.tapAt(onA);
      expect(taps, <String>['text']);
      taps.clear();

      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[
            _TestPlugin(detectorOnX, layers: const <TextWidgetLayer>{TextWidgetLayer.background}),
          ],
          text,
        ),
      );
      await tester.tapAt(onX);
      expect(taps, <String>['text']);
    });

    testWidgets('TextPositioned places its child against the range', (WidgetTester tester) async {
      const anchored = ValueKey<String>('anchored');
      const filled = ValueKey<String>('filled');
      const twoLines = ValueKey<String>('two lines');
      const caret = ValueKey<String>('caret');
      const fromRect = ValueKey<String>('from rect');
      const invalid = ValueKey<String>('invalid');
      const pastTheEnd = ValueKey<String>('past the end');
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          TextPositioned(
            delegate: delegate,
            range: const TextRange(start: 1, end: 2),
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -1),
            child: const SizedBox(key: anchored, width: 6, height: 4),
          ),
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 0, end: 2),
            child: const SizedBox.expand(key: filled),
          ),
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 2, end: 5),
            child: const SizedBox.expand(key: twoLines),
          ),
          TextPositioned(
            delegate: delegate,
            range: const TextRange.collapsed(2),
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            child: const SizedBox(key: caret, width: 8, height: 8),
          ),
          const TextPositioned.fromRect(
            rect: Rect.fromLTWH(3, 4, 5, 6),
            child: SizedBox.expand(key: fromRect),
          ),
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange.empty,
            child: const SizedBox.expand(key: invalid),
          ),
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 50, end: 51),
            child: const SizedBox.expand(key: pastTheEnd),
          ),
        ],
      );
      // Three glyphs fit on a line, so the text is "aXb" and "cd". The text
      // widget is at (10, 20).
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          const Padding(
            padding: EdgeInsets.only(left: 10, top: 20),
            child: SizedBox(width: 42, child: Text('aXbcd')),
          ),
        ),
      );

      // The bottom right of the child is one pixel above the top right of
      // the X, which is at (38, 20).
      expect(tester.getRect(find.byKey(anchored)), const Rect.fromLTRB(32, 15, 38, 19));
      expect(tester.getRect(find.byKey(filled)), const Rect.fromLTRB(10, 20, 38, 34));
      // "b" is at the end of the first line and "cd" at the start of the
      // second, so the bounding box spans both lines.
      expect(tester.getRect(find.byKey(twoLines)), const Rect.fromLTRB(10, 20, 52, 48));
      // Centered below the caret between "X" and "b", which is at x = 38.
      expect(tester.getRect(find.byKey(caret)), const Rect.fromLTRB(34, 34, 42, 42));
      expect(tester.getRect(find.byKey(fromRect)), const Rect.fromLTRB(13, 24, 18, 30));

      // A child without a rectangle stays in the tree, but it is not painted
      // and cannot be hit.
      for (final key in <ValueKey<String>>[invalid, pastTheEnd]) {
        final RenderObject child = tester.renderObject(find.byKey(key));
        expect((child.parentData! as TextWidgetParentData).isVisible, isFalse, reason: key.value);
      }
    });

    testWidgets('a widget for a range that was truncated is hidden', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[_TestPlugin(_markX)],
          const SizedBox(
            width: 56,
            child: Text('aaaaaaX', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );

      final RenderObject marker = tester.renderObject(
        find.byKey(_marker(TextWidgetLayer.foreground)),
      );
      expect((marker.parentData! as TextWidgetParentData).isVisible, isFalse);
    });

    testWidgets('widgets keep their state when the text changes', (WidgetTester tester) async {
      final plugin = _TestPlugin((BuildContext context, TextDelegate delegate, TextWidgetLayer _) {
        final int index = delegate.text.indexOf('X');
        return <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange(start: index, end: index + 1),
            child: const _Stateful(),
          ),
        ];
      });
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aX')));
      final State<_Stateful> state = tester.state(find.byType(_Stateful));
      expect(tester.getRect(find.byType(_Stateful)), const Rect.fromLTWH(14, 0, 14, 14));

      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aaaX')));
      expect(tester.state(find.byType(_Stateful)), same(state));
      expect(tester.getRect(find.byType(_Stateful)), const Rect.fromLTWH(42, 0, 14, 14));
    });

    testWidgets('a plugin that is a Listenable rebuilds its widgets when it notifies', (
      WidgetTester tester,
    ) async {
      final plugin = _CounterPlugin();
      addTearDown(plugin.dispose);
      var textBuilds = 0;
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          Builder(
            builder: (BuildContext context) {
              textBuilds += 1;
              return const Text('aX');
            },
          ),
        ),
      );
      expect(find.text('count: 0'), findsOneWidget);
      expect(plugin.builds, 1);

      plugin.increment();
      await tester.pump();

      expect(find.text('count: 1'), findsOneWidget);
      expect(plugin.builds, 2);
      // Only the widgets of the plugin were rebuilt.
      expect(textBuilds, 1);
    });

    testWidgets('a plugin that notifies during a frame has its widgets rebuilt in the next frame', (
      WidgetTester tester,
    ) async {
      final plugin = _LengthPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aX')));
      await tester.pump();
      expect(find.text('length: 2'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aXbb')));
      // The widgets of this frame were built before didLayoutText was called.
      expect(find.text('length: 2'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pump();
      expect(find.text('length: 4'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a plugin that notifies before layout has its widgets rebuilt in that frame', (
      WidgetTester tester,
    ) async {
      final plugin = _CounterPlugin();
      addTearDown(plugin.dispose);
      Widget build(String text, {bool notify = false}) {
        return _app(
          plugins: <TextPlugin>[plugin],
          Builder(
            builder: (BuildContext context) {
              if (notify) {
                // During build, when no other widget can be marked as needing
                // to build. This is what happens when a parent updates the
                // plugin from its own build or didUpdateWidget.
                plugin.increment();
              }
              return Text(text);
            },
          ),
        );
      }

      await tester.pumpWidget(build('aX'));
      await tester.pump();
      expect(plugin.builds, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(build('aXb', notify: true));
      expect(plugin.count, greaterThan(0));
      expect(find.text('count: ${plugin.count}'), findsOneWidget);
      expect(plugin.builds, 2);
      // The widgets were built after the notification, so nothing is left to
      // do.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('text plugins and selection do not apply to the widgets of a plugin', (
      WidgetTester tester,
    ) async {
      SelectionRegistrar? registrarOutside;
      SelectionRegistrar? registrarInside;
      List<TextPlugin>? pluginsInside;
      // This plugin shows a Text for every text widget. If it applied to its
      // own widgets, it would never stop building.
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          TextPositioned(
            delegate: delegate,
            range: const TextRange(start: 0, end: 1),
            targetAnchor: Alignment.bottomLeft,
            child: Builder(
              builder: (BuildContext context) {
                registrarInside = SelectionContainer.maybeOf(context);
                pluginsInside = TextPluginScope.maybeOf(context);
                return const Text('badge');
              },
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          SelectableRegion(
            selectionControls: emptyTextSelectionControls,
            child: Builder(
              builder: (BuildContext context) {
                registrarOutside = SelectionContainer.maybeOf(context);
                return const Text('aX');
              },
            ),
          ),
        ),
      );

      expect(find.text('badge'), findsOneWidget);
      expect(registrarOutside, isNotNull);
      expect(registrarInside, isNull);
      expect(pluginsInside, isNull);
      expect(plugin.builds, <String>['build foreground "aX" hasLayout: true']);
      expect(find.byType(TextPluginWidgetHost), findsOneWidget);
    });

    testWidgets('widgets of a plugin are in the semantics tree', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      var taps = 0;
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 1, end: 2),
            child: Semantics(
              button: true,
              label: 'Open',
              onTap: () => taps += 1,
              child: const SizedBox.expand(),
            ),
          ),
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange.empty,
            child: Semantics(label: 'Hidden', child: const SizedBox.expand()),
          ),
        ],
      );
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aXb')));

      expect(find.semantics.byLabel('aXb'), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Open')),
        matchesSemantics(label: 'Open', isButton: true, hasTapAction: true),
      );
      expect(tester.getRect(find.bySemanticsLabel('Open')), const Rect.fromLTWH(14, 0, 14, 14));
      expect(find.semantics.byLabel('Hidden'), findsNothing);

      tester.semantics.tap(find.semantics.byLabel('Open'));
      expect(taps, 1);
      handle.dispose();
    });

    for (final scopeAboveApp in <bool>[false, true]) {
      final where = scopeAboveApp ? 'above' : 'inside';
      testWidgets('focusable widgets of a plugin take part in focus traversal '
          '(scope $where the app)', (WidgetTester tester) async {
        final before = FocusNode(debugLabel: 'before');
        final inPlugin = FocusNode(debugLabel: 'in plugin');
        final after = FocusNode(debugLabel: 'after');
        addTearDown(before.dispose);
        addTearDown(inPlugin.dispose);
        addTearDown(after.dispose);
        final plugin = _TestPlugin(
          (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
            TextPositioned.fill(
              delegate: delegate,
              range: const TextRange(start: 1, end: 2),
              child: Focus(focusNode: inPlugin, child: const SizedBox.expand()),
            ),
          ],
        );
        final Widget content = Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Focus(focusNode: before, child: const SizedBox(width: 10, height: 10)),
              const Text('aXb'),
              Focus(focusNode: after, child: const SizedBox(width: 10, height: 10)),
            ],
          ),
        );
        // The focus node is created where the text is, so it is in the focus
        // scope of the route even when the plugin is installed above the app.
        await tester.pumpWidget(
          scopeAboveApp
              ? TextPluginScope(
                  plugin: plugin,
                  child: TestWidgetsApp(home: content),
                )
              : TestWidgetsApp(
                  home: TextPluginScope(plugin: plugin, child: content),
                ),
        );
        before.requestFocus();
        await tester.pump();
        expect(before.hasPrimaryFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(inPlugin.hasPrimaryFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(after.hasPrimaryFocus, isTrue);
      });
    }

    testWidgets('a MouseRegion in a plugin widget tracks the pointer and sets the cursor', (
      WidgetTester tester,
    ) async {
      final events = <String>[];
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 1, end: 2),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (PointerEnterEvent _) => events.add('enter'),
              onExit: (PointerExitEvent _) => events.add('exit'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aXb')));

      final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(100, 100));
      await gesture.moveTo(const Offset(21, 7));
      await tester.pump();
      expect(events, <String>['enter']);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await gesture.moveTo(const Offset(7, 7));
      await tester.pump();
      expect(events, <String>['enter', 'exit']);
      await gesture.removePointer();
    });

    testWidgets('the host does not change the size, intrinsic size or baseline of the text', (
      WidgetTester tester,
    ) async {
      const small = ValueKey<String>('small');
      const large = ValueKey<String>('large');
      const Widget content = IntrinsicWidth(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text('aX', key: small, style: TextStyle(fontSize: 10)),
            Text('bX', key: large, style: TextStyle(fontSize: 30)),
          ],
        ),
      );

      await tester.pumpWidget(_app(plugins: const <TextPlugin>[], content));
      expect(find.byType(TextPluginWidgetHost), findsNothing);
      final Rect smallRect = tester.getRect(find.byKey(small));
      final Rect largeRect = tester.getRect(find.byKey(large));
      final Rect rowRect = tester.getRect(find.byType(Row));
      // The baselines are aligned, so the small text is not at the top.
      expect(smallRect.top, greaterThan(largeRect.top));

      await tester.pumpWidget(
        _app(plugins: <TextPlugin>[_TestPlugin(_markX, layers: _allLayers)], content),
      );
      expect(find.byType(TextPluginWidgetHost), findsNWidgets(2));
      expect(tester.getRect(find.byKey(small)), smallRect);
      expect(tester.getRect(find.byKey(large)), largeRect);
      expect(tester.getRect(find.byType(Row)), rowRect);
    });

    testWidgets('each plugin has its own widgets, stacked in the order of the plugins', (
      WidgetTester tester,
    ) async {
      const first = Color(0xFF111111);
      const second = Color(0xFF222222);
      // Both plugins use the same key, and the second one only has a widget
      // when the text contains a Y.
      final a = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          const ColoredBox(key: ValueKey<String>('same'), color: first, child: _Stateful()),
        ],
      );
      final b = _SecondTestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          if (delegate.text.contains('Y'))
            const ColoredBox(key: ValueKey<String>('same'), color: second),
        ],
      );

      await tester.pumpWidget(_app(plugins: <TextPlugin>[a, b], const Text('aX')));
      final State<_Stateful> state = tester.state(find.byType(_Stateful));
      expect(
        _host(tester),
        paints
          ..paragraph()
          ..rect(color: first),
      );
      expect(_host(tester), isNot(paints..rect(color: second)));

      await tester.pumpWidget(_app(plugins: <TextPlugin>[a, b], const Text('aXY')));
      expect(
        _host(tester),
        paints
          ..paragraph()
          ..rect(color: first)
          ..rect(color: second),
      );
      expect(tester.state(find.byType(_Stateful)), same(state));

      await tester.pumpWidget(_app(plugins: <TextPlugin>[a, b], const Text('aX')));
      expect(_host(tester), isNot(paints..rect(color: second)));
      expect(tester.state(find.byType(_Stateful)), same(state));
    });
  });

  group('TextWidgetLayer.overlay', () {
    testWidgets('widgets are shown in the overlay, over the text', (WidgetTester tester) async {
      final plugin = _TestPlugin(_markX, layers: const <TextWidgetLayer>{TextWidgetLayer.overlay});
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          const Padding(padding: EdgeInsets.only(left: 10, top: 20), child: Text('aX')),
        ),
      );

      final Finder marker = find.byKey(_marker(TextWidgetLayer.overlay));
      expect(tester.getRect(marker), const Rect.fromLTWH(24, 20, 14, 14));
      // The widget is below the Text in the widget tree, but its render
      // object is in the overlay, not in the host.
      expect(find.descendant(of: find.byType(Text), matching: marker), findsOneWidget);
      expect(_isRenderDescendant(tester.renderObject(marker), _host(tester)), isFalse);
    });

    testWidgets('an OverlayPortal only exists while a plugin has widgets in the layer', (
      WidgetTester tester,
    ) async {
      final plugin = _TestPlugin(_markX, layers: const <TextWidgetLayer>{TextWidgetLayer.overlay});
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('a')));
      expect(find.byType(TextPluginWidgetHost), findsOneWidget);
      expect(find.byType(OverlayPortal), findsNothing);

      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aX')));
      expect(find.byType(OverlayPortal), findsOneWidget);
      expect(
        tester.getRect(find.byKey(_marker(TextWidgetLayer.overlay))),
        const Rect.fromLTWH(14, 0, 14, 14),
      );

      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('a')));
      expect(find.byType(OverlayPortal), findsNothing);
      expect(find.byKey(_marker(TextWidgetLayer.overlay)), findsNothing);

      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aaX')));
      expect(
        tester.getRect(find.byKey(_marker(TextWidgetLayer.overlay))),
        const Rect.fromLTWH(28, 0, 14, 14),
      );
    });

    testWidgets('widgets follow the text when it scrolls, but are not clipped with it', (
      WidgetTester tester,
    ) async {
      final taps = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      // A foreground widget on the X and an overlay widget on the Y.
      final plugin = _TestPlugin((
        BuildContext context,
        TextDelegate delegate,
        TextWidgetLayer layer,
      ) {
        final index = layer == TextWidgetLayer.foreground ? 1 : 2;
        return <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange(start: index, end: index + 1),
            child: GestureDetector(
              key: _marker(layer),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps.add(layer.name),
            ),
          ),
        ];
      }, layers: const <TextWidgetLayer>{TextWidgetLayer.foreground, TextWidgetLayer.overlay});
      // The viewport is the area from y = 100 to y = 200.
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          Padding(
            padding: const EdgeInsets.only(top: 100),
            child: SizedBox(
              width: 200,
              height: 100,
              child: SingleChildScrollView(
                controller: controller,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[SizedBox(height: 60), Text('aXY'), SizedBox(height: 500)],
                ),
              ),
            ),
          ),
        ),
      );
      final Finder foreground = find.byKey(_marker(TextWidgetLayer.foreground));
      final Finder overlay = find.byKey(_marker(TextWidgetLayer.overlay));
      expect(tester.getRect(foreground), const Rect.fromLTWH(14, 160, 14, 14));
      expect(tester.getRect(overlay), const Rect.fromLTWH(28, 160, 14, 14));
      await tester.tapAt(const Offset(21, 167));
      await tester.tapAt(const Offset(35, 167));
      expect(taps, <String>['foreground', 'overlay']);
      taps.clear();
      await tester.pump();
      plugin.log.clear();

      // Both follow the text, and the plugin is not asked again.
      controller.jumpTo(30);
      await tester.pump();
      expect(tester.getRect(foreground), const Rect.fromLTWH(14, 130, 14, 14));
      expect(tester.getRect(overlay), const Rect.fromLTWH(28, 130, 14, 14));
      expect(plugin.log, isEmpty);

      // The text is now above the viewport, at y = 80. The foreground widget
      // is clipped with it. The overlay widget is not.
      controller.jumpTo(80);
      await tester.pump();
      expect(tester.getRect(overlay), const Rect.fromLTWH(28, 80, 14, 14));
      await tester.tapAt(const Offset(21, 87));
      await tester.tapAt(const Offset(35, 87));
      expect(taps, <String>['overlay']);
    });

    testWidgets('widgets are in front of everything else in the route', (
      WidgetTester tester,
    ) async {
      final taps = <String>[];
      // A foreground widget on the X and an overlay widget on the Y.
      final plugin = _TestPlugin((
        BuildContext context,
        TextDelegate delegate,
        TextWidgetLayer layer,
      ) {
        final index = layer == TextWidgetLayer.foreground ? 1 : 2;
        return <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange(start: index, end: index + 1),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps.add(layer.name),
            ),
          ),
        ];
      }, layers: const <TextWidgetLayer>{TextWidgetLayer.foreground, TextWidgetLayer.overlay});
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          Stack(
            children: <Widget>[
              const Text('aXY'),
              // Painted after the text, and covering it.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps.add('cover'),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.tapAt(const Offset(21, 7));
      await tester.tapAt(const Offset(35, 7));
      expect(taps, <String>['cover', 'overlay']);
    });

    testWidgets('widgets outside the bounds of the text can only be hit in the overlay layer', (
      WidgetTester tester,
    ) async {
      final taps = <String>[];
      // Each layer has a widget just above the text: the foreground layer
      // above the "a" and the overlay layer above the "X".
      final plugin = _TestPlugin((
        BuildContext context,
        TextDelegate delegate,
        TextWidgetLayer layer,
      ) {
        final index = layer == TextWidgetLayer.foreground ? 0 : 1;
        return <Widget>[
          TextPositioned(
            delegate: delegate,
            range: TextRange(start: index, end: index + 1),
            followerAnchor: Alignment.bottomLeft,
            child: GestureDetector(
              key: _marker(layer),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps.add(layer.name),
              child: const SizedBox(width: 14, height: 14),
            ),
          ),
        ];
      }, layers: const <TextWidgetLayer>{TextWidgetLayer.foreground, TextWidgetLayer.overlay});
      // The text widget is at (10, 40).
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          const Padding(padding: EdgeInsets.only(left: 10, top: 40), child: Text('aXb')),
        ),
      );

      // Both widgets are above the text, at negative coordinates in the
      // coordinate space of the text widget.
      expect(
        tester.getRect(find.byKey(_marker(TextWidgetLayer.foreground))),
        const Rect.fromLTWH(10, 26, 14, 14),
      );
      expect(
        tester.getRect(find.byKey(_marker(TextWidgetLayer.overlay))),
        const Rect.fromLTWH(24, 26, 14, 14),
      );
      await tester.tapAt(const Offset(17, 33));
      await tester.tapAt(const Offset(31, 33));
      expect(taps, <String>['overlay']);
    });

    testWidgets('the layer is not built without an Overlay', (WidgetTester tester) async {
      final plugin = _TestPlugin(
        _markX,
        layers: const <TextWidgetLayer>{TextWidgetLayer.foreground, TextWidgetLayer.overlay},
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextPluginScope(
            plugin: plugin,
            child: const Align(alignment: Alignment.topLeft, child: Text('aX')),
          ),
        ),
      );

      expect(find.byKey(_marker(TextWidgetLayer.foreground)), findsOneWidget);
      expect(find.byKey(_marker(TextWidgetLayer.overlay)), findsNothing);
      expect(plugin.builds, <String>['build foreground "aX" hasLayout: true']);
    });

    testWidgets('a foreground widget can show its own overlay child instead', (
      WidgetTester tester,
    ) async {
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: const TextRange(start: 1, end: 2),
            child: const _Popup(),
          ),
        ],
      );
      await tester.pumpWidget(_app(plugins: <TextPlugin>[plugin], const Text('aXb')));
      const popup = ValueKey<String>('popup');
      expect(find.byKey(popup), findsNothing);

      await tester.tapAt(const Offset(21, 7));
      await tester.pump();
      // Below the X, and larger than the text widget.
      expect(tester.getRect(find.byKey(popup)), const Rect.fromLTWH(14, 14, 50, 20));

      await tester.tapAt(const Offset(21, 7));
      await tester.pump();
      expect(find.byKey(popup), findsNothing);
    });
  });

  group('EditableText', () {
    Rect rectOfX(WidgetTester tester) {
      final RenderEditable editable = tester.allRenderObjects.whereType<RenderEditable>().single;
      final int index = editable.plainText.indexOf('X');
      final Rect local = editable
          .getBoxesForSelection(TextSelection(baseOffset: index, extentOffset: index + 1))
          .single
          .toRect();
      return MatrixUtils.transformRect(editable.getTransformTo(null), local);
    }

    Widget editableText(
      TextEditingController controller,
      FocusNode focusNode, {
      ScrollController? scrollController,
      double width = 300,
    }) {
      return SizedBox(
        width: width,
        child: EditableText(
          controller: controller,
          focusNode: focusNode,
          scrollController: scrollController,
          style: const TextStyle(),
          cursorColor: const Color(0xFF000000),
          backgroundCursorColor: const Color(0xFF000000),
        ),
      );
    }

    testWidgets('widgets are built from the new layout in the frame in which the text changes', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'aX');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      final plugin = _TestPlugin(_markX, layers: _allLayers);
      await tester.pumpWidget(
        _app(plugins: <TextPlugin>[plugin], editableText(controller, focusNode)),
      );
      expect(find.byType(TextPluginWidgetHost), findsOneWidget);
      for (final TextWidgetLayer layer in _allLayers) {
        expect(
          tester.getRect(find.byKey(_marker(layer))),
          const Rect.fromLTWH(14, 0, 14, 14),
          reason: layer.name,
        );
      }
      await tester.pump();
      plugin.log.clear();

      controller.text = 'aaaX';
      await tester.pump();

      expect(rectOfX(tester), const Rect.fromLTWH(42, 0, 14, 14));
      _expectBuiltThen(
        plugin,
        'aaaX',
        layers: _allLayers,
        then: <String>['didUpdateText', 'didLayoutText'],
      );
      for (final TextWidgetLayer layer in _allLayers) {
        expect(tester.getRect(find.byKey(_marker(layer))), rectOfX(tester), reason: layer.name);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('widgets follow the text when it scrolls and are clipped with it', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'aaaaaaaaXb');
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);
      const color = Color(0xFF123456);
      final plugin = _TestPlugin((BuildContext context, TextDelegate delegate, TextWidgetLayer _) {
        final int index = delegate.text.indexOf('X');
        return <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange(start: index, end: index + 1),
            child: ColoredBox(key: _marker(TextWidgetLayer.foreground), color: color),
          ),
        ];
      });
      // Four of the ten glyphs fit.
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          editableText(controller, focusNode, scrollController: scrollController, width: 56),
        ),
      );
      final Finder marker = find.byKey(_marker(TextWidgetLayer.foreground));
      expect(tester.getRect(marker), const Rect.fromLTWH(112, 0, 14, 14));
      // The layers of an EditableText are clipped to its bounds, like its
      // text.
      expect(
        find.descendant(of: find.byType(TextPluginWidgetHost), matching: find.byType(ClipRect)),
        findsOneWidget,
      );
      expect(
        _host(tester),
        paints
          ..clipRect(rect: const Rect.fromLTWH(0, 0, 56, 14))
          ..rect(color: color),
      );

      scrollController.jumpTo(84);
      await tester.pump();

      expect(rectOfX(tester), const Rect.fromLTWH(28, 0, 14, 14));
      expect(tester.getRect(marker), const Rect.fromLTWH(28, 0, 14, 14));
    });

    testWidgets('widgets are rebuilt in the same frame when the selection changes', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'abcdef');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      final plugin = _TestPlugin(
        (BuildContext context, TextDelegate delegate, TextWidgetLayer layer) => <Widget>[
          for (final TextSelection selection in delegate.selections)
            if (!selection.isCollapsed)
              TextPositioned.fill(
                delegate: delegate,
                range: selection,
                child: SizedBox.expand(key: _marker(layer)),
              ),
        ],
      );
      await tester.pumpWidget(
        _app(plugins: <TextPlugin>[plugin], editableText(controller, focusNode)),
      );
      await tester.pump();
      final Finder marker = find.byKey(_marker(TextWidgetLayer.foreground));
      expect(marker, findsNothing);

      controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      await tester.pump();
      expect(tester.getRect(marker), const Rect.fromLTWH(14, 0, 28, 14));
      expect(tester.binding.hasScheduledFrame, isFalse);

      controller.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
      await tester.pump();
      expect(tester.getRect(marker), const Rect.fromLTWH(28, 0, 56, 14));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('TextPluginWidgetHost', () {
    Widget richText(BuildContext context, String text) {
      return RichText(
        text: TextSpan(text: text, style: DefaultTextStyle.of(context).style),
      );
    }

    testWidgets('hosts the widgets of a RichText', (WidgetTester tester) async {
      final plugin = _TestPlugin(_markX, layers: _allLayers);
      Widget build(String text) {
        return _app(
          plugins: <TextPlugin>[plugin],
          Builder(
            builder: (BuildContext context) {
              return TextPluginWidgetHost(child: richText(context, text));
            },
          ),
        );
      }

      // Without a host, a RichText gets the plugin but not its widgets.
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          Builder(builder: (BuildContext context) => richText(context, 'aX')),
        ),
      );
      expect(plugin.log, <String>['didAddText', 'didLayoutText']);

      await tester.pumpWidget(build('aX'));
      await tester.pump();
      plugin.log.clear();
      await tester.pumpWidget(build('aaaX'));
      for (final TextWidgetLayer layer in _allLayers) {
        expect(
          tester.getRect(find.byKey(_marker(layer))),
          const Rect.fromLTWH(42, 0, 14, 14),
          reason: layer.name,
        );
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('never drops the widgets when the text is not its child, and catches up in the '
        'next frame', (WidgetTester tester) async {
      final plugin = _TestPlugin((
        BuildContext context,
        TextDelegate delegate,
        TextWidgetLayer layer,
      ) {
        final int index = delegate.text.indexOf('X');
        return <Widget>[
          TextPositioned.fill(
            delegate: delegate,
            range: TextRange(start: index, end: index + 1),
            child: _Stateful(key: _marker(layer)),
          ),
        ];
      }, layers: const <TextWidgetLayer>{TextWidgetLayer.background, TextWidgetLayer.foreground});
      // The Padding is between the host and the text, and the text has tight
      // constraints. When the text changes, the host cannot tell whether a
      // layer or the text is laid out first.
      Widget build(String text) {
        return _app(
          plugins: <TextPlugin>[plugin],
          SizedBox(
            width: 300,
            height: 50,
            child: Builder(
              builder: (BuildContext context) {
                return TextPluginWidgetHost(
                  child: Padding(padding: EdgeInsets.zero, child: richText(context, text)),
                );
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(build('aX'));
      await tester.pump();
      final Finder background = find.byKey(_marker(TextWidgetLayer.background));
      final Finder foreground = find.byKey(_marker(TextWidgetLayer.foreground));
      final State<_Stateful> backgroundState = tester.state(background);
      final State<_Stateful> foregroundState = tester.state(foreground);

      await tester.pumpWidget(build('aaaX'));
      // A layer that was laid out before the text shows what it showed
      // before.
      expect(tester.state(background), same(backgroundState));
      expect(tester.state(foreground), same(foregroundState));
      expect(tester.takeException(), isNull);

      await tester.pump();
      expect(tester.getRect(background), const Rect.fromLTWH(42, 0, 14, 14));
      expect(tester.getRect(foreground), const Rect.fromLTWH(42, 0, 14, 14));
      expect(tester.state(background), same(backgroundState));
      expect(tester.state(foreground), same(foregroundState));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
