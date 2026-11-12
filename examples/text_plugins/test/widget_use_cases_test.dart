// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Tests for the two plugins that validate TextWidgetPlugin:
//
//  * SpellcheckSuggestionsPlugin, which uses the overlay layer.
//  * FrostedSpoilerPlugin, which uses the foreground layer.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_plugins/main.dart';
import 'package:text_plugins/plugins/frosted_spoiler_plugin.dart';
import 'package:text_plugins/plugins/spellcheck_linter_plugin.dart';
import 'package:text_plugins/plugins/spellcheck_suggestions_plugin.dart';

// What the menu shows for "recieve": an action in a text field, and plain
// text elsewhere.
const String _replaceLabel = 'Replace with \u201Creceive\u201D';
const String _suggestionLabel = 'Suggestion: \u201Creceive\u201D';

class _CountingSuggestions extends SpellcheckSuggestionsPlugin {
  _CountingSuggestions();

  int builds = 0;

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    builds += 1;
    return super.buildTextWidgets(context, delegate, layer);
  }
}

class _CountingFrosted extends FrostedSpoilerPlugin {
  _CountingFrosted();

  int builds = 0;

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    builds += 1;
    return super.buildTextWidgets(context, delegate, layer);
  }
}

/// Covers every `||spoiler||` with an opaque bar, using only a painter.
class _PaintedMaskPlugin extends TextPlugin {
  static final RegExp _pattern = RegExp(r'\|\|[^|\n]+\|\|');

  @override
  void didAddText(TextDelegate delegate) => _update(delegate);

  @override
  void didUpdateText(TextDelegate delegate) => _update(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.foregroundPainter = null;
  }

  void _update(TextDelegate delegate) {
    delegate.foregroundPainter = _MaskPainter(delegate, <TextRange>[
      for (final RegExpMatch match in _pattern.allMatches(delegate.text))
        TextRange(start: match.start, end: match.end),
    ]);
  }
}

class _MaskPainter extends CustomPainter {
  _MaskPainter(this.delegate, this.ranges);

  final TextDelegate delegate;
  final List<TextRange> ranges;

  @override
  void paint(Canvas canvas, Size size) {
    if (!delegate.hasLayout) {
      return;
    }
    final paint = Paint()..color = const Color(0xFF263238);
    for (final TextRange range in ranges) {
      for (final ui.TextBox box in delegate.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      )) {
        canvas.drawRect(box.toRect(), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MaskPainter oldDelegate) => true;
}

/// Marks the word "recieve" from ranges that it collects in the lifecycle
/// callbacks, which is what the documentation says not to do.
class _CollectedRangePlugin extends TextPlugin
    with TextWidgetPlugin, ChangeNotifier {
  static const Key markerKey = Key('collected marker');

  final Map<TextDelegate, TextRange> _ranges = <TextDelegate, TextRange>{};

  void _scan(TextDelegate delegate) {
    final int start = delegate.text.indexOf('recieve');
    if (start < 0) {
      _ranges.remove(delegate);
    } else {
      _ranges[delegate] = TextRange(start: start, end: start + 7);
    }
    notifyListeners();
  }

  @override
  void didAddText(TextDelegate delegate) => _scan(delegate);

  @override
  void didUpdateText(TextDelegate delegate) => _scan(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    _ranges.remove(delegate);
  }

  @override
  Iterable<Widget> buildTextWidgets(
    BuildContext context,
    TextDelegate delegate,
    TextWidgetLayer layer,
  ) {
    final TextRange? range = _ranges[delegate];
    return <Widget>[
      if (range != null)
        TextPositioned.fill(
          delegate: delegate,
          range: range,
          child: const SizedBox.expand(key: markerKey),
        ),
    ];
  }
}

Widget _app({required List<TextPlugin> plugins, required Widget child}) {
  return MaterialApp(
    home: Scaffold(
      body: TextPluginScope.multiple(plugins: plugins, child: child),
    ),
  );
}

RenderParagraph _paragraph(WidgetTester tester, String containing) {
  // allRenderObjects lists a render object once for every element that has
  // it, so a Text without a host yields its paragraph twice.
  return tester.allRenderObjects
      .whereType<RenderParagraph>()
      .toSet()
      .singleWhere(
        (RenderParagraph paragraph) =>
            paragraph.text.toPlainText().contains(containing),
      );
}

/// Whether a pointer at [position] hits the text that contains
/// [containing] itself, and not only something in front of it.
bool _hitsText(WidgetTester tester, String containing, Offset position) {
  final RenderParagraph paragraph = _paragraph(tester, containing);
  return tester
      .hitTestOnBinding(position)
      .path
      .any((HitTestEntry entry) => identical(entry.target, paragraph));
}

/// The text field that contains [word], or the one whose text is [text].
RenderEditable _editable(WidgetTester tester, String word, {String? text}) {
  return tester.allRenderObjects
      .whereType<RenderEditable>()
      .toSet()
      .singleWhere(
        (RenderEditable editable) => text == null
            ? editable.plainText.contains(word)
            : editable.plainText == text,
      );
}

/// The boxes of [word] in the paragraph that contains [containing], in global
/// coordinates.
List<Rect> _boxes(WidgetTester tester, String containing, String word) {
  final RenderParagraph paragraph = _paragraph(tester, containing);
  final int start = paragraph.text.toPlainText().indexOf(word);
  expect(start, isNonNegative);
  final Matrix4 transform = paragraph.getTransformTo(null);
  return <Rect>[
    for (final ui.TextBox box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    ))
      MatrixUtils.transformRect(transform, box.toRect()),
  ];
}

Rect _word(WidgetTester tester, String containing, String word) {
  return _boxes(
    tester,
    containing,
    word,
  ).reduce((Rect a, Rect b) => a.expandToInclude(b));
}

/// The boxes of [word] in a text field, in global coordinates.
///
/// The field is the one that contains [word], or the one whose text is
/// [text].
List<Rect> _fieldBoxes(WidgetTester tester, String word, {String? text}) {
  final RenderEditable editable = _editable(tester, word, text: text);
  final int start = editable.plainText.indexOf(word);
  expect(start, isNonNegative);
  final Matrix4 transform = editable.getTransformTo(null);
  return <Rect>[
    for (final ui.TextBox box in editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    ))
      MatrixUtils.transformRect(transform, box.toRect()),
  ];
}

final Finder _menuMessage = find.textContaining('Spelling:');

