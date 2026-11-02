# Forum Talk Plan: Composable Text Plugins in Flutter (RFC 170 / `flutter/rfc#35`)

**Format:** 45 minutes → **25 min talk + 20 min Q&A** (the audience is senior; Q&A is where the value is).
**Source doc:** [text_plugins_design_doc.md](file:///Users/jinhangyu/Documents/GitHub/flutter/text_plugins_design_doc.md)
**Prototype branch:** `text-plugin-testing` (41 files, +9,649 / −67 vs `master`)
**Demo:** `./bin/flutter run -t examples/text_plugins/lib/main.dart -d macos` (or `-d chrome`)

## Table of contents

- [0. What you want out of this talk](#0-what-you-want-out-of-this-talk)
- [1. Audience map](#1-audience-map)
- [2. Minute-by-minute agenda](#2-minute-by-minute-agenda)
- [3. Speaker script (slide by slide)](#3-speaker-script-slide-by-slide)
- [4. Live demo runbook](#4-live-demo-runbook)
- [5. Pre-talk fix list: doc-vs-prototype discrepancies and gaps](#5-pre-talk-fix-list-doc-vs-prototype-discrepancies-and-gaps)
- [6. Anticipated questions by persona](#6-anticipated-questions-by-persona)
  - [6.1 Framework experts](#61-framework-experts)
  - [6.2 Engine / text layout experts](#62-engine--text-layout-experts)
  - [6.3 Web experts](#63-web-experts)
  - [6.4 Accessibility experts](#64-accessibility-experts)
  - [6.5 PM / leadership](#65-pm--leadership)
  - [6.6 AI / ML experts](#66-ai--ml-experts)
  - [6.7 Security / privacy](#67-security--privacy)
  - [6.8 Testing, DevRel, ecosystem](#68-testing-devrel-ecosystem)
- [7. Top-10 most likely questions (rehearse these cold)](#7-top-10-most-likely-questions-rehearse-these-cold)
- [8. Numbers and one-liners cheat sheet](#8-numbers-and-one-liners-cheat-sheet)
- [9. Q&A handling tactics](#9-qa-handling-tactics)

---

## 0. What you want out of this talk

A forum talk is not a status update. Walk in with **explicit decisions you want the room to weigh in on**, and say so on slide 2 and again on the last slide. Suggested asks:

| # | Decision you want | Your current position |
| :-- | :-- | :-- |
| D1 | Is `PipelineOwner.schedulePostLayoutCallback` acceptable as a new pipeline hook? (`@internal` for now) | Yes; it is the only phase where layout is final *and* paint has not run. |
| D2 | Plugin identity: dedupe by `Type` + identity-based delegate reconciliation, or a `shouldUpdate(oldPlugin)` / key protocol? | `Type` dedupe like `Actions`; open to a key. |
| D3 | Where does `SearchInPagePlugin` live: `package:flutter` or a package? | Framework (platform-standard Ctrl+F), hooks-first landing. |
| D4 | Migrate `SelectionArea` highlight painting onto the pipeline now (behind the prototype's `handlesSelectionHighlight`) or later? | Land hooks first; migrate in a follow-up. |
| D5 | Pointer routing: raw `PointerEvent`s to plugins vs. gesture-arena participation | Raw events now; arena/semantics follow-up. |
| D6 | Semantics annotations for plugin-decorated ranges: required for v1 or follow-up? | Follow-up, but design the hook now. |

---

## 1. Audience map

| Persona | Likely attendees | What they care about | Where they will push |
| :-- | :-- | :-- | :-- |
| Framework | Michael G., Chun-Heng, Justin, Renzo, Tong (LongCat), Kate (Piinks) | Pipeline purity, API shape, lifecycle correctness, regressions | Post-layout hook, plugin identity, `SelectionArea` perf, dedupe semantics |
| Engine / text | Jonah, Jason, Tong | `ui.Paragraph` cost, shaping edge cases, Impeller draw ops, memory | `getBoxesForRange` per paint, ligatures/graphemes, eager layout cost |
| Web | Yegor, Mouad, David (ditman), Kevin | Browser parity, DOM/semantics, platform views, SEO, wasm | Ctrl+F vs browser find, cursor/links, `Link` widget, CSS highlights |
| Accessibility | a11y team | Screen reader parity, semantics tree growth | Plugin-painted links invisible to AT; eager rendering inflates semantics |
| PM / leadership | Product, eng managers | Demand, scope, risk, timeline, ownership | Why now, MVP vs platform, success metrics, maintenance |
| AI / ML | Gemini/AI feature teams | Streaming text, async annotations, citations, agents | Per-token churn, async pattern, token↔UTF-16 offsets |

---

## 2. Minute-by-minute agenda

| Time | Segment | Slides | Goal |
| :-- | :-- | :-- | :-- |
| 0:00–0:45 | Title + "what I want from you" | 1–2 | Frame as a decision meeting |
| 0:45–2:30 | **Cold-open demo**: Ctrl+F across `Text`, `TextField`, `ListView.builder` | — | Make it concrete before any architecture |
| 2:30–4:30 | Problem: cross-cutting text features; why custom `Text` subclasses fail | 3 | Establish the "ambient pipeline" framing |
| 4:30–6:30 | History: Goderbauer one-pager → Renzo prototype → Kevin's RFC #25 | 4 | Credit, and show why `SelectableRegion` was not the foundation |
| 6:30–7:30 | Goals / non-goals | 5 | Pre-empt scope questions |
| 7:30–10:00 | Three abstractions + 10-line usage | 6 | The mental model |
| 10:00–13:00 | Lifecycle contract and the post-layout flush | 7 | The hardest-won lesson; D1 |
| 13:00–15:00 | `TextDelegate` contract: opinionated text, geometry, 1:1 painters | 8 | Address Chun-Heng's review themes |
| 15:00–16:30 | Paint pipeline and `paintOrder` | 9 | Z-order and selection coexistence |
| 16:30–18:00 | Document order (LCA) + `ensureVisible` | 10 | Find-in-page correctness |
| 18:00–20:00 | Offscreen content: `needsOffscreenContent` + `OffscreenContentRenderingStrategy`, costs | 11 | Be honest about main-thread cost |
| 20:00–21:00 | Selection: what can / cannot move | 12 | D4 |
| 21:00–22:30 | Future: `TextDelegateHostMixin`, platform views / CSS highlights | 13 | Forward compatibility |
| 22:30–25:00 | Status, landing plan, decisions requested | 14–15 | D1–D6 |
| 25:00–45:00 | Q&A | — | See §6–§9 |

**Cut list if running long** (in order): slide 13 (future) → slide 4 history to 60s → slide 12 selection to a single table → skip the second demo.

---

## 3. Speaker script (slide by slide)

> [!TIP]
> Speak at ~130 wpm. Each block below is 1–3 minutes. Timings are cumulative. `[SLIDE]` = advance; `[DEMO]` = switch to the app; `[BACK]` = return to slides.

### Slide 1 — Title (0:00)

"Hi everyone. I'm Hannah. This is about RFC 170, *Composable Text Plugins* — a small set of hooks in `RenderParagraph` and `RenderEditable` that let apps and packages inspect, decorate, and interact with text across a whole subtree without replacing any widgets. The headline feature it unlocks is browser-style Find-in-Page, but the point of the design is that Find-in-Page is one plugin among many."

### Slide 2 — What I want from you (0:20)

"Before the demo, here's what I'm hoping to get from this room today. Six decisions, listed on the slide — I'll come back to them at the end. The two I care most about: whether a post-layout callback on `PipelineOwner` is an acceptable new pipeline phase, and how plugins should be identified and reconciled. Everything else is detail we can iterate on in the RFC thread."

### Cold-open demo (0:45 → 2:30)

`[DEMO]` — follow §4, Demo A. Narration:

"This is a plain Material page: `Text`, `Text.rich` with a `WidgetSpan`, a `TextField`, a `SelectionArea`, and a 20-item `ListView.builder`. None of these widgets are custom. I press Cmd+F… type `Flutter`… every match is highlighted, including inside the text field. Enter walks matches in document order and scrolls them into view — including items that were not built yet when I started typing. The search bar itself says '3 of 12' and does not match itself, because it sits in a `TextPluginScope.none`. That's the whole pitch: ambient, composable, zero widget replacement."

`[BACK]`

### Slide 3 — The problem (2:30)

"Cross-cutting text features show up everywhere: find-in-page, entity highlighting like tickers and mentions, auto-linkification, read-aloud karaoke, content extraction. Today the ecosystem solves each one with a replacement widget — `LinkifyText`, `SearchableText`, `ParsedText`. That fails in three ways. They don't compose: you cannot stack `LinkifyText` from one package with `TickerText` from another on the same paragraph. They require invasive refactoring: you have to replace every `Text`, including the ones inside `ListTile`, `DataTable`, or a third-party markdown renderer. And they have no document-level coordination — 'next match' needs an ancestor that knows about every paragraph. So the feature belongs in an ambient pipeline attached through an `InheritedWidget`, executed by the two render objects that actually own text layout."

### Slide 4 — History (4:30)

"This isn't new thinking. Michael wrote the Text Plugins one-pager in late 2023 after his find-in-page demo hit the composition wall; the three abstractions are his. Renzo turned it into a working prototype — he's the one who made `TextDelegate` a `Listenable` and `Comparable`, exposed placeholder ranges, and added `ensureVisible`. Kevin built end-to-end Ctrl+F on top of `SelectableRegion` in PR 193186 and RFC 25. That experiment was decisive: it validated demand, surfaced offscreen slivers and semantics labels as edge cases, and showed that `SelectableRegion` cannot be the foundation — it needs a registrar, so non-selectable pages needed a hidden find-only region, and `EditableText` never registers at all. So we unified on `TextPluginScope`."

### Slide 5 — Goals and non-goals (6:30)

"Goals: existing `Text`, `Text.rich`, and `EditableText` participate automatically; multiple plugins stack with a stable Z-order; plugins talk to a capability-scoped delegate, never the render object; subtrees can opt out; and nothing depends on Material or Cupertino. Non-goals for v1: non-text widgets and platform views — although section 6 shows the shape — and plugins never mutate the span tree or layout. They decorate and observe. And this is explicitly not a redaction mechanism: a painted bar hides glyphs, not the string."

### Slide 6 — Three abstractions (7:30)

"The API has three names. `TextPluginScope` is the inherited widget: it merges ancestor and local plugins, dedupes by `Type` like `Actions` does, sorts by `paintOrder`, and offers `.none` and `.exclude`. `TextPlugin` is the plugin: two declarative getters — `needsOffscreenContent` and `paintOrder` — and five hooks: `didAddText`, `didUpdateText`, `didLayoutText`, `didRemoveText`, `handlePointerEvent`. `TextDelegate` is the proxy a plugin gets for each text render object: plain text, geometry queries, a background and a foreground painter slot, coordinate helpers, `ensureVisible`, and `compareTo` for document order. Crucially, there is one delegate per *(render object, plugin)* pair. Two plugins on the same paragraph never share painter slots — that's the answer to the 'should painters be a list' review question."

### Slide 7 — Lifecycle and the post-layout flush (10:00)

"This is the part I most want scrutiny on. Early prototypes fired `didAddText` in `attach`, `didUpdateText` in `set text`, and `didLayoutText` inside `performLayout`. All three are traps. Before layout, `getBoxesForSelection` asserts or returns stale geometry. Inside `performLayout`, `_needsLayout` is still true, `debugActiveLayout` is set so touching another delegate's size asserts, and the parent hasn't set your offset yet so `localToGlobal` is wrong. And `debugNeedsLayout` is always false in release, so a check that passes in debug lies in profile.

So the prototype adds `PipelineOwner.schedulePostLayoutCallback`. It runs at the very end of `flushLayout`, after every dirty node has exited `layout()` and parents have positioned children, and *before* `flushPaint`. Three consequences: `delegate.hasLayout` is guaranteed true in all three callbacks; geometry and coordinates just work; and a painter set inside `didAddText` paints in the same frame — no one-frame flicker, which a post-frame callback would give you. We track `hasValidLayout` ourselves — cleared in `markNeedsLayout`, set in `performLayout` — so it's correct in release too. The hook is 39 lines in `object.dart` and is `@internal`. The question for you is whether this is an acceptable pipeline phase."

### Slide 8 — The delegate contract (13:00)

"Chun-Heng's review pushed us to make the delegate opinionated rather than document footguns, and I think that was right. `delegate.text` always returns `toPlainText(includeSemanticsLabels: false)` with placeholders kept, so every `WidgetSpan` is one U+FFFC code unit and string offsets line up with `ui.Paragraph` offsets. Plugins never call `toPlainText` themselves. `getBoxesForSelection` defaults to `includePlaceholders: false` and splits ranges around placeholders so a highlight never paints across an inline widget. Setting a painter checks `shouldRepaint`, wires the painter's `Listenable` to `markNeedsPaint`, and only repaints when needed. Each painter runs inside its own `save`/`translate`/`restore`, and in debug we assert the save count is balanced and name the offending painter."

### Slide 9 — Paint pipeline and `paintOrder` (15:00)

"Painting is three stages: plugin backgrounds, then glyphs and inline children, then plugin foregrounds, each clipped when the paragraph clips. Order within a stage is ascending `paintOrder`, ties broken by root-to-leaf installation. `paintOrder` exists because of one concrete case: `SelectionArea` is near the root, a ticker plugin painting an opaque green pill is deeper in the tree. If order were tied to nesting, the pill would cover the selection highlight and 'GOOG' would look unselected. A selection plugin with a higher `paintOrder` fixes that while still painting behind glyphs."

### Slide 10 — Document order and `ensureVisible` (16:30)

"Two find-in-page problems. First, lazy lists mount out of order — scroll up and you get item 10, 9, 8, 7 — so 'next match' needs a stable document order, and screen coordinates fail for side-by-side columns. `TextDelegate.compareTo` walks up to the lowest common render ancestor and asks `visitChildren` which branch comes first. Cost is O(depth + siblings) per comparison, and the search plugin keeps only the K matching delegates sorted with binary insertion, so a single text change never touches the other N paragraphs. Second, scrolling to a character range, not a widget: `ensureVisible` unions the glyph boxes and calls `showOnScreen(rect:)`, which walks every enclosing viewport and scrolls the minimal distance in each."

### Slide 11 — Offscreen content (18:00)

"Browsers find text that isn't on screen; `ListView.builder` doesn't build it. We split this into two decoupled pieces. `TextPlugin.needsOffscreenContent` is a declarative request. `OffscreenContentRenderingStrategy` is a standalone inherited widget that `Viewport` consults for its cache extent — `Viewport` never imports text plugins. When any active plugin asks, the scope installs an eager policy with a 1e6-pixel cache extent; when Ctrl+F closes, it flips back to lazy and `collectGarbage` unmounts the items. Why 1e6 and not infinity: `fullCacheExtent = mainAxis + 2 × cache` goes NaN with `maxFinite`. The honest cost: building and laying out thousands of items happens on the UI thread in one frame. That's why the policy carries a configurable `ScrollCacheExtent` — apps bound it per scroll view, or pin a list to lazy. I'll take questions on chunking across frames; I think it's the right follow-up."

### Slide 12 — Selection (20:00)

"Can selection highlighting be a plugin? Painting the boxes — yes, it's literally a `backgroundPainter` with `getBoxesForSelection`, and the prototype does it inside `SelectableRegion`. What can't move: mobile drag handles need `LeaderLayer`s pushed into the `PaintingContext`, which a `CustomPainter` cannot do, and cross-widget gesture coordination stays in `SelectionRegistrar`. So the proposal lands the pipeline first and keeps built-in selection rendering unchanged; the four-step migration is in section 5.2.4."

### Slide 13 — Future (21:00)

"Two forward-compatibility checks. First, custom render objects: `TextDelegateHostMixin` lets any `RenderBox` that paints with `TextPainter` — or a labeled image or chart — participate; section 6.1 has two complete examples. Second, platform views: the W3C CSS Custom Highlight API is the same non-destructive range-decoration model, so a declarative `setHighlights` alongside `CustomPainter` would let an `HtmlElementView` translate ranges into `CSS.highlights`. Neither is in v1; both fit the shape."

### Slide 14 — Status and landing plan (22:30)

"Status: the branch has the rendering and widget layers, `RenderParagraph` and `RenderEditable` integration, the viewport policy, 17 widget tests, and a demo app with seven plugins exercising paint, pointer, scroll, and headless use. Proposed landing order: the pipeline hook plus `TextPlugin`/`TextDelegate` and `RenderParagraph`; then `RenderEditable`; then `TextPluginScope` and the viewport policy; then `SearchInPagePlugin`; selection migration and host mixin as follow-ups. Each PR is independently testable."

### Slide 15 — Decisions requested (24:00)

"Back to the six decisions. D1: the post-layout hook. D2: plugin identity. D3: where `SearchInPagePlugin` lives. D4: selection migration timing. D5: raw pointer events versus gesture arena. D6: semantics annotations in v1 or after. Thank you — let's go to questions."

---

## 4. Live demo runbook

### Pre-flight (30 min before)

- [ ] `./bin/flutter run -t examples/text_plugins/lib/main.dart -d macos --release` (release: no debug banner, smoother scroll). Keep a second instance on Chrome ready if a web person asks.
- [ ] Window at ~1280×800, font scaling up (`Cmd +` if on web) so the back row can read highlights.
- [ ] Disable notifications / Do Not Disturb.
- [ ] **Backup:** record a 90-second screen capture of Demo A and Demo B today; have it open in QuickTime.
- [ ] Have the `rfc#35` PR and the design doc open in tabs for Q&A reference.

### Demo A — Find-in-page (90 s, cold open)

1. Point at the page: "stock `Text`, `Text.rich` + `WidgetSpan`, `TextField`, `SelectionArea`, `ListView.builder` with 20 items."
2. `Cmd+F` → focus lands in the search bar (`CallbackShortcuts` at line ~431 of `main.dart`).
3. Type `Flutter` slowly; call out: match count, highlights in `TextField`, no self-match in the search bar.
4. Press `Enter` 3–4 times: active match border, scroll into view, document order across the list.
5. Toggle case-sensitive chip once (shows live rescan).
6. Clear query → highlights vanish, lazy policy restored.

### Demo B — Composition and opt-out (optional, 90 s before slide 14)

1. Enable tickers + linkify + spoiler chips: show pills, underlines, masked `||Rosebud is the sled||`; tap the spoiler to reveal; tap `GOOG` to open the quote sheet.
2. Drag-select across a ticker pill inside `SelectionArea`: selection highlight stays visible over the pill (**`paintOrder` in action**).
3. Scroll to "5. Opt-Out Zone": same words, no decorations.
4. If time: Read-Aloud bar → word-by-word highlight crossing paragraphs.

### Failure modes

| Symptom | Recovery |
| :-- | :-- |
| App won't launch | Play the recording; say "the branch is `text-plugin-testing`, demo is `examples/text_plugins`." |
| `Enter` loses focus | Known and fixed (`onEditingComplete`); click back into the field. |
| Scroll-to-match jumps oddly | Acknowledge, move on; note it for the thread. |

---

## 5. Pre-talk fix list: doc-vs-prototype discrepancies and gaps

> [!IMPORTANT]
> Senior reviewers read the branch, not just the doc. Fix or consciously pre-empt each item below before the talk.

### 5.1 Discrepancies (fix the doc or the code)

| # | What the doc says | What the branch does | Suggested action |
| :-- | :-- | :-- | :-- |
| 1 | §3.2: "Within a single frame, a delegate receives **at most one** of `didAddText`, `didUpdateText`, or `didLayoutText`." | [`_flushTextPluginNotifications`](file:///Users/jinhangyu/Documents/GitHub/flutter/packages/flutter/lib/src/rendering/text_plugin.dart#L710-L746) calls `didAddText` **then** `didLayoutText`, and `didUpdateText` **then** `didLayoutText`. | Pick one. The code's behavior is arguably better (one "layout is valid" hook to implement). Update the doc + sequence diagram. |
| 2 | §5.2.2 / §3.5: `paintOrder` solves selection-vs-plugin ordering. | `RenderParagraph.paint` uses an `@internal` [`handlesSelectionHighlight`](file:///Users/jinhangyu/Documents/GitHub/flutter/packages/flutter/lib/src/rendering/text_plugin.dart#L82-L90) flag and a hard-coded second background pass. | Either make `_SelectionHighlightTextPlugin` use `paintOrder => 100` and delete the flag, or document the flag as an internal optimization. Expect the question. |
| 3 | §3 usage example constructs plugins inline: `TextPluginScope.multiple(plugins: [SearchInPagePlugin(query: 'Flutter'), SpoilerMaskPlugin()])`. | Reconciliation is **by instance identity** (`Map<TextPlugin, TextDelegate>`). Inline construction in `build` churns every delegate (`didRemoveText`/`didAddText`) on every rebuild. | Change the sample to hoist plugins into `State`, and add a doc note. Better: decide D2 (a `shouldUpdate`/key protocol). |
| 4 | `SearchInPagePlugin(query: ...)` constructor parameter; `eagerLoadOffscreenText = true` default. | No `query` ctor param (setter only); default `_eagerLoadOffscreenText = false`. | Align doc snippet with code. |
| 5 | `TextDelegate.getBoxesForSelection` honors `boxHeightStyle`, `boxWidthStyle`, `includePlaceholders`. | For `RenderEditable` all three are [dropped](file:///Users/jinhangyu/Documents/GitHub/flutter/packages/flutter/lib/src/rendering/text_plugin.dart#L352-L354). `ensureVisible` passes `BoxHeightStyle.max` which is silently ignored for editables. | Plumb the parameters through `RenderEditable.getBoxesForSelection` or document the limitation. |
| 6 | §5.1.2: LCA compare "without allocating". | `compareTo` allocates two ancestor `List`s per call. | Say "no geometric transforms"; or walk depths without lists. |
| 7 | §3.4 tie-break: "root-to-leaf installation order". | When an inner scope overrides an outer plugin of the same `Type`, `LinkedHashMap` keeps the **outer** insertion position, so the override inherits the outer tie-break slot. | Remove-then-insert on override, or document. |
| 8 | §5.1.3: apps can bound cache extent with `OffscreenContentRenderingStrategy`. | Under `TextPluginScope.exclude`, [`effectivePolicy`](file:///Users/jinhangyu/Documents/GitHub/flutter/packages/flutter/lib/src/widgets/text_plugin.dart#L235-L241) ignores the inherited policy, so a bounded extent reverts to the 1e6 default below an `exclude` scope. | Fix the branch logic. |
| 9 | Framework and host code paths are identical. | `_syncTextPluginDelegates`, `_flushTextPluginNotifications`, painter helpers are duplicated **three times** (`RenderParagraph`, `RenderEditable`, `TextDelegateHostMixin`); `TextDelegate` switches on `is RenderParagraph / RenderEditable / Host`. | Say up front: "the prototype duplicates; the landing PR will have `RenderParagraph`/`RenderEditable` use the mixin and `TextDelegate` talk to one host interface." |

### 5.2 Gaps you should raise before someone else does

1. **Eager offscreen rendering inflates the semantics tree.** [`RenderViewportBase.describeSemanticsClip`](file:///Users/jinhangyu/Documents/GitHub/flutter/packages/flutter/lib/src/rendering/viewport.dart#L935-L963) expands the semantics clip by `_calculatedCacheExtent`. With a 1e6 extent every eagerly built item gets a `SemanticsNode` (hidden, but present). On web that is thousands of DOM nodes in the semantics overlay; on mobile it is a very large `SemanticsUpdate`. Proposed mitigation: separate "layout cache extent" from "semantics cache extent" (keep semantics clip at the normal 250 px), or have the eager policy not widen the semantics clip.
2. **`SelectionArea` now installs a `TextPluginScope` for every app that uses it.** Every `Text` inside gains a `TextDelegate` (a `ChangeNotifier`), a painter, and listeners — even in apps that never heard of plugins. Have a benchmark plan ready (`macrobenchmarks` text-heavy pages, `complex_layout`), and goldens for pixel parity with `_SelectableFragment.paintSelection`.
3. **Marking layout dirty inside a post-layout callback.** If a plugin calls `markNeedsLayout` (directly or via `setState` on a `LayoutBuilder`) from `didAddText`, the render object is skipped in this frame's paint (`_paintWithContext` returns early when `_needsLayout`) and painted next frame. No assert exists today. Say you will add a debug assert mirroring `_debugDoingLayout`.
4. **`delegate.text` is recomputed on every call** (`toPlainText` per access; `placeholderRanges` and `getBoxesForSelection` call it again), and `RenderParagraph.set text` computes it twice per change when plugins are active. Plan: cache per layout generation.
5. **`Icon` is a `RichText`.** Icons inside a scope register delegates whose `text` is a single private-use-area code unit; `SeoExtractorPlugin` would count them as words and `ReadAloudPlugin` could try to speak them. Plan: `Icon` passes `textPlugins: const []` (or the scope filters by `TextSpan` with PUA-only text).
6. **Overlays do not inherit the scope.** Dialogs, menus, tooltips mount under `Overlay` above the page's `TextPluginScope`. Same as `Theme` before `InheritedTheme`; decide whether `TextPluginScope` should implement `InheritedTheme` capture.
7. **No gesture-arena participation and no semantics for plugin affordances.** A plugin tap inside a `GestureDetector` fires both; plugin-painted links are invisible to screen readers and to agents. This is D5/D6.

---

## 6. Anticipated questions by persona

Format: **Q** → *why they ask* → **A** (say this) → *Gap/follow-up* (be honest).

### 6.1 Framework experts

**Q1. Why a new `PipelineOwner` phase instead of `addPostFrameCallback`, a persistent frame callback, or doing the work in `performLayout`?**
*They guard the pipeline and will have strong opinions on any new phase.*
**A:** Post-frame runs after `flushPaint`, so a painter set there paints a frame late — visible flicker on every mount. Inside `performLayout`, `_needsLayout` is still true, `debugActiveLayout` is set, and the parent has not positioned us, so geometry and `localToGlobal` are wrong. The end of `flushLayout` is the only point where layout is final and paint hasn't started. It is 39 lines, `@internal`, drains until stable, and recurses into child `PipelineOwner`s for multi-view.
*Follow-up:* "If the room prefers, this could be generalized as a public `RenderObject`-level 'after layout, before paint' hook — but I'd rather land it internal first."

**Q2. What happens if a plugin mutates layout (or calls `setState` that reaches a `LayoutBuilder`) from a post-layout callback?**
**A:** Today the node is laid out next frame and skipped in this frame's paint — one blank frame, no crash. We should assert in debug, the same way `_debugDoingLayout` guards `markNeedsLayout` re-entrancy. The contract: painters and `markNeedsPaint` are allowed; `markNeedsLayout` is not. `setState` is deferred by the plugin (§7.1) via a post-frame callback.

**Q3. Plugins are reconciled by instance identity, yet your sample constructs them in `build`. Isn't this the `GestureDetector`-recognizer-churn problem all over again?**
*This is the sharpest framework critique in the doc as written.*
**A:** Yes — the sample is wrong and will be fixed to hoist plugins into `State`. The deeper question is D2. Options: (a) keep identity and document "plugins are long-lived objects like `ScrollController`"; (b) add `bool shouldUpdate(covariant TextPlugin old)` like `CustomPainter.shouldRepaint` so a new instance can adopt old delegates; (c) split configuration from state the way `Widget`/`State` or `GestureRecognizerFactory` do. My lean is (b): small, familiar, and keeps per-delegate state alive across rebuilds.

**Q4. Why dedupe by `runtimeType`? `Actions` keys by `Intent` type — a capability — not by implementation type. What if I legitimately want two `LinkifyPlugin`s with different regexes, or a generic plugin?**
**A:** Dedupe-by-Type gives "inner overrides outer" and a clean `exclude(types:)` story, matching `Actions`/`Shortcuts`, and it prevents double alpha and double tap callbacks. For two instances of one class, subclass or use a composite plugin. If the room prefers an explicit `Object get identity` key defaulting to `runtimeType`, that's a two-line change.

**Q5. `RenderEditable` already has `painter` / `foregroundPainter` slots (`RenderEditablePainter`). Why a parallel `CustomPainter` pipeline?**
**A:** `RenderEditablePainter.paint(canvas, size, renderEditable)` is editable-specific and single-slot, consumed by `EditableText` for caret and selection. `CustomPainter` is the universal primitive, works identically for `RenderParagraph`, and the plugin pipeline needs per-plugin isolated slots with `shouldRepaint` + `Listenable` wiring. Long-term, `_CaretPainter` and `_TextHighlightPainter` could themselves become plugins — that's the same direction as selection migration.

**Q6. `SelectionArea` now wraps its child in a `TextPluginScope`. That's a perf change for every Material app using it. Numbers?**
**A:** Not benchmarked yet; it's prototype plumbing to validate that selection painting fits the pipeline. Before landing, the selection migration is gated (D4) and I'll add text-heavy macrobenchmarks plus pixel goldens against `_SelectableFragment.paintSelection`. The v1 landing does **not** need to change `SelectionArea`.

**Q7. Pointer events bypass the gesture arena. A link tap inside a `GestureDetector` fires both; a tap on a link inside a scrollable competes with drag only via manual `kTouchSlop`. Why not recognizers?**
**A:** Deliberate v1 simplicity: plugins get raw events like a `Listener`, and the two interactive demo plugins implement slop manually. The right follow-up is to let `TextDelegate` expose `addGestureRecognizer(range, recognizer)` so the arena resolves conflicts and `TextSpan.recognizer` precedent is reused; `RenderParagraph.hitTestChildren` already adds span `HitTestTarget`s. Related: mouse cursors — `TextSpan` already implements `MouseTrackerAnnotation`, so per-range cursors can ride the same path.

**Q8. `compareTo` uses `visitChildren`. That's paint order, not reading order — `Stack`, `reverse: true` lists, center-anchored `CustomScrollView`s, `Flow`, overlays.**
**A:** Correct; it approximates reading order for `Flex`, `Wrap`, `Table`, `SliverList`, which covers the demo and most documents. Known gaps are exactly those. Two options: let hosts override comparison, or reuse the semantics traversal order (`visitChildrenForSemantics` + the geometry-based default sort), which already encodes reading order with `Directionality`. I'd rather not duplicate that logic; happy to explore reuse.

**Q9. Why switch on `is RenderParagraph / RenderEditable / Host` inside `TextDelegate` instead of one host interface? And why is the sync/flush logic duplicated three times?**
**A:** Prototype expedience. Landing shape: a single `TextDelegateHost` interface implemented by all three, `RenderParagraph`/`RenderEditable` mix in the host mixin, `TextDelegate` only talks to the interface. `rendering/text_plugin.dart` then stops importing `paragraph.dart` and `editable.dart`.

**Q10. `Icon` widgets render through `RichText`. Do they register delegates?**
**A:** Yes today, which is wrong for headless and TTS plugins. Fix: `Icon` passes an empty `textPlugins` list (it already builds its own `RichText`).

**Q11. Overlays (dialogs, menus, tooltips) won't see the scope.**
**A:** Correct, same as every `InheritedWidget`. If we want capture, `TextPluginScope` can implement `InheritedTheme` so `InheritedTheme.captureAll` carries it into routes. Not in v1.

**Q12. Toggling a plugin list rebuilds every `RichText` in scope.**
**A:** `_InheritedTextPluginScope.updateShouldNotify` is `listEquals`, so flipping `needsOffscreenContent` doesn't notify text dependents — only `Viewport`s rebuild via the strategy widget. Adding/removing a plugin does notify, by design; the mitigation is to keep plugins installed and toggle state inside them (which is what the search plugin does).

**Q13. What about `TextOverflow.fade` — do foreground painters get faded?**
**A:** No; foreground painters paint after the overflow `saveLayer` is restored, so an underline stays crisp on a faded tail. Debatable; we could move foregrounds inside the layer.

**Q14. Does `RenderParagraph.hitTestSelf` change? Will every `Text` now swallow hits?**
**A:** No change — it already returns `true`. We only add a `handleEvent` override that forwards to plugins when delegates exist.

**Q15. Shortcuts: should `WidgetsApp` ship a `FindInPageIntent` with default Ctrl/Cmd+F bindings like `SelectAllTextIntent`?**
**A:** Not in the RFC, but I'd like that for D3: if `SearchInPagePlugin` is in the framework, a default `Intent`/`Action` pair and a Material find bar make Ctrl+F a one-liner.

### 6.2 Engine / text layout experts

**Q16. `getBoxesForRange` crosses into SkParagraph every time. Your painters call it for every match on every paint — and `ReadAloudPlugin` repaints per word.**
**A:** True in the prototype. Boxes are stable until the next layout; the fix is a per-delegate box cache keyed on layout generation (`hasValidLayout` already flips in `markNeedsLayout`). That makes paint O(matches) rect draws with zero engine calls in steady state.

**Q17. Character offsets vs glyphs: ligatures (`fi`, Arabic shaping), combining marks, emoji ZWJ sequences, Indic clusters. What does a highlight of half a ligature look like?**
**A:** Exactly what selection highlight looks like today — we call the same `getBoxesForSelection`, so we inherit SkParagraph's grapheme-cluster behavior and any proportional splitting it does. The doc tells plugin authors to iterate every returned box and to treat offsets as UTF-16 code units; `characters` is recommended for tokenizing.

**Q18. Why `BoxHeightStyle.tight` for highlights? Browsers paint contiguous line-height highlights.**
**A:** `tight` is the default to match selection today; the API passes `boxHeightStyle`/`boxWidthStyle` through, so a plugin can choose `includeLineSpacingMiddle`. (Note: for `RenderEditable` the prototype drops these — fix list #5.)

**Q19. Impeller: many small `drawRRect` calls and a `save`/`restore` per painter per paragraph, plus `clipRect` when clipping. Any measured overdraw cost?**
**A:** Not measured yet. Draw ops scale with matches, not paragraphs — delegates without painters cost one null check. No `saveLayer` is introduced by the pipeline; plugins that use blend modes pay their own cost like any `CustomPaint`.

**Q20. Eager offscreen layout: thousands of `ui.Paragraph`s hold shaped glyph data in native memory, and `TextPainter.layout` for all of them in one frame is seconds of jank. Have you measured memory and frame time?**
**A:** Not at scale, and this is the real cost of the feature; the doc is candid that it's UI-thread work. Mitigations in the design: bounded `ScrollCacheExtent` per scroll view, opt-out per list, lazy restored on close. Follow-ups I'd like help on: growing the extent incrementally across frames (progressive expansion), and whether off-thread paragraph layout is realistic.

**Q21. Typing in a large `TextField` triggers `didUpdateText` per keystroke and a full rescan of the field.**
**A:** Yes; the per-delegate incremental design means only that field is rescanned, but within the field it's O(length). For editor-scale documents the right API is delta-aware updates (`TextEditingDelta` is already available in `EditableText`); `didUpdateText` could carry the changed range in a follow-up.

**Q22. IME composing region and the built-in spellcheck underline — conflicts?**
**A:** Plugins paint around them, not instead of them. Interesting opportunity: `EditableText` today rebuilds spans with wavy underline styles for spellcheck (`buildTextSpanWithSpellCheckSuggestions`), which is destructive; that is a natural migration target for a non-destructive plugin painter.

**Q23. Should "highlight ranges" be an engine feature (paragraph-level background ranges) rather than framework overdraw?**
**A:** Possibly for the common case, and the `setHighlights` idea in §6.2 is shaped so a host could forward ranges to the engine or to CSS highlights. But the plugin pipeline needs arbitrary painting (pills, borders, karaoke pills, masks), so `CustomPainter` stays regardless.

### 6.3 Web experts

**Q24. On web, how does your Ctrl+F interact with the browser's find bar? Users expect the native one.**
**A:** When the framework handles the key (`CallbackShortcuts`/`Shortcuts`), the engine calls `preventDefault`, so the browser bar stays closed; if the app doesn't bind it, native find opens as before. Native find can't see canvas text anyway (only the semantics DOM when enabled). I'd like web-team input on whether to recommend binding Ctrl+F by default on web.

**Q25. `LinkifyPlugin` paints a fake link. On web a real link means `<a href>`: right-click, middle-click, status bar, crawlers, screen readers. `url_launcher`'s `Link` exists for exactly this.**
**A:** Agreed — `Link` remains the right tool when you author the spans. Linkify is for text you don't control. Bridging the gap is the semantics annotation work (D6): `SemanticsProperties.linkUrl` + `isLink` already exist, so a plugin-annotated range can surface as `<a href>` in the web semantics tree and expose `onTap`.

**Q26. Hover cursor and hover previews for links?**
**A:** `handlePointerEvent` already receives `PointerHoverEvent`. Cursors need a `MouseTrackerAnnotation` in the hit-test result; `TextSpan` already implements that interface, so a `TextDelegate` API to register per-range annotations is a small follow-up.

**Q27. SEO via `SeoExtractorPlugin` — crawlers don't run CanvasKit apps meaningfully; is this a real story?**
**A:** It demonstrates a headless plugin (no painters), not an SEO strategy. If an app injects JSON-LD, it does so with JS interop; the broader SEO story belongs to the web team.

**Q28. CanvasKit/Skwasm: `getRectsForRange` is a JS↔Wasm hop returning a typed array; wasm GC strings and `toPlainText` churn.**
**A:** Same mitigation as Q16: cache boxes per layout and cache `text` per layout generation. Nothing in the design forces per-frame engine calls.

**Q29. Multi-view embedding: delegates in different views have no common root.**
**A:** `compareTo` falls back to `identityHashCode` ordering when there's no common ancestor — deterministic within a session, arbitrary across views. A document-order plugin should scope per view; worth a doc note.

**Q30. Platform views and the CSS Custom Highlight API — browser support?**
**A:** Chromium 105+, Safari 17.2+, Firefox 140+. It's future work in §6.2 and only reachable through a declarative `setHighlights` on `TextDelegate`, because a canvas overlay can't paint between a DOM element's background and its glyphs or stay in sync with DOM scrolling.

**Q31. Does the web context-menu DOM overlay in `SelectableRegion` eat pointer events before plugins see them?**
**A:** Plugins only receive events that hit-test to the `RenderParagraph`; if the DOM overlay consumes them, neither the paragraph nor the plugin sees them — unchanged behavior.

### 6.4 Accessibility experts

**Q32. Plugin-painted links, tickers, spoilers: are they in the semantics tree?**
**A:** Not in v1. Today a `TextSpan` with a recognizer becomes its own `SemanticsNode` via `InlineSpanSemanticsInformation`; the proposed `TextPluginSemanticAnnotation` reuses that path so a plugin can register `(range, label, actions, isLink/linkUrl)` and `RenderParagraph.assembleSemanticsNode` splits accordingly. Design the hook now, land it in a follow-up (D6).

**Q33. Spoiler masks hide glyphs but screen readers read them. UX leak?**
**A:** Yes, by design in v1 — plugins are visual. With annotations a spoiler plugin could mark the range `hidden` until revealed. Also worth noting: `SelectionArea` copy and Ctrl+F still see the text, which the doc states explicitly.

**Q34. Match count and navigation announcements?**
**A:** App-level: `SemanticsService.announce` or a live region on the find bar. If `SearchInPagePlugin` ships with a Material find bar, it should do this by default. Also: should a11y focus follow the active match? That requires a node for the range — same D6 dependency.

**Q35. Eager offscreen rendering and the semantics tree.**
**A:** This is the gap I flagged in §5.2.1: `describeSemanticsClip` grows with the cache extent, so every eagerly built item becomes a hidden `SemanticsNode`. Proposal: keep the semantics clip at the normal extent when the eager policy is active. I'd like to land that with the viewport policy, not after.

### 6.5 PM / leadership

**Q36. Who is asking for this, and how do we know?**
**A:** The long-standing find-in-page request is one of the most-upvoted text issues; desktop and web customers raise it every launch review; Kevin's RFC #25 and PR 193186 were an explicit demand check. Three separate engineers prototyped this independently over two years — that's signal that the hooks, not just Ctrl+F, are the missing primitive. *(Insert the issue link and upvote count before the talk.)*

**Q37. Why a platform instead of just shipping Ctrl+F?**
**A:** Because Ctrl+F alone was tried (RFC #25) and could not generalize or reach `TextField`. The platform is small — two interfaces, one inherited widget, one pipeline hook — and Ctrl+F is the first consumer. Every other feature in the demo (linkify, tickers, spoilers, TTS highlights, extraction) comes for free from the same hooks and lives in packages, not in the framework.

**Q38. What's the MVP, and what's the timeline?**
**A:** MVP = hooks + `RenderParagraph` + `RenderEditable` + `TextPluginScope` + `SearchInPagePlugin`, landed as four reviewable PRs. Selection migration, host mixin, semantics annotations, and platform views are follow-ups. Timeline depends on D1–D3 today; I can give PR-level estimates after.

**Q39. Risk: a new public API we maintain forever. Who owns it?**
**A:** Text editing & selection area owns it; the surface is deliberately primitive-based (geometry + painters) so feature-specific churn stays in packages. `@internal` on the pipeline hook keeps our options open.

**Q40. Does it change behavior or performance for apps that never opt in?**
**A:** With the v1 landing plan: no — zero delegates are created without a scope. The one exception is the `SelectionArea` migration, which is why it's gated behind D4 and benchmarks.

**Q41. How does this compare to other toolkits?**
**A:** Web has the CSS Custom Highlight API (non-destructive ranges — the same model). SwiftUI has `findNavigator` for a single `TextEditor`; Compose has `LinkAnnotation` for spans you author. None of them have a composable, cross-widget, cross-package decoration pipeline — this would be a differentiator, and it reuses a model web developers already know.

**Q42. Success metrics?**
**A:** Ctrl+F usable in any Flutter desktop/web app with one widget; at least two external pub packages built on the hooks within a release; no regression on text macrobenchmarks; `SelectionArea` parity goldens.

**Q43. Mobile relevance?**
**A:** Spoilers, linkify, read-aloud highlighting, and in-app "find on page" (Safari and Chrome both have it on mobile) all apply; Ctrl+F is just the desktop/web headline.

### 6.6 AI / ML experts

**Q44. Streaming LLM output rebuilds a `Text` per token. What does the pipeline do per token?**
**A:** `set text` detects the plain-text change, schedules one post-layout `didUpdateText` for that paragraph only, and the plugin rescans that paragraph — O(paragraph) per token, not O(page). The real churn risk is markdown renderers that recreate widget subtrees per token: that triggers remove/add and loses per-delegate state. Guidance: keyed widgets, or plugin state keyed by content rather than delegate.

**Q45. Annotations are computed asynchronously (classifiers, grounding, entity extraction on-device). What's the pattern?**
**A:** Snapshot `delegate.text` in `didUpdateText`, compute off the UI thread (`compute`/isolate or platform API), and on completion check `delegate.attached && delegate.text == snapshot` before setting a painter and `markNeedsPaint`. Delegates are stable handles until `didRemoveText`, so this is safe. A small `TextDelegate.textVersion` would make the staleness check cheaper — easy to add.

**Q46. Citations/grounding spans come as token or UTF-8 byte offsets.**
**A:** Convert to UTF-16 code units once; iterate all boxes for multi-line/bidi; never split a grapheme (`characters`). The delegate is deliberately UTF-16-only to match `ui.Paragraph`.

**Q47. Many AI features rewrite text (translation, simplification). You only decorate.**
**A:** Correct — rewriting changes layout and belongs at the data layer. Decoration covers highlights, citations, "AI-generated" badges, hover explanations, and read-aloud sync. The spoiler plugin shows the limit: delimiters stay in the string; you mask them, you don't remove them.

**Q48. Can agents (computer-use) or on-device assistants discover plugin affordances?**
**A:** Only through semantics, which is why D6 matters beyond screen readers: the same annotation that makes a plugin link accessible makes it actionable for an agent. Conversely, a headless plugin like the extractor already produces document-ordered text that a "summarize this page" feature could consume.

**Q49. The spellcheck demo is regex-based; real spellcheck exists in `EditableText`.**
**A:** Yes — the demo is a read-only linter for static text. The existing editable spellcheck rebuilds spans with wavy underlines, which is destructive; migrating it onto a plugin painter is a natural follow-up (same as Q22).

### 6.7 Security / privacy

**Q50. A plugin at the root can read every `TextField` — including card numbers — without per-widget consent.**
**A:** Same trust boundary as any dependency: a package in your app already has your widget tree. But the ambient nature deserves guardrails: `TextPluginScope.none`/`exclude` for sensitive subtrees, `obscureText` fields expose bullets (the `RenderEditable` span is already obscured), and I'm open to `EditableText(textPlugins: const [])` as an explicit opt-out. The doc states plainly that plugins are not a redaction mechanism.

### 6.8 Testing, DevRel, ecosystem

**Q51. How do app developers test plugin output?**
**A:** Goldens for painting; `tester.renderObject<RenderParagraph>(find.text(...)).textPlugins` for registration; plugin unit tests via a fake `TextDelegate` host. A `WidgetTester` helper to fetch delegates for a finder would be a nice addition.

**Q52. Does `flutter_markdown` / third-party renderers just work?**
**A:** Anything that bottoms out in `RichText` or `EditableText` participates automatically — that's the central selling point. Custom `TextPainter` render objects need the host mixin (§6.1).

**Q53. Will `SearchInPagePlugin` come with UI?**
**A:** The plugin is UI-agnostic (`ChangeNotifier` + `ListenableBuilder`). A Material find bar is a reasonable follow-up if D3 lands it in the framework.

---

## 7. Top-10 most likely questions (rehearse these cold)

1. Why a post-layout `PipelineOwner` hook, and what if a callback dirties layout? (Q1, Q2)
2. Plugins built in `build` churn delegates — identity vs `shouldUpdate`? (Q3)
3. `SelectionArea` now creates delegates for every `Text` — perf? (Q6)
4. Raw pointer events vs gesture arena. (Q7)
5. Eager offscreen rendering: main-thread cost, memory, and semantics-tree growth. (Q20, Q35)
6. `getBoxesForRange` per paint — cache? (Q16)
7. `paintOrder` vs the `handlesSelectionHighlight` flag in the branch. (fix list #2)
8. Dedupe by `runtimeType` — two instances of the same plugin? (Q4)
9. Web: fake links vs `Link`, hover cursor, browser find. (Q24–Q26)
10. Semantics for plugin-painted affordances. (Q32)

---

## 8. Numbers and one-liners cheat sheet

| Fact | Value |
| :-- | :-- |
| Branch diff | 41 files, +9,649 / −67 |
| `rendering/text_plugin.dart` | 935 lines (`TextPlugin`, `TextDelegate`, `TextDelegateHostMixin`) |
| `widgets/text_plugin.dart` | 267 lines (`TextPluginScope`) |
| `paragraph.dart` / `editable.dart` / `object.dart` / `viewport.dart` | +329 / +280 / +39 / +115 |
| Tests | `text_plugin_test.dart` 1,162 lines, 17 `testWidgets` |
| Demo | 7 plugins, ~3,800 lines, `examples/text_plugins` |
| Default eager cache extent | `1e6` px (≈1,200–1,500 screens); not `maxFinite` because `2 × cache` overflows |
| Normal cache extent | 250 px |
| LCA compare | O(D + B), D ≤ ~30; sort O((D + B) · N log N); search keeps only K matching delegates |
| Placeholder char | U+FFFC, one UTF-16 code unit per `WidgetSpan` |
| Lifecycle | add / update / layout fire **post-layout, pre-paint**; remove is synchronous; add/remove strictly paired |

One-liners:

- "One delegate per (render object, plugin) pair — painters never collide."
- "Decorate and observe; never mutate spans or layout."
- "`Viewport` never imports text plugins — it reads a policy."
- "The end of `flushLayout` is the only moment layout is final and paint hasn't run."
- "`delegate.text` is the one true string; offsets line up with `ui.Paragraph` by construction."

---

## 9. Q&A handling tactics

- **Repeat the question** in one sentence; it buys time and helps remote attendees.
- **Answer → trade-off → ask**: give the position, name the cost, and when it maps to D1–D6 say "that's decision Dn; what's your preference?"
- **Unknown numbers:** "Not measured yet; I'll post the benchmark in the RFC thread this week." Never estimate a perf number live.
- **Scope pressure** ("add X to v1"): "Does X block landing the hooks, or can it be the first follow-up plugin?"
- **Hostile framing** ("this is overengineered"): go back to the three-failure story (compose, refactor, coordinate) and RFC #25's dead end.
- **Parking lot:** keep a visible list for anything that needs more than two minutes; commit to answering on the RFC.
- Close with: "Thanks — I'll summarize decisions D1–D6 and the parking lot on `flutter/rfc#35` today."
