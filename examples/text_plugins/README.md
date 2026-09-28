# Flutter Text Plugins Demo (`examples/text_plugins`)

An interactive demonstration of the **Text Plugins** architecture (`TextPlugin`, `TextDelegate`, and `TextPluginScope`) described in `Text-Plugins-One-Pager.md`.

## Featured Plugins

1. **Search in Page (`SearchInPagePlugin`)**:
   - Highlights all occurrences of a search query across all `Text` and `RichText` widgets in the scope using a `backgroundPainter` and highlights the active match with a `foregroundPainter`.
   - Supports case-sensitive matching and Previous/Next navigation with automatic scroll-into-view (`TextDelegate.showOnScreen`).
2. **Stock Ticker Highlighter (`StockTickerPlugin`)**:
   - Automatically detects stock ticker symbols (`GOOG`, `AAPL`, `MSFT`, `NVDA`, `TSLA`, `AMZN`) in any `Text` widget.
   - Paints color-coded badges and dotted underlines, and handles tap events (`TextPlugin.handlePointerEvent` + `TextDelegate.getBoxesForSelection`) to open a live stock quote sheet.
3. **Linkify (`LinkifyPlugin`)**:
   - Auto-detects URLs (`http://`, `https://`, `www.`) in any `Text` widget, highlights them as links, and makes them clickable.
4. **SEO / Live Text Extractor (`SeoExtractorPlugin`)**:
   - Tracks all active `Text` widgets (`didAddText`, `didUpdateText`, `didRemoveText`) and generates live word/character counts and a `schema.org` JSON-LD payload without needing the semantics tree.

## Running the Demo

From the root of the Flutter repository:

```bash
./bin/flutter run -t examples/text_plugins/lib/main.dart -d macos
# or on Chrome:
./bin/flutter run -t examples/text_plugins/lib/main.dart -d chrome
```

## Running Tests

```bash
./bin/flutter test examples/text_plugins/test/widget_test.dart
```
