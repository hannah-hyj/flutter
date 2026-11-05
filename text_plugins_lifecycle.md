# Lifecycle of Composable Text Plugins

This document summarizes the end-to-end lifecycle of `TextPlugin` and `TextDelegate`—covering frame timing, why callbacks run post-layout, what each hook is for, how `ChangeNotifier` fits in, and how painters and delegates are created and disposed.

---

## 1. End-to-End Frame Timeline

Within a single Flutter frame, text plugins participate across **Build → Layout → Post-Layout → Paint**:

1. **Build (`Text` / `TextField` → `RenderParagraph` / `RenderEditable`):**
   - The widget resolves active plugins from `TextPluginScope.maybeOf(context)` and passes `textPlugins` to its render object.
   - The render object creates a dedicated `TextDelegate(this, plugin)` for each new `(RenderObject, TextPlugin)` pair (`backgroundPainter` and `foregroundPainter` both start as `null`).
2. **Layout (`PipelineOwner.flushLayout()` → `performLayout()`):**
   - `RenderParagraph` / `RenderEditable` lays out the text, marks `delegate.hasValidLayout = true`, and schedules a post-layout callback on `PipelineOwner` (`schedulePostLayoutCallback`).
3. **Post-Layout (`PipelineOwner` → `TextPlugin`):**
   - Immediately after `flushLayout()` finishes (all sizes and parent offsets are finalized) and **before** `flushPaint()` begins, `PipelineOwner` dispatches `didAddText(delegate)`, `didUpdateText(delegate)`, or `didLayoutText(delegate)`.
   - The plugin inspects `delegate.text` / geometry and sets `delegate.backgroundPainter` (and/or `foregroundPainter`) if needed.
4. **Paint (`PipelineOwner.flushPaint()` → `paint()`):**
   - `RenderParagraph` / `RenderEditable` paints in back-to-front order on the same `Canvas`:
     1. Each `delegate.backgroundPainter` (in ascending `paintOrder`)
     2. The text glyphs and inline `WidgetSpan`s
     3. Each `delegate.foregroundPainter` (in ascending `paintOrder`)
5. **Unmount / Scope Removal (`detach()` / `dispose()` or plugin removed from scope):**
   - `RenderParagraph` / `RenderEditable` detaches painter listeners (`delegate.detachPainters()`), calls `plugin.didRemoveText(delegate)` (if `didAddText` had fired), and calls `delegate.dispose()`.

**Same-frame guarantee (zero flicker):** Because step 3 (Post-Layout) runs immediately after `flushLayout()` and **before** `flushPaint()`, assigning `delegate.backgroundPainter` inside `didAddText` or `didUpdateText` paints the highlight in the **very first frame** alongside the text glyphs.

---

## 2. Evolution: What We Tried First & Why It Didn't Work

