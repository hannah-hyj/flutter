# Key Components of Composable Text Plugins

This overview introduces the 5 core components in the Composable Text Plugins design, with a short explanation and abridged code snippet for each.

---

## 1. `TextPluginScope`

`TextPluginScope` is an `InheritedWidget` wrapper that attaches one or more `TextPlugin`s to every standard `Text`, `RichText`, and `EditableText` (`TextField`) in its subtree without modifying those widgets. Nested scopes automatically merge, deduplicate plugins by `Type`, sort them by `paintOrder`, and let UI chrome (such as a search bar or toolbar) opt out via `TextPluginScope.exclude` or `TextPluginScope.none`.

```dart
TextPluginScope.multiple(
  plugins: [
    SearchInPagePlugin()..query = 'Flutter',
    SpoilerMaskPlugin(), // e.g., tap-to-reveal ||spoiler|| & {{cloze}} masks
  ],
  child: Column(
    children: [
      // Standard widgets automatically participate in the plugin pipeline!
      Text('Welcome to Flutter! ||Plot twist||'), // Automatically highlighted & masked
      TextField(),                                // Text input also automatically inspected

      // Developers can easily firewall UI chrome from being affected:
      TextPluginScope.none(
        child: Text('Search query: Flutter'), // Safely isolated from plugins
      ),
    ],
  ),
)
```

---

## 2. `TextPlugin`

`TextPlugin` is the abstract contract that plugin authors implement to define cross-cutting text inspection, decoration, or pointer interaction. Its `didAddText`, `didUpdateText`, and `didLayoutText` hooks fire at the end of layout (`PipelineOwner` post-layout phase) so glyph geometry is always valid, while `paintOrder` and `needsOffscreenContent` declaratively control Z-order and lazy viewport behavior.

```dart
abstract class TextPlugin {
  const TextPlugin();

  bool get needsOffscreenContent => false;
  int get paintOrder => 0;

  // Fired post-layout (geometry queries on `delegate` are guaranteed valid):
  void didAddText(TextDelegate delegate) {}
  void didUpdateText(TextDelegate delegate) {}
  void didLayoutText(TextDelegate delegate) {}

  void didRemoveText(TextDelegate delegate) {}
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {}
}
```

---

## 3. `TextDelegate` *(Created per `(RenderObject, TextPlugin)` pair)*

`TextDelegate` is a capability-scoped proxy created 1-to-1 for each `(RenderObject, TextPlugin)` pair so plugins cannot corrupt layout state or overwrite another plugin's painters. Each delegate exposes plain `text` (with `WidgetSpan` offsets aligned and semantics labels excluded), isolated `backgroundPainter` and `foregroundPainter` slots, glyph-box geometry queries (`getBoxesForSelection`), and viewport scrolling (`ensureVisible`).

```dart
class TextDelegate extends ChangeNotifier {
  final RenderBox renderObject;
  final TextPlugin plugin;

  // Text & layout state
  String get text;
  InlineSpan get textSpan;
  bool get hasLayout;
  Size get size;

  // Isolated per-plugin painter slots
  CustomPainter? backgroundPainter;
  CustomPainter? foregroundPainter;

  // Geometry & scrolling
  List<ui.TextBox> getBoxesForSelection(TextSelection selection, { ... });
  ui.TextPosition getPositionForOffset(Offset offset);
  void ensureVisible(ui.TextRange range, { ... });
}
```

---

## 4. `RenderParagraph` & `RenderEditable`

`RenderParagraph` (backing `Text` / `RichText`) and `RenderEditable` (backing `EditableText` / `TextField`) are the rendering hosts that execute the plugin pipeline. They reconcile `TextDelegate` instances from `textPlugins`, schedule post-layout callbacks after `performLayout()`, forward pointer events, and paint plugin `backgroundPainter`s behind the text glyphs and `foregroundPainter`s in front of them.

```dart
class RenderParagraph extends RenderBox { // Same host contract on RenderEditable
  List<TextPlugin>? textPlugins; // Resolved from TextPluginScope

  @override
  void performLayout() {
    _layoutTextWithConstraints(constraints);
    // Fires didAddText / didUpdateText / didLayoutText right after flushLayout()
    owner?.schedulePostLayoutCallback(_flushTextPluginCallbacks);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // 1. Plugin backgrounds (in ascending paintOrder)
    for (final delegate in _delegates) delegate.backgroundPainter?.paint(...);
    // 2. Text glyphs & inline spans
    _textPainter.paint(context.canvas, offset);
    // 3. Plugin foregrounds (in ascending paintOrder)
    for (final delegate in _delegates) delegate.foregroundPainter?.paint(...);
  }
}
```

---

## 5. `SearchInPagePlugin`

`SearchInPagePlugin` is the built-in first-party `TextPlugin` providing `Ctrl+F` / `Cmd+F` find-in-page across static text and editable text fields. It incrementally indexes matches per `TextDelegate`, orders matches in visual document order, paints passive and active highlights, and scrolls the active match into view while exposing match counts via `ChangeNotifier` for custom search bars.

```dart
class SearchInPagePlugin extends TextPlugin with ChangeNotifier {
  SearchInPagePlugin({bool caseSensitive = false, bool eagerLoadOffscreenText = false, ...});

  String query;
  List<SearchMatch> get matches;
  int get activeMatchIndex;

  void nextMatch();
  void previousMatch();
  void scrollToActiveMatch(); // Calls activeMatch.delegate.ensureVisible(...)

  @override
  bool get needsOffscreenContent => eagerLoadOffscreenText;

  @override
  void didAddText(TextDelegate delegate) => _indexAndPaint(delegate);

  @override
  void didUpdateText(TextDelegate delegate) => _indexAndPaint(delegate);

  @override
  void didRemoveText(TextDelegate delegate) {
    delegate.backgroundPainter = null;
    _removeMatchesFor(delegate);
  }
}
```
