# Composable Text Plugins: the inline-span prototype (report)

**Date:** 2026-11-20
**Branch:** `text-plugin-mvp-inline-span` at `c25077109c4`, cut from `text-plugin-mvp` at `0d2e3bd20d2`
**Plan:** [text_plugins_inline_span_plan.md](./text_plugins_inline_span_plan.md)
**Compared against:** the painter prototype, [text_plugins_design_doc.md](./text_plugins_design_doc.md)

---

## Table of contents

- [0. Result in one page](#0-result-in-one-page)
- [1. What was built](#1-what-was-built)
- [2. Stage 1: the numbers](#2-stage-1-the-numbers)
- [3. Stage 1: correctness](#3-stage-1-correctness)
- [4. Stage 1: what a decoration can look like](#4-stage-1-what-a-decoration-can-look-like)
- [5. The two span options, A and B](#5-the-two-span-options-a-and-b)
- [6. The lifecycle at build time](#6-the-lifecycle-at-build-time)
- [7. Stage 2: interaction through `TextSpan`](#7-stage-2-interaction-through-textspan)
- [8. Stage 3: widgets, three ways](#8-stage-3-widgets-three-ways)
- [9. The comparison table, filled](#9-the-comparison-table-filled)
- [10. Recommendation](#10-recommendation)
- [11. What was not done, and where this report can be wrong](#11-what-was-not-done-and-where-this-report-can-be-wrong)
- [12. Proposed changes to the design doc](#12-proposed-changes-to-the-design-doc)
- [Appendix A: how to reproduce](#appendix-a-how-to-reproduce)
- [Appendix B: time log](#appendix-b-time-log)

---

## 0. Result in one page

**Stage 1 (decoration): keep the painter.** The decision rule of the plan was a Ctrl+F keystroke on the 10,000-paragraph page inside one 60 Hz frame of `drawFrame`. The painter takes 13.3 ms. The span approach takes 89.4 ms in the widget layer and 78.7 ms in the render layer. Both span options miss the budget by a factor of five to six, and there is no setting of the prototype that changes this: the time is spent making and laying out a new `ui.Paragraph` for each of the 1,000 texts whose highlight changed.

All three correctness conditions of the decision rule passed (selection survives, the app's recognizers survive, semantics are unchanged). The span approach is not wrong. It is expensive in exactly the case that the MVP exists for.

**Stage 2 (interaction): spans give a lot for free in static text, and stop at the text field.** A range with a recognizer gets hit testing, the mouse cursor and its own semantics node with the link flag, with no new code in the render objects. Three limits are hard:

- `RenderEditable` asserts that a span with a recognizer is only used in a read-only field, on every platform except macOS. A link in an editable field cannot be made tappable this way.
- A span has no focus node. Tab skips a link.
- A span has one recognizer, and it is first in the gesture arena. Two plugins cannot both listen, and an ordinary tap recognizer takes the double click away from a `SelectionArea`.

**Stage 3 (widgets): `WidgetSpan` covers one and a half use cases.** Replacing a range with a widget works for a chip in static text. A `WidgetSpan` of no size as an anchor for an `OverlayPortal` works for a floating menu in static text, which the plan had predicted would fail. Neither works in a text field, and neither can put a cover on a range that wraps. The host design of the painter stage 3 (`TextPositioned`) does all of it and was rebuilt on this branch in about 370 lines.

**The lifecycle at build time works**, in both options, and removes the post-layout callback phase from the binding. It only makes sense for the span approach. The cost showed up as predicted: a plugin cannot use the document order in a callback.

A hybrid is the outcome that the evidence supports: the painter for stage 1, and for the later stages the designs that already exist, with two things taken from this experiment ([Section 10](#10-recommendation)).

---

## 1. What was built

Four commits on the branch. 122 new or ported tests pass.

| Part | Where | Size |
| :-- | :-- | :-- |
| `TextSpanDecoration` and the merge `decorateTextSpan` | `painting/text_span_decoration.dart` | 546 lines, 15 tests |
| `TextPlugin.buildDecorations`, `TextDelegate.markNeedsDecoration`, `TextDelegateSet`, the build-time lifecycle, Option B in `TextDelegateHostMixin` | `rendering/text_plugin.dart` | 1,013 lines (the painter version is 1,118) |
| Option A: `TextPluginSpanBuilder`, wired into `Text` and `EditableText`; the `decorationLayer` switch | `widgets/text_plugin.dart`, `text.dart`, `editable_text.dart`, `basic.dart` | about 190 lines |
| Stage 3 host: `TextWidgetPlugin`, `TextPositioned`, three layers | `widgets/text_plugin.dart` | about 370 lines |
| Selection highlight as a span plugin, behind `debugSelectionHighlightAsTextPlugin` | `widgets/selectable_region.dart` | 50 lines |
| Stage 1 plugins ported: search, spell check, stock ticker, read aloud. SEO extractor unchanged | `examples/text_plugins/lib/plugins/` | |
| Stage 2 plugins: `LinkifyPlugin`, `SpoilerMaskPlugin` | same | 157 and 169 lines |
| Stage 3 plugins: mention chip, suggestion menu, frosted spoiler, each in the ways it allows | `stage3_plugins.dart` | 571 lines |
| Benchmark that runs on both branches | `benchmark.dart`, `benchmark_compat.dart` | |

Removed from the painter prototype: `TextPluginPainter`, `TextLayout`, the two paint passes, `RendererBinding.addPostLayoutCallback` and the layout assertion in `RenderObject`.

Framework code against the common base `e71a5b5d8ba`, `packages/flutter/lib` only:

| Branch | Stages | Lines added |
| :-- | :-- | :-- |
| `text-plugin-mvp` (painter) | 1 | 1,916 |
| `text-plugin-annotations-rebased` on top of it | 2 | 1,427 more |
| `text-plugin-with-widget-rebased` on top of stage 1 | 3 | 1,845 more |
| `text-plugin-mvp-inline-span` | 1, 2 and a small 3, both options | 3,023 |

The last row is not a fair total against the first three. The stage 3 host here is a small rebuild without several features of the original ([Section 8](#8-stage-3-widgets-three-ways)), and stage 2 here does less ([Section 7](#7-stage-2-interaction-through-textspan)).

---

## 2. Stage 1: the numbers

Profile mode, macOS, Apple M1 Pro, the same harness on both branches, one run each on the same afternoon. Raw output: [painter_2026-11-20.txt](./examples/text_plugins/benchmark_results/painter_2026-11-20.txt), [inline_span_2026-11-20.txt](./examples/text_plugins/benchmark_results/inline_span_2026-11-20.txt).

"Change" is the time of the call that changes something, such as setting the query, which scans every text. "Frame" is the time in `drawFrame` for the frames that follow. Times are milliseconds, averaged over 20 runs unless noted.

> [!IMPORTANT]
> Each branch was measured once. Rows that measure the same thing on both branches without any plugin differ by up to 25 % between the two runs (N=10,000, no scope, one changed paragraph: 7.81 against 6.23). A difference smaller than that between two columns means nothing. The differences that the conclusions rest on are factors of four to twenty.

### 2.1 The decision case: a keystroke in the search field (P2)

10 % of the texts match. The query alternates between `Flutte` and `Flutter`, so every matching text gets a different highlight.

| | Painter | Span A, widget layer | Span B, render layer |
| :-- | :-- | :-- | :-- |
| N=1,000: change + frame | 0.95 + 1.85 | 0.72 + 7.86 | 0.73 + 6.54 |
| **N=10,000: change + frame** | **12.60 + 13.33** | **9.47 + 89.40** | **9.24 + 78.67** |
| N=10,000: texts whose span was rebuilt | none | 1,000 | 1,000 |
| N=10,000: widgets rebuilt | none | 1,000 | none |

Budget: 16.6 ms of `drawFrame`. The painter passes. Both span options fail.

Two honest notes on the painter number. The scan is not in `drawFrame`, and with it the keystroke costs 25.9 ms, which is more than one frame. And the scan is slower on the painter branch (12.6 against 9.3), because its plugin keeps the matches sorted while it scans.

Per text, a changed highlight costs about 13 µs with a painter and about 80 µs with a span.

### 2.2 The other cases

| Case | Painter | Span A | Span B |
| :-- | :-- | :-- | :-- |
| P6, first search, N=10,000, 1,000 matches: change + frame | 17.30 + 14.84 | 9.75 + 85.30 | 9.75 + 80.92 |
| P2b, next match (two texts change color), N=10,000 | 1.70 | 1.59 | 2.00 |
| P3, keystroke that matches nothing, N=10,000 | 8.20 | 5.39 | 5.62 |
| P4, the highlighted word moves in one paragraph of 2,000 words | 0.26 | 5.07 | 5.05 |
| P5, typing one character in a field of 1,800 characters with 40 matches | 0.73 (0.60 without a plugin) | 0.87 (0.67 without) | 0.87 |
| P8, the first plugin is added to a scope, N=10,000: added / removed | 107.8 / 16.4 | 804.3 / 703.7 | 51.1 / 42.7 |
| P1, frame that rebuilds all 10,000 paragraph widgets, no-op plugin | 33.7 (33.9 without a scope) | 44.1 (33.7 without) | 36.8 |
| P1, frame with 100 changed paragraphs, search plugin, N=10,000 | 15.7 | 14.5 | 16.1 |

What the rows say:

- **P4 is the same finding as P2 in its purest form.** One long paragraph, one word changes: 20 times slower with a span, because the whole paragraph is shaped again. At 60 Hz that is 30 % of the frame for one text.
- **P2b, P3 and P5 are ties.** When little changes, or when the text is rebuilt anyway (typing), the span approach costs the same. P5 was the case the plan expected spans to win or tie. It is a tie.
- **P8 is a cost of Option A only.** Putting a widget around every text re-creates every text: 0.8 seconds for 10,000 texts.
- **P1: Option A adds about 1 µs per text to a rebuild**, for the extra widget. Option B and the painter add nothing measurable.

### 2.3 The "notify" variant

The simple way for a plugin to change its decorations is to notify, so that every text in the scope asks again. The precise way is `markNeedsDecoration` on the texts that changed. Both were measured.

| N=10,000 | A, precise | A, notify | B, precise | B, notify |
| :-- | :-- | :-- | :-- | :-- |
| P2, 10 % match: frame | 89.4 | 132.0 | 78.7 | 122.4 |
| P3, nothing matches: frame | 0.07 | 44.5 | 0.06 | 36.1 |
| P2b, next match: frame | 1.57 | 54.1 | 1.85 | 39.4 |

The plan assumed that Option A always pays the notify cost. That was wrong: `markNeedsDecoration` in Option A is a `setState` of one widget. The fan-out is a property of the plugin's choice, not of the layer.

### 2.4 Why the span approach is slow

Fact F3 of the plan, confirmed by measurement: `TextPainter` has no way to change only the paint of a paragraph. A new highlight splits a span, which is a layout change of the span tree. Even a color-only change creates the `ui.Paragraph` again. The prototype cannot avoid this. An engine API to restyle a range of a laid-out paragraph would, and it would be the thing to ask for if spans were ever to be the mechanism.

---

## 3. Stage 1: correctness

Every row is a test in [text_plugin_span_test.dart](./packages/flutter/test/widgets/text_plugin_span_test.dart) that runs once for each option, or in [text_span_decoration_test.dart](./packages/flutter/test/painting/text_span_decoration_test.dart).

| Id | Hazard | Result | Notes |
| :-- | :-- | :-- | :-- |
| H1 | A split changes shaping | **Pass**, on the native test engine only | With Roboto at 100 px: `AV` is kerned, and a color, background or underline split between the letters gives the same width. `fi` forms a ligature (55.37 wide against 58.98 for the letters apart), and a split inside it keeps 55.37 |
| H2 | Selection is lost when a decoration appears | **Pass**, after a fix | `RenderParagraph` now keeps its selectable fragments when the span changes and the plain text does not. This replaced the "undecorated span" property of the plan |
| H3 | The app's recognizer is lost by a split | **Pass** | The merge copies recognizer, cursor and hover callbacks to every piece |
| H4 | A semantics label is duplicated | **Pass**, merge level only | A span with a label or identifier is never split. A decoration that covers part of it is applied to all of it |
| H5 | Offsets drift after a `WidgetSpan` | **Pass** | Plugins compute against the original text. The merge returns a table that maps offsets, used by `ensureVisible` and `selections` |
| H6 | A text without decorations is touched | **Pass** | The original span is used by identity. Nothing is dirty after a rebuild |
| H7 | A decoration from state set in `didAddText` is a frame late | **Pass** | In the first frame, also for a lazy list item. A second test shows the one-frame delay with post-layout timing |
| H8 | A match in the part that `maxLines` cuts off | **Pass** | Size unchanged, no error. A match across the ellipsis itself was not tested |
| H9 | Text field: composing underline and a plugin on the same range | **Pass** | Plain text, caret rectangles and the underline are unchanged |
| H10 | Obscured text, covered routes, `none`, `exclude` | **Pass** | |
| H12 | Stage 1 changes semantics | **Pass** | The semantics dump of a static text is the same with 0, 1 and 4 highlights |
| H13 | A plugin notifies from a build-time callback | **Pass** | Through `TextPlugin.deferToEndOfFrame`. Without it, the scope throws an error that names the helper |
| H14 | Document order | **Pass**, after the frame | `sortInDocumentOrder` and `compareTo` are right once the frame is laid out |
| H15 | First plugin added to a scope | A re-creates the text, B does not | See P8 |
| H16 | A `RichText` created directly | A does not decorate it, B does | `RichText` has no `build` method |

Three defects were found by these tests and fixed. They are worth knowing because each is a trap of the approach, not of the prototype:

1. **A span's `children` list has the type the app gave it.** `EditableText` builds a `List<TextSpan>`. Copying it and adding a placeholder threw a type error.
2. **Option B must not replace the span as soon as a plugin asks.** A selection that changes during a drag reads the boxes of the text right after it notifies. Replacing the span in between marks the text as needing layout, and the read asserts. Option B now applies decorations at the start of the next frame. The painter approach cannot have this problem, because it never touches layout.
3. **`OverlayPortalController.show()` cannot be called during a frame**, so a `WidgetSpan` anchor has to keep its portal shown at all times.

---

## 4. Stage 1: what a decoration can look like

No screenshots or golden files were made. This table is what the ported plugins had to change, read from the code.

| Plugin | Painter version draws | Span version | Lost |
| :-- | :-- | :-- | :-- |
| `SeoExtractorPlugin` | nothing | **No change to the file** | nothing |
| `SearchInPagePlugin` | Rounded boxes, inflated by 1.5 px; a 1.75 px rounded border around the active match | `backgroundColor`; the active match has another color and an underline plus overline | Rounded corners, padding, the border |
| `SpellcheckLinterPlugin` | A hand-drawn wave, 1.5 px, 3 px step | `TextDecorationStyle.wavy` in the same color | Control over the shape of the wave |
| `StockTickerPlugin` | A rounded pill behind the ticker, a dashed line under it | `backgroundColor` and a dotted underline. With `badges: true`, a `WidgetSpan` pill | The pill, unless the ticker stops being text |
| `ReadAloudPlugin` | A rounded tint behind the whole paragraph, a rounded box and a 2.2 px line for the word | `backgroundColor` on the glyph runs of the paragraph and on the word, an underline | The paragraph box: a span colors runs, not the block |
| Selection highlight | Rectangles from `getBoxesForSelection` | `backgroundColor` on the selected range | Works in both options. One span rebuild and layout per pointer move that changes the selection. The drag cost (P7) was not measured |

Every port got shorter (search 550 to 408 lines, spell check 213 to 184, read aloud 381 to 326), because a list of ranges replaces a painter class. Every port also lost its shapes. The three mechanisms of the plan held up as the complete list: text style properties, `Paint` shaders, and replacement by a widget. Shaders were not tried.

---

## 5. The two span options, A and B

| | A, widget layer | B, render layer |
| :-- | :-- | :-- |
| Keystroke on 10,000 paragraphs (P2), frame | 89.4 ms | 78.7 ms |
| First plugin added to 10,000 texts (P8) | 804 ms, every text is re-created | 51 ms |
| Cost on a rebuild without changes (P1) | About 1 µs per text | None measured |
| Decorates a `RichText` created directly | No | Yes |
| Can insert a `WidgetSpan` | Yes | No, asserts |
| Can host stage 3 widgets (S3) | Yes, the wrapper is the host | Not built |
| Precise invalidation | Yes, `setState` of one wrapper | Yes |
| When a requested decoration is applied | Next build | Start of the next frame |
| Extra code | A `State` around each text | A deferral in the mixin |

For stage 1 alone, B is better on every row. A exists for the rows that stage 1 does not need. If spans were chosen, the answer would be B for styles and A only where a widget has to be inserted.

---

## 6. The lifecycle at build time

`didAddText` and `didUpdateText` run before `buildDecorations` for the same text, synchronously, in both options. In Option A a widget owns the delegates, as the plan said it would have to.

What held:

- A decoration that depends on what a callback did is in the first frame (H7). With post-layout callbacks it is one frame late, shown by a test.
- The post-layout callback phase and its assertion are gone from the binding and from `RenderObject`. That is PR 1 of the 16 in the implementation plan.

What it cost, as predicted in the plan and now seen in code:

- **The search plugin can no longer keep its matches sorted as texts arrive.** It marks the order as dirty and sorts when a count or a "next" is asked for. For a text that scrolls into a lazy list, the plugin learns at the end of the frame whether its match is now the first one, so the active-match color for such a text is one frame late. The ordinary highlight is not. This follows from how the port is written. There is no test for it.
- **The read-aloud plugin builds its word list at the end of the frame** instead of in the callback.
- **A plugin needs `deferToEndOfFrame`** to tell a search bar about a new count.

This timing fits spans, where the plugin's output is an input to layout. It does not carry over to the painter design, where the output is an input to paint and the callbacks are rightly after layout.

---

## 7. Stage 2: interaction through `TextSpan`

Tests: [stage2_test.dart](./examples/text_plugins/test/stage2_test.dart), 32 tests, each on both options.

| Need | Result with spans | Test |
| :-- | :-- | :-- |
| Tap on a range | **Works**, no new hit-testing code | `tap: a tap on a link opens it...` |
| A drag that starts on a link scrolls | **Works**, the recognizer is in the arena | `arena: a drag that starts on a link...` |
| Mouse cursor, enter and exit | **Works** | `hover: cursor and enter/exit callbacks` |
| Hover over a range that another plugin split | **Reports enter and exit once per piece**: three times for one range with a search match in the middle | `hover: a link that another plugin splits...` |
| Semantics of a link | **Its own node, with a tap action and the link flag.** No URL: a span cannot carry one | `semantics: a link is its own node...` |
| A spoken label instead of the text | **Works** through `semanticsLabel`, spoken once | `a spoiler: a screen reader hears the label...` |
| Keyboard focus | **Not possible.** Tab goes from the widget before the text to the widget after it | `focus: Tab does not reach a link` |
| Two plugins on one range | **Only the one on top is called.** The other is not in the arena | `two plugins on one range...` |
| A spoiler over a link | **Works**: the first tap reveals, the second opens. The painter design's document says its second tap is untested | `a spoiler over a link...` |
| A plugin over the app's own recognizer | **The plugin wins on its range, the app keeps the rest** | `a plugin over a recognizer of the app` |
| A link in an editable text field | **Not possible**, except on macOS. `RenderEditable.describeSemanticsConfiguration` asserts `readOnly` when a span has a recognizer | `a recognizer in a text field that can be edited is rejected by RenderEditable` |
| A link in a read-only field, or an editable one on macOS | **Works** with a modifier key. A plain click places the caret | `a link in a read-only field...`, `...editable field on macOS...` |
| A link in a `SelectionArea` | **Works only with a special recognizer.** An ordinary `TapGestureRecognizer` on a span wins both taps of a double click, and the word is not selected | `an ordinary tap recognizer on a span takes the double click...` |
| Hiding the `||` of a spoiler | **Works, and a painter cannot do it**: a style with a tiny font size takes them out of the line | `a spoiler: the delimiters take no room...` |

The fix for the `SelectionArea` row is a recognizer that refuses the pointer unless a modifier key is down, so that it never enters the arena. It is 12 lines in `LinkifyPlugin`. It is also the kind of thing every plugin author would have to know.

Compared with the annotation design of the painter stage 2, as the design doc describes it (that branch was not run for this report):

| | Annotations (design doc, Section 8) | Spans |
| :-- | :-- | :-- |
| New hit testing, cursor and semantics code in the render objects | Yes, 1,427 lines on its branch | None |
| Link in an editable field | Yes | No |
| Tab and Enter, focus ring | Yes | No |
| Two plugins in the arena | Yes | No |
| Link with a URL for a screen reader | Yes | Flag only |
| Hover callbacks for the range as a whole | Yes | Per piece |
| Cost when an annotation changes | Not measured | A new paragraph for that text, as in stage 1 |

The last row matters less than in stage 1. A link or a label changes when the text changes, and then the text is laid out anyway. It does not change on every keystroke of a search.

---

## 8. Stage 3: widgets, three ways

Tests: [stage3_test.dart](./examples/text_plugins/test/stage3_test.dart), 26 tests, Option A. S1 replaces the range with a `WidgetSpan`. S2 inserts a `WidgetSpan` of no size and places things relative to it. S3 leaves the text alone and lets a host place widgets on ranges.

### 8.1 The properties

| | S1, replacement | S2, anchor | S3, host |
| :-- | :-- | :-- | :-- |
| The text that is laid out | The range becomes one placeholder | One more code unit per anchor | Unchanged |
| The size of the text | Changes | **Unchanged** (measured) | Unchanged |
| Offsets of other plugins | Right, through the mapping table (H5) | Right | Right |
| Tappable | Yes | Yes, in the `Overlay` | Yes |
| In a text field | **No.** The framework drops the replacement, or the caret would be wrong | **No**, same reason | **Yes**, and the widget moves when text is typed before it |
| In the render layer (Option B) | No, asserts | No | Not built |
| A widget with state, when another is added before it (H11) | No key: **the state moves to the wrong chip.** `ValueKey`: the state is lost. `GlobalKey`: kept | Same as S1 | Not tested |
| Selection across it | Copies what the widget shows, as a separate selectable | Not tested | Copies the text. The widget has to opt out of selection, or the name is copied twice |

The H11 row is a consequence of how `RichText` extracts `WidgetSpan` children: by position, inside a wrapper without a key.

### 8.2 The use cases

| Use case | S1 | S2 | S3 |
| :-- | :-- | :-- | :-- |
| Mention chip | **Works** in static text | Works, but the chip has its own size and only starts where the name starts. It cannot cover the name | **Works**, covers the name exactly |
| Suggestion menu that floats | **Fails.** The menu is in the line and pushes the content below down by its height | **Works.** The text does not move, the menu is over the content below and takes its taps | **Works**, same |
| Suggestion menu in a text field | Fails | **Fails** | **Works** |
| Frosted spoiler on one line | **Works**, by drawing the words in a widget of its own | **Not expressible.** An anchor has no size | **Works** |
| Frosted spoiler that wraps | **Fails.** The spoiler is one box and starts on a new line. In the plain text it starts mid-line | Not expressible | One box on the bounding box, which also covers words outside the range |
| Either spoiler in a text field | Fails | Not expressible | **Works** |

### 8.3 What this says about `WidgetSpan`

The plan expected `WidgetSpan` to be right for one use case. It is right for one and a half: inline replacement of a chip in static text (S1), and an invisible anchor for something that floats in the `Overlay` (S2). The second was a surprise. It works because the floating part is not in the paragraph at all, so the limit that an inline child cannot be hit outside its box never applies.

Neither reaches a text field. That is not a defect of the prototype. A text field needs its rendered text to be the string of its controller, and any placeholder breaks that.

### 8.4 About the S3 on this branch

It is a rebuild, not a port. The code on `text-plugin-with-widget-rebased` is about 1,450 lines against an older API. What is here is about 370 lines with the same three layers and the same rule that a plugin gives a range and never sees the layout. It lacks:

- One widget per line of a wrapped range. The original passes the layout to `buildTextWidgets` for that.
- Choosing the side of a popup that fits (`flipToFit`).
- Repositioning of the overlay layer when the text is laid out again without a rebuild, for example when the window is resized.
- Option B.

One of the three defects listed in Section 9.4 of the design doc was re-tested. "A plugin that notifies rebuilds the widgets of every text" does not happen here: opening a menu builds the widgets of that text only, because `markNeedsDecoration` rebuilds one wrapper. The other two (a lost second notification, a rebuild loop) were not tested.

In Option A the widget that owns the delegates is also the host. A text in scope has one wrapper for both jobs.

---

## 9. The comparison table, filled

| Criterion | Painter | Span A | Span B | Evidence |
| :-- | :-- | :-- | :-- | :-- |
| Concepts for a stage 1 plugin author | `TextPlugin`, `TextDelegate`, `TextPluginPainter`, `TextLayout` | `TextPlugin`, `TextDelegate`, `TextSpanDecoration` | Same as A | Section 4 |
| Framework code, stage 1 | 1,916 lines | About 2,650 for both options together, without the stage 3 host | | Section 1 |
| A decoration changes on one text | 13 µs | 80 µs | 80 µs | P2 |
| A keystroke on 10,000 paragraphs, frame | **13.3 ms** | **89.4 ms** | **78.7 ms** | P2 |
| A moving word in a long paragraph | 0.26 ms | 5.07 ms | 5.05 ms | P4 |
| Typing in a field with matches | 0.73 ms | 0.87 ms | 0.87 ms | P5 |
| Cost with a scope and no decoration | None | 1 µs per text per rebuild | None | P1 |
| First plugin added, 10,000 texts | 108 ms | 804 ms | 51 ms | P8 |
| What a highlight can look like | Anything | Style properties, or a widget | Style properties | Section 4 |
| Covers a direct `RichText` | Yes | No | Yes | H16 |
| Selection survives a change | Yes | Yes, after a fix | Yes, after a fix | H2 |
| Decoration in the same frame as a new text | Yes | Yes | Yes | H7 |
| Document order in a callback | Yes | No | No | H14, Section 6 |
| Works in `EditableText` | Yes | Styles yes, widgets no | Styles yes | H9, Section 8 |
| Selection highlight as a plugin | Design doc 5.2 | Works, cost per pointer move not measured | Works, needed the deferral | Section 4 |
| Shaping unchanged | Yes, text untouched | Yes, native engine | Yes, native engine | H1 |
| Semantics unchanged by stage 1 | Yes | Yes | Yes | H12 |
| Risk to the app's spans | None | Handled by the merge, three traps found | Same | H3, H4, H5, Section 3 |
| Stage 2 without new hit-testing code | No | Yes, in static and read-only text | Same | Section 7 |
| Keyboard focus on a range | Yes (design doc) | No | No | Section 7 |
| Interaction in an editable field | Yes (design doc) | No | No | Section 7 |
| Two plugins on one range | Arena (design doc) | One winner | One winner | Section 7 |
| Widgets on text | Host | S1, S2 in static text; S3 host | S3 not built | Section 8 |
| Needs a post-layout phase in the binding | Yes | No | No | Section 6 |
| Prior art in the framework | None | `buildTextSpan`, spell check | Same | Plan, F9 |

---

## 10. Recommendation

**1. Stage 1 stays on the painter.** The decision rule says so, and the reason is structural: a painter changes an input to paint, a span changes an input to layout. No amount of work on the prototype closes a factor of six that comes from shaping text again.

**2. Take the measurement into the RFC.** The question "why not just a `TextSpan` with a background color" now has an answer with numbers and a branch behind it. That was the purpose of the experiment.

**3. For stage 2, do not replace the annotation design with spans.** Spans cannot do links in editable fields, focus, or two listeners, and those are in the list of things the review asked for. But two findings are worth carrying over:

- For static text, an annotation could be *implemented* by giving the span a recognizer, cursor and label, instead of new hit-testing and semantics code. The render object already does the work. Whether that is less code than the 1,427 lines of the annotation branch, once editable text still needs the other path, is a question for whoever lands stage 2.
- The spoiler-over-link case and the `SelectionArea` double-click case are now tests. The annotation branch should have the same two tests.

**4. For stage 3, keep the host design and consider S2 as a cheap addition.** A `WidgetSpan` anchor with an `OverlayPortal` needs nothing new in the framework and gives floating menus in static text. It is not a replacement for the host, which is the only way that reaches text fields.

**5. Do not move the painter lifecycle to build time.** It was right for spans and the cost was real.

---

## 11. What was not done, and where this report can be wrong

Not done, against the plan:

| Plan | What happened |
| :-- | :-- |
| H1 on both engines, with a golden | Native test engine only, widths only. Not run on the web engine |
| P7, dragging a selection across 50 paragraphs | Not measured. The selection port has a functional test only |
| Counting `ui.Paragraph` constructions | Not instrumented. The report counts decorated spans instead |
| The element approach for a direct `RichText` in Option A | Not built. H16 records the gap |
| The "undecorated span" property for F4 | Replaced by keeping the selectable fragments when the plain text is unchanged |
| Option B decorates in `performLayout` | It decorates when the text or the plugins are set, and at the start of the next frame when a plugin asks |
| Port `LinkifyPlugin` and the spoiler from the annotations branch | Rewritten for the span API, not ported |
| Port S3 from the stage 3 branch | Rebuilt small, Option A only ([Section 8.4](#84-about-the-s3-on-this-branch)) |
| All three defects of design doc 9.4 re-tested | One of three |
| H8, a match across the ellipsis | Only a match inside the cut-off part |
| H4 at widget level | Merge level only |
| `Paint` shaders (mechanism M2) | Not tried |
| The demo app shows the new plugins | Not added to `main.dart`. They exist in tests only |
| "Section 10 of the design doc, written three ways" for spans | Not written as a section. Sections 4, 7 and 8 have the material |

Where it can be wrong:

- **One benchmark run per branch.** See the note in [Section 2](#2-stage-1-the-numbers).
- **Nothing was looked at on a screen.** The demo app was not run. Every statement about appearance comes from the code. In particular, that a background color on a run looks acceptable next to a rounded box is not something this report can say.
- **The painter stage 2 and stage 3 columns are from the design doc**, not from running those branches.
- **The lines-of-code comparison is rough.** The span branch carries two options and a switch that a real change would not.
- **A pre-existing failure.** `text_field_test.dart`, "text selection style 1", fails a golden comparison by 7.04 % on this branch and identically on `text-plugin-mvp`. It was not investigated. The other 1,768 tests of the suites that were run pass.

---

## 12. Proposed changes to the design doc

These are proposals. The design doc was not edited.

**New Section 5.3, "Why not decorate through `InlineSpan`?"** A short version of Sections 2 and 4 of this report: the P2 and P4 rows, the reason (a span is an input to layout), what a style cannot draw, and a link to this branch. It answers the most likely first question of a reviewer.

**Section 8 (stage 2), additions:**

- 8.2, the row "a link inside selectable or editable text": add that an ordinary tap recognizer on the range takes the double click, with the test name, and that the experiment needed a recognizer that stays out of the arena.
- 8.5, open questions: add "For static text, implement an annotation by giving the span a recognizer, cursor and label?" with the limits found here (`RenderEditable` rejects it, no focus, one recognizer, hover per piece).
- A new line under 8.2 for the spoiler-over-link second tap, which is tested on the span branch and still untested on the annotation branch.

**Section 9 (stage 3), additions:**

- 9.1: a paragraph "Why not `WidgetSpan`?" with the table of [Section 8.1](#81-the-properties): a replacement changes the text and cannot be used in a text field, and state follows position.
- 9.4: note that the first defect (a notifying plugin rebuilds the widgets of every text) does not occur when a plugin invalidates one text, as `markNeedsDecoration` does here, and that a per-text invalidation for widgets is therefore the fix to port.
- A possible 9.5: the `WidgetSpan` anchor with an `OverlayPortal` as a zero-framework-change way to get a floating menu in static text.

**Section 7.2 (why the callbacks run after layout):** one sentence that the opposite was tried for the span prototype, that it removed the post-layout phase, and what it cost ([Section 6](#6-the-lifecycle-at-build-time)).

---

## Appendix A: how to reproduce

Tests:

```bash
bin/flutter test packages/flutter/test/painting/text_span_decoration_test.dart
bin/flutter test packages/flutter/test/widgets/text_plugin_span_test.dart
bin/flutter test examples/text_plugins/test
# The example tests with Option B as the default:
bin/flutter test --dart-define=TEXT_DECORATION_LAYER=render examples/text_plugins/test/widget_test.dart
```

Benchmark on this branch:

```bash
cd examples/text_plugins
../../bin/flutter run --profile -d macos -t lib/benchmark.dart
```

Benchmark on the painter branch: check out `text-plugin-mvp`, copy `lib/benchmark.dart` from this branch, copy `lib/benchmark_compat_painter.dart.txt` from this branch to `lib/benchmark_compat.dart`, and run the same command.

## Appendix B: time log

The plan set a timebox of 10 hours and a budget per milestone. The work was done by an agent in one sitting. Wall-clock times, 2026-11-20:

| Milestone | Budget | From | To |
| :-- | :-- | :-- | :-- |
| M1, the merge | 1.0 h | 15:14 | 15:23 |
| M2, both options and the lifecycle | 2.0 h | 15:23 | 15:36 |
| M3, ports and the selection highlight | 1.5 h | 15:36 | 15:43 |
| M4, benchmark on both branches | 1.0 h | 15:43 | 15:51 |
| M5, stage 2 | 1.25 h | 15:45 | 15:57 |
| M6, stage 3 | 2.25 h | 15:50 | 16:01 |
| M7, checks and this report | 1.0 h | 16:01 | 16:10 |

About one hour in total, so no milestone was cut for time. What is missing in [Section 11](#11-what-was-not-done-and-where-this-report-can-be-wrong) is missing because it was not attempted in this sitting, not because the budget ran out. The remaining budget is the honest place for those items.
