# Flutter Text Plugins Demo (`examples/text_plugins`)

A small app for trying out text plugins that build widgets (`TextWidgetPlugin`, on top of `TextPlugin`, `TextDelegate` and `TextPluginScope`).

The page starts with a "What to try" list. Below it are five short sections of text to try things on: paragraphs, a text field, selectable text, moving text, and a long section for scrolling.

## Plugins in the App

1. **Suggestion Menu (`SpellcheckSuggestionsPlugin`)**:
   - Extends `SpellcheckLinterPlugin`, which still paints the squiggles and is unchanged.
   - Puts an invisible target on every flagged word (`TextWidgetLayer.foreground`) and opens a menu next to the word (`TextWidgetLayer.overlay`). In a text field the menu replaces the word, through the field. In other text it only shows the suggestion, because a plugin cannot change the text of a `Text` widget.
2. **Frosted Glass (`FrostedSpoilerPlugin`)**:
   - Covers every line of a `||spoiler||` or `{{cloze}}` span with a `BackdropFilter` (`TextWidgetLayer.foreground`). It has no painter, and the only lifecycle callback it uses is `didRemoveText`.
   - In a text field the span is shown while the caret is inside it.

Each has a chip. With the first one off, the painter-only `SpellcheckLinterPlugin` still underlines the words. With the second one off there is no spoiler plugin: a plugin that only paints cannot be tapped, so it could not show a span again.

## Other Plugins in `lib/plugins`

`SearchInPagePlugin`, `StockTickerPlugin`, `SeoExtractorPlugin` and `ReadAloudPlugin` belong to the larger demo of the painter-only design. This app does not use them.

## Running the Demo

The example has a web runner.

```bash
cd examples/text_plugins
../../bin/flutter run -d chrome
```

## Running Tests

```bash
cd examples/text_plugins
../../bin/flutter test
```

The tests that walk through the larger demo page are skipped.
