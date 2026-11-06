// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'semantics_tester.dart';

/// Annotates every match of [pattern] in the text widgets of its scope.
class _AnnotatingPlugin extends TextPlugin {
  _AnnotatingPlugin({
    required this.pattern,
    this.onTap,
    this.linkUrl,
    this.semanticsLabel,
    this.cursor = MouseCursor.defer,
    this.onEnter,
    this.onExit,
    this.recognizerFactory,
    this.useKey = false,
    this.paintOrder = 0,
  });

  final RegExp pattern;
  final ValueChanged<String>? onTap;
  final Uri? Function(String match)? linkUrl;
  final String? semanticsLabel;
  final MouseCursor cursor;
  final PointerEnterEventListener? onEnter;
  final PointerExitEventListener? onExit;
  final GestureRecognizer Function(String match)? recognizerFactory;
  final bool useKey;
  @override
  final int paintOrder;

  final List<TextDelegate> delegates = <TextDelegate>[];
  final List<String> taps = <String>[];

  void _scan(TextDelegate delegate) {
    delegate.annotations = <TextAnnotation>[
      for (final RegExpMatch match in pattern.allMatches(delegate.text))
        TextAnnotation(
          range: TextRange(start: match.start, end: match.end),
          key: useKey ? match.group(0) : null,
          onTap: onTap == null
              ? null
              : () {
                  taps.add(match.group(0)!);
                  onTap!(match.group(0)!);
                },
          recognizer: recognizerFactory?.call(match.group(0)!),
          linkUrl: linkUrl?.call(match.group(0)!),
          semanticsLabel: semanticsLabel,
          cursor: cursor,
          onEnter: onEnter,
          onExit: onExit,
        ),
    ];
  }

  @override
  void didAddText(TextDelegate delegate) {
    delegates.add(delegate);
    _scan(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) {
    _scan(delegate);
  }

  @override
  void didRemoveText(TextDelegate delegate) {
    delegates.remove(delegate);
  }
}

/// A second plugin type, so that both can be active in the same scope.
class _OtherAnnotatingPlugin extends _AnnotatingPlugin {
  _OtherAnnotatingPlugin({
    required super.pattern,
    super.onTap,
    super.paintOrder,
    super.recognizerFactory,
  });
}

/// A plugin that only decorates, without annotations.
class _DecorationOnlyPlugin extends TextPlugin {
  @override
  void didAddText(TextDelegate delegate) {
    delegate.backgroundPainter = _NoopPainter();
  }
}

class _NoopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_NoopPainter oldDelegate) => false;
}

/// A tap recognizer that only competes for modifier-clicks.
class _ModifierClickRecognizer extends TapGestureRecognizer {
  _ModifierClickRecognizer({required VoidCallback onActivate}) {
    onTap = onActivate;
  }

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    return (keyboard.isMetaPressed || keyboard.isControlPressed) && super.isPointerAllowed(event);
  }
}

/// Mirrors SpoilerMaskPlugin: a tap toggles state and re-installs annotations
/// from inside the annotation's own callback.
class _TogglePlugin extends TextPlugin {
  TextDelegate? delegate;
  bool revealed = false;

  static final RegExp _pattern = RegExp(r'\|\|[^|]+\|\|');

  void _install(TextDelegate delegate) {
    delegate.annotations = <TextAnnotation>[
      for (final RegExpMatch match in _pattern.allMatches(delegate.text))
        TextAnnotation(
          range: TextRange(start: match.start, end: match.end),
          key: match.group(0),
          semanticsLabel: revealed ? null : 'Spoiler, hidden',
          onTap: () {
            revealed = !revealed;
            _install(delegate);
          },
        ),
    ];
  }

  @override
  void didAddText(TextDelegate delegate) {
    this.delegate = delegate;
    _install(delegate);
  }

  @override
  void didUpdateText(TextDelegate delegate) => _install(delegate);
}

Offset _globalCenterOf(TextDelegate delegate, String substring) {
  final int start = delegate.text.indexOf(substring);
  expect(start, isNonNegative, reason: '"$substring" not found in "${delegate.text}"');
  final List<TextBox> boxes = delegate.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + substring.length),
  );
  expect(boxes, isNotEmpty);
  return delegate.localToGlobal(boxes.first.toRect().center);
}

