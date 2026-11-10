// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editable_text_tester.dart';

/// Anchors [link] to the glyphs of the first occurrence of [pattern].
class _AnchoringPlugin extends TextPlugin {
  _AnchoringPlugin(this.pattern, this.link);

  final String pattern;
  final LayerLink link;
  final List<TextDelegate> delegates = <TextDelegate>[];

  /// The anchored rectangle, in the coordinates of the text widget.
  Rect? rect;

  bool get enabled => _enabled;
  bool _enabled = true;
  set enabled(bool value) {
    _enabled = value;
    delegates.forEach(_update);
  }

  void _update(TextDelegate delegate) {
    final int start = delegate.text.indexOf(pattern);
    if (!_enabled || start < 0) {
      rect = null;
      delegate.anchors = const <TextAnchor>[];
      return;
    }
    final List<TextBox> boxes = delegate.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + pattern.length),
    );
    rect = boxes.first.toRect();
    delegate.anchors = <TextAnchor>[TextAnchor(link: link, rect: rect!)];
  }

  @override
  void didAddText(TextDelegate delegate) {
    delegates.add(delegate);
  }

  // Also runs right after didAddText and didUpdateText.
  @override
  void didLayoutText(TextDelegate delegate) => _update(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    delegates.remove(delegate);
  }
}

/// Records the text widgets of its scope.
class _RecordingPlugin extends TextPlugin {
  final List<TextDelegate> delegates = <TextDelegate>[];

  @override
  void didAddText(TextDelegate delegate) {
    delegates.add(delegate);
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegates.remove(delegate);
  }
}

/// Paints the selection with rounded corners.
class _RoundedSelectionPlugin extends TextSelectionPlugin {
  const _RoundedSelectionPlugin();

  @override
  void paintSelectionHighlight(Canvas canvas, TextDelegate delegate, TextSelection selection) {
    final paint = Paint()..color = delegate.selectionColor ?? const Color(0xFF000000);
    for (final TextBox box in delegate.getBoxesForSelection(selection)) {
      canvas.drawRRect(RRect.fromRectAndRadius(box.toRect(), const Radius.circular(4)), paint);
    }
  }
}

/// A second selection plugin type, with the default look.
class _OtherSelectionPlugin extends TextSelectionPlugin {
  const _OtherSelectionPlugin();
}

/// Paints an opaque badge behind every "GOOG".
class _BadgePlugin extends TextPlugin {
  @override
  void didAddText(TextDelegate delegate) {
    delegate.backgroundPainter = _BadgePainter(delegate);
  }
}

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.delegate);

  final TextDelegate delegate;

  @override
  void paint(Canvas canvas, Size size) {
    final int start = delegate.text.indexOf('GOOG');
    final paint = Paint()..color = const Color(0xFF00FF00);
    for (final TextBox box in delegate.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + 4),
    )) {
      canvas.drawRect(box.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) => false;
}

/// The selection plugins that currently have a delegate on [paragraph].
List<TextSelectionPlugin> _selectionPluginsOf(RenderParagraph paragraph) {
  return paragraph.textPluginDelegates
      .map((TextDelegate delegate) => delegate.plugin)
      .whereType<TextSelectionPlugin>()
      .toList();
}

/// A [SelectableRegion] with the minimal selection controls of the tests.
Widget _selectableRegion({
  required Widget child,
  ValueChanged<SelectedContent?>? onSelectionChanged,
}) {
  return SelectableRegion(
    selectionControls: testTextSelectionHandleControls,
    onSelectionChanged: onSelectionChanged,
    child: child,
  );
}

