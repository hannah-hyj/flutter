&nbsp;

# SUMMARY

Allow third-party packages to interact and change the visual appearance of Text rendered by Flutter.

&nbsp;

**Author: Michael Goderbauer (@goderbauer)**

**Go Link: flutter.dev/go/{document-title}**

**Created:** November 2023  /  **Last updated:** November 2023

# GOALS

The goal of the proposed Text Plugin architecture is to allow third-party packages to extract and highlight arbitrary text that is rendered by `Text` widgets within a Flutter application. The plugins should be composable to allow multiple plugins to act on the same text. Plugins can extend the framework's text rendering in a generic way without requiring use-case specific implementations in the framework.

&nbsp;

This is not a design document. It is a proposal for adding an API, that still needs to be designed.

&nbsp;

# USE CASES

* **Text selection**: The new API should be powerful enough to implement Flutter's `TextRegion` / `SelectionArea` feature on top of it. This feature allows users to select arbitrary text in a Flutter application. It is currently implemented deep inside Flutter's text rendering engine making that part of the framework more complex than necessary. Ideally, the text plugin API outlined in this document could be used to implement this keeping text rendering in the framework as simple as possible while providing a customization hook for users, who want different selection behavior.  
* **Search in Page**: In web browsers, one can hit Cmd+F or Ctrl+F to search for text in a page. In Flutter, this is currently not supported, but a [prototype](https://goderbauer.github.io/demos/find-in-page/) exists. It requires the use of a special `SearchableText` widget, which replaces the `Text` widget and therefore limits composition: An app developer may have limited control to get `SearchableText` adopted by third-party packages and `SearchableText` is also incompatible with any other feature (e.g. SEO, see next bullet) that requires a custom text widget. Implementing "Search in page" on top of a text plugin API would remove these limitations.  
* **SEO (Search Engine Optimization)**: A SEO package may want to extract all text currently displayed in a Flutter app and present it in a format better understood by search engines. Currently, this requires either the use of the semantics tree (which has performance implications) or the use of a custom text widget (which comes with the limitations discussed in the previous bullet).  
* **Highlight stock ticker symbols in text (and similar use cases)**: Some websites auto-highlight all stock ticker symbols (e.g. GOOG or AAPL) found in any body of text. The text plugin API should be able to handle this use case: Identify all occurrences of GOOG, AAPL, etc. in any body of text and then change its visual representation to highlight them. Ideally, it would also make the occurrence clickable, so users can learn more about the ticker symbol, if desired.  
* **LinkedText (Linkify)**: Auto-detect hyperlinkable strings in Text widgets (e.g. [http://www.goderfarmers.com](http://www.goderfarmers.com)), automatically highlights them as a Link and makes them clickable.

&nbsp;

# API CONSIDERATIONS

The rough idea is that an app developer can install a text plugin for a subtree of the widge tree by wrapping it with a new `TextPluginScope` widget. The `TextPlugin` provided to this widget can henceforth keep track of all the `Text` widgets inside its subtree.&nbsp;

&nbsp;

The API exposed to a `TextPlugin` enables it to do the following:

* Query what string a given `Text` widget is displaying.  
* Query layout information about the displayed text in a `Text` widget and substrings within it (e.g. what are the `TextBox`es encompassing a given `TextSelection`, similar to `RenderParagraph.getBoxesForSelection`).  
* Provide a background/foreground painter to be painted behind or in front of a given `Text` widget to highlight certain substrings. If multiple plugins are installed for a subtree, their painters are applied in the order in which they were installed in the widget tree: text plugins installed closer to the root paint first.  
* *(not required for initial use cases, could be added later)* Register for pointer events that originate from the `Text` widgets inside the subtree.  
* *(not required for initial use cases, could be added later)* Change the `TextStyle` of substrings in the `Text` widget.  
* *(not required for initial use cases, could be added later)* Query the `TextStyle` used for a given section of the text.

&nbsp;

Special thought needs to be given to the life cycle of the `TextPlugin`: Obviously, the layout information of a `Text` widget is only available after the layout pass of Flutter's rendering pipeline has completed and the painters need to be provided before the `Text` is painted. This seems to indicate that the plugin should be given a chance to insert itself into the rendering of a `Text` widget between layout and paint. On the other hand, if we allow a plugin to change the `TextStyle` of text, it needs to do so before layout since the provided `TextStyle` may change the layout of the text (e.g. if font size is increased). This also means that the provided `TextStyle` may not depend on layout information since layout hasn't happened yet.

&nbsp;

TODO: Determine accessibility implications. Do the plugins need to be able to provide additional semantics information for the `Text` widget? E.g. if a "Search in Page'' plugin highlights a subsection of text, does that need to be reflected in the semantics tree in any way? Presumably, if plugins have the option to listen to pointer events there'll have to be an API to specify semantic actions for substrings as well.

&nbsp;

Some of the envisioned use cases (e.g. "Text Selection" and "Search in Page") also require grouping of `Text` widgets into logical units. Just organizing them by screen position alone may not be enough: If the content is organized in two columns, the author of a "Search In Page" plugin should likely be able to search one column first before moving on to the next one when the user clicks the button to highlight the next occurrence. While each text plugin could implement its own grouping mechanism, we should consider providing a generic one since multiple text plugin use cases could make use of it.&nbsp;

&nbsp;

# API SKETCH

Note: This section does not suggest a final design. It just explores some design option and should only be seen as a basis for discussion. All code shown is written in Dart (even though it says JavaScript).

&nbsp;

```js
abstract class TextPlugin {
  void didAddText(TextDelegate delegate) {
    // Called whenever a new `Text` widget appears in the
    // subtree covered by the plugin.
  }

  void didUpdateText(TextDelegate delegate) {
    // Called whenever the text displayed in a `Text` widget changes.
  }


  void didRemoveText(TextDelegate delegate) {
    // Called whenever a `Text` widget is removed from the
    // subtree covered by the plugin.
  }
}
```

Instead of having separate `didUpdateText` / `didRemoveText` we could also expose listeners on the `TextDelegate` for these events, so only plugins that actually care, are informed.&nbsp;

&nbsp;

```js
class TextDelegate {
  // Returns the text in the `Text` widget represented by this delegate.
  String get text;

  // To be painted in front of the `Text` widget.
  CustomPainter? get foregroundPainter;
  set (CustomPainter? foregroundPainter);

  // To be painted behind the `Text` widget.
  CustomPainter? get backgroundPainter;
  set (CustomPainter? backgroundPainter);

  // Query for layout information.
  List<TextBox> getBoxesForSelection(TextSelection selection);

  // ... more API as needed.
}
```

&nbsp;

&nbsp;