/// The outline of the open menu.
Finder _menu() {
  return find
      .ancestor(of: _menuMessage, matching: find.byType(TapRegion))
      .first;
}

Finder _target(String label) {
  return find.byWidgetPredicate(
    (Widget widget) => widget is Semantics && widget.properties.label == label,
  );
}

bool _targetHasFocus(WidgetTester tester, String label) {
  return Focus.of(tester.element(_target(label))).hasPrimaryFocus;
}

Iterable<BackdropFilter> _filters(WidgetTester tester) {
  return tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
}

/// The sigma of a blur, read from its description.
double _sigma(BackdropFilter filter) {
  final RegExpMatch match = RegExp(r'ImageFilter\.blur\(([\d.e-]+),')
      .firstMatch(filter.filter.toString())!;
  return double.parse(match.group(1)!);
}

int _countElements(Element root) {
  var count = 1;
  root.visitChildren((Element child) => count += _countElements(child));
  return count;
}

int _countRenderObjects(Element root) {
  var count = root is RenderObjectElement ? 1 : 0;
  root.visitChildren((Element child) => count += _countRenderObjects(child));
  return count;
}

int _countLayers(Layer root) {
  var count = 1;
  if (root is ContainerLayer) {
    for (
      Layer? child = root.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      count += _countLayers(child);
    }
  }
  return count;
}