In the initial prototype commits (`55076f2411b`–`b12414188a0`) and initial RFC draft (`00b52ae` / `aa61a31` on [`flutter/rfc#35`](https://github.com/flutter/rfc/pull/35)), we dispatched lifecycle hooks **synchronously at the moment each event occurred**:
- `didAddText(delegate)` ran inside `_syncTextPluginDelegates()` during `attach()` / `updateRenderObject()` (**before layout**).
- `didUpdateText(delegate)` ran inside `RenderParagraph.text = ...` right after `markNeedsLayout()` (**while layout was dirty**).
- `didLayoutText(delegate)` ran synchronously at the bottom of `RenderParagraph.performLayout()` (**mid-layout**).

During prototyping and [`flutter/rfc#35`](https://github.com/flutter/rfc/pull/35) review (`@chunhtai` in [`r4296904756`](https://github.com/flutter/rfc/pull/35#discussion_r4296904756), [`r4296977178`](https://github.com/flutter/rfc/pull/35#discussion_r4296977178), [`r4297160957`](https://github.com/flutter/rfc/pull/35#discussion_r4297160957), [`r4297852209`](https://github.com/flutter/rfc/pull/35#discussion_r4297852209)), this failed for **four concrete reasons**:

### Failure 1: Pre-layout `didAddText` / `didUpdateText` crashed or used stale constraints
- On initial mount, `performLayout()` had not run yet (`!hasSize`). Calling `delegate.getBoxesForSelection(...)`, `delegate.size`, or `delegate.localToGlobal(...)` inside `didAddText` immediately crashed (`RenderBox was not laid out`).
- On `set text` (`didUpdateText`), `markNeedsLayout()` had *just* been called. Querying `getBoxesForSelection` crashed on `assert(!debugNeedsLayout)` in debug mode—or worse, if synchronous code forced `_textPainter` layout early, it laid out the **new text against old/stale constraints**!
- Plugin authors had to awkwardly split logic across `didAddText` + `didLayoutText` and guard everything with `if (!delegate.hasLayout) return;`.

### Failure 2: `hasLayout` lied in Release builds
- Initially, `delegate.hasLayout` was written as `_paragraph.hasSize && !_paragraph.debugNeedsLayout`.
- In Flutter, `RenderObject.debugNeedsLayout` **always returns `false` in release mode** (it is debug-only). So in release builds during `didUpdateText` (right after `markNeedsLayout()`), `delegate.hasLayout` returned `true` even though layout was dirty, returning wrong/stale glyph boxes!
- *(Fix: we added an explicit release-safe `hasValidLayout` boolean set to `false` in `markNeedsLayout()` and `true` after layout.)*

### Failure 3: Moving callbacks to the end of `performLayout()` ALSO failed!
Next, we considered firing `didAddText` / `didUpdateText` / `didLayoutText` at the end of `RenderParagraph.performLayout()`. That also broke three `RenderObject` pipeline invariants:
1. **`_needsLayout` is still `true` inside `performLayout()`:** In `RenderObject.layout()`, `performLayout()` runs *before* `_needsLayout = false` is cleared—so `debugNeedsLayout` is still `true`!
2. **`RenderObject.debugActiveLayout` is still locked:** While Paragraph A is inside `performLayout()`, reading size/geometry on Paragraph B (for example, `SearchInPagePlugin` sorting delegates with `compareTo`) triggers Flutter's mid-layout assertion.
3. **Parent offsets (`BoxParentData.offset`) are NOT set yet:** A parent (`Column`, `Row`, `RenderSliverList`) calls `child.layout()` *first* and sets `childParentData.offset = Offset(x, y)` *after* `child.layout()` returns. At the end of `performLayout()`, `delegate.localToGlobal(Offset.zero)` returns `(0, 0)` (or last frame's stale offset)!

### Failure 4: `WidgetsBinding.addPostFrameCallback` caused a 1-frame visual flicker
- Deferring callbacks to `addPostFrameCallback` runs **after `flushPaint()` has already finished** for Frame 1.
- Frame 1 would paint unhighlighted text (or worse, expose unmasked `||spoiler||` text for 1 frame!), and `delegate.backgroundPainter` would only appear in Frame 2.

---

### The Solution: Post-Layout Flush (`PipelineOwner.schedulePostLayoutCallback`, commit `cc7edf3c06f`)

Scheduling callbacks at the very end of `PipelineOwner.flushLayout()`—after **all** dirty `RenderObject`s (including child `PipelineOwner`s) have finished layout and parent offsets are finalized, and **right before** `PipelineOwner.flushPaint()`—solves all four problems at once:
- `delegate.hasLayout` is guaranteed `true`, `_needsLayout` is `false`, `debugActiveLayout` is `null`, and `localToGlobal` has final screen coordinates.
- Setting `delegate.backgroundPainter` calls `markNeedsPaint()` before `flushPaint()`, painting in the **exact same frame** with zero flicker.
- **Open review refinements on `flutter/rfc#35`:**
  - `@loic-sharma` ([`r4475856756`](https://github.com/flutter/rfc/pull/35#discussion_r4475856756), [`r4475948556`](https://github.com/flutter/rfc/pull/35#discussion_r4475948556)): Enforce debug assertions forbidding `markNeedsLayout()` and `setState()`/`markNeedsBuild()` during post-layout callbacks, and flush post-layout callbacks only after child `PipelineOwner`s have also flushed layout.
  - `@chunhtai` ([`r4460795548`](https://github.com/flutter/rfc/pull/35#discussion_r4460795548)): Ensure at most one `did*` fires per frame (currently `paragraph.dart` still calls `didLayoutText` after `didAddText`/`didUpdateText`), and consider renaming `didLayoutText` → `didRelayoutText` so the name clearly means constraint-only relayout.

---

## 3. The 4 Lifecycle Hooks & When Plugins Need Them

| Hook | When It Fires | Typical Plugin Work |
| :--- | :--- | :--- |
| **`didAddText(delegate)`** | Once after a newly paired `(RenderObject, TextPlugin)` finishes its first layout. | Register `delegate`, scan `delegate.text` for matches, and assign `backgroundPainter` / `foregroundPainter` if matched. |
| **`didUpdateText(delegate)`** | Post-layout when the paragraph's text or span styles changed since the last layout. | Re-run text parsing (regex, `Ctrl+F` indexing, spellcheck) for **only this `delegate`** and update/clear its painters. |
| **`didLayoutText(delegate)`** | Post-layout when constraints/size changed (e.g. window resize) **without** text changing. | Recompute layout-dependent state (truncation checks, anchored popup coordinates, cached `Path` meshes) **without** re-parsing strings. |
| **`didRemoveText(delegate)`** | Synchronously when a plugin leaves `TextPluginScope` or the `RenderObject` detaches/disposes. | Remove `delegate` from plugin maps/lists and clean up per-delegate state. *(Skipped if layout never ran so `didAddText` and `didRemoveText` stay strictly paired.)* |

### Who actually needs `didLayoutText`?
Simple highlight plugins (like `SearchInPagePlugin` or `LinkifyPlugin`) do **not** need `didLayoutText` just to repaint: `RenderObject.layout()` already calls `markNeedsPaint()` automatically whenever a paragraph relayouts, so `CustomPainter.paint` will query fresh `getBoxesForSelection(...)` boxes anyway.

`didLayoutText` is specifically for plugins whose **state or external UI depends on box constraints**:
- **Truncation / overflow audit plugins:** Resizing a window can cause `Text(..., maxLines: 1, overflow: TextOverflow.ellipsis)` to truncate (or stop truncating) without the string ever changing.
- **External anchored UI (popovers / hover tooltips):** Repositioning a floating quote card or citation popup (`delegate.localToGlobal(...)`) when a word wraps from line 1 to line 2 during resize.
- **Cached `Path` / mesh animations:** Rebuilding an expensive wavy-underline or multi-line union `Path` once on relayout rather than 60 times per second during an opacity/shimmer animation.
- **Keeping an active range on screen:** Re-calling `delegate.ensureVisible(...)` if soft-keyboard insets reflow a long paragraph and push the active match out of view.

---

## 4. Why Have Both Lifecycle Hooks *and* `TextDelegate extends ChangeNotifier`?

`ChangeNotifier` (`Listenable`) only sends a zero-argument *"something changed"* signal (`void Function()`). It cannot replace `TextPlugin`'s lifecycle methods for three reasons:

1. **Discovery & removal (`didAddText` / `didRemoveText`):** A plugin cannot call `delegate.addListener(...)` on a `Text` widget it hasn't discovered yet, nor does `ChangeNotifier` distinguish an update from unmounting.
2. **Cause separation (`didUpdateText` vs. `didLayoutText`):** `ChangeNotifier` cannot tell a plugin whether the **string changed** (expensive regex/search re-scan needed) or the **window resized** (offsets unchanged, skip regex re-scan).
3. **Zero closure/listener boilerplate:** Passing `delegate` directly to `didUpdateText(delegate)` avoids allocating $N$ per-paragraph closures and tracking `Map<TextDelegate, VoidCallback>` across hundreds of `Text` widgets.

**Why `TextDelegate` is still a `ChangeNotifier`:** It acts as a ready-made `Listenable` for Flutter APIs that take `repaint: Listenable`—specifically `CustomPainter(repaint: delegate)`. Stateless `const` plugins (such as `_SelectionHighlightTextPlugin`) attach a painter once in `didAddText` with `super(repaint: delegate)`; whenever selection or layout changes on that single paragraph, `delegate` triggers `markNeedsPaint` on **only that paragraph**.

---

## 5. `TextDelegate` Cardinality, Painter Lifecycle, & Disposal

### $M \times N$ 1-to-1 Cardinality
- Each active `(RenderObject, TextPlugin)` pair gets its own isolated `TextDelegate`.
- Example: **3 plugins × 5 `Text` widgets = 15 `TextDelegate` instances** (each of the 5 `RenderParagraph`s holds a 3-entry `Map<TextPlugin, TextDelegate>`).
- If **0 plugins** are in scope, `_textPluginDelegates` stays `null` (zero overhead on apps not using `TextPluginScope`).

### When `backgroundPainter` / `foregroundPainter` Are Defined
- Both painter slots start as **`null`** when a `TextDelegate` is created—non-matching paragraphs allocate no `CustomPainter`.
- A `TextPlugin` assigns `delegate.backgroundPainter = ...` (or resets it to `null`) at two times:
  1. **Synchronously in post-layout (`didAddText` / `didUpdateText`)** when mounted or edited text matches.
  2. **Asynchronously on user/plugin events** (e.g. typing into the `Ctrl+F` bar sets `searchPlugin.query = 'Flutter'`, or clicking `nextMatch()`). None of the `Text` widgets rebuild or relayout; assigning `delegate.backgroundPainter` checks `shouldRepaint`, wires `painter.addListener(renderObject.markNeedsPaint)`, and marks only the affected `RenderParagraph`s dirty for paint.

### Automatic Disposal
`RenderParagraph` and `RenderEditable` own and dispose all `TextDelegate`s automatically (plugins never call `delegate.dispose()`):

1. **Plugin removed from `TextPluginScope`:** Surviving plugins keep their existing `TextDelegate`s intact; only the removed plugin's delegates are disposed.
2. **`Text` widget unmounts or scrolls offscreen (`detach()` / `dispose()`):** All delegates on that `RenderParagraph` / `RenderEditable` are disposed immediately.

Each disposed delegate runs a strict 3-step teardown:
1. `delegate.detachPainters()` — removes `markNeedsPaint` listeners from `backgroundPainter` and `foregroundPainter`.
2. `plugin.didRemoveText(delegate)` *(if `didAddText` had fired)* — runs **before** `dispose()` so the plugin can evict `delegate` from its internal collections without leaking memory.
3. `delegate.dispose()` — sets `isDisposed = true` (canceling any pending post-layout callback), clears painter references, and disposes the underlying `ChangeNotifier`.