final RegExp _urlPattern = RegExp(r'https?://\S+');

void main() {
  testWidgets('TextDelegate reports the kind of text it represents', (WidgetTester tester) async {
    final plugin = _AnnotatingPlugin(pattern: _urlPattern);

    await tester.pumpWidget(
      MaterialApp(
        home: TextPluginScope(
          plugin: plugin,
          child: const Column(
            children: <Widget>[
              Text('plain'),
              SelectionArea(child: Text('selectable')),
            ],
          ),
        ),
      ),
    );

    final TextDelegate plain = plugin.delegates.singleWhere((TextDelegate d) => d.text == 'plain');
    final TextDelegate selectable = plugin.delegates.singleWhere(
      (TextDelegate d) => d.text == 'selectable',
    );
    expect(plain.isEditable, isFalse);
    expect(plain.isReadOnly, isFalse);
    expect(plain.isSelectable, isFalse);
    expect(selectable.isEditable, isFalse);
    expect(selectable.isSelectable, isTrue);
  });

  testWidgets('A plugin may replace its annotations from within an annotation tap', (
    WidgetTester tester,
  ) async {
    final semantics = SemanticsTester(tester);
    final plugin = _TogglePlugin();

    await tester.pumpWidget(
      MaterialApp(
        home: TextPluginScope(
          plugin: plugin,
          child: const Center(child: Text('The killer is ||the butler||.')),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(RichText)),
      matchesSemantics(
        children: <Matcher>[
          containsSemantics(label: 'The killer is '),
          containsSemantics(label: 'Spoiler, hidden', isButton: true, hasTapAction: true),
          containsSemantics(label: '.'),
        ],
      ),
    );

    // Tapping reveals: the plugin installs a new annotation while the old
    // one's recognizer is still delivering the tap.
    final TextDelegate delegate = plugin.delegate!;
    await tester.tapAt(_globalCenterOf(delegate, 'the butler'));
    await tester.pump();
    expect(plugin.revealed, isTrue);
    expect(
      tester.getSemantics(find.byType(RichText)),
      matchesSemantics(
        children: <Matcher>[
          containsSemantics(label: 'The killer is '),
          containsSemantics(label: '||the butler||', isButton: true, hasTapAction: true),
          containsSemantics(label: '.'),
        ],
      ),
    );

    // And back again, through the new annotation.
    await tester.tapAt(_globalCenterOf(delegate, 'the butler'));
    await tester.pump();
    expect(plugin.revealed, isFalse);
    semantics.dispose();
  });

  testWidgets('TextAnnotation.onTap fires once per tap and not for a scroll drag', (
    WidgetTester tester,
  ) async {
    final plugin = _AnnotatingPlugin(pattern: _urlPattern, onTap: (_) {});
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TextPluginScope(
          plugin: plugin,
          child: SingleChildScrollView(
            controller: controller,
            child: const Column(
              children: <Widget>[Text('Visit https://flutter.dev today'), SizedBox(height: 2000)],
            ),
          ),
        ),
      ),
    );

    final TextDelegate delegate = plugin.delegates.single;
    final Offset link = _globalCenterOf(delegate, 'https://flutter.dev');

    // Tapping the link fires exactly once.
    await tester.tapAt(link);
    await tester.pump();
    expect(plugin.taps, <String>['https://flutter.dev']);

    // Tapping outside the link does nothing.
    await tester.tapAt(_globalCenterOf(delegate, 'Visit'));
    await tester.pump();
    expect(plugin.taps, hasLength(1));

    // A drag that starts on the link scrolls instead of opening the link.
    await tester.dragFrom(link, const Offset(0.0, -300.0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0.0));
    expect(plugin.taps, hasLength(1));
  });

  testWidgets('Overlapping annotations: the topmost plugin wins the tap, exactly once', (
    WidgetTester tester,
  ) async {
    final bottom = _AnnotatingPlugin(pattern: RegExp('flutter'), onTap: (_) {});
    final top = _OtherAnnotatingPlugin(pattern: RegExp('flutter'), onTap: (_) {}, paintOrder: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: TextPluginScope.multiple(
          plugins: <TextPlugin>[top, bottom],
          child: const Center(child: Text('Visit https://flutter.dev today')),
        ),
      ),
    );

    final Offset target = _globalCenterOf(bottom.delegates.single, 'flutter');

    // Hit test order is topmost first, then the paragraph itself.
    final HitTestResult result = tester.hitTestOnBinding(target);
    final List<TextAnnotation> annotations = result.path
        .map((HitTestEntry entry) => entry.target)
        .whereType<TextAnnotation>()
        .toList();
    expect(annotations, hasLength(2));
    expect(annotations[0].delegate!.plugin, same(top));
    expect(annotations[1].delegate!.plugin, same(bottom));

    await tester.tapAt(target);
    await tester.pump();
    expect(top.taps, <String>['flutter']);
    expect(bottom.taps, isEmpty);

    // Annotations only cover their own glyphs.
    expect(
      tester
          .hitTestOnBinding(_globalCenterOf(bottom.delegates.single, 'Visit'))
          .path
          .map((HitTestEntry entry) => entry.target)
          .whereType<TextAnnotation>(),
      isEmpty,
    );
  });

  testWidgets(
    'Annotation taps win over an ancestor GestureDetector; a declined recognizer lets the tap fall through',
    (WidgetTester tester) async {
      var ancestorTaps = 0;
      final callbackPlugin = _AnnotatingPlugin(pattern: _urlPattern, onTap: (_) {});
      final modifierTaps = <String>[];
      // Use the recognizer escape hatch: only modifier-clicks compete.
      final modifierPlugin = _OtherAnnotatingPlugin(
        pattern: RegExp('today'),
        recognizerFactory: (String match) =>
            _ModifierClickRecognizer(onActivate: () => modifierTaps.add(match)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            onTap: () => ancestorTaps += 1,
            child: TextPluginScope.multiple(
              plugins: <TextPlugin>[callbackPlugin, modifierPlugin],
              child: const Center(child: Text('Visit https://flutter.dev today')),
            ),
          ),
        ),
      );

      final TextDelegate delegate = callbackPlugin.delegates.single;

      // onTap annotation: the annotation wins the arena, the ancestor loses.
      await tester.tapAt(_globalCenterOf(delegate, 'https://flutter.dev'));
      await tester.pump();
      expect(callbackPlugin.taps, hasLength(1));
      expect(ancestorTaps, 0);

      // Recognizer that declines the pointer: the tap falls through.
      await tester.tapAt(_globalCenterOf(delegate, 'today'));
      await tester.pump();
      expect(modifierTaps, isEmpty);
      expect(ancestorTaps, 1);

      // With the modifier held, the recognizer competes and wins.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(_globalCenterOf(delegate, 'today'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(modifierTaps, <String>['today']);
      expect(ancestorTaps, 1);
    },
  );

  testWidgets('TextAnnotation provides mouse cursor and hover callbacks', (
    WidgetTester tester,
  ) async {
    var enters = 0;
    var exits = 0;
    final plugin = _AnnotatingPlugin(
      pattern: _urlPattern,
      onTap: (_) {},
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent event) => enters += 1,
      onExit: (PointerExitEvent event) => exits += 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TextPluginScope(
          plugin: plugin,
          child: const Center(child: Text('Visit https://flutter.dev today')),
        ),
      ),
    );

    final TextDelegate delegate = plugin.delegates.single;
    final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    await mouse.moveTo(_globalCenterOf(delegate, 'https://flutter.dev'));
    await tester.pump();
    expect(enters, 1);
    expect(exits, 0);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    await mouse.moveTo(_globalCenterOf(delegate, 'Visit'));
    await tester.pump();
    expect(enters, 1);
    expect(exits, 1);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      isNot(SystemMouseCursors.click),
    );
  });

  testWidgets(
    'Interactive annotations become link semantics nodes; decoration does not fragment the tree',
    (WidgetTester tester) async {
      final semantics = SemanticsTester(tester);
      final plugin = _AnnotatingPlugin(
        pattern: _urlPattern,
        onTap: (_) {},
        linkUrl: (String match) => Uri.parse(match),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TextPluginScope.multiple(
            plugins: <TextPlugin>[_DecorationOnlyPlugin(), plugin],
            child: const Center(child: Text('Visit https://flutter.dev today')),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(RichText)),
        matchesSemantics(
          children: <Matcher>[
            containsSemantics(label: 'Visit '),
            containsSemantics(
              label: 'https://flutter.dev',
              isLink: true,
              hasTapAction: true,
              isFocusable: true,
              isFocused: false,
            ),
            containsSemantics(label: ' today'),
          ],
        ),
      );
      final SemanticsNode linkNode = tester
          .getSemantics(find.byType(RichText))
          .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)[1];
      expect(linkNode.linkUrl, Uri.parse('https://flutter.dev'));

      // Activating the node through assistive technology taps the annotation.
      tester.binding.pipelineOwner.semanticsOwner!.performAction(linkNode.id, SemanticsAction.tap);
      expect(plugin.taps, <String>['https://flutter.dev']);

      // Removing the interactive plugin collapses the paragraph into one node.
      await tester.pumpWidget(
        MaterialApp(
          home: TextPluginScope(
            plugin: _DecorationOnlyPlugin(),
            child: const Center(child: Text('Visit https://flutter.dev today')),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(RichText)),
        matchesSemantics(label: 'Visit https://flutter.dev today'),
      );
      semantics.dispose();
    },
  );

  testWidgets('A semanticsLabel-only annotation replaces the spoken text without a new node', (
    WidgetTester tester,
  ) async {
    final semantics = SemanticsTester(tester);
    final plugin = _AnnotatingPlugin(pattern: RegExp(r'\|\|.*\|\|'), semanticsLabel: 'spoiler');

    await tester.pumpWidget(
      MaterialApp(
        home: TextPluginScope(
          plugin: plugin,
          child: const Center(child: Text('The killer is ||the butler||.')),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(RichText)),
      matchesSemantics(label: 'The killer is spoiler.'),
    );
    semantics.dispose();
  });

  testWidgets(
    'A tappable annotation without a URL is a button and coexists with an authored span recognizer',
    (WidgetTester tester) async {
      final semantics = SemanticsTester(tester);
      final plugin = _AnnotatingPlugin(pattern: RegExp('GOOG'), onTap: (_) {});
      final recognizer = TapGestureRecognizer()..onTap = () {};
      addTearDown(recognizer.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: TextPluginScope(
            plugin: plugin,
            child: Center(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    const TextSpan(text: 'Buy GOOG, read '),
                    TextSpan(text: 'the docs', recognizer: recognizer),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(RichText)),
        matchesSemantics(
          children: <Matcher>[
            containsSemantics(label: 'Buy '),
            containsSemantics(label: 'GOOG', isButton: true, hasTapAction: true),
            containsSemantics(label: ', read '),
            containsSemantics(label: 'the docs', isLink: true, hasTapAction: true),
          ],
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets('Annotations split read-only editable text but never an editable field', (
    WidgetTester tester,
  ) async {
    final semantics = SemanticsTester(tester);
    final plugin = _AnnotatingPlugin(
      pattern: _urlPattern,
      onTap: (_) {},
      linkUrl: (String match) => Uri.parse(match),
    );
    final controller = TextEditingController(text: 'Visit https://flutter.dev today');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextPluginScope(
            plugin: plugin,
            child: Column(
              children: <Widget>[
                const SelectableText('Visit https://flutter.dev today'),
                TextField(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );

    expect(plugin.delegates, hasLength(2));
    expect(plugin.delegates.every((TextDelegate delegate) => delegate.isEditable), isTrue);
    expect(plugin.delegates.where((TextDelegate delegate) => delegate.isReadOnly), hasLength(1));
    expect(plugin.delegates.every((TextDelegate delegate) => delegate.isSelectable), isTrue);

    // The read-only SelectableText exposes the link as its own node.
    expect(
      semantics,
      includesNodeWith(
        label: 'https://flutter.dev',
        flags: <SemanticsFlag>[SemanticsFlag.isLink],
        actions: <SemanticsAction>[SemanticsAction.tap],
      ),
    );

    // The editable field stays a single text field whose value is the text.
    final SemanticsNode fieldNode = tester.getSemantics(
      find.descendant(of: find.byType(TextField), matching: find.byType(EditableText)),
    );
    expect(fieldNode.hasFlag(SemanticsFlag.isTextField), isTrue);
    expect(fieldNode.value, 'Visit https://flutter.dev today');
    expect(fieldNode.childrenCount, 0);
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'Tab reaches annotations in reading order, Enter activates, and a focus ring is painted',
    (WidgetTester tester) async {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() {
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
      });
      final plugin = _AnnotatingPlugin(pattern: _urlPattern, onTap: (_) {});
      final before = FocusNode(debugLabel: 'before');
      final after = FocusNode(debugLabel: 'after');
      addTearDown(before.dispose);
      addTearDown(after.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextPluginScope(
              plugin: plugin,
              child: Column(
                children: <Widget>[
                  Focus(focusNode: before, child: const SizedBox(width: 10, height: 10)),
                  const Text('Visit https://flutter.dev or https://dart.dev'),
                  const Text('Then https://pub.dev'),
                  Focus(focusNode: after, child: const SizedBox(width: 10, height: 10)),
                ],
              ),
            ),
          ),
        ),
      );

      before.requestFocus();
      await tester.pump();
      expect(before.hasPrimaryFocus, isTrue);

      Iterable<TextAnnotation> allAnnotations() =>
          plugin.delegates.expand((TextDelegate delegate) => delegate.annotations);

      final visited = <String>[];
      for (var i = 0; i < 3; i += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(primaryFocus!.debugLabel, startsWith('TextAnnotation'));
        final TextAnnotation annotation = allAnnotations().singleWhere(
          (TextAnnotation annotation) => annotation.isFocused,
        );
        final TextDelegate delegate = annotation.delegate!;
        visited.add(delegate.text.substring(annotation.range.start, annotation.range.end));
        // The focused range is reported to assistive technology and painted.
        expect(annotation.isFocusable, isTrue);
        expect(delegate.renderObject, paints..rrect());
      }
      expect(visited, <String>['https://flutter.dev', 'https://dart.dev', 'https://pub.dev']);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(plugin.taps, <String>['https://pub.dev']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(after.hasPrimaryFocus, isTrue);
      expect(allAnnotations().any((TextAnnotation annotation) => annotation.isFocused), isFalse);
      expect(plugin.delegates.last.renderObject, isNot(paints..rrect()));
    },
  );

  testWidgets(
    'Focus survives a re-scan of the same logical annotation and is dropped when it disappears',
    (WidgetTester tester) async {
      final plugin = _AnnotatingPlugin(pattern: _urlPattern, onTap: (_) {}, useKey: true);
      late StateSetter setText;
      var text = 'Visit https://flutter.dev today';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextPluginScope(
              plugin: plugin,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  setText = setState;
                  return Text(text);
                },
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final FocusNode node = primaryFocus!;
      expect(node.debugLabel, startsWith('TextAnnotation'));

      // Same link, different surrounding text: the node (and focus) is kept.
      setText(() => text = 'Go to https://flutter.dev now');
      await tester.pump();
      expect(primaryFocus, same(node));
      expect(plugin.delegates.single.annotations.single.isFocused, isTrue);

      // The link disappears: the node is disposed and focus moves on.
      setText(() => text = 'No links here');
      await tester.pump();
      expect(primaryFocus, isNot(same(node)));
      expect(plugin.delegates.single.annotations, isEmpty);
    },
  );

  testWidgets('Annotations inside editable text are not part of focus traversal', (
    WidgetTester tester,
  ) async {
    final plugin = _AnnotatingPlugin(pattern: _urlPattern, onTap: (_) {});
    final controller = TextEditingController(text: 'Visit https://flutter.dev today');
    addTearDown(controller.dispose);
    final after = FocusNode(debugLabel: 'after');
    addTearDown(after.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextPluginScope(
            plugin: plugin,
            child: Column(
              children: <Widget>[
                TextField(controller: controller, autofocus: true),
                Focus(focusNode: after, child: const SizedBox(width: 10, height: 10)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(plugin.delegates.single.annotations, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(after.hasPrimaryFocus, isTrue);
    expect(
      FocusManager.instance.rootScope.traversalDescendants.any(
        (FocusNode node) => node.debugLabel?.startsWith('TextAnnotation') ?? false,
      ),
      isFalse,
    );
  });
}