void main() {
  group('Spell-check suggestion menu (overlay layer)', () {
    testWidgets('opens next to the word, above what comes after the text', (
      WidgetTester tester,
    ) async {
      var boxTaps = 0;
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Teams recieve alerts', key: Key('text')),
              // Painted after the text, so over anything the text paints.
              GestureDetector(
                onTap: () => boxTaps += 1,
                child: Container(height: 300, color: const Color(0xFF00FF00)),
              ),
            ],
          ),
        ),
      );
      expect(_menuMessage, findsNothing);
      expect(find.byType(OverlayPortal), findsNothing);

      final Rect word = _word(tester, 'Teams', 'recieve');
      await tester.tapAt(word.center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      expect(find.text(_suggestionLabel), findsOneWidget);

      // Below the word, lined up with its left edge.
      final Rect menu = tester.getRect(_menu());
      expect(
        menu.topLeft,
        offsetMoreOrLessEquals(word.bottomLeft + const Offset(0, 4)),
      );

      // Bigger than the text widget, which a foreground widget could not be
      // tapped outside of.
      final Rect text = tester.getRect(find.byKey(const Key('text')));
      expect(menu.bottom, greaterThan(text.bottom + 40));

      // Not below the text in the render tree: it is in the overlay.
      final RenderObject host = tester.renderObject(
        find.byKey(const Key('text')),
      );
      var isInsideText = false;
      for (
        RenderObject? node = tester.renderObject(_menu());
        node != null;
        node = node.parent
      ) {
        isInsideText = isInsideText || identical(node, host);
      }
      expect(isInsideText, isFalse);

      // The menu is over the green box, and it still gets the tap. The box
      // does not get it, and it does not count as a tap outside the menu.
      final Offset onMenu = tester.getCenter(find.text(_suggestionLabel));
      expect(onMenu.dy, greaterThan(text.bottom));
      await tester.tapAt(onMenu);
      await tester.pump();
      expect(boxTaps, 0);
      expect(_menuMessage, findsOneWidget);

      // A tap on the box next to the menu reaches the box, and closes the
      // menu.
      await tester.tapAt(Offset(menu.right + 100, onMenu.dy));
      await tester.pump();
      expect(boxTaps, 1);
      expect(_menuMessage, findsNothing);
      expect(find.byType(OverlayPortal), findsNothing);
    });

    testWidgets('leaves the tap to the text', (WidgetTester tester) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Align(
            alignment: Alignment.topLeft,
            child: Text('Teams recieve alerts'),
          ),
        ),
      );

      // The target of the word is in front of the text, and the text is
      // still hit.
      final Offset center = _word(tester, 'Teams', 'recieve').center;
      expect(_hitsText(tester, 'Teams', center), isTrue);

      await tester.tapAt(center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
    });

    testWidgets('a drag or a long press on the word is not a tap', (
      WidgetTester tester,
    ) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Align(
            alignment: Alignment.topLeft,
            child: Text('Teams recieve alerts'),
          ),
        ),
      );
      final Offset center = _word(tester, 'Teams', 'recieve').center;

      await tester.dragFrom(center, const Offset(60, 0));
      await tester.pump();
      expect(_menuMessage, findsNothing);

      final TestGesture gesture = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up(
        timeStamp: kLongPressTimeout + const Duration(milliseconds: 50),
      );
      await tester.pump();
      expect(_menuMessage, findsNothing);

      await tester.tapAt(center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
    });

    testWidgets(
      'in a text field: the caret is placed, and the word is replaced',
      (WidgetTester tester) async {
        final changes = <String>[];
        final replaced = <String>[];
        final plugin = SpellcheckSuggestionsPlugin(
          onReplace: (SpellcheckIssue issue, String replacement) {
            replaced.add(replacement);
          },
        );
        addTearDown(plugin.dispose);
        final controller = TextEditingController(text: 'I Recieve mail');
        addTearDown(controller.dispose);
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await tester.pumpWidget(
          _app(
            plugins: <TextPlugin>[plugin],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: changes.add,
              ),
            ),
          ),
        );
        expect(focusNode.hasFocus, isFalse);

        final Rect word = _fieldBoxes(tester, 'Recieve').single;
        await tester.tapAt(word.center, kind: PointerDeviceKind.mouse);
        await tester.pump();

        // The field received the tap: it has the focus, and the caret is in
        // the word.
        expect(focusNode.hasFocus, isTrue);
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.baseOffset, inInclusiveRange(2, 9));
        // And the menu is open, below the word.
        expect(_menuMessage, findsOneWidget);
        expect(
          tester.getTopLeft(_menu()),
          offsetMoreOrLessEquals(word.bottomLeft + const Offset(0, 4)),
        );
        // The menu is outside the field.
        expect(
          tester
              .getRect(find.byType(TextField))
              .contains(
                tester.getCenter(find.text('Replace with \u201CReceive\u201D')),
              ),
          isFalse,
        );

        await tester.tap(
          find.text('Replace with \u201CReceive\u201D'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        // Replaced through the field, as if the user had typed it.
        expect(controller.text, 'I Receive mail');
        expect(changes, <String>['I Receive mail']);
        expect(replaced, <String>['Receive']);
        expect(_menuMessage, findsNothing);
        // A tap on the menu was not a tap outside the field.
        expect(focusNode.hasFocus, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('text that cannot be edited: the menu only informs', (
      WidgetTester tester,
    ) async {
      final text = ValueNotifier<String>('Teams recieve alerts');
      addTearDown(text.dispose);
      final replaced = <String>[];
      final plugin = SpellcheckSuggestionsPlugin(
        onReplace: (SpellcheckIssue issue, String replacement) {
          replaced.add(replacement);
        },
      );
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<String>(
              valueListenable: text,
              builder: (BuildContext context, String value, Widget? child) {
                return Text(value);
              },
            ),
          ),
        ),
      );

      // A plugin cannot change the text of a Text widget, so the menu shows
      // the suggestion and has no action.
      await tester.tapAt(_word(tester, 'Teams', 'recieve').center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      expect(find.text(_suggestionLabel), findsOneWidget);
      expect(find.text(_replaceLabel), findsNothing);
      // A tap on the suggestion changes nothing.
      await tester.tap(find.text(_suggestionLabel));
      await tester.pump();
      expect(find.text('Teams recieve alerts'), findsOneWidget);
      expect(replaced, isEmpty);
      expect(_menuMessage, findsOneWidget);

      // Only the app can change the text. When it does, the menu and the
      // target of the word are gone in the same frame.
      text.value = 'Teams receive alerts';
      await tester.pump();
      expect(find.text('Teams receive alerts'), findsOneWidget);
      expect(_menuMessage, findsNothing);
      expect(_target('Misspelled: recieve'), findsNothing);
      expect(plugin.openIssue, isNull);
    });

    testWidgets('closes on a tap outside, and moves to another word', (
      WidgetTester tester,
    ) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Teams recieve alerts'),
              SizedBox(height: 200),
              Text('They are seperate things'),
            ],
          ),
        ),
      );

      await tester.tapAt(_word(tester, 'Teams', 'recieve').center);
      await tester.pump();
      expect(plugin.openIssue?.matchedText, 'recieve');
      expect(find.textContaining('before "e"'), findsOneWidget);

      // A word in another text widget: one menu at a time.
      await tester.tapAt(_word(tester, 'They', 'seperate').center);
      await tester.pump();
      expect(plugin.openIssue?.matchedText, 'seperate');
      expect(find.textContaining('before "e"'), findsNothing);
      expect(find.textContaining('-par-'), findsOneWidget);
      expect(find.byType(OverlayPortal), findsOneWidget);

      // The same word again closes it.
      await tester.tapAt(_word(tester, 'They', 'seperate').center);
      await tester.pump();
      expect(plugin.openIssue, isNull);
      expect(find.textContaining('-par-'), findsNothing);

      // A tap anywhere else closes it.
      await tester.tapAt(_word(tester, 'Teams', 'recieve').center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      await tester.tapAt(const Offset(700, 500));
      await tester.pump();
      expect(plugin.openIssue, isNull);
      expect(_menuMessage, findsNothing);
    });

    testWidgets(
      'a menu that has the focus gives way to the menu of another word',
      (WidgetTester tester) async {
        final plugin = SpellcheckSuggestionsPlugin();
        addTearDown(plugin.dispose);
        final first = TextEditingController(text: 'It occured twice');
        addTearDown(first.dispose);
        final second = TextEditingController(text: 'They are seperate things');
        addTearDown(second.dispose);
        await tester.pumpWidget(
          _app(
            plugins: <TextPlugin>[plugin],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(controller: first),
                  // Room for the menu of the field, which opens below it.
                  const SizedBox(height: 200),
                  TextField(controller: second),
                ],
              ),
            ),
          ),
        );

        // The menu of a word in the first field, with the keyboard focus on
        // its action.
        await tester.tapAt(_fieldBoxes(tester, 'occured').single.center);
        await tester.pumpAndSettle();
        expect(plugin.openIssue?.matchedText, 'occured');
        final FocusNode action = Focus.of(
          tester.element(find.textContaining('Replace with')),
        );
        action.requestFocus();
        await tester.pump();
        expect(action.hasPrimaryFocus, isTrue);

        // A word in the second field. That field takes the focus, and the
        // first menu sees the focus leave. It must not close the second menu.
        await tester.tapAt(_fieldBoxes(tester, 'seperate').single.center);
        await tester.pumpAndSettle();
        expect(plugin.openIssue?.matchedText, 'seperate');
        expect(find.textContaining('-par-'), findsOneWidget);
        expect(find.textContaining('double "r"'), findsNothing);
      },
    );

    testWidgets('works with the keyboard', (WidgetTester tester) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Teams recieve alerts'),
              SizedBox(height: 200),
              Text('They are seperate things'),
            ],
          ),
        ),
      );

      // Tab reaches the word.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_targetHasFocus(tester, 'Misspelled: recieve'), isTrue);

      // Enter opens the menu. The menu has nothing to focus, so the focus
      // stays on the word.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      expect(_targetHasFocus(tester, 'Misspelled: recieve'), isTrue);

      // Escape closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_menuMessage, findsNothing);
      expect(_targetHasFocus(tester, 'Misspelled: recieve'), isTrue);

      // Space opens it as well, and closes it again.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(_menuMessage, findsNothing);

      // Tab moves on to the next word. A menu that is open stays open, until
      // Enter swaps it for the menu of the word that has the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_targetHasFocus(tester, 'Misspelled: seperate'), isTrue);
      expect(plugin.openIssue?.matchedText, 'recieve');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(plugin.openIssue?.matchedText, 'seperate');
      expect(find.textContaining('-par-'), findsOneWidget);
      expect(find.textContaining('before "e"'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(plugin.openIssue, isNull);
    });

    testWidgets('is a button for a screen reader, next to the text', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Align(
            alignment: Alignment.topLeft,
            child: Text('Teams recieve alerts'),
          ),
        ),
      );

      expect(
        tester.getSemantics(_target('Misspelled: recieve')),
        isSemantics(
          label: 'Misspelled: recieve',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // The text itself still reads as one piece, with the word in it.
      expect(find.bySemanticsLabel('Teams recieve alerts'), findsOneWidget);

      tester.semantics.tap(find.semantics.byLabel('Misspelled: recieve'));
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      handle.dispose();
    });

    testWidgets('follows the word in the same frame', (
      WidgetTester tester,
    ) async {
      final plugin = _CountingSuggestions();
      addTearDown(plugin.dispose);
      final width = ValueNotifier<double>(400);
      addTearDown(width.dispose);
      final left = ValueNotifier<double>(0);
      addTearDown(left.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: Align(
            alignment: Alignment.topLeft,
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[width, left]),
              builder: (BuildContext context, Widget? child) {
                return Padding(
                  padding: EdgeInsets.only(left: left.value),
                  child: SizedBox(width: width.value, child: child),
                );
              },
              child: const Text('Our teams recieve alerts'),
            ),
          ),
        ),
      );
      await tester.tapAt(_word(tester, 'Our', 'recieve').center);
      await tester.pump();
      final Rect before = _word(tester, 'Our', 'recieve');
      expect(
        tester.getTopLeft(_menu()),
        offsetMoreOrLessEquals(before.bottomLeft + const Offset(0, 4)),
      );

      // The text gets narrower and the word wraps to the next line.
      width.value = 150;
      await tester.pump();
      final Rect wrapped = _word(tester, 'Our', 'recieve');
      expect(wrapped.top, greaterThan(before.top));
      expect(
        tester.getTopLeft(_menu()),
        offsetMoreOrLessEquals(wrapped.bottomLeft + const Offset(0, 4)),
      );

      // The text moves without being laid out again. Nothing is built, and
      // the menu still follows.
      plugin.builds = 0;
      left.value = 37;
      await tester.pump();
      final Rect moved = _word(tester, 'Our', 'recieve');
      expect(moved.left, wrapped.left + 37);
      expect(
        tester.getTopLeft(_menu()),
        offsetMoreOrLessEquals(moved.bottomLeft + const Offset(0, 4)),
      );
      expect(plugin.builds, 0);
    });

    testWidgets('goes to the other side when there is no room', (
      WidgetTester tester,
    ) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      final alignment = ValueNotifier<Alignment>(Alignment.bottomLeft);
      addTearDown(alignment.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: ValueListenableBuilder<Alignment>(
            valueListenable: alignment,
            builder: (BuildContext context, Alignment value, Widget? child) {
              return Align(alignment: value, child: child);
            },
            child: const Text('recieve'),
          ),
        ),
      );

      // At the bottom of the screen: above the word.
      Rect word = _word(tester, 'recieve', 'recieve');
      await tester.tapAt(word.center);
      await tester.pump();
      Rect menu = tester.getRect(_menu());
      expect(
        menu.bottomLeft,
        offsetMoreOrLessEquals(word.topLeft - const Offset(0, 4)),
      );
      await tester.tapAt(word.center);
      await tester.pump();
      expect(_menuMessage, findsNothing);

      // At the right edge: lined up with the right edge of the word.
      alignment.value = Alignment.topRight;
      await tester.pump();
      word = _word(tester, 'recieve', 'recieve');
      await tester.tapAt(word.center);
      await tester.pump();
      menu = tester.getRect(_menu());
      expect(
        menu.topRight,
        offsetMoreOrLessEquals(word.bottomRight + const Offset(0, 4)),
      );
      expect(menu.left, greaterThanOrEqualTo(0));
    });

    testWidgets('closes when something scrolls', (WidgetTester tester) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final controller = TextEditingController(text: 'I recieve mail');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: ListView(
            controller: scrollController,
            children: <Widget>[
              const Text('Teams recieve alerts'),
              const SizedBox(height: 100),
              TextField(controller: controller),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );

      // A word in a text.
      await tester.tapAt(_word(tester, 'Teams', 'recieve').center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      scrollController.jumpTo(10);
      await tester.pump();
      expect(_menuMessage, findsNothing);

      // A word in a text field, which has a scrollable of its own between
      // itself and the list.
      await tester.tapAt(_fieldBoxes(tester, 'recieve').single.center);
      await tester.pump();
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      scrollController.jumpTo(20);
      await tester.pump();
      expect(_menuMessage, findsNothing);
    });

    testWidgets('in a text field: closes when the word moves or is fixed', (
      WidgetTester tester,
    ) async {
      final plugin = SpellcheckSuggestionsPlugin();
      addTearDown(plugin.dispose);
      final controller = TextEditingController(text: 'I recieve mail');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(controller: controller),
          ),
        ),
      );

      Future<void> openMenu() async {
        await tester.tapAt(_fieldBoxes(tester, 'recieve').single.center);
        await tester.pump();
        await tester.pump();
        expect(_menuMessage, findsOneWidget);
      }

      // Text is added after the word: the word stays where it is, and so
      // does the menu.
      await openMenu();
      final Offset before = tester.getTopLeft(_menu());
      controller.text = 'I recieve mail today';
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      expect(tester.getTopLeft(_menu()), before);

      // Text is added before the word: the menu is gone in the same frame.
      controller.text = 'Now I recieve mail today';
      await tester.pump();
      expect(_menuMessage, findsNothing);
      expect(plugin.openIssue, isNull);

      // The word is fixed by typing.
      await openMenu();
      controller.text = 'Now I receive mail today';
      await tester.pump();
      expect(_menuMessage, findsNothing);
      expect(plugin.openIssue, isNull);
      expect(_target('Misspelled: recieve'), findsNothing);
    });
  });

  group('Frosted-glass spoiler (foreground layer)', () {
    testWidgets('covers every line of a spoiler with a clipped blur', (
      WidgetTester tester,
    ) async {
      final plugin = FrostedSpoilerPlugin();
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: Text(
                'The end: ||the butler did it in the hall|| so there',
              ),
            ),
          ),
        ),
      );

      final List<Rect> boxes = _boxes(
        tester,
        'The end',
        '||the butler did it in the hall||',
      );
      expect(boxes.length, greaterThan(1));

      // One blur for each line, each clipped to its line.
      expect(_filters(tester), hasLength(boxes.length));
      for (final BackdropFilter filter in _filters(tester)) {
        expect(_sigma(filter), 5);
      }
      final List<Rect> clips = <Rect>[
        for (final Element element in find.byType(ClipRRect).evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ];
      expect(clips, hasLength(boxes.length));
      for (var i = 0; i < boxes.length; i += 1) {
        expect(clips[i], rectMoreOrLessEquals(boxes[i].inflate(1.5)));
      }

      // The blur needs compositing, which a painter cannot ask for.
      expect(
        tester.renderObject(find.byType(BackdropFilter).first).needsCompositing,
        isTrue,
      );
    });

    testWidgets('a tap shows and hides the whole spoiler, animated', (
      WidgetTester tester,
    ) async {
      final log = <String>[];
      final plugin = FrostedSpoilerPlugin(
        onMatchTapped: (SpoilerMaskMatch match, {required bool isRevealed}) {
          log.add('${match.rawValue} $isRevealed');
        },
      );
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: Text(
                'The end: ||the butler did it in the hall|| so there',
              ),
            ),
          ),
        ),
      );
      final List<Rect> boxes = _boxes(
        tester,
        'The end',
        '||the butler did it in the hall||',
      );

      // A tap on the second line.
      await tester.tapAt(boxes.last.center);
      await tester.pump();
      expect(log, <String>['||the butler did it in the hall|| true']);

      // Halfway: every line is half as blurred.
      await tester.pump(const Duration(milliseconds: 125));
      for (final BackdropFilter filter in _filters(tester)) {
        expect(_sigma(filter), moreOrLessEquals(2.5, epsilon: 0.01));
      }

      // Done: nothing is blurred.
      await tester.pump(const Duration(milliseconds: 125));
      expect(_filters(tester), isEmpty);

      // A tap on the first line hides it again.
      await tester.tapAt(boxes.first.center);
      await tester.pumpAndSettle();
      expect(log.last, '||the butler did it in the hall|| false');
      expect(_filters(tester), hasLength(boxes.length));
      expect(_filters(tester).map(_sigma), everyElement(5));
    });

    testWidgets('takes the tap, unlike a painter', (WidgetTester tester) async {
      Future<bool> spoilerTapHitsTheText(TextPlugin spoilerPlugin) async {
        await tester.pumpWidget(
          _app(
            plugins: <TextPlugin>[spoilerPlugin],
            child: const Align(
              alignment: Alignment.topLeft,
              child: Text('See ||https://flutter.dev|| now'),
            ),
          ),
        );
        // A pointer next to the spoiler always hits the text.
        expect(
          _hitsText(tester, 'See', _word(tester, 'See', 'now').center),
          isTrue,
        );
        final bool onSpoiler = _hitsText(
          tester,
          'See',
          _word(tester, 'See', '||https://flutter.dev||').center,
        );
        await tester.pumpWidget(const SizedBox());
        return onSpoiler;
      }

      // A painter cannot stop the event: whatever is under the mask, such
      // as a link in the text, is hit together with it.
      expect(await spoilerTapHitsTheText(_PaintedMaskPlugin()), isTrue);

      // The widget is in front of the text, so the text is not hit.
      final frosted = FrostedSpoilerPlugin();
      addTearDown(frosted.dispose);
      expect(await spoilerTapHitsTheText(frosted), isFalse);
    });

    testWidgets('moves with the text when it scrolls, and builds nothing', (
      WidgetTester tester,
    ) async {
      final plugin = _CountingFrosted();
      addTearDown(plugin.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: ListView(
            controller: scrollController,
            children: const <Widget>[
              SizedBox(height: 100),
              Text('A ||secret|| here'),
              SizedBox(height: 2000),
            ],
          ),
        ),
      );
      final Rect before = tester.getRect(find.byType(TextPositioned));
      expect(
        before,
        rectMoreOrLessEquals(_word(tester, 'A ', '||secret||').inflate(1.5)),
      );

      plugin.builds = 0;
      scrollController.jumpTo(40);
      await tester.pump();
      final Rect after = tester.getRect(find.byType(TextPositioned));
      expect(after, before.shift(const Offset(0, -40)));
      expect(
        after,
        rectMoreOrLessEquals(_word(tester, 'A ', '||secret||').inflate(1.5)),
      );
      expect(plugin.builds, 0);
    });

    testWidgets('keeps animating when the text is laid out again', (
      WidgetTester tester,
    ) async {
      final plugin = FrostedSpoilerPlugin();
      addTearDown(plugin.dispose);
      final text = ValueNotifier<String>('A ||secret|| here');
      addTearDown(text.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<String>(
              valueListenable: text,
              builder: (BuildContext context, String value, Widget? child) {
                return Text(value);
              },
            ),
          ),
        ),
      );
      await tester.tapAt(_word(tester, 'A ', '||secret||').center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _sigma(_filters(tester).single),
        moreOrLessEquals(3, epsilon: 0.01),
      );

      // The text changes while the cover is fading. The cover is built again
      // from the new layout, and its animation carries on from where it was.
      text.value = 'A ||secret|| here, and more';
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _sigma(_filters(tester).single),
        moreOrLessEquals(2, epsilon: 0.01),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_filters(tester), isEmpty);
    });

    testWidgets(
      'in a text field: the caret goes under the cover and shows the span',
      (WidgetTester tester) async {
        final plugin = FrostedSpoilerPlugin();
        addTearDown(plugin.dispose);
        final controller = TextEditingController(text: 'a ||secret|| b');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            plugins: <TextPlugin>[plugin],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(controller: controller),
            ),
          ),
        );
        expect(_sigma(_filters(tester).single), 5);
        expect(
          tester.getRect(find.byType(TextPositioned)),
          rectMoreOrLessEquals(
            _fieldBoxes(tester, '||secret||').single.inflate(1.5),
          ),
        );

        // A tap on the cover goes through to the field.
        await tester.tapAt(_fieldBoxes(tester, '||secret||').single.center);
        await tester.pump();
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.baseOffset, inInclusiveRange(2, 12));
        // The selection touches the span, so it is shown.
        await tester.pumpAndSettle();
        expect(_filters(tester), isEmpty);

        // Typing inside the span: the cover has the new size in the same frame.
        controller.value = const TextEditingValue(
          text: 'a ||secrets!|| b',
          selection: TextSelection.collapsed(offset: 11),
        );
        await tester.pump();
        expect(
          tester.getRect(find.byType(TextPositioned)),
          rectMoreOrLessEquals(
            _fieldBoxes(tester, '||secrets!||').single.inflate(1.5),
          ),
        );

        // The caret leaves the span, and it is hidden again.
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pumpAndSettle();
        expect(_sigma(_filters(tester).single), 5);
      },
    );

    testWidgets('is a button for the keyboard and for a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final log = <bool>[];
      final plugin = FrostedSpoilerPlugin(
        onMatchTapped: (SpoilerMaskMatch match, {required bool isRevealed}) {
          log.add(isRevealed);
        },
      );
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: Text(
                'The end: ||the butler did it in the hall|| so there',
              ),
            ),
          ),
        ),
      );

      // One button for the spoiler, though it has two lines.
      expect(find.bySemanticsLabel('Spoiler'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Spoiler')),
        isSemantics(
          label: 'Spoiler',
          value: 'Hidden',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );

      // A limit: the text node still contains the hidden words.
      expect(
        find.bySemanticsLabel(RegExp('the butler did it')),
        findsOneWidget,
      );

      // Tab and Enter.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(log, <bool>[true]);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Spoiler')),
        isSemantics(value: 'Shown'),
      );

      // The screen reader's tap.
      tester.semantics.tap(find.semantics.byLabel('Spoiler'));
      await tester.pumpAndSettle();
      expect(log, <bool>[true, false]);
      handle.dispose();
    });

    testWidgets('in a selection area: a tap toggles, a drag selects', (
      WidgetTester tester,
    ) async {
      final log = <bool>[];
      final selections = <String>[];
      final plugin = FrostedSpoilerPlugin(
        onMatchTapped: (SpoilerMaskMatch match, {required bool isRevealed}) {
          log.add(isRevealed);
        },
      );
      addTearDown(plugin.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[plugin],
          child: Align(
            alignment: Alignment.topLeft,
            child: SelectionArea(
              onSelectionChanged: (SelectedContent? content) {
                selections.add(content?.plainText ?? '');
              },
              child: const Text('A ||secret|| here'),
            ),
          ),
        ),
      );
      final Rect spoiler = _word(tester, 'A ', '||secret||');

      await tester.tapAt(spoiler.center, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(log, <bool>[true]);
      await tester.tapAt(spoiler.center, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(log, <bool>[true, false]);

      // A drag that starts on the cover selects the text under it.
      final TestGesture gesture = await tester.startGesture(
        spoiler.centerLeft + const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(_word(tester, 'A ', 'here').centerRight);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selections.last, contains('secret'));
      expect(selections.last, contains('here'));
      // The drag did not toggle the spoiler.
      expect(log, <bool>[true, false]);
    });
  });

  group('What the two plugins show about the design', () {
    testWidgets(
      'widgets built from state that callbacks collect are a frame late',
      (WidgetTester tester) async {
        final text = ValueNotifier<String>('recieve x');
        addTearDown(text.dispose);
        final collected = _CollectedRangePlugin();
        addTearDown(collected.dispose);
        final derived = SpellcheckSuggestionsPlugin();
        addTearDown(derived.dispose);
        await tester.pumpWidget(
          _app(
            plugins: <TextPlugin>[collected, derived],
            child: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<String>(
                valueListenable: text,
                builder: (BuildContext context, String value, Widget? child) {
                  return Text(value);
                },
              ),
            ),
          ),
        );
        final Finder collectedMarker = find.byKey(
          _CollectedRangePlugin.markerKey,
        );
        final Finder derivedMarker = _target('Misspelled: recieve');

        // First frame. buildTextWidgets ran before didAddText, so the plugin
        // that collects had nothing to show yet.
        expect(derivedMarker, findsOneWidget);
        expect(
          tester.getRect(derivedMarker),
          _word(tester, 'recieve x', 'recieve'),
        );
        expect(collectedMarker, findsNothing);
        await tester.pump();
        expect(
          tester.getRect(collectedMarker),
          _word(tester, 'recieve x', 'recieve'),
        );

        // The text changes. The derived marker is on the word in the same
        // frame. The collected one is still on the old range.
        text.value = 'xx recieve x';
        await tester.pump();
        final Rect word = _word(tester, 'xx recieve x', 'recieve');
        expect(tester.getRect(derivedMarker), word);
        expect(tester.getRect(collectedMarker), isNot(word));
        expect(
          tester.getRect(collectedMarker),
          _word(tester, 'xx recieve x', 'xx reci'),
        );
        await tester.pump();
        expect(tester.getRect(collectedMarker), word);
      },
    );

    testWidgets('a plugin that notifies rebuilds the widgets of every text', (
      WidgetTester tester,
    ) async {
      const count = 20;
      final suggestions = _CountingSuggestions();
      addTearDown(suggestions.dispose);
      final frosted = _CountingFrosted();
      addTearDown(frosted.dispose);
      await tester.pumpWidget(
        _app(
          plugins: <TextPlugin>[suggestions, frosted],
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var i = 0; i < count; i += 1)
                  Text('Line $i: we recieve a ||secret|| here'),
              ],
            ),
          ),
        ),
      );
      // Two layers for the suggestions, one for the spoilers.
      expect(suggestions.builds, 2 * count);
      expect(frosted.builds, count);

      // Showing one spoiler: its covers listen themselves, so no text builds
      // its widgets again.
      suggestions.builds = 0;
      frosted.builds = 0;
      await tester.tapAt(_word(tester, 'Line 7:', '||secret||').center);
      await tester.pumpAndSettle();
      expect(_filters(tester), hasLength(count - 1));
      expect(frosted.builds, 0);
      expect(suggestions.builds, 0);

      // Opening one menu: the plugin notifies, and every text builds the
      // widgets of every plugin again, the spoilers included.
      await tester.tapAt(_word(tester, 'Line 3:', 'recieve').center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      expect(suggestions.builds, 2 * count);
      expect(frosted.builds, count);
    });

    testWidgets('what one text costs', (WidgetTester tester) async {
      // Elements and render objects from the Text down, and how many
      // compositing layers the view has.
      Future<(int, int, int)> measure(
        List<TextPlugin> plugins,
        String text, {
        Future<void> Function()? then,
      }) async {
        await tester.pumpWidget(
          _app(
            plugins: plugins,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(text, key: const Key('text')),
            ),
          ),
        );
        await then?.call();
        final Element element = tester.element(find.byKey(const Key('text')));
        final result = (
          _countElements(element),
          _countRenderObjects(element),
          _countLayers(tester.binding.renderViews.single.debugLayer!),
        );
        await tester.pumpWidget(const SizedBox());
        return result;
      }

      final painted = _PaintedMaskPlugin();
      final frosted = FrostedSpoilerPlugin();
      addTearDown(frosted.dispose);
      final linter = SpellcheckLinterPlugin();
      final suggestions = SpellcheckSuggestionsPlugin();
      addTearDown(suggestions.dispose);

      final (int, int, int) plain = await measure(<TextPlugin>[], 'a ||b|| c');
      expect(plain.$1, 2);
      expect(plain.$2, 1);

      // The painter-only plugins cost nothing per text.
      expect(await measure(<TextPlugin>[painted], 'a ||b|| c'), plain);
      expect(await measure(<TextPlugin>[linter], 'a recieve c'), plain);

      // Elements, render objects, and compositing layers on top of what the
      // plain text has.
      Future<String> cost(
        List<TextPlugin> plugins,
        String text, {
        Future<void> Function()? then,
      }) async {
        final (int elements, int renderObjects, int layers) = await measure(
          plugins,
          text,
          then: then,
        );
        return '$elements/$renderObjects/+${layers - plain.$3}';
      }

      final String spoilersNone = await cost(<TextPlugin>[frosted], 'a b c');
      final String suggestionsNone = await cost(<TextPlugin>[
        suggestions,
      ], 'a b c');
      final String spoilerHidden = await cost(<TextPlugin>[
        frosted,
      ], 'a ||b|| c');
      final String spoilerShown = await cost(
        <TextPlugin>[frosted],
        'a ||b|| c',
        then: () async {
          await tester.tapAt(_word(tester, 'a ||b|| c', '||b||').center);
          await tester.pumpAndSettle();
        },
      );
      final String wordFlagged = await cost(<TextPlugin>[
        suggestions,
      ], 'a recieve c');
      final String menuOpen = await cost(
        <TextPlugin>[suggestions],
        'a recieve c',
        then: () async {
          await tester.tapAt(_word(tester, 'a recieve c', 'recieve').center);
          await tester.pump();
          expect(_menuMessage, findsOneWidget);
        },
      );

      // A snapshot. The numbers change when the widgets that the plugins use
      // change.
      expect(
        <String>[
          // A text with nothing to decorate still gets a host: one layer
          // for the spoilers, two for the suggestions.
          'spoilers, none in the text: $spoilersNone',
          'suggestions, none in the text: $suggestionsNone',
          // The blur needs compositing layers. They go when it is shown.
          'one spoiler, hidden: $spoilerHidden',
          'one spoiler, shown: $spoilerShown',
          'one flagged word: $wordFlagged',
          'one flagged word, menu open: $menuOpen',
        ].join('\n'),
        <String>[
          'spoilers, none in the text: 6/4/+0',
          'suggestions, none in the text: 8/6/+0',
          'one spoiler, hidden: 35/14/+3',
          'one spoiler, shown: 33/12/+0',
          'one flagged word: 25/14/+0',
          'one flagged word, menu open: 60/29/+3',
        ].join('\n'),
      );
    });

    testWidgets(
      'under a widget plugin, the render object of a Text is the host',
      (WidgetTester tester) async {
        final frosted = FrostedSpoilerPlugin();
        addTearDown(frosted.dispose);
        final painted = _PaintedMaskPlugin();

        await tester.pumpWidget(
          _app(plugins: <TextPlugin>[painted], child: const Text('a ||b|| c')),
        );
        expect(tester.renderObject(find.byType(Text)), isA<RenderParagraph>());

        // Code that reads the paragraph of a Text, as many tests do, has to
        // look for the RichText instead.
        await tester.pumpWidget(
          _app(plugins: <TextPlugin>[frosted], child: const Text('a ||b|| c')),
        );
        expect(
          tester.renderObject(find.byType(Text)),
          isNot(isA<RenderParagraph>()),
        );
        expect(
          tester.renderObject(find.byType(RichText)),
          isA<RenderParagraph>(),
        );
        expect(
          tester.getSize(find.byType(Text)),
          tester.getSize(find.byType(RichText)),
        );
      },
    );
  });

  group(
    'In the demo app',
    () {
      // Stops the two animations that never end, so that pumpAndSettle works.
      Future<void> pumpDemo(
        WidgetTester tester, {
        bool pauseMovingCard = true,
      }) async {
        await tester.pumpWidget(const TextPluginsDemoApp());
        await tester.pump();
        for (final key in <String>[
          if (pauseMovingCard) 'moving_card_toggle_button',
          'changing_text_toggle_button',
        ]) {
          await Scrollable.ensureVisible(
            tester.element(find.byKey(Key(key))),
            alignment: 0.85,
          );
          await tester.pump();
          await tester.tap(find.byKey(Key(key)));
          await tester.pump();
        }
      }

      // The chips are in a row that scrolls sideways.
      Future<void> tapChip(WidgetTester tester, String key) async {
        await Scrollable.ensureVisible(
          tester.element(find.byKey(Key(key))),
          alignment: 0.5,
        );
        await tester.pump();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      Future<void> show(WidgetTester tester, String key) async {
        await Scrollable.ensureVisible(
          tester.element(find.byKey(Key(key))),
          alignment: 0.3,
        );
        await tester.pumpAndSettle();
      }

      testWidgets(
        'both are on by default, and work next to the other plugins',
        (WidgetTester tester) async {
          await pumpDemo(tester);
          await tester.pumpAndSettle();
          expect(find.byType(TextPluginWidgetHost), findsWidgets);

          // The first added paragraph has a misspelling and two hidden spans.
          await show(tester, 'custom_note_text_0');
          final Finder note = find.byKey(const Key('custom_note_text_0'));
          expect(
            find.descendant(of: note, matching: find.byType(BackdropFilter)),
            findsAtLeastNWidgets(2),
          );

          // The page can change this paragraph, so the menu offers to.
          await tester.tapAt(_word(tester, 'teams recieve', 'recieve').center);
          await tester.pumpAndSettle();
          expect(find.text('Lint "recieve" → "receive"'), findsOneWidget);
          expect(find.text(_replaceLabel), findsOneWidget);
          await tester.tap(find.text(_replaceLabel));
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(note).data,
            contains('teams receive seperate alerts'),
          );
          expect(_menuMessage, findsNothing);

          // A spoiler in the same paragraph.
          await tester.tapAt(
            _boxes(
              tester,
              'teams receive',
              '||Rosebud is the sled||',
            ).first.center,
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Spoiler: Revealed (||Rosebud is the sled||)'),
            findsOneWidget,
          );

          // The page cannot change this paragraph, so the menu only informs.
          await show(tester, 'selection_area_paragraph_1');
          await tester.tapAt(_word(tester, 'Drag across', 'seperate').center);
          await tester.pumpAndSettle();
          expect(find.text('Suggestion: \u201Cseparate\u201D'), findsOneWidget);
          expect(find.textContaining('Replace with'), findsNothing);
          await tester.tapAt(_word(tester, 'Drag across', 'Drag').center);
          await tester.pumpAndSettle();
          expect(find.textContaining('-par-'), findsNothing);

          // The text field: the plugin replaces the word itself.
          await show(tester, 'custom_note_input');
          await tester.enterText(
            find.byKey(const Key('custom_note_input')),
            'we recieve mail',
          );
          await tester.pumpAndSettle();
          await tester.tapAt(
            _fieldBoxes(
              tester,
              'recieve',
              text: 'we recieve mail',
            ).single.center,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(_replaceLabel));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('custom_note_input')))
                .controller!
                .text,
            'we receive mail',
          );
        },
      );

      testWidgets('the chips switch back to the painter-only plugins', (
        WidgetTester tester,
      ) async {
        await pumpDemo(tester);
        await tester.pumpAndSettle();
        await tapChip(tester, 'chip_suggestion_menu');
        // The spoilers still build widgets.
        expect(find.byType(TextPluginWidgetHost), findsWidgets);
        await tapChip(tester, 'chip_frosted_spoiler');

        // No widget plugin is left, so no text has a host.
        expect(find.byType(TextPluginWidgetHost), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);

        await show(tester, 'custom_note_text_0');
        await tester.tapAt(_word(tester, 'teams recieve', 'recieve').center);
        await tester.pumpAndSettle();
        expect(find.text('Lint "recieve" → "receive"'), findsOneWidget);
        expect(_menuMessage, findsNothing);

        await tester.tapAt(
          _boxes(
            tester,
            'teams recieve',
            '||Rosebud is the sled||',
          ).first.center,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Spoiler: Revealed (||Rosebud is the sled||)'),
          findsOneWidget,
        );

        // And back.
        await tapChip(tester, 'chip_frosted_spoiler');
        expect(find.byType(TextPluginWidgetHost), findsWidgets);
        expect(find.byType(BackdropFilter), findsWidgets);
      });

      testWidgets('the menu follows the card that moves', (
        WidgetTester tester,
      ) async {
        await pumpDemo(tester, pauseMovingCard: false);
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('moving_card_text'))),
          alignment: 0.2,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final Rect before = _word(tester, 'Animated Moving Card', 'recieve');
        await tester.tapAt(before.center);
        await tester.pump();
        expect(_menuMessage, findsOneWidget);

        for (var i = 0; i < 5; i += 1) {
          await tester.pump(const Duration(milliseconds: 100));
          final Rect word = _word(tester, 'Animated Moving Card', 'recieve');
          final Rect menu = tester.getRect(_menu());
          // On the word in every frame, on whichever side there is room.
          expect(<double>[
            (menu.top - (word.bottom + 4)).abs(),
            (menu.bottom - (word.top - 4)).abs(),
          ], contains(lessThan(0.01)));
          expect(<double>[
            (menu.left - word.left).abs(),
            (menu.right - word.right).abs(),
          ], contains(lessThan(0.01)));
        }
        expect(
          _word(tester, 'Animated Moving Card', 'recieve').center,
          isNot(offsetMoreOrLessEquals(before.center, epsilon: 1)),
        );
      });

      testWidgets('removing the last widget plugin re-creates every text', (
        WidgetTester tester,
      ) async {
        await pumpDemo(tester);
        await tester.tap(find.byKey(const Key('chip_search_plugin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('search_next_button')));
        await tester.pumpAndSettle();
        expect(find.text('2 / 5'), findsOneWidget);
        final RenderParagraph before = _paragraph(tester, 'Flutter continues');

        await tapChip(tester, 'chip_suggestion_menu');
        // A widget plugin is still in scope: nothing was re-created.
        expect(_paragraph(tester, 'Flutter continues'), same(before));
        expect(find.text('2 / 5'), findsOneWidget);

        await tapChip(tester, 'chip_frosted_spoiler');
        // The last one is gone. Every Text lost its host, and with it its
        // render object, so every plugin saw every text removed and added.
        expect(_paragraph(tester, 'Flutter continues'), isNot(same(before)));
        // What a user sees of it: find-in-page is back at its first match.
        expect(find.text('1 / 5'), findsOneWidget);

        // The same happens when the first widget plugin is added.
        await tester.tap(find.byKey(const Key('search_next_button')));
        await tester.pumpAndSettle();
        expect(find.text('2 / 5'), findsOneWidget);
        final RenderParagraph withoutHost = _paragraph(
          tester,
          'Flutter continues',
        );
        await tapChip(tester, 'chip_frosted_spoiler');
        expect(
          _paragraph(tester, 'Flutter continues'),
          isNot(same(withoutHost)),
        );
        expect(find.text('1 / 5'), findsOneWidget);
      });
    },
    skip: 'These walk through the larger demo page, which was replaced by a smaller one.',
  );

  group('The demo page', () {
    testWidgets('shows what to try, and both plugins work on it', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const TextPluginsDemoApp());
      await tester.pump();
      expect(find.text('What to try'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);

      // A paragraph: the menu shows the suggestion and offers no replacement,
      // because a plugin cannot change the text of a Text widget.
      await tester.tapAt(_word(tester, 'Teams recieve', 'recieve').center);
      await tester.pump();
      expect(_menuMessage, findsOneWidget);
      expect(find.text(_suggestionLabel), findsOneWidget);
      expect(find.text(_replaceLabel), findsNothing);

      // The text field: the menu offers the replacement, and the plugin makes
      // it through the field.
      final Finder field = find.byKey(const Key('custom_note_input'));
      await tester.ensureVisible(field);
      await tester.pump();
      await tester.tapAt(_fieldBoxes(tester, 'recieve').single.center);
      await tester.pump();
      expect(find.text(_replaceLabel), findsOneWidget);
      await tester.tap(find.text(_replaceLabel));
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'We receive ||a secret|| by mail',
      );
      expect(
        find.text('Last event: replaced "recieve" with "receive"'),
        findsOneWidget,
      );
      // The paragraph is as it was.
      expect(
        tester.widget<Text>(find.byKey(const Key('custom_note_text_0'))).data,
        startsWith('Teams recieve seperate'),
      );

      // The chips switch to the painter-only plugins.
      await tester.tap(find.byKey(const Key('chip_suggestion_menu')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('chip_frosted_spoiler')));
      await tester.pump();
      expect(find.byType(TextPluginWidgetHost), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });
}