void main() {
  RenderParagraph paragraphOf(WidgetTester tester, String text) {
    return tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
  }

  Future<void> selectAll(WidgetTester tester, GlobalKey key) async {
    Actions.invoke(key.currentContext!, const SelectAllTextIntent(SelectionChangedCause.keyboard));
    await tester.pump();
  }

  group('TextAnchor', () {
    testWidgets('keeps a follower attached to static text, also while it scrolls', (
      WidgetTester tester,
    ) async {
      final link = LayerLink();
      final plugin = _AnchoringPlugin('world', link);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const followerKey = Key('follower');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 100),
                    TextPluginScope(plugin: plugin, child: const Text('Hello world')),
                    const SizedBox(height: 2000),
                  ],
                ),
              ),
              CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.bottomLeft,
                showWhenUnlinked: false,
                child: const SizedBox(key: followerKey, width: 10, height: 10),
              ),
            ],
          ),
        ),
      );

      final RenderParagraph paragraph = paragraphOf(tester, 'Hello world');
      final Rect anchored = plugin.rect!;
      expect(anchored.left, greaterThan(0.0), reason: '"world" does not start the line.');

      // The follower sits at the bottom left of the anchored glyphs, and the
      // leader reports their size so that it can align with any edge.
      expect(link.leaderSize, anchored.size);
      expect(
        tester.getTopLeft(find.byKey(followerKey)),
        offsetMoreOrLessEquals(paragraph.localToGlobal(anchored.bottomLeft)),
      );
      // The paragraph pushes a layer for the anchor.
      expect(paragraph.needsCompositing, isTrue);

      // Scrolling moves the follower with the text. The plugin is not involved.
      final Offset before = tester.getTopLeft(find.byKey(followerKey));
      controller.jumpTo(40.0);
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(followerKey)),
        offsetMoreOrLessEquals(before - const Offset(0.0, 40.0)),
      );
      expect(
        tester.getTopLeft(find.byKey(followerKey)),
        offsetMoreOrLessEquals(paragraph.localToGlobal(anchored.bottomLeft)),
      );

      // Without anchors the paragraph stops pushing layers.
      plugin.enabled = false;
      await tester.pump();
      expect(link.leader, isNull);
      expect(paragraph.needsCompositing, isFalse);
    });

    testWidgets('follows the text when it is laid out again', (WidgetTester tester) async {
      final link = LayerLink();
      final plugin = _AnchoringPlugin('world', link);
      const followerKey = Key('follower');

      Widget build(double width) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: TextPluginScope(plugin: plugin, child: const Text('Hello world')),
                ),
              ),
              CompositedTransformFollower(
                link: link,
                showWhenUnlinked: false,
                child: const SizedBox(key: followerKey, width: 10, height: 10),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(build(400.0));
      final RenderParagraph paragraph = paragraphOf(tester, 'Hello world');
      final Rect oneLine = plugin.rect!;
      expect(
        tester.getTopLeft(find.byKey(followerKey)),
        offsetMoreOrLessEquals(paragraph.localToGlobal(oneLine.topLeft)),
      );

      // Narrow enough to wrap "world" onto a second line.
      await tester.pumpWidget(build(oneLine.left + oneLine.width / 2));
      final Rect wrapped = plugin.rect!;
      expect(wrapped.top, greaterThan(oneLine.top));
      expect(wrapped.left, 0.0);
      expect(
        tester.getTopLeft(find.byKey(followerKey)),
        offsetMoreOrLessEquals(paragraph.localToGlobal(wrapped.topLeft)),
      );
    });

    testWidgets('keeps a follower attached to editable text', (WidgetTester tester) async {
      final link = LayerLink();
      final plugin = _AnchoringPlugin('world', link);
      final controller = TextEditingController(text: 'Hello world');
      addTearDown(controller.dispose);
      const followerKey = Key('follower');

      await tester.pumpWidget(
        TestWidgetsApp(
          home: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(50.0),
                child: TextPluginScope(
                  plugin: plugin,
                  child: TestTextField(controller: controller),
                ),
              ),
              CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.bottomLeft,
                showWhenUnlinked: false,
                child: const SizedBox(key: followerKey, width: 10, height: 10),
              ),
            ],
          ),
        ),
      );

      final RenderEditable editable = tester.allRenderObjects.whereType<RenderEditable>().single;
      expect(plugin.rect!.left, greaterThan(0.0), reason: '"world" does not start the line.');
      expect(
        tester.getTopLeft(find.byKey(followerKey)),
        offsetMoreOrLessEquals(editable.localToGlobal(plugin.rect!.bottomLeft)),
      );
    });
  });

  group('TextSelectionPlugin', () {
    testWidgets('selectable text has exactly one, which a TextPluginScope can replace', (
      WidgetTester tester,
    ) async {
      final GlobalKey columnKey = GlobalKey();

      await tester.pumpWidget(
        TestWidgetsApp(
          home: _selectableRegion(
            child: Column(
              key: columnKey,
              children: const <Widget>[
                Text('Default'),
                TextPluginScope(
                  plugin: _RoundedSelectionPlugin(),
                  child: Column(
                    children: <Widget>[
                      Text('Rounded'),
                      // The innermost selection plugin wins.
                      TextPluginScope(plugin: _OtherSelectionPlugin(), child: Text('Inner')),
                      // Text that is not selectable gets none.
                      SelectionContainer.disabled(child: Text('Disabled')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final RenderParagraph defaultParagraph = paragraphOf(tester, 'Default');
      final RenderParagraph roundedParagraph = paragraphOf(tester, 'Rounded');
      final RenderParagraph innerParagraph = paragraphOf(tester, 'Inner');
      final RenderParagraph disabledParagraph = paragraphOf(tester, 'Disabled');

      // The region installs no TextPluginScope: the text adds the default
      // selection plugin itself.
      expect(defaultParagraph.textPlugins, isNull);
      expect(_selectionPluginsOf(defaultParagraph).single.runtimeType, TextSelectionPlugin);
      expect(_selectionPluginsOf(roundedParagraph).single, isA<_RoundedSelectionPlugin>());
      expect(_selectionPluginsOf(innerParagraph).single, isA<_OtherSelectionPlugin>());
      expect(_selectionPluginsOf(disabledParagraph), isEmpty);

      await selectAll(tester, columnKey);

      expect(defaultParagraph.selections, hasLength(1));
      expect(roundedParagraph.selections, hasLength(1));
      expect(innerParagraph.selections, hasLength(1));
      expect(disabledParagraph.selections, isEmpty);

      expect(defaultParagraph, paints..rect());
      expect(defaultParagraph, isNot(paints..rrect()));
      expect(roundedParagraph, paints..rrect());
      expect(roundedParagraph, isNot(paints..rect()));
      expect(innerParagraph, paints..rect());
      expect(innerParagraph, isNot(paints..rrect()));
      expect(disabledParagraph, isNot(paints..rect()));
    });

    testWidgets('editable text keeps its own selection and gets no selection plugin', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'Editable');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        TestWidgetsApp(
          home: _selectableRegion(
            child: TextPluginScope.multiple(
              plugins: <TextPlugin>[const _RoundedSelectionPlugin(), _RecordingPlugin()],
              child: TestTextField(controller: controller),
            ),
          ),
        ),
      );

      final RenderEditable editable = tester.allRenderObjects.whereType<RenderEditable>().single;
      final List<TextPlugin> plugins = editable.textPluginDelegates
          .map((TextDelegate delegate) => delegate.plugin)
          .toList();
      expect(plugins.whereType<_RecordingPlugin>(), hasLength(1));
      expect(plugins.whereType<TextSelectionPlugin>(), isEmpty);
    });

    testWidgets('other plugins can read the selection and are notified when it changes', (
      WidgetTester tester,
    ) async {
      final plugin = _RecordingPlugin();
      final GlobalKey columnKey = GlobalKey();

      await tester.pumpWidget(
        TestWidgetsApp(
          home: _selectableRegion(
            child: TextPluginScope(
              plugin: plugin,
              child: Column(
                key: columnKey,
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
      );

      expect(plugin.delegates, hasLength(2));
      final TextDelegate firstDelegate = plugin.delegates[0];
      final TextDelegate secondDelegate = plugin.delegates[1];

      // The paragraph is given the plugin of the scope and the scope's
      // internal focus plugin, and adds the default selection plugin itself.
      final firstParagraph = firstDelegate.renderObject as RenderParagraph;
      expect(firstParagraph.textPlugins, hasLength(2));
      expect(_selectionPluginsOf(firstParagraph), hasLength(1));
      expect(firstDelegate.isSelectable, isTrue);
      expect(firstDelegate.selectionRegistrar, isNotNull);

      expect(firstDelegate.selectionColor, const Color(0xFFFF5722));
      expect(firstDelegate.selections, isEmpty);
      expect(secondDelegate.selections, isEmpty);

      var firstDelegateNotifications = 0;
      firstDelegate.addListener(() => firstDelegateNotifications += 1);

      await selectAll(tester, columnKey);

      expect(firstDelegateNotifications, greaterThan(0));
      expect(firstDelegate.selections, <TextSelection>[
        const TextSelection(baseOffset: 0, extentOffset: 22),
      ]);
      // The WidgetSpan at index 7 splits the second paragraph into two
      // selectables, each with its own selection.
      expect(secondDelegate.selections, <TextSelection>[
        const TextSelection(baseOffset: 0, extentOffset: 7),
        const TextSelection(baseOffset: 8, extentOffset: 14),
      ]);
    });

    testWidgets('TextPluginScope.exclude and TextPluginScope.none do not make text unselectable', (
      WidgetTester tester,
    ) async {
      final plugin = _RecordingPlugin();
      final GlobalKey columnKey = GlobalKey();

      await tester.pumpWidget(
        TestWidgetsApp(
          home: _selectableRegion(
            child: TextPluginScope(
              plugin: plugin,
              child: Column(
                key: columnKey,
                children: const <Widget>[
                  Text('Body Text'),
                  TextPluginScope.exclude(
                    types: <Type>{_RecordingPlugin},
                    child: Text('Toolbar Text'),
                  ),
                  TextPluginScope.none(child: Text('Chrome Text')),
                  SelectionContainer.disabled(child: Text('Unselectable Text')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(plugin.delegates.map((TextDelegate delegate) => delegate.text), <String>[
        'Body Text',
        'Unselectable Text',
      ]);

      // Toolbar Text excluded the recording plugin and only keeps the scope's
      // internal focus plugin. Chrome Text opted out of every plugin.
      final RenderParagraph bodyParagraph = paragraphOf(tester, 'Body Text');
      final RenderParagraph toolbarParagraph = paragraphOf(tester, 'Toolbar Text');
      final RenderParagraph chromeParagraph = paragraphOf(tester, 'Chrome Text');
      final RenderParagraph unselectableParagraph = paragraphOf(tester, 'Unselectable Text');
      expect(toolbarParagraph.textPlugins, hasLength(1));
      expect(toolbarParagraph.textPlugins, isNot(contains(plugin)));
      expect(chromeParagraph.textPlugins, isNull);

      // Selection does not come from a scope, so these three stay selectable.
      // Only SelectionContainer.disabled turns it off.
      expect(_selectionPluginsOf(bodyParagraph), hasLength(1));
      expect(_selectionPluginsOf(toolbarParagraph), hasLength(1));
      expect(_selectionPluginsOf(chromeParagraph), hasLength(1));
      expect(_selectionPluginsOf(unselectableParagraph), isEmpty);

      await selectAll(tester, columnKey);

      expect(bodyParagraph.selections, hasLength(1));
      expect(toolbarParagraph.selections, hasLength(1));
      expect(chromeParagraph.selections, hasLength(1));
      expect(unselectableParagraph.selections, isEmpty);
    });

    testWidgets('the selection highlight is painted above the decorations of other plugins', (
      WidgetTester tester,
    ) async {
      final GlobalKey columnKey = GlobalKey();

      await tester.pumpWidget(
        TestWidgetsApp(
          home: _selectableRegion(
            child: Column(
              key: columnKey,
              children: <Widget>[
                TextPluginScope(
                  plugin: _BadgePlugin(),
                  child: const Text('Buy GOOG today', selectionColor: Color(0xFF0000FF)),
                ),
              ],
            ),
          ),
        ),
      );
      await selectAll(tester, columnKey);

      // The opaque badge of the plugin first, then the highlight.
      expect(
        paragraphOf(tester, 'Buy GOOG today'),
        paints
          ..rect(color: const Color(0xFF00FF00))
          ..rect(color: const Color(0xFF0000FF)),
      );
    });

    testWidgets('a selection survives its text being moved in the tree', (
      WidgetTester tester,
    ) async {
      final GlobalKey columnKey = GlobalKey();
      final GlobalKey textKey = GlobalKey();
      SelectedContent? content;

      Widget build({required bool wrapped}) {
        final Widget text = Text('Movable text', key: textKey);
        return TestWidgetsApp(
          home: _selectableRegion(
            onSelectionChanged: (SelectedContent? value) => content = value,
            child: Column(
              key: columnKey,
              children: <Widget>[
                const Text('Before'),
                if (wrapped) Padding(padding: const EdgeInsets.all(8.0), child: text) else text,
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(build(wrapped: false));
      final RenderParagraph paragraph = paragraphOf(tester, 'Movable text');
      await selectAll(tester, columnKey);
      expect(paragraph.selections, <TextSelection>[
        const TextSelection(baseOffset: 0, extentOffset: 12),
      ]);
      expect(content?.plainText, 'BeforeMovable text');

      // The GlobalKey moves the same render object under a new parent, which
      // detaches and re-attaches it.
      await tester.pumpWidget(build(wrapped: true));
      expect(paragraphOf(tester, 'Movable text'), same(paragraph));
      expect(paragraph.selections, <TextSelection>[
        const TextSelection(baseOffset: 0, extentOffset: 12),
      ]);
      expect(_selectionPluginsOf(paragraph), hasLength(1));
    });
  });
}
