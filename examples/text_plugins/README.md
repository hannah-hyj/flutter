# Flutter Text Plugins Demo (`examples/text_plugins`)

An interactive demonstration of the **Text Plugins** architecture (`TextPlugin`, `TextDelegate`, and `TextPluginScope`) described in `Text-Plugins-One-Pager.md`.

## Featured Plugins

1. **Search in Page (`SearchInPagePlugin`)**:
   - Highlights all occurrences of a search query across all `Text` and `RichText` widgets in the scope using a `backgroundPainter` and highlights the active match with a `foregroundPainter`.
   - Supports case-sensitive matching and Previous/Next navigation with automatic scroll-into-view (`TextDelegate.showOnScreen`).
2. **Stock Ticker Highlighter (`StockTickerPlugin`)**:
   - Automatically detects stock ticker symbols (`GOOG`, `AAPL`, `MSFT`, `NVDA`, `TSLA`, `AMZN`) in any `Text` widget.
   - Paints color-coded badges and dotted underlines (`TextDelegate.getBoxesForSelection`).
3. **SEO / Live Text Extractor (`SeoExtractorPlugin`)**:
   - Tracks all active `Text` widgets (`didAddText`, `didUpdateText`, `didRemoveText`) and generates live word/character counts and a `schema.org` JSON-LD payload without needing the semantics tree.

Plugins in this version only paint. They do not receive pointer events and they do not change semantics, so a plugin that needs a tap to be useful (a link, a spoiler that is revealed on tap) is not part of this demo.

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
