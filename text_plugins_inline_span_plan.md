# Composable Text Plugins: the inline-span prototype (plan)

**Status:** plan, reviewed 2026-11-20. The decisions in [Section 10](#10-decisions-resolved-2026-11-20) are folded into the text. Nothing in this document has been built yet.
**Timebox:** 10 hours of working time for the whole experiment ([Section 8](#8-work-plan)).
**Branch:** `text-plugin-mvp-inline-span`, cut from `text-plugin-mvp` at `0d2e3bd20d2`.
**Compared against:** the painter prototype on `text-plugin-mvp` ([text_plugins_design_doc.md](./text_plugins_design_doc.md), RFC [flutter/rfc#35](https://github.com/flutter/rfc/pull/35)).
**Tracking issue:** [flutter/flutter#65504](https://github.com/flutter/flutter/issues/65504).

---

## Table of contents

- [0. What this experiment is for](#0-what-this-experiment-is-for)
- [1. The two approaches in one paragraph each](#1-the-two-approaches-in-one-paragraph-each)
- [2. What the code already tells us, before writing anything](#2-what-the-code-already-tells-us-before-writing-anything)
- [3. Stage 1 design: decorations as spans](#3-stage-1-design-decorations-as-spans)
  - [3.1 Plugins hand over data, the framework builds the span](#31-plugins-hand-over-data-the-framework-builds-the-span)
  - [3.2 Where the span is built: widget layer or render layer](#32-where-the-span-is-built-widget-layer-or-render-layer)
  - [3.3 The merge: from ranges to a span tree](#33-the-merge-from-ranges-to-a-span-tree)
  - [3.4 Invalidation: how a plugin changes what is on screen](#34-invalidation-how-a-plugin-changes-what-is-on-screen)
  - [3.5 "Complex painting" with spans: the three mechanisms](#35-complex-painting-with-spans-the-three-mechanisms)
  - [3.6 What is kept from the painter prototype and what is removed](#36-what-is-kept-from-the-painter-prototype-and-what-is-removed)
  - [3.7 The lifecycle moves to build time](#37-the-lifecycle-moves-to-build-time)
- [4. Stage 2 redesign: gestures, hover, semantics through `TextSpan`](#4-stage-2-redesign-gestures-hover-semantics-through-textspan)
- [5. Stage 3 redesign: widgets through `WidgetSpan`](#5-stage-3-redesign-widgets-through-widgetspan)
- [6. The experiments](#6-the-experiments)
  - [6.1 Fidelity: port the demo plugins](#61-fidelity-port-the-demo-plugins)
  - [6.2 Correctness hazards, one test each](#62-correctness-hazards-one-test-each)
  - [6.3 Performance](#63-performance)
  - [6.4 API ergonomics](#64-api-ergonomics)
- [7. How the two approaches will be compared](#7-how-the-two-approaches-will-be-compared)
- [8. Work plan](#8-work-plan)
- [9. What would stop the experiment early](#9-what-would-stop-the-experiment-early)
- [10. Decisions (resolved 2026-11-20)](#10-decisions-resolved-2026-11-20)

---

## 0. What this experiment is for

The painter prototype adds a new vocabulary to Flutter text: `TextPluginPainter`, `TextLayout`, a background and a foreground paint pass in `RenderParagraph` and `RenderEditable`, and a post-layout callback phase in the binding. Reviewers can reasonably ask why a highlight is not simply a `TextSpan` with a `backgroundColor`, which is how Flutter has always decorated text, how `EditableText` draws the composing underline, and how spell check draws its squiggles today (`buildTextSpanWithSpellCheckSuggestions`).

This experiment builds that alternative far enough to answer the question with evidence rather than opinion. A second prototype, on this branch, expresses every plugin effect as a change to the `InlineSpan` tree:

- Stage 1 (decoration): highlight, underline, strike-through, colour, and anything else `TextStyle` can say, as split `TextSpan`s.
- Stage 2 (interaction): taps, hover, cursors and semantics through the properties `TextSpan` already has (`recognizer`, `onEnter`, `onExit`, `mouseCursor`, `semanticsLabel`).
- Stage 3 (widgets): real widgets through `WidgetSpan`, and a frank account of what `WidgetSpan` cannot do.

The output is not a recommendation to switch. It is a filled-in comparison table ([Section 7](#7-how-the-two-approaches-will-be-compared)) where every row points at a test or a measurement on one of the two branches, so that the RFC can say "we tried both" and show the numbers.

Plan first, code second. This document is the plan.

---

## 1. The two approaches in one paragraph each

**Painter (current, `text-plugin-mvp`).** The text is never changed. A plugin sets a painter on a `TextDelegate`; the render object calls it behind and in front of the glyphs and gives it the layout while it paints. A change costs a repaint of one text. The plugin sees geometry only during `paint`, so it can draw anything, but it cannot change what the text *is*: no semantics, no gestures, no widgets in stage 1.

**Inline span (this branch).** The text *is* changed. A plugin describes ranges and what they should look like; the framework splits the `InlineSpan` tree so that each range becomes its own `TextSpan` with the requested style, recognizer or cursor, and hands the new tree to the same `TextPainter` the text already uses. Nothing new is painted; the engine paints it. A change costs a new span tree and a new `ui.Paragraph` for that text, and in general a relayout. The plugin can only say what `TextSpan` and `WidgetSpan` can say.

The CSS world made this same choice once. Browsers find-in-page and spellcheck used to wrap matches in `<span>` elements and stopped, because mutating the DOM broke selection, scripts and layout; the CSS Custom Highlight API (`::highlight()`) was created so that a range could be styled *without* changing the tree. That history is a point for the painter approach, but it is an analogy, not evidence about Flutter. This experiment collects the Flutter evidence.

---

## 2. What the code already tells us, before writing anything

These are facts read from `master` today. They shape the design in [Section 3](#3-stage-1-design-decorations-as-spans) and they are the first things the experiment has to confirm or refute with tests.

| # | Fact | Where | Consequence for the inline-span approach |
| :-- | :-- | :-- | :-- |
| F1 | `TextStyle.compareTo` returns `paint` for `color`, `backgroundColor`, `decoration`, `decorationColor`, `decorationStyle`, `decorationThickness`, and `layout` for everything else, including `background` and `foreground` (`Paint`) and `shadows`. | `painting/text_style.dart` | A highlight with `backgroundColor` is a paint-only change. A highlight with a custom `Paint` is a layout change. |
| F2 | `TextSpan.compareTo` returns `layout` when the number of children differs. | `painting/text_span.dart` | Splitting one span into three is always a layout change, whatever the styles are. The first time a highlight appears on a text, that text relayouts. |
| F3 | Even for a paint-only change, `TextPainter` recreates the `ui.Paragraph` and lays it out again. The comment says so: "there's no API to only make those updates so the paragraph has to be recreated and re-laid out." | `painting/text_painter.dart`, `_rebuildParagraphForPaint` | There is no cheap path. Every visible change to a decoration costs one engine shaping pass for that text. The painter approach costs zero shaping passes. |
| F4 | `RenderParagraph.text=` with a `layout` comparison disposes the `_SelectableFragment`s and registers new ones. | `rendering/paragraph.dart` | A highlight appearing in a `SelectionArea` would clear the user's selection unless the comparison is made against the original span, not the decorated one. |
| F5 | `TextSpan.recognizer`, `onEnter`, `onExit`, `mouseCursor` and `semanticsLabel` are not inherited by children. Hit testing uses `getSpanForPosition`, which returns the leaf span. | `painting/text_span.dart`, `rendering/paragraph.dart` `hitTestChildren` | Splitting an app's `TextSpan(recognizer: tap)` into pieces silently drops the tap unless the splitter copies the recognizer to every piece. `semanticsLabel` cannot be copied (it would be spoken once per piece), so a span with one is atomic to the splitter. |
| F6 | A `PlaceholderSpan` is one `\uFFFC` code unit in the plain text and in every offset the paragraph reports. | `painting/placeholder_span.dart` | Every `WidgetSpan` a plugin inserts shifts the offsets of every plugin, of selection and of `EditableText` after it. Plugins must compute ranges against the original text, and the framework must apply all of them in one pass. |
| F7 | `RenderBox.hitTest` returns false outside `size`. Inline children are painted wherever they overflow, but not hit-testable there. | `rendering/box.dart`, `RenderInlineChildrenContainerDefaults` | A zero-size `WidgetSpan` used as an anchor for a floating widget can be seen but not tapped. |
| F8 | `TextPainter` only knows `TextSpan` and `PlaceholderSpan` (`InlineSpan.build(ParagraphBuilder)`). The engine paints glyphs, backgrounds and decorations; there is no per-span paint callback. | `painting/inline_span.dart` | "Complex painting through a span" means one of exactly three things ([Section 3.5](#35-complex-painting-with-spans-the-three-mechanisms)). There is no fourth. |
| F9 | `EditableText` already composes span transforms: `TextEditingController.buildTextSpan` (composing underline), then spell check. Both split spans and both preserve the plain text, because `RenderEditable` needs the rendered text to equal `controller.text` for the caret and selection to be right. | `widgets/editable_text.dart`, `widgets/spell_check.dart` | The inline-span approach has prior art inside the framework, and a hard rule: in an editable, the decorated text must be the same string as the original. That rules out `WidgetSpan` replacement in text fields. |
| F10 | Shaping in SkParagraph groups adjacent style blocks that match on font attributes, so a split that only changes colour or decoration should not break ligatures or kerning. | Engine, `OneLineShaper` | Expected to hold. Must be shown with a test (`fi`, `ffi`, `AV`) on CanvasKit and on the native engine, since "should" is not evidence. |

---

## 3. Stage 1 design: decorations as spans

### 3.1 Plugins hand over data, the framework builds the span

Two shapes were possible. A plugin could transform the span tree itself (`InlineSpan transform(InlineSpan)`), or it could return ranges and let the framework split. **Decided: ranges.**

> A plugin returns a list of `TextSpanDecoration`s computed against the **original** plain text. The framework merges all plugins' lists and builds the span tree once.

The transform shape is not built. What it would have cost, so that the choice is on record:

| | Ranges (chosen) | Transform (`InlineSpan transform(InlineSpan)`) |
| :-- | :-- | :-- |
| What a plugin can express | What `TextSpanDecoration` has fields for | Anything an `InlineSpan` tree can say, including restructuring and custom span subclasses |
| Offsets with two plugins | Every plugin computes against the original text. The framework applies all of them in one pass | The second plugin sees the first one's output. After the first inserts a `WidgetSpan`, every offset the second computes is shifted (F6). Each plugin has to map offsets itself |
| Order | Only decides who wins an overlap | Changes the result. `linkify` then `search` is a different tree from `search` then `linkify` |
| The app's `recognizer`, `mouseCursor`, `semanticsLabel` (F5) | The framework copies or protects them, in one place, with tests | Every plugin author has to know that these are not inherited and copy them on every split. One plugin that forgets breaks the app's links |
| Tree walks and `toPlainText` calls per text | One, shared | One per plugin |
| Identity short-circuit when nothing matches | The framework returns the original span | Each plugin has to return its input by identity, or the text relayouts (F2) |
| The plain-text rule in `EditableText` (F9) | Enforced: only a `replacement` changes the string, and it is rejected in an editable | Cannot be enforced, only asserted after the fact |
| Debugging "who changed my text" | The decorations are data and can be listed per plugin | Only the final tree is visible |
| Later change of the internals (for example a cheaper paint-only path, or Option B) | Free, plugins never see the tree | Every plugin is coupled to the tree shape |
| Prototype effort | The merge is about 200 lines and its tests | Near zero in the framework |

The one real loss is expressiveness. If a use case in [Section 6.1](#61-fidelity-port-the-demo-plugins) cannot be written with ranges, it is recorded there with the field that would have been needed.

```dart
/// What a plugin wants done to one range of a text.
@immutable
class TextSpanDecoration {
  const TextSpanDecoration({
    required this.range,
    this.style,              // merged onto the span's style; stage 1
    this.recognizer,         // stage 2
    this.mouseCursor,        // stage 2
    this.onEnter, this.onExit,
    this.semanticsLabel,     // stage 2
    this.replacement,        // stage 3: a WidgetSpan that replaces the range
  });
  final TextRange range;
  final TextStyle? style;
  // ...
}

abstract class TextPlugin {
  const TextPlugin();

  // Lifecycle. Same three callbacks as the painter prototype, but they now run
  // at build time, before buildDecorations for that text (Section 3.7).
  void didAddText(TextDelegate delegate) {}
  void didUpdateText(TextDelegate delegate) {}
  void didRemoveText(TextDelegate delegate) {}

  /// Called whenever the framework (re)builds the span of a text in scope.
  /// Must be pure: same inputs, same output. No layout is available.
  List<TextSpanDecoration> buildDecorations(TextDelegate delegate) => const [];

  bool get needsOffscreenContent => false;
  int get paintOrder => 0;   // becomes the z-order of overlapping decorations
}
```

`buildDecorations` gets the delegate, and reads the plain text from `delegate.text` (`toPlainText(includeSemanticsLabels: false)`, same contract as today). The delegate always exists by then, because `didAddText` has already run for it ([Section 3.7](#37-the-lifecycle-moves-to-build-time)). The `TextDelegate` keeps `text`, `textSpan`, `ensureVisible`, `compareTo`, `sortInDocumentOrder` and the listeners. It loses `backgroundPainter`, `foregroundPainter`, `markNeedsPaint`, and `TextLayout` goes away entirely.

### 3.2 Where the span is built: widget layer or render layer

This is the main design decision and it is where the two stages after this one are decided too.

**Option A, widget layer.** `Text.build` and `EditableTextState.build` (after `buildTextSpan` and spell check) ask `TextPluginScope` for the decorated span. A plugin state change notifies the scope, the scope rebuilds, every `Text` under it rebuilds, each compares its new span against the old one (F2) and relayouts if it changed.

A correction to the first draft of this plan, which said `RichText.build`: `RichText` is a `MultiChildRenderObjectWidget`. It has no `build`, and it extracts its `WidgetSpan` children in its constructor, before any `BuildContext` exists. So in Option A the decoration happens one level up, in `Text` and `EditableText`. A `RichText` that an app creates directly is **not** decorated in Option A unless `RichText` gets its own element class. That is tried in M2 only if time allows, and otherwise recorded as a coverage gap of Option A that the painter approach and Option B do not have.

**Option B, render layer.** `RenderParagraph` and `RenderEditable` keep the original span, and `TextDelegateHostMixin` builds the decorated span in `performLayout` before `_layoutTextWithConstraints`. A plugin state change calls `delegate.markNeedsDecoration()` on the texts it cares about, which marks only those render objects as needing layout.

| | A: widget layer | B: render layer |
| :-- | :-- | :-- |
| Can insert a `WidgetSpan` (stage 3) | Yes, children are extracted in `build` | No. A render object cannot create elements |
| Invalidation granularity | Every text in scope rebuilds on any plugin change | Only the texts the plugin touches |
| Selection survives a decoration change (F4) | Only if `RenderParagraph.text=` is taught to compare the undecorated spans | Natural: the original span never changes |
| Covers a `RichText` created directly | No (see the correction above) | Yes |
| Who owns the `TextDelegate` | A `State` in the widget layer, so that `didAddText` can run before the first `buildDecorations` ([Section 3.7](#37-the-lifecycle-moves-to-build-time)) | The render object, as today |
| A decoration that depends on state set in `didAddText` lands in the same frame | Yes, with the lifecycle at build time | Yes, with the lifecycle at build time |
| `EditableText` | Slots in after spell check, like the composing underline | `RenderEditable` would re-split what `_Editable` already split |
| Code touched | `text.dart`, `editable_text.dart`, `text_plugin.dart` (widgets) | `paragraph.dart`, `editable.dart`, `text_plugin.dart` (rendering) |

**Decided: build both from the start and compare them.** They share everything except where the merge is called from: the same `TextPlugin`, the same `TextSpanDecoration`, the same merge function, the same plugins and the same tests. An experiment-only switch on the scope picks the layer:

```dart
enum TextDecorationLayer { widget, render }   // experiment only, not a proposed API

TextPluginScope(plugin: search, decorationLayer: TextDecorationLayer.render, child: ...)
```

Every hazard test in [Section 6.2](#62-correctness-hazards-one-test-each) and every benchmark case in [Section 6.3](#63-performance) runs once per layer, so the report has an A column and a B column. Two things are known to differ before any code is written, and the tests are there to confirm them:

- F4 (selection survives a decoration change). In B the original span never changes, so nothing has to be fixed. In A, `RenderParagraph` and `RenderEditable` get a second property, the undecorated span, and `text=` decides between `paint` and `layout` handling of the selection fragments by comparing the undecorated spans.
- Stage 3. A `replacement` (`WidgetSpan`) only works in A. In B it is rejected with an assertion. So the `WidgetSpan` parts of [Section 5](#5-stage-3-redesign-widgets-through-widgetspan) run on A only.

A hybrid is a possible result and the report should be ready to say so: B for style decorations (cheap invalidation, covers `RichText`), A only for texts that have a `replacement`.

### 3.3 The merge: from ranges to a span tree

Input: the original `InlineSpan` tree and N lists of `TextSpanDecoration`s, one per plugin in `paintOrder`. Output: a new tree with the same plain text (unless a stage 3 replacement says otherwise).

1. Flatten the original tree into leaf runs `(start, end, style chain, leaf span)`. A `PlaceholderSpan` is a run of length 1 that is never split. A `TextSpan` with a `semanticsLabel` is a run that is never split (F5); a decoration that partially overlaps it is applied to the whole run, and a debug warning says so.
2. Collect every range boundary from every decoration. Cut the runs at those boundaries. This is the classic interval-splitting pass; `buildTextSpanWithSpellCheckSuggestions` does a one-list version of it today.
3. For each piece, merge the styles of the decorations covering it, lowest `paintOrder` first, so that the highest wins on conflicts. For `recognizer`, `mouseCursor`, `onEnter`, `onExit`: the highest `paintOrder` wins; if none, the piece keeps what its leaf had (F5).
4. Rebuild the tree. The simplest correct output is flat: one root with the original root style and one child per piece. The experiment starts flat. Keeping the original nesting is an optimisation to try only if the flat tree shows a measurable cost or a semantics difference.
5. If no decoration touched a text, return the original span **by identity**, so `compareTo` short-circuits and nothing relayouts.

Cost per text per build: O(runs + boundaries) plus the `toPlainText` string. The string is the known expensive part (the painter prototype avoids building it when the span is unchanged); cache it on the span instance.

### 3.4 Invalidation: how a plugin changes what is on screen

**Option A.** A plugin that is a `Listenable` notifies. `TextPluginScope` already listens (for `needsOffscreenContent`); it now also bumps a `decorationVersion` in `_InheritedTextPluginScope`, whose `updateShouldNotify` returns true, and every dependent `Text` and `EditableText` rebuilds. For each text: `buildDecorations` for every plugin, the merge, the `compareTo`, and if anything changed, layout plus a new `ui.Paragraph` (F3).

**Option B.** The plugin calls `delegate.markNeedsDecoration()` on the texts whose decorations changed. Only those render objects are marked as needing layout, and `performLayout` runs `buildDecorations` and the merge for them. No widget rebuilds. A plugin that does not know which texts changed (a new search query) calls it on all the delegates it holds, which is still cheaper than A because nothing is built.

Two consequences the experiment has to measure, not guess:

- A search keystroke in Option A rebuilds every text in scope, matched or not. On the painter branch it repaints only the texts whose match list changed (3.8.1 of the design doc: the lifecycle cost follows the changed text, not the page). Option B should sit between the two: only changed texts, but a relayout for each instead of a repaint.
- A karaoke or caret-following plugin that changes a decoration at 10 to 60 Hz recreates a `ui.Paragraph` at that rate for each affected text.

Plugins must keep recognizer instances stable across builds, or a tap that began on the old recognizer never completes. The decoration object is cheap to rebuild; the recognizer is not.

### 3.5 "Complex painting" with spans: the three mechanisms

Because of F8, when the user says "for complex painting we use the inline span too", it has to mean one of these. The experiment tries each where it fits and records what it could not do.

| Mechanism | What it can draw | What it cannot | Cost class |
| :-- | :-- | :-- | :-- |
| **M1. `TextStyle` properties** (`backgroundColor`, `color`, `decoration` with `decorationStyle` solid/double/dotted/dashed/wavy, `decorationColor`, `decorationThickness`, `shadows`, `fontWeight`) | Flat highlight on the run box, underline in five styles, strike-through, colour change, bold | Rounded corners, padding, borders, a box taller than the run, anything shaped, anything animated without a rebuild | Paint-only comparison (F1), but still a paragraph rebuild (F3). `shadows` and weight are layout |
| **M2. `TextStyle.foreground` / `background` `Paint`** with a `shader` (gradient, `ImageShader`) or a `MaskFilter` | Gradient text, blurred text, an opaque cover (spoiler: `foreground` and `background` both opaque), a tiled image behind the run | Still rectangular per run; a shader is in paragraph coordinates, hard to align to a range | Layout comparison (F1) |
| **M3. `WidgetSpan` replacement**: the range's glyphs are removed and a widget that renders the same text (a `Container` with a decoration around a `Text`) takes their place | Anything a widget can draw: pill badges, borders, icons, animation | Line-wrapping inside the range, baseline fidelity, selection across the range, screen-reader continuity, and any use in `EditableText` (F9). Changes offsets for everyone (F6) | Layout, and the text is now a different string |

A fourth idea, a custom `InlineSpan` subclass with a paint hook, is an engine and framework change, not a use of the existing API, and is out of scope for this prototype. It will be noted in the report as "what it would take".

### 3.6 What is kept from the painter prototype and what is removed

Kept, unchanged: `TextPluginScope` (merging, `exclude`, `none`, dedup by type, `paintOrder`), `TextPluginSuspension` and the `Overlay` change, the obscured-text rule, `OffscreenRenderingPolicy` and `needsOffscreenContent`, `TextDelegate.ensureVisible`, `compareTo`, `sortInDocumentOrder`, and the three lifecycle callbacks by name.

Changed: **when** the lifecycle callbacks run ([Section 3.7](#37-the-lifecycle-moves-to-build-time)), and in Option A who owns the delegate.

Removed: `TextPluginPainter`, `TextLayout`, `TextDelegate.backgroundPainter` / `foregroundPainter` / `markNeedsPaint`, `paintTextPluginBackgrounds` / `paintTextPluginForegrounds`, the clipping around plugin paint in `RenderParagraph`. Also `RendererBinding.addPostLayoutCallback`, `flushPostLayoutCallbacks` and the layout assertion in `RenderObject`: the lifecycle was their only user. That is PR 1 of the 16 in the implementation plan, and its absence is a line in the comparison table. `handlesSelectionHighlight` and the painter version of `_SelectionHighlightTextPlugin` are removed too; a span version of the selection highlight is part of the experiment ([Section 6.1](#61-fidelity-port-the-demo-plugins)).

Added: `TextSpanDecoration`, `TextPlugin.buildDecorations`, the merge (`TextSpanDecorator`, a pure function with its own unit tests), the undecorated-span property on the two render objects (A), `TextDelegate.markNeedsDecoration` (B), `decorationVersion` and the experiment-only `decorationLayer` in the scope.

The unrelated semantics fixes (PR A and PR B in the implementation plan) ride along untouched.

### 3.7 The lifecycle moves to build time

**Decided: `didAddText` and `didUpdateText` run at build time on this branch**, not after layout. This section says why the painter prototype's timing does not work for spans, what "build time" means exactly, and what the move costs.

#### Why keeping them after layout makes a decoration one frame late

A frame runs in a fixed order:

```
build  →  layout  →  [post-layout callbacks]  →  paint
          ↑ the span is an input here            ↑ a painter is an input here
```

On the painter branch a plugin reacts to `didAddText` by setting a painter. A painter is an input to **paint**, and paint has not happened yet when the post-layout callbacks run. So the painter paints in the same frame. That is the whole reason the callbacks could sit after layout without a visible delay.

A decoration is a change to the span, and the span is an input to **layout**: `TextPainter` shapes it and the text gets its size from it. When a post-layout callback runs, layout for this frame is over. A plugin that wants to change a decoration from there has three choices, and each one loses a frame or is wrong:

1. Mark the text as needing layout. The layout pass does not run again in this frame, so the text is painted with its old paragraph and laid out in the next frame. The painter branch added an assertion that throws in exactly this case, because the node is painted while dirty.
2. Call `setState` or notify the scope. Build is also over. The rebuild happens in the next frame.
3. Run layout a second time in the same frame. That is what the frame pipeline is designed not to do, and no existing phase allows it.

So with post-layout callbacks, any decoration that depends on something a callback did (the plugin learned about a text, indexed it, decided it holds the active match) shows up one frame after the text does. The user sees the text appear without its highlight and then gain it: a flash on every newly scrolled-in list item. Only a decoration that is a pure function of the text alone would escape this, and a plugin with state (search query, active match, speech position) is not that.

#### What "build time" means

The rule is: **for each text, the callback runs before `buildDecorations` for that text, in the same frame, and synchronously.**

| | Option A (widget layer) | Option B (render layer) |
| :-- | :-- | :-- |
| Who owns the delegate | A `State` that `Text` and `EditableText` put around their render object widget when a plugin is in scope | The render object (`TextDelegateHostMixin`), as today |
| `didAddText` | In the first `build` of that `State`, right before `buildDecorations` | In `attach`, or in the `textPlugins` setter for a plugin that is added later. Both happen while the widget is being built |
| `didUpdateText` | In `build`, when the plain text differs from the last build | In the `text` setter, when the plain text differs |
| `buildDecorations` | In the same `build`, after the callback | In `performLayout`, which is later in the same frame |
| `didRemoveText` | In `dispose` of the `State` | In `detach`, as today |
| How the delegate reaches the render object for `ensureVisible` and `compareTo` | Through `context.findRenderObject()`, only when asked | Directly |

"Build time" is not one phase of the frame. A text inside a lazy list or a `LayoutBuilder` is built during the layout phase, so its callbacks run then. The rule above still holds for it.

#### What the move costs

These are the things the painter prototype got from the post-layout timing (Section 7.2 of the design doc). Each one is given up, and each has a test in [Section 6.2](#62-correctness-hazards-one-test-each).

| Given up | Why | What a plugin does instead |
| :-- | :-- | :-- |
| Document order is valid inside the callback | During build the tree is half built. A lazy list mounts items out of order, and a sibling that comes earlier in the document may not exist yet | Do not sort in a callback. Mark the order as dirty and sort when the order is needed (next/previous, "3 of 17"), or once after the frame. `sortInDocumentOrder` is valid from the end of layout on (H14) |
| A callback may notify listeners | The callback runs inside `build`. A synchronous `notifyListeners` that reaches a `setState` throws "setState() called during build" | It does not need to notify for decorations any more, because `buildDecorations` for this text runs right after. For anything else (a match counter in a search bar) it defers the notification to the end of the frame. The framework offers one helper for that, so each plugin does not write its own (H13) |
| The text has a layout when the callback runs | Layout has not happened | Nothing in the span API reads geometry in a callback. `ensureVisible` already waits for the end of the frame when called during one |
| One callback per frame per text | A text can be rebuilt several times before a frame | `didUpdateText` is only sent when the plain text changed, so repeated builds with the same text send nothing |
| Symmetry between A and B | The callbacks come from the widget layer in A and from the render layer in B | Nothing. Both are checked by the same tests |

One thing is gained beyond the same-frame decoration: the post-layout callback phase in the binding is no longer needed ([Section 3.6](#36-what-is-kept-from-the-painter-prototype-and-what-is-removed)).

One thing needs care in Option A: putting a `State` around a text only when a plugin is in scope means that adding the first plugin to a scope, or removing the last, re-creates the text below it. The stage 3 branch has the same defect (9.4 of the design doc). The alternative, a `State` around every `Text` in every app, is a cost for apps that use no plugin and is not acceptable for a framework change. M2 measures the first and notes the second.

---

## 4. Stage 2 redesign: gestures, hover, semantics through `TextSpan`

The painter design's stage 2 invents `TextAnnotation` and teaches `RenderParagraph` and `RenderEditable` to hit-test, cursor and build semantics for it. With spans, most of that machinery exists already, because `TextSpan` carries these properties and both render objects already honour them.

| Stage 2 need | Painter design (`TextAnnotation`) | Span design | Already works in `RenderParagraph` | In `RenderEditable` |
| :-- | :-- | :-- | :-- | :-- |
| Tap, long press, any recognizer | `onTap`, `onLongPress`, recognizer | `TextSpanDecoration.recognizer` → `TextSpan.recognizer` | Yes, via `hitTestChildren` and `TextSpan.handleEvent` | Yes, same code path (`getSpanForPosition`), to be verified while editing and selecting |
| Mouse cursor, hover | `cursor`, `onEnter`, `onHover`, `onExit` | `mouseCursor`, `onEnter`, `onExit` (there is no `onHover` on `TextSpan`) | Yes | Yes |
| Semantics: a link node, a spoken label | `linkUrl`, `semanticsLabel`, an action | A span with a recognizer already becomes its own semantics node; `semanticsLabel`, `semanticsIdentifier`, `spellOut`, `locale` | Yes, `_cachedCombinedSemanticsInfos` | A text field is one node; spans do not split it. Same limit as the painter design |
| Keyboard focus, Tab to a link, Enter | An internal focus plugin, a focus ring painter | **Nothing in `TextSpan`.** The only span-level way is a `WidgetSpan` with a `Focus` child, which is stage 3 and changes the text | No | No |
| Two plugins on one range | Arena, topmost wins | Only one `recognizer` per leaf. The merge picks the highest `paintOrder`; the other plugin gets nothing, not even an arena loss | n/a | n/a |
| A plugin over the app's own `TextSpan(recognizer:)` | Both in the arena | The merge must copy the app's recognizer to the pieces the plugin does not claim (F5), and decide who wins where it does | n/a | n/a |

Things stage 2 on spans gets for free and the painter branch had to build: hit testing, cursor regions, semantics node splitting. Things it cannot do at all: focus, hover callbacks with position, more than one listener per range, and anything that needs the arena to see two parties. The experiment ports `LinkifyPlugin` and the tappable half of `SpoilerMaskPlugin` from the annotations branch and records which rows above hold.

Risk to look at specifically: `RenderEditable` and `SelectableRegion` both run their own recognizers. A `TextSpan.recognizer` inside them joins the same arena as today's `TextSpan` links in a `SelectableText`, with the same known conflicts; the painter design avoided a plain click opening a link in editable text with a modifier-key convention. The span design has no place to put that rule except the plugin.

---

## 5. Stage 3 redesign: widgets through `WidgetSpan`

The question asked is "can we use `WidgetSpan`?". The honest framing is that `WidgetSpan` puts a widget **in the flow of the text** and stage 3 wants widgets **on top of the text** (behind, in front, or floating). Those are different things, and the experiment should show where they meet and where they do not.

Three ways to try it:

| | S1. Inline replacement | S2. Zero-size anchor | S3. Painter-branch host (`TextPositioned`), no `WidgetSpan` |
| :-- | :-- | :-- | :-- |
| What | The range's glyphs are replaced by a widget (M3 above) | A `WidgetSpan` of width 0 at the range start, whose child overflows and is positioned over the glyphs | The existing stage 3 branch design, unchanged |
| Text layout unchanged | No. The replaced run wraps as one block | Almost: a zero-width placeholder can still take a line-break opportunity and an ascent | Yes |
| Offsets unchanged (F6) | No, the range becomes one `\uFFFC` | No, +1 per anchor | Yes |
| Tappable where it is drawn (F7) | Yes, it is inside its box | No, the overflow is not hit-testable | Yes |
| Works in `EditableText` (F9) | No | No | Yes |
| Selection, screen reader | The widget is its own selectable and node; the text inside is not part of the paragraph's | The anchor is a node of its own, empty | Unaffected |
| State kept across span rebuilds | Needs a `key` per `WidgetSpan`; an insertion before it otherwise re-creates it | Same | Same as today's branch (9.4) |
| Widget on each line of a wrapped range | Not applicable, it is one block | Needs the layout, which build does not have | Yes, with `TextLayout` in `buildTextWidgets` |
| Floating over later siblings (menus) | No, clipped with the text | No | Yes, overlay layer |

Expected result, to be confirmed: `WidgetSpan` is right for exactly one stage 3 use case, **replace this text with a chip** (mentions, tokens, pills) in static text, and wrong for the rest (menus, blur covers, per-line markers, anything in a text field). If that is what the experiment shows, the stage 3 recommendation becomes "S1 for inline replacement in static text, S3 for everything else", which is the same `TextPositioned` design as today with one addition, not a replacement.

**Decided: a full experiment for stage 3.** All three are built on this branch, and the same use cases are attempted in each, so that every cell of the table above is a test result and not a prediction.

| Use case | From | S1 | S2 | S3 |
| :-- | :-- | :-- | :-- | :-- |
| Mention chip: `@name` becomes a tappable pill with an avatar | New | Try | Try | Try |
| Spell-check suggestion menu that opens on a misspelled word and floats over later content | `spellcheck_suggestions_plugin.dart` on `text-plugin-with-widget-rebased` | Try, expected to fail | Try | Port |
| Frosted-glass spoiler: a `BackdropFilter` over a range, revealed on tap, on wrapped text | `frosted_spoiler_plugin.dart` on the same branch | Try | Try | Port |
| The same three inside a `TextField` | | Expected to be rejected (F9) | Expected to be rejected | Try |
| The same three inside a `SelectionArea`, with a selection dragged across | | Try | Try | Try |

"Try, expected to fail" is deliberate. The report needs the failure and its reason (a test that shows the clip, the missing hit test, the shifted caret), not an empty cell.

What porting S3 to this branch needs:

- The host and positioning code from `text-plugin-with-widget-rebased` (`TextWidgetPlugin`, `TextPositioned`, `TextPluginWidgetHost`, about 1,450 lines in `widgets/text_plugin.dart`, and its 1,940-line test file). That branch is built on the older stage 1 API with geometry on the delegate.
- `TextPositioned` places a child on a range, so it needs the layout. This branch removes `TextLayout` from the plugin API. The host therefore reads geometry through a non-public path from the widgets layer to the render object, as the unpublished follow-up experiment on that branch did (note at the top of Section 9 of the design doc). No plugin sees the layout.
- With Option A, S3's host and the delegate-owning `State` of [Section 3.7](#37-the-lifecycle-moves-to-build-time) are the same widget. That is a simplification worth recording: on this branch a text in scope has one wrapper for both purposes, where the painter stage 3 adds a wrapper that stage 1 did not need.
- S3 is independent of how decorations are built, so it runs on both A and B. S1 and S2 need `replacement` and run on A only.

The stage 3 defects listed in 9.4 of the design doc (a notifying plugin rebuilds the widgets of every text; a lost second notification; the rebuild loop) are re-tested here rather than assumed. The build-time lifecycle and Option A's `decorationVersion` change how notifications flow, so some may be fixed and some may get worse.

One engine-level question will come out of this and should be written down, not solved: whether a placeholder that consumes no code unit and no advance ("a mark, not a box") is something SkParagraph could offer. Without it, every anchor shifts offsets (F6).

---

## 6. The experiments

Every experiment has a name so the comparison table can cite it.

### 6.1 Fidelity: port the demo plugins

Port each plugin from `examples/text_plugins` to the span API, keeping the painter version in the tree for side-by-side use. Record, per plugin, the mechanism used (M1, M2, M3), what looks different, and what could not be done.

| Plugin | Expected mechanism | What to watch |
| :-- | :-- | :-- |
| `SearchInPagePlugin` | M1: `backgroundColor` for matches, a second colour for the active match | Run-height box vs. today's `BoxHeightStyle` choice; active-match change relayouts two texts; match counting still from the lifecycle |
| `SpellcheckLinterPlugin` | M1: `decoration: underline`, `decorationStyle: wavy` | Underline thickness and offset are the font's, not the plugin's |
| `StockTickerPlugin` | M1 for the dotted underline; the badge needs M3 | The badge is the first thing M1 cannot do. Try M3 and record what breaks |
| `ReadAloudPlugin` | M1: colour change per word at speech rate | Paragraph rebuild per tick (F3), measured |
| `SeoExtractorPlugin` | None; lifecycle only | Should port with zero changes. Confirms the lifecycle split is clean |
| Selection highlight (`_SelectionHighlightTextPlugin`, 5.2 of the design doc) | M1 `backgroundColor` | **Included.** Run-height vs. line-height boxes; a span rebuild per pointer move while dragging; in Option A the selection must survive its own highlight (F4 applied to itself). Likely the clearest "do not" case. The result goes into 5.2 of the design doc next to the painter experiment |

### 6.2 Correctness hazards, one test each

Each becomes a `testWidgets` in `packages/flutter/test/widgets/text_plugin_span_test.dart` (new file; the painter test file is kept for the parts that are shared).

| Id | Hazard | Test |
| :-- | :-- | :-- |
| H1 | Ligature or kerning breaks at a split (F10) | Lay out `office` and `AV` with and without a split in the middle, compare `getBoxesForSelection` of the whole word and a golden, on the test engine and in `web_ui` |
| H2 | Selection cleared when a decoration appears (F4) | Select in a `SelectionArea`, type a query that matches, expect the selection intact |
| H3 | App's recognizer lost by a split (F5) | `TextSpan(recognizer: tap)` with a plugin highlight in the middle; tap left, middle, right |
| H4 | `semanticsLabel` duplicated or lost (F5) | A labelled span half-covered by a match; semantics tree has the label exactly once |
| H5 | Offsets drift after a `WidgetSpan` (F6) | Two plugins, one inserts a `WidgetSpan`; the other's highlight lands on the right characters; `EditableText` caret is right |
| H6 | Identity short-circuit | Plugin returns no decorations; `RenderParagraph` neither relayouts nor repaints (count with a test render object) |
| H7 | Decoration lands in the same frame as the text ([Section 3.7](#37-the-lifecycle-moves-to-build-time)) | A plugin keeps state that it sets in `didAddText`, and `buildDecorations` reads it. A text added in a lazy list has its highlight in the first frame it is painted. Also run once with the callbacks forced back to post-layout, to show the one-frame delay that the move removes |
| H8 | `maxLines` and ellipsis | A match inside the elided part, and one straddling the ellipsis |
| H9 | `EditableText`: composing underline, spell check and a plugin decoration on the same range | All three visible, plain text unchanged, caret positions unchanged |
| H10 | Obscured text, covered routes, `TextPluginScope.none` | The three existing tests pass unchanged on the span API |
| H11 | `WidgetSpan` state across rebuilds | A stateful chip keeps its state when a match is added before it |
| H12 | Semantics tree shape | The same paragraph with 0, 1 and 3 highlights produces the same semantics nodes (stage 1 must not change semantics) |
| H13 | A plugin notifies from a build-time callback | A `ChangeNotifier` plugin that updates a match counter in `didAddText` through the deferral helper does not throw, and the counter is right after the frame. Without the helper it throws, with a message that names the helper |
| H14 | Document order with build-time callbacks | Scroll a lazy list upward so that items mount out of order. Inside `didAddText` the order may be wrong (recorded, not asserted). After the frame, `sortInDocumentOrder` is right and "next match" goes to the right text |
| H15 | First plugin added to a scope, last one removed (Option A) | Count how many texts are re-created and whether their state (scroll offset of a field, selection) is lost |
| H16 | A `RichText` created directly | Decorated in B. In A: not decorated, or decorated if the element approach was built |

Every test runs once with `TextDecorationLayer.widget` and once with `.render`, except where a row says otherwise.

### 6.3 Performance

Extend `examples/text_plugins/lib/benchmark.dart` so the same harness produces three columns: painter (run on `text-plugin-mvp`), span A and span B (run on this branch with the switch). Same machine, same day, profile mode, numbers into the report next to 3.8.1 of the design doc.

| Case | What it measures | Why |
| :-- | :-- | :-- |
| P1 | Page of 1,000 and 10,000 paragraphs; 0, 1, 10, 100 change per frame; no scope / empty scope / no-op plugin / search plugin | The existing cases, so the two branches are directly comparable |
| P2 | Query change on a page where 10 % match | Painter: repaint of matched texts. Span: rebuild of all, relayout of matched. This is the Ctrl+F keystroke |
| P3 | Query change on a page where 0 % match | Isolates the fan-out cost of Option A (every text rebuilds, nothing changes) against Option B (nothing is marked) |
| P4 | `ReadAloudPlugin` at 10 Hz on one long paragraph | F3 cost in steady state |
| P5 | Typing in a `TextField` with a highlight plugin | The case the span approach should win or tie: the span is rebuilt per keystroke anyway |
| P6 | First search on a 10,000-paragraph page | Shaping pass count; worst case for spans |
| P7 | Dragging a selection across 50 paragraphs with the span selection highlight | The per-pointer-move cost of the selection port |
| P8 | Adding the first plugin to a scope with 1,000 texts | The re-creation cost of the Option A wrapper (H15) |

Report frame time (`drawFrame`), and separately build, layout and paint phase times where the harness can split them, and the number of `ui.Paragraph` constructions (count via a `TextPainter` test hook or `Timeline` events).

### 6.4 API ergonomics

Rewrite Section 10 of the design doc ("the same feature, written three ways") for the span API, and the `SearchInPagePlugin` in full. Count lines, count concepts a plugin author has to learn, and list what each author can get wrong (stable recognizers, pure `buildDecorations`, no layout in build). Not a number, but it goes in the table.

---

## 7. How the two approaches will be compared

The report fills this table. Each cell is a test id, a benchmark case or a plugin port from [Section 6](#6-the-experiments), never an adjective. The span approach has two columns because both options are built.

| Criterion | Painter (`text-plugin-mvp`) | Span, Option A (widget layer) | Span, Option B (render layer) | Evidence |
| :-- | :-- | :-- | :-- | :-- |
| New public concepts for a stage 1 plugin author | `TextPlugin`, `TextDelegate`, `TextPluginPainter`, `TextLayout` | `TextPlugin`, `TextDelegate`, `TextSpanDecoration` | Same as A, plus `markNeedsDecoration` | 6.4 |
| New framework machinery | Paint passes, post-layout callback phase, `TextLayout` validity | Merge, undecorated-span property, scope version, a `State` around texts in scope | Merge, decoration in `performLayout` | Lines of code per branch |
| Cost of a decoration change on one text | Repaint | Rebuild, relayout, re-shape | Relayout, re-shape | P2, P4 |
| Cost of a plugin change to the page | Changed texts only | All texts in scope | Changed texts only | P2, P3 |
| Cost for an app with a scope and no decoration | ? | ? | ? | P1 |
| What a highlight can look like | Anything | M1, M2, M3 | M1, M2 | 6.1 |
| Covers a `RichText` created directly | Yes | ? | Yes | H16 |
| Selection survives a decoration change | Yes | ? | ? | H2 |
| Decoration in the same frame as a new text | Yes | ? | ? | H7 |
| Document order available in a callback | Yes | No, after the frame | No, after the frame | H14 |
| Works in `EditableText` | Yes | M1, M2: ? M3: no | M1, M2: ? | H9 |
| Selection highlight as a plugin | Painter experiment, 5.2 of the design doc | ? | ? | 6.1, P7 |
| Glyph shaping unchanged by a decoration | Yes, text untouched | ? | ? | H1 |
| Semantics unchanged by stage 1 | Yes | ? | ? | H12 |
| Risk to the app's own spans | None, text untouched | ? | ? | H3, H4, H5 |
| Interaction (stage 2) without new hit-testing code | No | ? | ? | Section 4 |
| Keyboard focus on a range | Yes, on the annotations branch | ? | ? | Section 4 |
| Two plugins interacting on one range | Arena | One winner | One winner | Section 4 |
| Widgets on text (stage 3) | Host and `TextPositioned` | S1, S2, S3: one result per cell of the Section 5 table | S3 only | Section 5 |
| Adding the first plugin to a scope | Nothing is re-created | ? | Nothing is re-created | H15, P8 |
| Prior art in the framework | None | `buildTextSpan`, spell check | Same | F9 |

**Decision rule (agreed).** The report recommends keeping the painter for stage 1 if either of these holds for both span options:

- H2, H3 or H12 fails and there is no fix.
- P2 misses the budget: **a Ctrl+F keystroke on the 10,000-paragraph page must finish `drawFrame` within one frame at 60 Hz (16.6 ms)**, in profile mode on the benchmark machine. The painter number for the same case is reported next to it.

If one span option passes and the other does not, the report says which and why. If both pass, the report presents all three and the RFC thread decides. In every case the stage 2 and stage 3 sections of the design doc are rewritten with what [Sections 4](#4-stage-2-redesign-gestures-hover-semantics-through-textspan) and [5](#5-stage-3-redesign-widgets-through-widgetspan) found, because those findings do not depend on who wins stage 1. A hybrid is a legitimate outcome: painter for decoration, `TextSpan` properties for interaction, `WidgetSpan` for inline replacement.

---

## 8. Work plan

**Timebox: 10 hours of working time in total.** Each milestone has a budget. Each is one or a few commits on this branch, with the same commit-message style as `text-plugin-mvp`. "Done when" is checkable.

| M | Work | Budget | Done when |
| :-- | :-- | :-- | :-- |
| **M0** | This plan, reviewed | done | [Section 10](#10-decisions-resolved-2026-11-20) is resolved |
| **M1** | `TextSpanDecoration` and the merge (`TextSpanDecorator`) as a pure function, with unit tests for splitting, overlap, `paintOrder` precedence, recognizer copying, atomic labelled spans, placeholder runs, identity short-circuit | 1.0 h | The merge tests are green. H1, H3, H4, H6 pass at the `TextPainter` level |
| **M2** | The wiring, for both options behind `decorationLayer`. A: the delegate-owning `State` in `Text` and `EditableText`, `decorationVersion`, the undecorated-span property. B: decoration in `performLayout`, `markNeedsDecoration`. Both: `buildDecorations`, the lifecycle at build time with the deferral helper, removal of the painter pipeline and of the post-layout callback phase | 2.0 h | The stage-neutral tests of the painter test file pass on both layers (H10). H2, H7, H8, H9, H12 to H16 have a result per layer |
| **M3** | Ports: `SeoExtractorPlugin`, `SearchInPagePlugin`, `SpellcheckLinterPlugin`, `ReadAloudPlugin`, `StockTickerPlugin` (with M3 for the badge), and the selection highlight | 1.5 h | The demo app runs on both layers. The example tests pass. The 6.1 table is filled |
| **M4** | Benchmark P1 to P8: painter, A, B | 1.0 h | Three columns of numbers, with the harness commit hash and the machine |
| | **Checkpoint at 5.5 h.** Apply the decision rule to stage 1 and write the result down before going on | | A short entry in the report draft |
| **M5** | Stage 2 on spans: `LinkifyPlugin` and the tappable spoiler ported from `text-plugin-annotations-rebased`; cursor, semantics, a plugin over the app's own recognizer, inside `SelectionArea` and `TextField` | 1.25 h | Every row of the [Section 4](#4-stage-2-redesign-gestures-hover-semantics-through-textspan) table has a test, including a test that documents the focus row as not possible |
| **M6** | Stage 3, full: S1 and S2 on Option A, S3 ported from `text-plugin-with-widget-rebased`; the three use cases in each; H5, H11; the 9.4 defects re-tested | 2.25 h | Every cell of the two [Section 5](#5-stage-3-redesign-widgets-through-widgetspan) tables is pass or fail with a test name |
| **M7** | The report, `text_plugins_inline_span_report.md`: [Section 7](#7-how-the-two-approaches-will-be-compared) filled, the recommendation, and a proposed rewrite of Sections 8 and 9 of the design doc | 1.0 h | It can be cited in the RFC thread |
| | **Total** | **10.0 h** | |

Rules for staying inside the timebox:

- The clock is tracked per milestone in a log at the end of the report, so that the report can say what the time bought.
- A milestone that runs over its budget by more than a quarter is stopped. What is missing is written down as "not done, because", and the next milestone starts. A table cell that says "not reached in the timebox" is an acceptable result. A cell that is guessed is not.
- If time has to be cut, it is cut in this order: the element approach for a direct `RichText` in Option A (H16), P7 and P8, S2 for the menu and the spoiler, the port of the S3 test file beyond the tests the Section 5 tables need.
- Not cut under any circumstances: the A and B comparison in M2 to M4, the selection highlight port, at least one use case in each of S1, S2 and S3, and the report.

The tightest part is M6. The S3 port alone is about 1,450 lines of host code written against an older API. The budget assumes the host is moved over with its geometry access made internal, and that only the tests needed for the Section 5 tables are ported. If the port does not compile inside its first hour, S3 is measured on its own branch instead, with the difference in the stage 1 API stated, and the remaining time goes to S1 and S2.

---

## 9. What would stop the experiment early

Nothing stops the whole experiment, because stages 2 and 3 are worth studying whatever stage 1 shows. These findings change what the rest of the time is spent on:

- **H1 fails on either engine**: a split changes glyph shaping. Then no span-based highlight is safe in general text. The stage 1 result is final at that point. M3 is reduced to the ports needed for M4, and the time goes to M5 and M6.
- **The F4 fix for Option A needs changes to `_SelectableFragment` lifetimes** that do not fit in M2. Then A fails H2, that is recorded, and stage 1 continues on B only. Stage 3 still uses A for S1 and S2, in texts without selection.
- **P2 misses the budget on both options.** Then the checkpoint entry says that the painter stays for stage 1, and M5 and M6 continue as a study of stages 2 and 3 on top of it.

---

## 10. Decisions (resolved 2026-11-20)

| # | Question | Decision | Where it is in this plan |
| :-- | :-- | :-- | :-- |
| 1 | Option A first with B as a fallback, or both? | **Build both from the start and compare.** | [3.2](#32-where-the-span-is-built-widget-layer-or-render-layer), [7](#7-how-the-two-approaches-will-be-compared), M2 to M4 |
| 2 | Plugins return ranges, or transform the tree? | **Ranges, and the framework splits.** The cost of the transform shape is listed. | [3.1](#31-plugins-hand-over-data-the-framework-builds-the-span) |
| 3 | Keep the post-layout lifecycle, or move it to build time? | **Move it.** The plan explains why keeping it makes a decoration from a callback one frame late, and lists what the move costs. | [3.7](#37-the-lifecycle-moves-to-build-time), H7, H13, H14 |
| 4 | Port the selection highlight? | **Yes.** | [6.1](#61-fidelity-port-the-demo-plugins), P7 |
| 5 | Stage 3 scope | **Full experiment:** S1, S2 and S3 on this branch, the same use cases in each. | [5](#5-stage-3-redesign-widgets-through-widgetspan), M6 |
| 6 | Performance budget | **Agreed as proposed:** a Ctrl+F keystroke on the 10,000-paragraph page inside 16.6 ms. | [7](#7-how-the-two-approaches-will-be-compared) |
| 7 | Timebox | **10 hours.** | [8](#8-work-plan) |

Two things came up while folding these in that the reviewer should know about before M1 starts:

1. `RichText` has no `build` method, so Option A decorates in `Text` and `EditableText` and does not cover a `RichText` that an app creates directly ([3.2](#32-where-the-span-is-built-widget-layer-or-render-layer)). The first draft of this plan had that wrong.
2. Moving the lifecycle to build time in Option A means the delegate is owned by a `State` in the widget layer, not by the render object ([3.7](#37-the-lifecycle-moves-to-build-time)). Without that, `didAddText` would run at mount, after the first `buildDecorations`, and the move would not buy the same-frame decoration it is made for.
