# Design Document: Composable Text Plugins in Flutter

**Author**: Antigravity & User  
**Status**: Implemented Prototype (`packages/flutter` + `examples/text_plugins`)  
**Reference**: [Text-Plugins-One-Pager.md](Text-Plugins-One-Pager.md)

---

## 1. Problem Statement & Motivation

Flutter applications frequently need cross-cutting text capabilities that inspect, decorate, or attach interactions to text across an entire page or subtree:

1. **Find-in-Page / Search Highlighting**: Locating all occurrences of a query across disparate [Text](widgets/text.dart) and [RichText](widgets/basic.dart#L7892-L8098) widgets, painting active/inactive highlights, and scrolling the active match into view.
2. **Entity & Pattern Decoration**: Highlighting and making stock tickers (`GOOG`, `AAPL`), hashtags, mentions, or citations interactive without mutating the source string or requiring callers to pre-tokenize `TextSpan` trees.
3. **Automatic Linkification**: Detecting URLs (`https://...`, `www....`) in plain [Text](widgets/text.dart) widgets, painting link underlines, and handling tap gestures.
4. **Live Content & SEO Extraction**: Indexing visible text across a subtree to generate Schema.org JSON-LD metadata, word/reading-time analytics, or crawler snapshots.

### Why Custom `Text` Subclasses Fail

Historically, package authors solved these problems by creating custom drop-in replacement widgets (`LinkifyText`, `SearchableText`, `ParsedText`). This approach breaks down in real applications:

- **Zero Composability**: A developer cannot simultaneously use `LinkifyText` from Package A and `StockTickerText` from Package B on the same paragraph.
- **Invasive Refactoring**: Every [Text](widgets/text.dart) widget in the app—including those buried inside third-party widgets or Material/Cupertino components ([ListTile](material/list_tile.dart), [Card](material/card.dart), [DataTable](material/data_table.dart))—would have to be replaced.
- **No Document-Level Coordination**: Individual custom text widgets lack a shared coordinator unless accompanied by bespoke ancestor state management.

> [!IMPORTANT]
> **Core Architectural Insight**: Text cross-cutting concerns belong in an ambient, composable **plugin pipeline** attached via `InheritedWidget` ([TextPluginScope](widgets/text_plugin.dart#L30-L117)) and executed directly by [RenderParagraph](rendering/paragraph.dart#L317-L1381), leaving standard [Text](widgets/text.dart) and [RichText](widgets/basic.dart#L7892-L8098) widgets unchanged.

---

## 2. Design Goals & Framework/Community Taxonomy

### 2.1 Design Goals & Non-Goals

### Goals
- **Zero-boilerplate adoption**: Existing `Text('...')`, `Text.rich(...)`, and `EditableText` (`TextField`) widgets automatically participate when placed inside a [TextPluginScope](widgets/text_plugin.dart#L30-L117).
- **Full support for static & editable text**: Works seamlessly across both [RenderParagraph](rendering/paragraph.dart#L317-L1381) (`Text` / `RichText`) and [RenderEditable](rendering/editable.dart#L285) (`EditableText` / `TextField`), updating decorations live during text editing.
- **Deterministic multi-plugin composition**: Multiple plugins can inspect, paint behind/in front of, and handle pointer events on the same [RenderParagraph](rendering/paragraph.dart#L317-L1381) or [RenderEditable](rendering/editable.dart#L285) in a predictable root-to-leaf installation order.
- **Encapsulation of RenderObjects**: Plugins interact with a capability-scoped [TextDelegate](rendering/text_plugin.dart#L108) wrapping either `RenderParagraph` or `RenderEditable`, rather than mutating RenderObject internals directly.
- **Subtree opt-out**: Subtrees (such as toolbars, search inputs, or decorative chrome) can opt out of ancestor plugins via [TextPluginScope.none](widgets/text_plugin.dart#L48-L52).
- **Strict layer separation**: Rendering primitives live in `package:flutter/rendering.dart` ([rendering/text_plugin.dart](rendering/text_plugin.dart)); widget scoping lives in `package:flutter/widgets.dart` ([widgets/text_plugin.dart](widgets/text_plugin.dart)). Neither depends on Material or Cupertino.

### Non-Goals (Current Scope)
- **Mutating the input `InlineSpan` tree or changing text metrics**: Plugins decorate and observe laid-out text via [CustomPainter](rendering/custom_paint.dart)s (`backgroundPainter` / `foregroundPainter`); they do not rewrite font sizes or insert layout-shifting inline widgets during layout.
- **Implementing all plugins upfront**: Our goal is to define the extensible architecture and provide a few minimal core plugins (like `SearchInPagePlugin` and `_SelectionHighlightTextPlugin`). We expect the community to build and publish the long tail of domain-specific plugins (linkifiers, spelling linters, etc.).

---


### 2.2 Framework-Builtin vs. Community Package Taxonomy & Generic API Design

A critical architectural consideration is defining **what belongs in the core Flutter framework (`package:flutter`)** versus **what should be published by the community as packages (`pub.dev`)**, and how to design the core API to maximize universality.

#### 2.2.1 Framework-Builtin Plugins (`package:flutter`)

Only plugins that fulfill universal, platform-standard expectations and have zero external dependencies belong inside `package:flutter`:

1. **`_SelectionHighlightTextPlugin`**: Internal plugin supporting `SelectionArea` / `SelectableRegion` text selection highlighting across all platforms.
2. **`SearchInPagePlugin`**: Standard desktop/web `Ctrl+F` search highlighting, sequential match navigation, and viewport lazy-loading management.

#### 2.2.2 Community Package Plugins (`pub.dev`)

Domain-specific, opinionated, or third-party-dependent features should be maintained by the community as standalone packages:

1. **`SpellCheckPlugin` (`package:flutter_spellcheck`)**: Integration for IME spellcheck squiggly underlines and grammar suggestions.
1. **`LinkifyPlugin` (`package:flutter_linkify_plugin`)**: Regex URL parsing, custom link styles, and integration with `url_launcher`.
2. **`StockTickerPlugin` / `FinancialTextPlugin`**: Financial symbol decoration (`GOOG`, `AAPL`), crypto address detection, and currency conversions.
3. **`PiiRedactionPlugin` (`package:flutter_pii_redaction`)**: Compliance masking for SSNs, API keys, and sensitive data with tap-to-reveal mechanisms.
4. **`ReadAloudPlugin` (`package:flutter_read_aloud`)**: TTS karaoke narration synchronizers integrated with `flutter_tts` or cloud speech APIs.
5. **`SeoExtractorPlugin` (`package:flutter_seo_text`)**: Scraping plain text for Schema.org JSON-LD web crawlers.
6. **`AiGroundingPlugin` / `SpoilerBlurPlugin`**: LLM citation grounding popups and animated spoiler blur shaders.

#### 2.2.3 Principles for Designing a Universal, Generic API

To ensure `TextPlugin` scales smoothly from simple core selection to complex community packages, the API adheres to four core design principles:

1. **Capability-Based Primitives over Hardcoded Assumptions**:
   - Instead of creating specific APIs for links or search matches, `TextDelegate` exposes generic low-level primitives: `getBoxesForSelection`, `getPositionForOffset`, `getWordBoundary`, `getLineBoundary`, `getOffsetForCaret`, `backgroundPainter`, and `foregroundPainter`.
2. **Layered Composability & Selective Filtering**:
   - `TextPluginScope` permits stacking arbitrary numbers of plugins.
   - `TextPluginScope.exclude(types: {...})` provides typed subtree filtering so app developers can exclude specific plugins on UI chrome without breaking core plugins like `_SelectionHighlightTextPlugin`.
3. **Reactive Viewport Control Protocol**:
   - The `disableLazyLoading` protocol lets document-wide plugins (search, SEO) temporarily request full sliver materialization across `ListView.builder` viewports without tight coupling between plugins and scroll widgets.
4. **Semantics & Accessibility Alignment**:
   - `TextDelegate` provides a path to register `TextPluginSemanticAnnotation`s so visually decorated text (links, tickers, redacted text) automatically maps to focusable, accessible `SemanticsNode`s for screen readers.

---

## 3. Architecture & Component Design

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogImdyYXBoIFREXG4gICAgc3ViZ3JhcGggV2lkZ2V0c1tcIldpZGdldHMgTGF5ZXIgKHBhY2thZ2U6Zmx1dHRlci93aWRnZXRzLmRhcnQpXCJdXG4gICAgICAgIFNjb3BlT3V0ZXJbXCJUZXh0UGx1Z2luU2NvcGUgKE91dGVyOiBlLmcuIFNlYXJjaFBsdWdpbilcIl1cbiAgICAgICAgU2NvcGVJbm5lcltcIlRleHRQbHVnaW5TY29wZS5tdWx0aXBsZSAoSW5uZXI6IFN0b2NrUGx1Z2luLCBMaW5raWZ5UGx1Z2luKVwiXVxuICAgICAgICBTY29wZU5vbmVbXCJUZXh0UGx1Z2luU2NvcGUubm9uZSAoT3B0LW91dCBTdWJ0cmVlKVwiXVxuICAgICAgICBUZXh0V2lkZ2V0W1wiVGV4dCAvIFRleHQucmljaFwiXVxuICAgICAgICBSaWNoVGV4dFdpZGdldFtcIlJpY2hUZXh0XCJdXG4gICAgICAgIEVkaXRhYmxlV2lkZ2V0W1wiRWRpdGFibGVUZXh0IC8gVGV4dEZpZWxkXCJdXG4gICAgZW5kXG5cbiAgICBzdWJncmFwaCBSZW5kZXJpbmdbXCJSZW5kZXJpbmcgTGF5ZXIgKHBhY2thZ2U6Zmx1dHRlci9yZW5kZXJpbmcuZGFydClcIl1cbiAgICAgICAgUlBbXCJSZW5kZXJQYXJhZ3JhcGhcIl1cbiAgICAgICAgUkVbXCJSZW5kZXJFZGl0YWJsZVwiXVxuICAgICAgICBURDFbXCJUZXh0RGVsZWdhdGUgKFNlYXJjaFBsdWdpbilcIl1cbiAgICAgICAgVEQyW1wiVGV4dERlbGVnYXRlIChTdG9ja1BsdWdpbilcIl1cbiAgICAgICAgVEQzW1wiVGV4dERlbGVnYXRlIChMaW5raWZ5UGx1Z2luKVwiXVxuICAgIGVuZFxuXG4gICAgU2NvcGVPdXRlciAtLT4gU2NvcGVJbm5lclxuICAgIFNjb3BlSW5uZXIgLS0-IFRleHRXaWRnZXRcbiAgICBTY29wZUlubmVyIC0tPiBFZGl0YWJsZVdpZGdldFxuICAgIFNjb3BlSW5uZXIgLS0-IFNjb3BlTm9uZVxuICAgIFRleHRXaWRnZXQgLS0-IFJpY2hUZXh0V2lkZ2V0XG4gICAgUmljaFRleHRXaWRnZXQgLS0-fFwidGV4dFBsdWdpbnMgPSBbU2VhcmNoLCBTdG9jaywgTGlua2lmeV1cInwgUlBcbiAgICBFZGl0YWJsZVdpZGdldCAtLT58XCJ0ZXh0UGx1Z2lucyA9IFtTZWFyY2gsIFN0b2NrLCBMaW5raWZ5XVwifCBSRVxuICAgIFJQIC0tPiBURDFcbiAgICBSRSAtLT4gVEQxXG4gICAgUlAgLS0-IFREMlxuICAgIFJFIC0tPiBURDJcbiAgICBSUCAtLT4gVEQzXG4gICAgUkUgLS0-IFREMyIsICJtZXJtYWlkIjogeyJ0aGVtZSI6ICJkZWZhdWx0In19)


### 3.1 Layering & File Organization

| Layer | File | Public Symbols | Responsibility |
| :--- | :--- | :--- | :--- |
| **Rendering** | [rendering/text_plugin.dart](rendering/text_plugin.dart) | [TextPlugin](rendering/text_plugin.dart), [TextDelegate](rendering/text_plugin.dart#L108) | Defines the plugin lifecycle interface and the unified delegate handle wrapping `RenderParagraph` or `RenderEditable`. |
| **Rendering** | [rendering/paragraph.dart](rendering/paragraph.dart) | [RenderParagraph.textPlugins](rendering/paragraph.dart#L565-L575) | Reconciles delegates, dispatches lifecycle & pointer events, and executes painters for static text. |
| **Rendering** | [rendering/editable.dart](rendering/editable.dart) | [RenderEditable.textPlugins](rendering/editable.dart#L285) | Reconciles delegates, dispatches typing/layout & pointer events, and executes painters for editable text fields. |
| **Widgets** | [widgets/text_plugin.dart](widgets/text_plugin.dart) | [TextPluginScope](widgets/text_plugin.dart#L30-L117) | Scopes and merges `TextPlugin` lists down the widget tree via `_InheritedTextPluginScope`. |
| **Widgets** | [widgets/basic.dart](widgets/basic.dart) | [RichText.textPlugins](widgets/basic.dart#L8035) | Resolves `textPlugins ?? TextPluginScope.maybeOf(context)` and forwards to `RenderParagraph`. |
| **Widgets** | [widgets/editable_text.dart](widgets/editable_text.dart) | [EditableText.textPlugins](widgets/editable_text.dart#L947) | Resolves `textPlugins ?? TextPluginScope.maybeOf(context)` and forwards to `_Editable` / `RenderEditable`. |

### 3.2 `TextPlugin` Lifecycle Contract

Defined in [rendering/text_plugin.dart](rendering/text_plugin.dart#L44-L71), `TextPlugin` exposes five hooks:

```dart
abstract class TextPlugin {
  const TextPlugin();

  void didAddText(TextDelegate delegate) {}
  void didUpdateText(TextDelegate delegate) {}
  void didLayoutText(TextDelegate delegate) {}
  void didRemoveText(TextDelegate delegate) {}
  void handlePointerEvent(TextDelegate delegate, PointerEvent event) {}
}
```

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogInNlcXVlbmNlRGlhZ3JhbVxuICAgIHBhcnRpY2lwYW50IFcgYXMgUmljaFRleHQgKFdpZGdldClcbiAgICBwYXJ0aWNpcGFudCBSUCBhcyBSZW5kZXJQYXJhZ3JhcGhcbiAgICBwYXJ0aWNpcGFudCBURCBhcyBUZXh0RGVsZWdhdGVcbiAgICBwYXJ0aWNpcGFudCBUUCBhcyBUZXh0UGx1Z2luXG5cbiAgICBXLT4-UlA6IGNyZWF0ZVJlbmRlck9iamVjdCAvIHVwZGF0ZVJlbmRlck9iamVjdCAodGV4dFBsdWdpbnMpXG4gICAgUlAtPj5URDogbmV3IFRleHREZWxlZ2F0ZSh0aGlzLCBwbHVnaW4pXG4gICAgUlAtPj5UUDogZGlkQWRkVGV4dChkZWxlZ2F0ZSlcbiAgICBOb3RlIG92ZXIgUlAsVFA6IE5vdGU6IExheW91dCBoYXMgTk9UIHJ1biB5ZXQgb24gaW5pdGlhbCBtb3VudCAoaGFzTGF5b3V0ID09IGZhbHNlKVxuXG4gICAgUlAtPj5SUDogcGVyZm9ybUxheW91dCgpXG4gICAgUlAtPj5URDogbm90aWZ5Q2hhbmdlZCgpXG4gICAgUlAtPj5UUDogZGlkTGF5b3V0VGV4dChkZWxlZ2F0ZSlcbiAgICBOb3RlIG92ZXIgUlAsVFA6IExheW91dCBxdWVyaWVzIChnZXRCb3hlc0ZvclNlbGVjdGlvbiwgc2l6ZSkgYXJlIG5vdyB2YWxpZFxuXG4gICAgUlAtPj5SUDogcGFpbnQoY29udGV4dCwgb2Zmc2V0KVxuICAgIFJQLT4-VEQ6IGJhY2tncm91bmRQYWludGVyPy5wYWludChjYW52YXMsIHNpemUpXG4gICAgUlAtPj5SUDogX3RleHRQYWludGVyLnBhaW50KGNhbnZhcywgb2Zmc2V0KVxuICAgIFJQLT4-VEQ6IGZvcmVncm91bmRQYWludGVyPy5wYWludChjYW52YXMsIHNpemUpXG5cbiAgICBXLT4-UlA6IHVwZGF0ZVJlbmRlck9iamVjdCAodGV4dCBjaGFuZ2VkKVxuICAgIFJQLT4-VEQ6IG5vdGlmeUNoYW5nZWQoKVxuICAgIFJQLT4-VFA6IGRpZFVwZGF0ZVRleHQoZGVsZWdhdGUpXG4gICAgUlAtPj5SUDogcGVyZm9ybUxheW91dCgpXG4gICAgUlAtPj5UUDogZGlkTGF5b3V0VGV4dChkZWxlZ2F0ZSlcblxuICAgIFctPj5SUDogZGlzcG9zZSgpIG9yIHBsdWdpbiByZW1vdmVkIGZyb20gc2NvcGVcbiAgICBSUC0-PlREOiBkZXRhY2hQYWludGVycygpXG4gICAgUlAtPj5UUDogZGlkUmVtb3ZlVGV4dChkZWxlZ2F0ZSlcbiAgICBSUC0-PlREOiBkaXNwb3NlKCkiLCAibWVybWFpZCI6IHsidGhlbWUiOiAiZGVmYXVsdCJ9fQ==)


### 3.3 `TextDelegate`: Capability-Scoped Proxy for `RenderParagraph`

Instead of passing [RenderParagraph](rendering/paragraph.dart#L317-L1381) directly to plugins—which would allow plugins to corrupt layout state, mutate constraints, or overwrite each other's painters—each `(RenderParagraph, TextPlugin)` pair gets its own [TextDelegate](rendering/text_plugin.dart#L86-L287) instance:

- **Isolated Painter Slots**: Each [TextDelegate](rendering/text_plugin.dart#L86-L287) owns its own [backgroundPainter](rendering/text_plugin.dart#L153-L162) and [foregroundPainter](rendering/text_plugin.dart#L141-L150). Setting or replacing a painter checks `shouldRepaint`, attaches/detaches the painter's `Listenable` (`addListener(_paragraph.markNeedsPaint)`), and calls `markNeedsPaint()` only when needed.
- **Content Inspection**:
  - [delegate.text](rendering/text_plugin.dart#L102): Returns `_paragraph.text.toPlainText(includeSemanticsLabels: false)` so plugins see the exact UTF-16 character stream laid out by `TextPainter` (without `semanticsLabel` overrides corrupting character offsets).
  - [delegate.textSpan](rendering/text_plugin.dart#L106): Exposes the raw `InlineSpan` tree for plugins that need style or span-structure inspection.
- **Layout & Coordinate Queries**:
  - [hasLayout](rendering/text_plugin.dart#L125) (`_paragraph.hasSize && !_paragraph.debugNeedsLayout`), [hasSize](rendering/text_plugin.dart#L117), and [size](rendering/text_plugin.dart#L130).
  - [getBoxesForSelection](rendering/text_plugin.dart#L183-L193), [getPositionForOffset](rendering/text_plugin.dart#L199-L201), [getWordBoundary](rendering/text_plugin.dart#L206-L208), [getOffsetForCaret](rendering/text_plugin.dart#L214-L216), and [getFullHeightForCaret](rendering/text_plugin.dart#L221-L223).
  - Coordinate conversion & scrolling helpers: [localToGlobal](rendering/text_plugin.dart#L234-L236), [globalToLocal](rendering/text_plugin.dart#L241-L243), [getTransformTo](rendering/text_plugin.dart#L227-L229), and [showOnScreen](rendering/text_plugin.dart#L247-L249) (enabling find-in-page plugins to auto-scroll the active match into the viewport).

### 3.4 `TextPluginScope` & Hierarchical Merging

[TextPluginScope](widgets/text_plugin.dart#L30-L117) uses an internal `InheritedWidget` (`_InheritedTextPluginScope`) that eagerly computes the merged, deduplicated list of plugins from root to leaf during `build`:

1. **Single & Multiple Registration**: `TextPluginScope(plugin: p, child: ...)` and `TextPluginScope.multiple(plugins: [p1, p2], child: ...)` look up `TextPluginScope.of(context)` and append their plugins after any ancestor plugins.
2. **Root-to-Leaf Deduplication**: If a plugin instance is already present in an ancestor scope, it retains its outer position so each `(RenderParagraph, TextPlugin)` pair is 1-to-1.
3. **Subtree Opt-Out (`TextPluginScope.none`)**: Installs an `_InheritedTextPluginScope` with `plugins: const <TextPlugin>[]`, shadowing all ancestor scopes for its `child` subtree.

### 3.5 `RenderParagraph` Painting & Z-Order Pipeline

Within [RenderParagraph.paint](rendering/paragraph.dart#L1218-L1319), layers are painted in the following strict Z-order (from back to front):

1. **Plugin `backgroundPainter`s** (in root-to-leaf plugin installation order, clipped to `offset & size` if `_needsClipping` is true).
2. **Selection highlights** (`_lastSelectableFragments` when inside a `SelectionArea` / `SelectableRegion`).
3. **Paragraph glyphs & inline children** (`_textPainter.paint` and `paintInlineChildren`, with overflow shader/clipping if applicable).
4. **Plugin `foregroundPainter`s** (in root-to-leaf plugin installation order, clipped if `_needsClipping` is true).
5. **Selection handles** (`_lastSelectableFragments` drag handles).

---

## 4. Broader Ecosystem Use Cases

Because `TextPlugin` combines **text inspection** (`plainText`, `placeholderRanges`), **sub-span geometry** (`getBoxesForSelection`, `getPositionForOffset`, `getWordBoundary`), **composited painting** (`backgroundPainter`, `foregroundPainter` without re-laying out text), **pointer routing** (`handlePointerEvent`), and **viewport control** (`ensureVisible`, `compareTo`, `disableLazyLoading`), it unlocks a broad ecosystem of drop-in plugins across any existing `Text` or `RichText` subtree.

Below is a summary of six broader ecosystem categories:

### 4.1 Accessibility, Reading Aids & Language Learning
1. **TTS "Read-Aloud Karaoke" Synchronizer**:
   - **How it works**: Sorts all mounted `TextDelegate`s in true visual reading order via `delegates.sort()` (`TextDelegate.compareTo`), tokenizes words while skipping `0xFFFC` `WidgetSpan` placeholders, tints the active paragraph in `backgroundPainter` and paints a pill highlight + underline over the currently spoken word in `foregroundPainter`, and automatically calls `delegate.ensureVisible(wordRange)` when narration crosses a paragraph or viewport boundary.
   - **Why `TextPlugin` shines**: Word-by-word TTS highlighting updates multiple times per second; using a `CustomPainter` via `TextDelegate.markNeedsPaint()` avoids rebuilding or re-shaping `RenderParagraph` on every word boundary.
2. **Inline Dictionary / Translation / Furigana Lookup**:
   - **How it works**: Listens for hover or long-press via `handlePointerEvent`, resolves the word via `getPositionForOffset` + `getWordBoundary`, highlights the hovered word, and anchors a translation or phonetic popover to `localToGlobal(wordBox.toRect().topCenter)`.
3. **Dyslexia / Focus Reading Ruler & Bionic Reading Guide**:
   - **How it works**: Tracks the pointer's vertical coordinate across paragraphs and uses `foregroundPainter` to dim surrounding lines while keeping a crisp spotlight window over the active line (`getLineBoundary`).

### 4.2 Security, Privacy & Compliance
1. **Live PII Redaction / Screen-Share Privacy Mask**:
   - **How it works**: Scans `delegate.plainText` for sensitive patterns (API keys like `sk-...`, SSNs, credit cards, email addresses). In `foregroundPainter` (which paints **after** `textPainter.paint()`), draws an opaque dark rounded badge with diagonal hazard stripes and `••••` dots completely covering the underlying sensitive glyphs. In `handlePointerEvent`, tapping a redacted box toggles revealing/masking that specific span (`markNeedsPaint()`).
   - **Why `TextPlugin` shines**: Banking, healthcare, and customer-support apps can wrap their entire app in `TextPluginScope(plugin: piiPlugin)` during screen-sharing, bug-report screenshots, or public demos without auditing thousands of individual `Text` widgets.

### 4.3 Editorial, Localization (l10n) & QA Tooling
1. **Read-Only Spellcheck, Grammar & Style-Guide Linter**:
   - **How it works**: Inspects rendered `Text` widgets for spelling errors (`recieve`, `seperate`, `occured`, `teh`) and company terminology violations (`utilize` vs. `use`). In `foregroundPainter`, draws classic wavy red (spelling) or amber (style) squiggly underlines along `box.toRect().bottom` using `Path`, and surfaces replacement suggestions when tapped.
2. **Untranslated / Broken-Interpolation l10n Detector**:
   - **How it works**: In staging builds, highlights raw translation keys (`auth.login.button_title`), uninterpolated placeholders (`{userName}`, `%1$s`), or `NaN` / `undefined` leaks in bright magenta and logs offending widget locations.
3. **Typography & Layout QA Inspector (Overflow / Orphans / Rivers)**:
   - **How it works**: Compares `getLineBoundary` and `getBoxesForSelection` across lines to highlight "widow/orphan" single-word last lines, clipped paragraphs, or cramped line heights for design QA.

### 4.4 Collaborative Annotation & Multi-User Presence
1. **Medium / Kindle-Style Persistent User Highlights & Margin Notes**:
   - **How it works**: Persists user character-range highlights and comment anchors in articles/documentation; `backgroundPainter` renders pastel highlighter strokes and `foregroundPainter` draws a comment badge at the end of the annotated span.
2. **Multiplayer Presence Carets & Live Co-Viewing Cursors**:
   - **How it works**: In collaborative doc viewers or review tools, renders remote teammates' selection ranges and named cursor flags using `getOffsetForCaret` and `getBoxesForSelection`.

### 4.5 AI / LLM Grounding, Citations & 120fps Effects
1. **RAG Source Attribution & Fact-Check Grounding Spans**:
   - **How it works**: Highlights claims in AI-generated responses that map to retrieved source documents; hovering or tapping a grounded span reveals the source citation card.
2. **Zero-Relayout Animated Shimmer / Spoiler Blur**:
   - **How it works**: Animates a gradient shader or blur mask over specific character ranges (`[spoiler]...[/spoiler]` or streaming tokens) at 120fps via `foregroundPainter` (`repaint: animationController`) with **zero** `TextPainter.layout()` cost.

### 4.6 Domain-Specific Smart Entities
1. **DevOps & Log Viewers**: Auto-detects UUIDs, Git commit SHAs, stack-trace `file.dart:123:45` references, and RFC-3339 timestamps inside plain `Text` logs—making them clickable to copy, jump to source, or preview local timezones.
2. **Medical, Legal & Scientific Reference Linkers**: Automatically turns ICD-10 codes, statute citations, or `arXiv:` / `DOI:` identifiers into interactive reference cards.

---

## 5. Feature Deep Dives

### 5.1 Scrolling, Document Ordering, and Canceling Lazy Loading (`Ctrl+F`)

Supporting browser-grade **"Find in Page" (`Ctrl+F`)** across scrollable Flutter views requires solving three interconnected problems at the rendering and widget layers:
1. **Scrolling to a matched character range** (`TextDelegate.ensureVisible`).
2. **Sorting matches in true document order** regardless of lazy mount order (`TextDelegate.compareTo`).
3. **Canceling lazy loading** in `ListView.builder` / `SliverList.builder` / `CustomScrollView` when `Ctrl+F` is active so offscreen items are materialized and searchable (`TextPlugin.disableLazyLoading` + `Viewport` integration).

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogInNlcXVlbmNlRGlhZ3JhbVxuICAgIHBhcnRpY2lwYW50IFVzZXJcbiAgICBwYXJ0aWNpcGFudCBQbHVnaW4gYXMgU2VhcmNoSW5QYWdlUGx1Z2luXG4gICAgcGFydGljaXBhbnQgU2NvcGUgYXMgVGV4dFBsdWdpblNjb3BlXG4gICAgcGFydGljaXBhbnQgVlAgYXMgVmlld3BvcnQgLyBSZW5kZXJWaWV3cG9ydFxuICAgIHBhcnRpY2lwYW50IFNsaXZlciBhcyBSZW5kZXJTbGl2ZXJMaXN0XG4gICAgcGFydGljaXBhbnQgUGFyYSBhcyBSZW5kZXJQYXJhZ3JhcGggKE9mZnNjcmVlbilcblxuICAgIFVzZXItPj5QbHVnaW46IFByZXNzZXMgQ3RybCtGIChlYWdlckxvYWRPZmZzY3JlZW5UZXh0ID0gdHJ1ZSlcbiAgICBQbHVnaW4tPj5TY29wZTogbm90aWZ5TGlzdGVuZXJzKCkgKGRpc2FibGVMYXp5TG9hZGluZyA9PSB0cnVlKVxuICAgIFNjb3BlLT4-VlA6IF9Jbmhlcml0ZWRUZXh0UGx1Z2luTGF6eUxvYWRpbmcgbm90aWZpZXMgVmlld3BvcnRcbiAgICBWUC0-PlZQOiBzY3JvbGxDYWNoZUV4dGVudCA9IFNjcm9sbENhY2hlRXh0ZW50LnBpeGVscygxZTkpXG4gICAgVlAtPj5TbGl2ZXI6IHBlcmZvcm1MYXlvdXQocmVtYWluaW5nQ2FjaGVFeHRlbnQ6IDFlOSlcbiAgICBTbGl2ZXItPj5QYXJhOiBCdWlsZHMsIG1vdW50cywgYW5kIGxheXMgb3V0IGFsbCBvZmZzY3JlZW4gaXRlbXNcbiAgICBQYXJhLT4-UGx1Z2luOiBhdHRhY2goKSAtPiBkaWRBZGRUZXh0KGRlbGVnYXRlKVxuICAgIFBhcmEtPj5QbHVnaW46IHBlcmZvcm1MYXlvdXQoKSAtPiBkaWRMYXlvdXRUZXh0KGRlbGVnYXRlKVxuICAgIFBsdWdpbi0-PlBsdWdpbjogU29ydHMgZGVsZWdhdGVzIHZpYSBkZWxlZ2F0ZS5jb21wYXJlVG8oKVxuICAgIFVzZXItPj5QbHVnaW46IE5leHQgTWF0Y2ggLyBFbnRlclxuICAgIFBsdWdpbi0-PlBhcmE6IGRlbGVnYXRlLmVuc3VyZVZpc2libGUobWF0Y2gucmFuZ2UpXG4gICAgUGFyYS0-PlZQOiBzaG93T25TY3JlZW4ocmVjdDogdGFyZ2V0UmVjdCkgLT4gc2Nyb2xscyB0byBtYXRjaCIsICJtZXJtYWlkIjogeyJ0aGVtZSI6ICJkZWZhdWx0In19)


---

#### 5.1.1 Scrolling to a Specific Character Range (`TextDelegate.ensureVisible`)

Scrolling to an entire `RenderParagraph` (`showOnScreen(rect: null)`) is insufficient when a paragraph is a multi-screen article block or when a horizontal/vertical nested scroll view clips part of a line.

[TextDelegate.ensureVisible](rendering/text_plugin.dart#L314-L342) computes the exact glyph bounding rectangle for any `TextRange` and reveals it across all enclosing viewports:

```dart
void ensureVisible(
  ui.TextRange range, {
  Duration duration = Duration.zero,
  Curve curve = Curves.ease,
}) {
  assert(hasLayout);
  final List<ui.TextBox> boxes = getBoxesForSelection(
    TextSelection(baseOffset: range.start, extentOffset: range.end),
    boxHeightStyle: ui.BoxHeightStyle.max,
    includePlaceholders: false,
  );
  if (boxes.isNotEmpty) {
    var targetRect = boxes.first.toRect();
    for (var i = 1; i < boxes.length; i += 1) {
      targetRect = targetRect.expandToInclude(boxes[i].toRect());
    }
    showOnScreen(rect: targetRect, duration: duration, curve: curve);
    return;
  }
  final position = ui.TextPosition(offset: range.start);
  final Offset caretOffset = getOffsetForCaret(position, Rect.zero);
  final double caretHeight = getFullHeightForCaret(position);
  showOnScreen(
    rect: Rect.fromLTWH(caretOffset.dx, caretOffset.dy, 1.0, caretHeight),
    duration: duration,
    curve: curve,
  );
}
```

#### How `showOnScreen` Traverses Slivers & Nested Viewports
1. `_paragraph.showOnScreen(descendant: _paragraph, rect: targetRect, duration: duration, curve: curve)` walks up the `RenderObject.parent` chain.
2. Each enclosing [RenderViewportBase](rendering/viewport.dart#L1429-L1517) invokes `RenderViewportBase.showInViewport`, querying `viewport.getOffsetToReveal(descendant, 0.0, rect: rect)` (leading edge) and `viewport.getOffsetToReveal(descendant, 1.0, rect: rect)` (trailing edge).
3. If `targetRect` is already fully visible between the leading and trailing edges of the viewport, `RevealedOffset.clampOffset` returns `null` and no unnecessary scroll occurs.
4. Otherwise, `offset.moveTo(targetOffset.offset, duration: duration, curve: curve)` scrolls (or animates) the minimal distance required to bring `targetRect` onscreen, and then continues walking up `super.showOnScreen` so **nested scroll views** (e.g., a horizontal scrollable inside a vertical `CustomScrollView`) scroll both axes into view.
5. **Deferred Scroll on Newly Mounted Items**: If [SearchInPagePlugin.scrollToActiveMatch](examples/text_plugins/lib/plugins/search_in_page_plugin.dart#L156-L171) is invoked while a newly mounted delegate has not yet completed layout (`!delegate.hasLayout`), the plugin sets `_pendingScrollToActiveMatch = true` and triggers `ensureVisible` inside `didLayoutText(delegate)` as soon as layout completes.

---

#### 5.1.2 Document-Order Sorting (`TextDelegate implements Comparable<TextDelegate>`)

#### The Problem: Mount Order $\neq$ Document Order
When a user starts at the middle of a `ListView.builder` (say at `Item 10`) and scrolls **upward**, `RenderSliverList` mounts `Item 9`, then `Item 8`, then `Item 7`. Consequently, `didAddText` is called in the chronological order `[Item 10, Item 9, Item 8, Item 7]`. If `SearchInPagePlugin` iterates over `_delegates` in registration order, pressing "Next Match" jumps **backward** up the document!

Furthermore, comparing global screen coordinates (`localToGlobal(Offset.zero).dy`) is insufficient for general layouts because two columns side-by-side or wrapped flex items may have overlapping vertical coordinates despite having a well-defined logical reading order in the widget tree.

#### How We Solved It: Lowest Common Ancestor Render-Tree Traversal
1. **Attach-Synchronized Registration**: [RenderParagraph](rendering/paragraph.dart#L568-L674) registers its `TextDelegate`s in `attach(PipelineOwner)` (when `RenderParagraph.parent` and the entire ancestor chain up to the root are already linked) and unregisters them immediately in `detach()`.
2. **Tree-Order Comparison ([TextDelegate.compareTo](rendering/text_plugin.dart#L353-L409))**:
   - Walks up `RenderObject.parent` from both `this._paragraph` and `other._paragraph` to find their **lowest common ancestor** (`commonParent`) and the two diverging child branches (`thisBranch` and `otherBranch`).
   - Calls `commonParent.visitChildren(...)` to determine which branch precedes the other.
   - Because `ContainerRenderObjectMixin.visitChildren` (used by `RenderFlex`, `RenderWrap`, `RenderViewport`, and `RenderSliverMultiBoxAdaptor` / `RenderSliverList`) always visits children from `firstChild` to `lastChild` in ascending logical index order—even when `insertAndLayoutLeadingChild` prepends children while scrolling upward—`delegates.sort()` guarantees true top-to-bottom document ordering.

---

#### 5.1.3 Canceling Lazy Loading on `Ctrl+F` (`TextPlugin.disableLazyLoading`)

#### Why Lazy Lists Hide Offscreen Text
In Flutter's sliver protocol ([RenderViewport._attemptLayout](rendering/viewport.dart#L1765-L1844) and [RenderSliverList.performLayout](rendering/sliver_list.dart#L46-L320)):
- `RenderViewport` computes `_calculatedCacheExtent` from `scrollCacheExtent` (defaulting to `250.0` logical pixels before and after the visible viewport).
- `RenderSliverList` only builds and lays out children whose layout offsets fall within `[scrollOffset + cacheOrigin, scrollOffset + cacheOrigin + remainingCacheExtent]`, and calls `collectGarbage(leadingGarbage, trailingGarbage)` to destroy children outside that window.
- Therefore, in a `ListView.builder` or `SliverList.builder` with 50 items, items #10–#50 do not exist in the Element or RenderObject trees until scrolled near the viewport.

#### How `TextPlugin.disableLazyLoading` Materializes Offscreen Slivers
We added a declarative, reactive mechanism that lets any `TextPlugin` (or `TextPluginScope`) temporarily cancel lazy loading in descendant viewports:

1. **Plugin Opt-In ([TextPlugin.disableLazyLoading](rendering/text_plugin.dart#L65))**:
   ```dart
   bool get disableLazyLoading => false;
   ```
   In [SearchInPagePlugin](examples/text_plugins/lib/plugins/search_in_page_plugin.dart#L69-L82), pressing `Ctrl+F` / `Cmd+F` (or toggling the **"Cancel Lazy Load"** chip) sets `eagerLoadOffscreenText = true` (`disableLazyLoading => true`) and calls `notifyListeners()`.
2. **Split Inherited Scope in [TextPluginScope](widgets/text_plugin.dart#L120-L246)**:
   - `_TextPluginScopeState` automatically subscribes to any installed `TextPlugin` that implements `Listenable`.
   - Crucially, `TextPluginScope` separates `_InheritedTextPluginScope` (which provides `List<TextPlugin>` to `RichText`) from `_InheritedTextPluginLazyLoading` (which provides `bool disableLazyLoading` via `TextPluginScope.shouldDisableLazyLoadingOf(context)`).
   - When `disableLazyLoading` flips from `false` to `true`, **only** `Viewport` and `ShrinkWrappingViewport` are notified—existing onscreen `RichText` widgets are **not** rebuilt!
3. **Viewport Cache Expansion ([Viewport._effectiveScrollCacheExtent](widgets/viewport.dart#L168-L185))**:
   - Both `Viewport` and `ShrinkWrappingViewport` check `TextPluginScope.shouldDisableLazyLoadingOf(context)`.
   - When `true`, they apply `const ScrollCacheExtent.pixels(1e9)`.
   - Why `1e9` (`1,000,000,000.0` logical pixels) instead of `double.maxFinite` or `double.infinity`?
     - In [RenderViewport._attemptLayout](rendering/viewport.dart#L1793-L1804), `fullCacheExtent = mainAxisExtent + 2 * _calculatedCacheExtent` and `centerCacheOffset = centerOffset + _calculatedCacheExtent`.
     - Using `double.maxFinite` (`1.79e308`) overflows `2 * _calculatedCacheExtent` to `double.infinity` (producing `NaN` in `fullCacheExtent - centerCacheOffset`) and loses all floating-point mantissa precision when adding `centerOffset`.
     - `1e9` pixels (equivalent to ~1,600,000 screens of scroll) is well within IEEE-754 float64's exact precision (`9e15`), preserving sub-pixel layout accuracy while forcing finite `SliverList` / `SliverGrid` / `ListView.builder` delegates to materialize and lay out all children from index `0` to `itemCount - 1`.
4. **Automatic Restoration**:
   - When the user closes `Ctrl+F` (`eagerLoadOffscreenText = false`), `_InheritedTextPluginLazyLoading` notifies the `Viewport` to restore its normal `250.0` pixel `cacheExtent`. On the very next layout pass, `RenderSliverList.collectGarbage` unmounts offscreen items and triggers `didRemoveText` for each one.

> [!WARNING]
> **Unbounded Infinite Lists (`itemCount == null`)**:  
> Developers should only enable `disableLazyLoading` on finite lists (`itemCount != null`). If a `SliverChildBuilderDelegate` has `childCount == null` (an infinite procedural generator that never returns `null`), expanding the cache extent will build items until the builder returns `null`.

---


### 5.2 Deep Dive: Should Selection Highlighting Be a `TextPlugin`?

A natural architectural question is whether Flutter's built-in text selection highlight ([_SelectableFragment.paintSelection](rendering/paragraph.dart#L3865-L3881)) should itself be migrated to a [TextPlugin](rendering/text_plugin.dart#L44-L89) installed by [SelectableRegion](widgets/selectable_region.dart#L240).

#### 5.2.1 What We Gain by Making Selection Highlight a `TextPlugin`

Look at how [_SelectableFragment.paintSelection](rendering/paragraph.dart#L3865-L3881) is implemented inside `RenderParagraph` today:

```dart
for (final TextBox textBox in paragraph.getBoxesForSelection(selection)) {
  context.canvas.drawRect(textBox.toRect().shift(offset), selectionPaint);
}
```

Mechanically, this is identical to a `TextPlugin` installing a `backgroundPainter` on [TextDelegate](rendering/text_plugin.dart#L102-L450). Extracting selection highlighting into a `TextPlugin` offers three major benefits:

1. **Composable Z-Order**: Instead of hardcoding whether selection highlights paint above or below plugin `backgroundPainter`s in [RenderParagraph.paint](rendering/paragraph.dart#L1245-L1333), the Z-order becomes controlled by scope ordering.
2. **Customizable Selection Visuals**: Applications could customize selection rendering (rounded `RRect` selection highlights, gradient highlights, or **multi-user collaborative cursors/selections** as in Google Docs) using standard `TextPlugin`s without modifying `RenderParagraph`.
3. **Decoupling `RenderParagraph`**: Over 2,100 lines of [paragraph.dart](rendering/paragraph.dart#L1752-L3937) are dedicated to `_SelectableFragment`. Moving selection highlight painting (and eventually selection state) out of `RenderParagraph` simplifies the core text render object.

---

#### 5.2.2 Corner Cases Discovered When Migrating Selection Highlight (`text-plugins-alt` Analysis)

Prototyping `_SelectionHighlightTextPlugin` inside `SelectableRegion` (as explored in [`Renzo-Olivares:text-plugins-alt`](https://github.com/Renzo-Olivares/flutter/commit/55f5d0af4503fe7950374addd625a5fd9ae8efb5)) reveals five subtle corner cases that must be addressed if selection highlighting is moved to a `TextPlugin`:

![Mermaid Diagram](https://mermaid.ink/img/eyJjb2RlIjogImdyYXBoIFREXG4gICAgU1JbXCJTZWxlY3RhYmxlUmVnaW9uIChOZWFyIEFwcCBSb290KVwiXVxuICAgIFNQU1tcIlRleHRQbHVnaW5TY29wZSAoX1NlbGVjdGlvbkhpZ2hsaWdodFRleHRQbHVnaW4pXCJdXG4gICAgRlBTW1wiVGV4dFBsdWdpblNjb3BlIChJbm5lciBGZWF0dXJlOiBlLmcuIFNlYXJjaEluUGFnZVBsdWdpbilcIl1cbiAgICBUWFRbXCJUZXh0KCdIZWxsbyBHT09HJywgc2VsZWN0aW9uQ29sb3I6IENvbG9ycy5hbWJlcilcIl1cblxuICAgIFNSIC0tPiBTUFMgLS0-IEZQUyAtLT4gVFhUIiwgIm1lcm1haWQiOiB7InRoZW1lIjogImRlZmF1bHQifX0=)


#### 1. Root-vs-Leaf Paint Order Inversion
- `SelectionArea` / `SelectableRegion` is almost always mounted near the root of a page or `Scaffold`, while feature plugins (`SearchInPagePlugin`, `StockTickerPlugin`, `LinkifyPlugin`) are mounted inside the page body.
- Under **root-first** painting (outermost scope paints first / at the back), the outer `_SelectionHighlightTextPlugin` paints *behind* inner feature plugins, so an opaque background badge from an inner plugin obscures the user's text selection highlight.
- Conversely, flipping all plugins to **leaf-first** painting (so the outer `SelectableRegion` paints on top) breaks the intuitive widget composition rule where a more specific inner `TextPluginScope` overrides a broader outer `TextPluginScope`.

#### 2. Per-Widget `Text(selectionColor: ...)` Overrides
- Flutter's [Text.selectionColor](widgets/text.dart#L713) allows an individual `Text` widget to override `DefaultSelectionStyle.of(context).selectionColor` on its own `RenderParagraph`.
- If `SelectableRegion` installs a single `_SelectionHighlightTextPlugin(color: defaultHighlightColor)` at the root of the selection scope and the painter uses `plugin.color`, per-widget `Text(selectionColor: ...)` overrides are lost unless `TextDelegate` exposes `Color? get selectionColor` from the underlying `RenderParagraph`.

#### 3. Disjoint Selections Across Embedded `WidgetSpan`s
- When a `RenderParagraph` contains inline `WidgetSpan`s (e.g., `"First [WidgetSpan] Second"`), `RenderParagraph` splits itself into multiple [_SelectableFragment](rendering/paragraph.dart#L1752)s around each `\uFFFC` placeholder code unit.
- Collapsing `_lastSelectableFragments` into a single `TextSelection?` union (`[minOffset, maxOffset]`) on `TextDelegate` causes two problems:
  1. Calling `getBoxesForSelection` on the union includes the box of the `\uFFFC` placeholder itself unless `includePlaceholders: false` is passed to slice around [TextDelegate.placeholderRanges](rendering/text_plugin.dart#L128-L145).
  2. If multi-fragment selection state is non-contiguous across nested selectables, a single union span cannot represent disjoint fragment ranges; exposing `List<TextSelection> get selections` on `TextDelegate` avoids lossy unioning.

#### 4. Legacy Fallback Suppression Bug (`skipLegacyHighlight`)
- To avoid double-painting semi-transparent selection colors when `_SelectionHighlightTextPlugin` is active, `_SelectableFragment.paintSelection` must know whether a plugin is already painting the selection highlight.
- Checking `final bool skipLegacyHighlight = paragraph.textPlugins.isNotEmpty;` is **broken**: if a developer uses a custom `SelectionRegistrar` (without `SelectableRegion`) and installs `LinkifyPlugin`, `textPlugins.isNotEmpty` is `true` and **silently disables selection highlighting** even though no selection highlight plugin is installed!
- **Fix**: Either remove legacy highlight painting from `_SelectableFragment` completely (having `SelectionContainer` always install the selection highlight plugin), or track an explicit `bool handlesSelectionHighlight` flag.

#### 5. Opt-Out Coupling (`TextPluginScope.none` vs. `SelectionContainer.disabled`)
- If `SelectableRegion` relies on `TextPluginScope` to paint selection highlights, wrapping a subtree in [TextPluginScope.none](widgets/text_plugin.dart#L50-L55) (for example, to exclude a card from `SeoExtractorPlugin` or `StockTickerPlugin`) will **also disable selection highlight painting** in that subtree, even though `_SelectableFragment` is still registered with `SelectionContainer` and copying text still works invisibly!
- **Fix**: Provide selective opt-out (`TextPluginScope.exclude`) or keep selection highlight registration orthogonal to `TextPluginScope.none`.

---

#### 5.2.3 Why Full Selection (`_SelectableFragment`) Requires More Than `CustomPainter`

While **selection highlight painting** fits into `TextDelegate.backgroundPainter`, the rest of [_SelectableFragment](rendering/paragraph.dart#L1752) cannot be moved out of `RenderParagraph` into a pure `TextPlugin` without extending `TextDelegate`:

1. **Mobile Selection Drag Handles Need `PaintingContext.pushLayer`**:
   [_SelectableFragment.paintHandles](rendering/paragraph.dart#L3883-L3907) pushes composited `LeaderLayer`s via `context.pushLayer(LeaderLayer(link: _startHandleLayerLink!, ...))` and requires [RenderParagraph.alwaysNeedsCompositing](rendering/paragraph.dart#L684) to return `true`. A `CustomPainter` only receives a `Canvas` and cannot push composited layers.
2. **Cross-RenderObject `SelectionRegistrar` Protocol**:
   `SelectionArea` selects across both text (`RenderParagraph`) and non-text `Selectable`s (such as selectable images). Any selection plugin must still bridge its fragments into `SelectionRegistrar`.

#### 5.2.4 Blueprint for Cleanly Extracting Selection into a `TextPlugin`

| Capability Needed | Required API on `TextDelegate` / `TextPluginScope` |
| :--- | :--- |
| **Per-fragment selection & color** | Expose `List<TextSelection> get selections` and `Color? get selectionColor` on `TextDelegate`. |
| **Skip `WidgetSpan` boxes** | Implemented via [TextDelegate.placeholderRanges](rendering/text_plugin.dart#L128-L145) and `includePlaceholders: false` on [TextDelegate.getBoxesForSelection](rendering/text_plugin.dart#L210-L257). |
| **Mobile drag handle layers** | Allow `TextDelegate` to register `LeaderLayer` handle links `(LayerLink, Offset)` painted during `RenderParagraph.paint` and reflected in `alwaysNeedsCompositing`. |
| **Orthogonal opt-out** | Add `TextPluginScope.exclude(types: {...})` so `TextPluginScope.none` does not inadvertently suppress `SelectionHighlightPlugin`. |

#### 5.2.5 Follow-up Roadmap Plan: Migrating `SelectionArea` / `SelectionContainer` to `TextPlugin`

Based on the prototype analysis of [`Renzo-Olivares:text-plugins-alt` (commit 55f5d0af4503fe7950374addd625a5fd9ae8efb5)](https://github.com/Renzo-Olivares/flutter/commit/55f5d0af4503fe7950374addd625a5fd9ae8efb5), migrating Flutter's built-in text selection highlights to a standard `TextPlugin` is planned as a four-phase follow-up item:

#### Phase 1: Internal `_SelectionHighlightTextPlugin` Prototype
- `SelectionContainer` / `SelectableRegion` installs a private `_SelectionHighlightTextPlugin` in its subtree.
- `_SelectionHighlightTextPlugin` listens to selection changes from `SelectionRegistrar`, reads selection bounds via `delegate.getBoxesForSelection(selection, includePlaceholders: false)`, and paints selection highlights using `delegate.backgroundPainter`.
- `RenderParagraph` and `RenderEditable` check whether a selection highlight plugin is active and suppress legacy `_SelectableFragment.paintSelection` fallback to avoid double-painting.

#### Phase 2: Mobile Selection Handle Layer Registration
- Extend `TextDelegate` with a handle layer registration method `delegate.registerHandleLayers(startLink, endLink)`, enabling selection plugins to push composited `LeaderLayer`s for mobile drag handles during `RenderParagraph.paint` / `RenderEditable._paintContents`.

#### Phase 3: Typed Subtree Opt-Out (`TextPluginScope.exclude`)
- Introduce `TextPluginScope.exclude(types: {SearchInPagePlugin, StockTickerPlugin})` alongside `TextPluginScope.none` so developers can disable feature plugins on UI chrome without inadvertently suppressing `_SelectionHighlightTextPlugin`.

#### Phase 4: Full Framework Decoupling
- Deprecate in-tree selection highlight painting inside `RenderParagraph` and `RenderEditable`, transferring 100% of selection highlight rendering to `_SelectionHighlightTextPlugin` for all Flutter applications.

---

## 6. Exhaustive Corner Cases & Architectural Analysis

Below are the 12 critical corner cases identified during design and implementation, how our implementation handles them today, and what additional safeguards or trade-offs apply.

### Corner Case 1: `ChangeNotifier` / `setState` Re-entrancy During Build, Layout, and Dispose

**The Problem**:  
`TextPlugin` callbacks are invoked synchronously inside rendering pipeline phases:
- `didAddText` and `didUpdateText` run during `RichText.createRenderObject` and `RichText.updateRenderObject` (**Widget Build phase**, `SchedulerPhase.persistentCallbacks`).
- `didLayoutText` runs at the end of `RenderParagraph.performLayout` (**Layout phase**, also `SchedulerPhase.persistentCallbacks`).
- `didRemoveText` runs during `RenderParagraph.dispose` (**Finalize Tree phase**, `SchedulerPhase.persistentCallbacks`).

If a `TextPlugin` is also a `ChangeNotifier` (or calls a callback that triggers `setState` on an ancestor widget, such as a search bar showing `"1 / 4 matches"` or an SEO inspector showing `"7 Text Widgets"`), calling `notifyListeners()` synchronously inside `didAddText`, `didLayoutText`, or `didRemoveText` throws a framework assertion:
> `setState() or markNeedsBuild() called during build.`

**How We Solved It**:
- **Painter updates happen synchronously**: Setting `delegate.backgroundPainter = ...` only calls `RenderParagraph.markNeedsPaint()`, which is completely legal during build and layout (before the paint phase).
- **External UI notifications are coalesced to post-frame**: In stateful plugins like [SearchInPagePlugin._scheduleNotify](examples/text_plugins/lib/plugins/search_in_page_plugin.dart#L194-L208) and [SeoExtractorPlugin._scheduleNotify](examples/text_plugins/lib/plugins/seo_extractor_plugin.dart#L82-L96), if `SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks`, `notifyListeners()` is deferred and coalesced via `SchedulerBinding.instance.addPostFrameCallback`, whereas interactive updates (e.g., typing in the search field during `SchedulerPhase.idle`) notify listeners immediately.

---

### Corner Case 2: Calling Layout Queries in `didAddText` or `didUpdateText` (`!delegate.hasLayout`)

**The Problem**:  
When `didAddText(delegate)` is called during `RichText.createRenderObject`, `RenderParagraph.performLayout()` has **not** run yet (`!_paragraph.hasSize`). Similarly, when `RichText.updateRenderObject` mutates `RenderParagraph.text`, `markNeedsLayout()` is called before `didUpdateText(delegate)`, so `_paragraph.debugNeedsLayout` is `true`. Calling `delegate.getBoxesForSelection(...)` or `delegate.size` inside `didAddText` or `didUpdateText` will fail with a `!debugNeedsLayout` assertion in `RenderParagraph`.

**How We Solved It**:
1. Exposed [TextDelegate.hasLayout](rendering/text_plugin.dart#L125) (`_paragraph.hasSize && !_paragraph.debugNeedsLayout`).
2. Added the explicit [TextPlugin.didLayoutText](rendering/text_plugin.dart#L62) lifecycle hook invoked at the end of `RenderParagraph.performLayout()` (and immediately in `_updateTextPlugins` if a new plugin is attached to an already-laid-out `RenderParagraph`).
3. Designed plugin `CustomPainter`s to query `delegate.getBoxesForSelection(...)` lazily inside `CustomPainter.paint(Canvas canvas, Size size)` (guarded by `if (!delegate.hasLayout) return;`), where layout is guaranteed to be up to date.

---

### Corner Case 3: Embedded `WidgetSpan`s (`PlaceholderSpan`) and UTF-16 Offset Alignment

**The Problem**:  
A `Text.rich` widget can contain inline `WidgetSpan` children (e.g., an inline icon or badge):
```dart
Text.rich(
  TextSpan(
    children: [
      TextSpan(text: 'Buy '),
      WidgetSpan(child: Icon(Icons.trending_up)),
      TextSpan(text: ' GOOG today'),
    ],
  ),
)
```
Inside `TextPainter` and native `ui.Paragraph`, every `PlaceholderSpan` occupies **1 UTF-16 code unit** represented by the Unicode Object Replacement Character `\uFFFC` (`0xFFFC`).
- If `delegate.text` omitted placeholders (`includePlaceholders: false`), `' GOOG today'` would start at index `4` in `delegate.text`, but at offset `5` in `TextPainter`! Passing `TextSelection(baseOffset: 4, extentOffset: 8)` to `getBoxesForSelection` would highlight `'GOO'` instead of `'GOOG'`.
- Conversely, if `delegate.text` used `includeSemanticsLabels: true` (the default of `InlineSpan.toPlainText()`), a `TextSpan(text: 'GOOG', semanticsLabel: 'Alphabet Inc.')` would return `'Alphabet Inc.'` in `delegate.text`, completely desynchronizing string indices from `TextPainter` glyph offsets!

**How We Solved It**:
- [TextDelegate.text](rendering/text_plugin.dart#L102) explicitly calls:
  ```dart
  String get text => _paragraph.text.toPlainText(includeSemanticsLabels: false);
  ```
  which keeps `includePlaceholders: true` (emitting `\uFFFC` for each `PlaceholderSpan`) and sets `includeSemanticsLabels: false`. This guarantees a **1-to-1 UTF-16 offset correspondence** between `delegate.text` indices and `TextSelection` / `TextPosition` offsets in `TextPainter`.

> [!TIP]
> Plugin authors writing regex matchers should note that `\uFFFC` is not a word character (`\w`) or whitespace (`\s`), so patterns like `\bGOOG\b` naturally treat adjacent `WidgetSpan`s as word boundaries without shifting character indices.

---

### Corner Case 4: Text Truncation (`maxLines`, `TextOverflow.ellipsis`, `TextOverflow.clip`, `TextOverflow.fade`)

**The Problem**:  
Suppose a `Text` widget has `maxLines: 1, overflow: TextOverflow.ellipsis` and a 500-character string where `'GOOG'` appears at character 400 (which is truncated behind `'...'`):
1. `delegate.text` returns the full 500-character string from `InlineSpan.toPlainText`, so a regex in `SearchInPagePlugin` or `StockTickerPlugin` will still find `'GOOG'` at offset `400..404`.
2. What happens when the plugin queries `delegate.getBoxesForSelection(TextSelection(baseOffset: 400, extentOffset: 404))`?
   - For characters completely past the ellipsis cutoff, `ui.Paragraph.getBoxesForRange` returns either an empty list `[]` or a collapsed zero-width box at the ellipsis end.
   - For a match that *straddles* the ellipsis cutoff (e.g., `'https://flut...'`), `getBoxesForSelection` returns the box for the visible prefix (`'https://flut'`).
3. What if a plugin's `CustomPainter` draws a rounded badge (`inflate(2.0)`) that extends outside `RenderParagraph.size` when `_needsClipping` is true?

**How We Solved It**:
- In [RenderParagraph.paint](rendering/paragraph.dart#L1235-L1247) and [L1299-L1311](rendering/paragraph.dart#L1299-L1311), when `_needsClipping` is `true` (`TextOverflow.clip`, `TextOverflow.ellipsis`, `TextOverflow.fade`), both `backgroundPainter` and `foregroundPainter` passes are clipped to `offset & size` via `context.canvas.clipRect(offset & size)`.
- **Future Enhancement**: Exposing `bool didExceedMaxLines` or `TextRange getVisibleTextRange()` on `TextDelegate` would allow search/SEO plugins to distinguish between *logical* text and *visually non-truncated* text when desired.

---

### Corner Case 5: Multi-Line Wrapping, Bidirectional (BiDi) Text, and Surrogate Pairs

**The Problem**:  
1. **Multi-Line & BiDi Discontinuity**: A single logical substring (e.g., a long URL wrapping across two lines, or an English phrase embedded inside an Arabic/Hebrew RTL paragraph) does **not** map to a single `Rect`. `getBoxesForSelection` returns multiple `ui.TextBox` instances—one per line fragment and BiDi directional run.
2. **UTF-16 Surrogate Pairs & Grapheme Clusters**: Dart `String` indices and `TextSelection` offsets are UTF-16 code units. Characters outside the Basic Multilingual Plane (such as emojis `🚀` or flags `🇺🇸`) occupy 2 or more UTF-16 code units. A naive substring search that splits a surrogate pair or combining mark could request boxes for half a grapheme cluster.

**How We Solved It**:
- All demo plugins ([SearchInPagePlugin](examples/text_plugins/lib/plugins/search_in_page_plugin.dart#L219-L263), [StockTickerPlugin](examples/text_plugins/lib/plugins/stock_ticker_plugin.dart#L204-L266), [LinkifyPlugin](examples/text_plugins/lib/plugins/linkify_plugin.dart#L158-L210)) iterate over **every** `ui.TextBox` returned by `delegate.getBoxesForSelection(...)` for both painting and pointer hit-testing (`boxes.any((box) => box.toRect().contains(localPosition))`).
- When scrolling a multi-line match into view ([SearchInPagePlugin._scrollToActiveMatch](examples/text_plugins/lib/plugins/search_in_page_plugin.dart#L179-L192)), the bounding union (`boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b))`) is computed and passed to `delegate.showOnScreen(rect: bounds)`.

---

### Corner Case 6: Dynamic Plugin List Reconciliation & Stateful Delegate Preservation

**The Problem**:  
Suppose a user toggles a single plugin on or off in `TextPluginScope.multiple(plugins: _activePlugins, ...)`, changing the active plugin list from `[stockPlugin, linkifyPlugin, searchPlugin]` to `[stockPlugin, linkifyPlugin]`.
If `RenderParagraph` naively disposed all delegates and recreated them whenever `textPlugins` changed:
- `stockPlugin` and `linkifyPlugin` would receive spurious `didRemoveText` + `didAddText` calls on every toggle.
- Any per-delegate state cached by `stockPlugin` (such as an ongoing animation or pointer-down tracking in `_pointerDownPositions[delegate]`) would be lost.

**How We Solved It**:
In [RenderParagraph._updateTextPlugins](rendering/paragraph.dart#L569-L629):
1. We diff the old `_textPluginDelegates` keys against `newPlugins`.
2. **Removed plugins**: Only plugins no longer present in `newPlugins` have their `TextDelegate` detached, notified via `plugin.didRemoveText(delegate)`, and disposed.
3. **Retained plugins**: Plugins present in both the old and new lists keep their exact existing `TextDelegate` instance (and its attached painters), re-indexed into `orderedDelegates` to match the new installation order.
4. **Newly added plugins**: Only newly added plugins receive a fresh `TextDelegate`, `didAddText(delegate)`, and (if already laid out) `didLayoutText(delegate)`.

---

### Corner Case 7: Duplicate Plugin Instances Across Nested `TextPluginScope`s

**The Problem**:  
What if a widget tree accidentally mounts the same `TextPlugin` instance twice—either twice in `TextPluginScope.multiple(plugins: [pluginA, pluginA])` or in both an outer `TextPluginScope(plugin: pluginA)` and an inner `TextPluginScope(plugin: pluginA)`?
If `RenderParagraph` created two `TextDelegate`s for the same `pluginA`, `pluginA.didAddText` would be called twice for the same paragraph, its painter would paint twice (doubling alpha opacity on semi-transparent highlights!), and `pluginA.handlePointerEvent` would fire twice per tap!

**How We Solved It**:
- We enforce deduplication at **both** layers:
  1. [TextPluginScope.build](widgets/text_plugin.dart#L93-L99) deduplicates `combined` using a `Set<TextPlugin>` while preserving first-seen (outermost/root-most) order.
  2. [RenderParagraph._updateTextPlugins](rendering/paragraph.dart#L605-L608) also guards with `if (orderedDelegates.containsKey(plugin)) continue;` in case a caller passes duplicate plugins directly to `RichText(textPlugins: [...])`.

---

### Corner Case 8: Pointer Event Routing, Multi-Plugin Conflicts, and Scroll Gesture Slop

**The Problem**:  
`RenderParagraph.handleEvent` forwards `PointerEvent`s to all active plugins in installation order. Several subtle interaction edge cases arise:
1. **Scroll vs. Tap Disambiguation**: Inside a `SingleChildScrollView` or `ListView`, a user might press their finger down on a highlighted link (`https://flutter.dev`) or stock ticker (`GOOG`) and drag to scroll. If a plugin triggered on `PointerDownEvent` or unconditionally on `PointerUpEvent`, scrolling the page would accidentally open links/modals!
2. **Overlapping Matches Across Plugins**: What if a search query highlights `'flutter'` inside `'https://flutter.dev'`, or two interactive plugins match overlapping ranges?
3. **Built-in `TextSpan.recognizer` Coexistence**: What if a `Text.rich` already has a `TapGestureRecognizer` on a `TextSpan`?

**How We Solved It**:
- **Touch Slop & Cancel Handling**: Both [StockTickerPlugin.handlePointerEvent](examples/text_plugins/lib/plugins/stock_ticker_plugin.dart#L99-L130) and [LinkifyPlugin.handlePointerEvent](examples/text_plugins/lib/plugins/linkify_plugin.dart#L75-L103) record `event.localPosition` on `PointerDownEvent`, clear it on `PointerCancelEvent`, and on `PointerUpEvent` verify `(event.localPosition - downPos).distance <= kTouchSlop` before firing their tap callback.
- **`TextSpan.recognizer` Coexistence**: In [RenderParagraph.hitTestChildren](rendering/paragraph.dart#L973-L993), if a `TextSpan` implements `HitTestTarget` (i.e., has a `GestureRecognizer`), it is added to the `HitTestResult` *before* `RenderParagraph` itself, and `RenderParagraph.hitTestSelf` returns `true` so both the span's recognizer and `RenderParagraph.handleEvent` receive the pointer event.
- **Future Enhancement**: If mutually exclusive gesture consumption between plugins is needed, `TextDelegate` can expose a gesture arena helper or `bool handlePointerEvent` return value to allow an earlier plugin to consume an event.

---

### Corner Case 9: `SelectionArea` / `SelectableRegion` Coexistence

**The Problem**:  
When a `Text` widget is inside both a `SelectionArea` and a `TextPluginScope`, both `RenderParagraph`'s `_SelectableFragment`s and `TextDelegate` painters are active on the same `RenderParagraph`.
- If a plugin's `backgroundPainter` painted *on top of* the user's text selection highlight, an opaque plugin badge would obscure the user's blue selection rectangle.
- If a plugin's `foregroundPainter` painted *on top of* selection drag handles, the handles could be partially covered.

**How We Solved It**:
- As shown in [RenderParagraph.paint](rendering/paragraph.dart#L1231-L1319):
  - Plugin `backgroundPainter`s paint **behind** `_SelectableFragment.paintSelection`, so user text selection remains visible over plugin background tints.
  - Plugin `foregroundPainter`s paint **in front of** glyphs (for underlines/overlays) but **behind** `_SelectableFragment.paintHandles`.

---

### Corner Case 10: Unintended Capture of UI Chrome & `TextPluginScope.none`

**The Problem**:  
In Flutter, almost every widget uses [Text](widgets/text.dart) and [RichText](widgets/basic.dart#L7892-L8098) internally: `AppBar` titles, `FilledButton` labels, `FilterChip` labels, `Tooltip` popups, `SnackBar` messages, and `TextField` hint/label/counter text.
If a developer wraps their entire `MaterialApp` or `Scaffold` in a `TextPluginScope(plugin: searchPlugin, ...)`:
- Searching for `'Add'` will highlight the `'Add Text'` button label!
- Even worse, if the search bar itself is inside the `TextPluginScope` and displays `'1 / 4'`, typing `'1'` in the search bar will match the search bar's own match counter!

**How We Solved It**:
1. Provided [TextPluginScope.none](widgets/text_plugin.dart#L48-L52) as a declarative firewall that strips all ancestor `TextPlugin`s for its `child` subtree.
2. In [examples/text_plugins/lib/main.dart](examples/text_plugins/lib/main.dart#L445-L590), we demonstrate two best-practice patterns:
   - Scoping `TextPluginScope.multiple` around the **content body** rather than the entire `Scaffold` chrome.
   - Wrapping embedded interactive controls inside the content body (such as the "Add Text" `TextField` + `FilledButton` row and the explicit Opt-Out Zone card) in `TextPluginScope.none`.

---

### Corner Case 11: Lazy Slivers (`ListView.builder`) & Offscreen Viewport Recycling

**The Problem**:  
In a `ListView.builder` or `CustomScrollView` with 1,000 paragraphs, Flutter by default only builds and mounts `RenderParagraph` instances for items currently inside the viewport + `cacheExtent` (`250.0` logical pixels).
- As the user scrolls down, top paragraphs are deactivated (`detach()` fires `didRemoveText`) and bottom paragraphs are mounted (`attach()` fires `didAddText` + `didLayoutText`).
- For **visual decoration plugins** (`StockTickerPlugin`, `LinkifyPlugin`), this works automatically with $O(\text{visible items})$ memory overhead!
- For **document-wide plugins** (`SearchInPagePlugin`, `SeoExtractorPlugin`), three scrolling challenges arise:
  1. **Out-of-order mounting when scrolling upward**: Items mounted while scrolling upward register via `didAddText` in reverse document order.
  2. **Scrolling to a specific substring match**: A match inside a tall paragraph or nested scroll view needs character-level scroll-to-range rather than just scrolling to the widget's top edge.
  3. **Offscreen unbuilt items in lazy lists (`Ctrl+F`)**: Unbuilt items outside `cacheExtent` have no `RenderParagraph` until lazy loading is canceled.
- **How We Solved All Three**: See **Section 6 (Scrolling, Document Ordering, and Canceling Lazy Loading)** below for the full architecture (`TextDelegate.compareTo`, `TextDelegate.ensureVisible`, and `TextPlugin.disableLazyLoading`).

---

### Corner Case 12: Canvas State Corruption in Plugin `CustomPainter`s

**The Problem**:  
Because all plugin `backgroundPainter`s and `foregroundPainter`s share the `PaintingContext.canvas` with `RenderParagraph`, a buggy plugin painter that calls `canvas.save()` without `canvas.restore()`, or mutates the canvas transform without restoring, could corrupt the rendering of subsequent plugins, the paragraph text itself, or sibling widgets in the same repaint boundary.

**How We Solved It**:
- [RenderParagraph._paintWithCustomPainter](rendering/paragraph.dart#L1178-L1224) wraps every individual plugin painter invocation in its own `canvas.save()` / `canvas.translate(offset.dx, offset.dy)` / `canvas.restore()` pair.
- In debug mode, it records `canvas.getSaveCount()` before and after `painter.paint(canvas, size)` and throws a descriptive `FlutterError` pinpointing the exact offending `CustomPainter` if its `save()`/`restore()` calls are unbalanced.

---
