# Summary & Prioritization of Comments on `flutter/rfc#35`

**PR:** [Add Design Doc for Composable Text Plugins in Flutter (`flutter/rfc#35`)](https://github.com/flutter/rfc/pull/35)

---

## Part 1: Complete Summary of Comments

### 1. General PR Comments (Resolved)

* **Demo App Focus Bug (`@fanchou`)** — [Comment](https://github.com/flutter/rfc/pull/35#issuecomment-6183551737)
  * Praised the composable approach and demo (highlighting how search and annotations work across existing text widgets without replacing them).
  * Noted a bug in the demo app where pressing `Enter` in the search `TextField` advances to the next match once and then loses focus (due to `TextField`'s default `onEditingComplete` behavior). Suggested setting `onEditingComplete: () {}`.
  * **`@hannah-hyj`** [replied](https://github.com/flutter/rfc/pull/35#issuecomment-6202468156) confirming the demo fix.

### 2. Inline Review Comments by `@chunhtai` ([Review](https://github.com/flutter/rfc/pull/35#pullrequestreview-5550703191))

#### Lifecycle & Layout Timing
1. **`didAddText` / `didUpdateText` called before layout** ([r4296904756](https://github.com/flutter/rfc/pull/35#discussion_r4296904756), [r4296977178](https://github.com/flutter/rfc/pull/35#discussion_r4296977178), [r4297852209](https://github.com/flutter/rfc/pull/35#discussion_r4297852209))
   * Questioned how developers should use `didAddText` / `didUpdateText` when text has not been laid out yet, since geometry APIs are unavailable or could crash.
   * Asked whether these callbacks should only be triggered *after* layout is complete, noting that if the delegate lacks layout at callback time, firing the callback before layout seems less useful to the caller.
2. **Synchronous geometry queries during `didAddText`** ([r4297160957](https://github.com/flutter/rfc/pull/35#discussion_r4297160957))
   * On `SearchInPagePlugin` calling `_rebuildMatches()` inside `didAddText` / `didUpdateText`: noted that if synchronous logic calls `getBoxesForSelection` before layout, it could force layout with old constraints.

#### API Naming & Ergonomics
3. **`ContentAccessIntent` naming** ([r4296892818](https://github.com/flutter/rfc/pull/35#discussion_r4296892818), [r4297616484](https://github.com/flutter/rfc/pull/35#discussion_r4297616484))
   * Suggested clearer names than `highlight` / `scan` (e.g., `onScreen` / `includeOffScreen`, or a `bool` if there won't be a third option).
   * Advised avoiding the `Intent` suffix so it isn't confused with Flutter's keyboard shortcut `Intent` system.
4. **Opinionated API for `TextSpan` text extraction & placeholders** ([r4297888894](https://github.com/flutter/rfc/pull/35#discussion_r4297888894), [r4297898099](https://github.com/flutter/rfc/pull/35#discussion_r4297898099))
   * On Section 7.3 (warning plugin authors to pass `includeSemanticsLabels: false` and handle `includePlaceholders` / `placeholderRanges`): asked if there is *any* use case where a text plugin wants to process semantics labels, and suggested providing an opinionated API directly on `TextDelegate` rather than making plugin authors handle `toPlainText` flags manually.
5. **Deduplicating plugins across nested scopes** ([r4297930581](https://github.com/flutter/rfc/pull/35#discussion_r4297930581))
   * On Section 7.7 (duplicate plugin instances in nested `TextPluginScope`s): noted that other Flutter systems (like `Actions` / `Shortcuts`) deduplicate by `Type` (e.g., using a `<Type, Factory>` map in the inherited widget rather than a raw list).

#### Painting & Ordering
6. **Multiple painters on `TextDelegate`** ([r4297197815](https://github.com/flutter/rfc/pull/35#discussion_r4297197815))
   * Asked whether `backgroundPainter` (and `foregroundPainter`) should be a list in case multiple plugins want to inject painters into the delegate.
7. **Plugin ordering independent of widget tree nesting** ([r4297724487](https://github.com/flutter/rfc/pull/35#discussion_r4297724487))
   * On Section 5.2.2.1 (paint order between `SelectionArea` and inner plugins): wondered if `TextPlugin` should have an explicit ordering mechanism so paint/event order isn't locked strictly to widget tree nesting order.

#### Performance & Offscreen Rendering
8. **Full re-evaluation on single text change in `SearchInPagePlugin`** ([r4297149464](https://github.com/flutter/rfc/pull/35#discussion_r4297149464))
   * Noted that `_rebuildMatches()` re-evaluates and sorts all delegates when a single text changes, which could be a performance issue for large documents.
9. **Document-order LCA sorting performance** ([r4297782876](https://github.com/flutter/rfc/pull/35#discussion_r4297782876))
   * On `TextDelegate.compareTo` (Section 5.1.2): noted we should keep an eye on the performance impact of render-tree LCA traversal.
10. **`OffscreenRenderingPolicy.eager` cache extent & main-thread cost** ([r4297656342](https://github.com/flutter/rfc/pull/35#discussion_r4297656342), [r4297697855](https://github.com/flutter/rfc/pull/35#discussion_r4297697855))
    * Asked why the cache extent isn't configurable directly inside `OffscreenRenderingPolicy` instead of hardcoding `ScrollCacheExtent.pixels(1e9)`.
    * Raised concern that eagerly building an entire list could be very expensive and block the main thread, wondering if there is a way to avoid blocking the main thread.

#### Examples & Use Cases
11. **`SpoilerMaskPlugin` syntax characters (`||`)** ([r4297236275](https://github.com/flutter/rfc/pull/35#discussion_r4297236275))
    * Asked whether the plugin can prevent the `||` delimiters from being painted after the spoiler is revealed, or if it has to paint over them with an opaque cover.
12. **`LinkifyPlugin` hover UI** ([r4297572438](https://github.com/flutter/rfc/pull/35#discussion_r4297572438))
    * Wondered if linkify use cases also need tooltips or popups on mouse hover.
13. **Example for non-text / custom `TextPainter` widgets** ([r4297809096](https://github.com/flutter/rfc/pull/35#discussion_r4297809096), [r4297817749](https://github.com/flutter/rfc/pull/35#discussion_r4297817749))
    * On Section 6 (future directions / custom render objects): requested adding example code showing how a non-standard text widget (e.g., a custom widget using `TextPainter` directly) would integrate with `TextDelegate`.

---

## Part 2: Recommended Prioritization

### P0: Core Lifecycle & Architecture (Resolve First)
These comments challenge fundamental assumptions about **when callbacks fire** and **how offscreen content is materialized**. Answering or adjusting the design here may change the rest of the API and example code.

1. **`didAddText` / `didUpdateText` timing vs. Layout (#1, #2)**
   * **Why P0:** `@chunhtai` raised this in 4 separate comments ([r4296904756](https://github.com/flutter/rfc/pull/35#discussion_r4296904756), [r4296977178](https://github.com/flutter/rfc/pull/35#discussion_r4296977178), [r4297160957](https://github.com/flutter/rfc/pull/35#discussion_r4297160957), [r4297852209](https://github.com/flutter/rfc/pull/35#discussion_r4297852209)). It is his biggest concern.
   * **Action:** Decide whether:
     * **(Option A)** Move `didAddText` / `didUpdateText` (or introduce `didLayoutText`) to fire *after* `RenderParagraph.performLayout()`, when geometry is guaranteed to be valid; **or**
     * **(Option B)** Keep `didAddText` / `didUpdateText` pre-layout (for pure text scanning like `SearchInPagePlugin` match counting before paint, since painters themselves only call `getBoxesForSelection` *during paint* when layout is guaranteed), and clearly explain in the RFC *why* text-scanning happens pre-layout while geometry queries happen inside `TextDelegatePainter.paint` (or a post-layout callback).
2. **`OffscreenRenderingPolicy.eager` performance & configurability (#10)**
   * **Why P0:** Forcing `ScrollCacheExtent.pixels(1e9)` can freeze the main thread on large lists ([r4297656342](https://github.com/flutter/rfc/pull/35#discussion_r4297656342), [r4297697855](https://github.com/flutter/rfc/pull/35#discussion_r4297697855)).
   * **Action:**
     * Easy win: Parameterize the cache extent on the policy (e.g., `OffscreenRenderingPolicy.eager({double cacheExtent = ...})` or pass `ScrollCacheExtent` directly).
     * Address the main-thread concern in the doc (e.g., bounding cache extent, incremental/chunked pre-building, or clarifying when `eager` is appropriate vs. data-layer search).

### P1: Public API Surface & Ergonomics (Quick, High-Impact Decisions)
These directly affect public class/method signatures in `packages/flutter/lib/src/widgets/text_plugin.dart` and `packages/flutter/lib/src/rendering/text_plugin.dart`, and are straightforward to adopt.

3. **Rename `ContentAccessIntent` (#3)**
   * **Why P1:** Avoids collision/confusion with Flutter's `Intent` class for keyboard shortcuts ([r4296892818](https://github.com/flutter/rfc/pull/35#discussion_r4296892818), [r4297616484](https://github.com/flutter/rfc/pull/35#discussion_r4297616484)).
   * **Action:** Rename to something like `bool includeOffscreen` or an enum without `Intent` (e.g., `TextVisibilityScope { onScreenOnly, includeOffscreen }`).
4. **Provide an opinionated plain-text / placeholder helper on `TextDelegate` (#4)**
   * **Why P1:** Instead of warning plugin authors in Section 7.3 to manually pass `includeSemanticsLabels: false` and compute `placeholderRanges` ([r4297888894](https://github.com/flutter/rfc/pull/35#discussion_r4297888894), [r4297898099](https://github.com/flutter/rfc/pull/35#discussion_r4297898099)), exposing a helper property/method on `TextDelegate` (e.g., `String get plainText` that defaults to `includeSemanticsLabels: false, includePlaceholders: true`) eliminates a major footgun.
5. **Deduplicating plugins across nested `TextPluginScope`s (#5)**
   * **Why P1:** Aligns `TextPluginScope` with `Actions` / `Shortcuts` ([r4297930581](https://github.com/flutter/rfc/pull/35#discussion_r4297930581)) or clarifies why multiple instances of the same type might or might not be allowed.
6. **Plugin ordering vs. widget tree nesting (#7)**
   * **Why P1:** Deciding whether paint/hit-test order is strictly determined by `TextPluginScope` nesting/list order or an optional `priority`/`order` property ([r4297724487](https://github.com/flutter/rfc/pull/35#discussion_r4297724487)).

### P2: Clarifications on Existing Design & Code Examples
These don't necessarily require changing your core architecture—many are places where the RFC text or sample code caused a misunderstanding that can be fixed by tightening the example or adding a short clarification.

7. **Clarify 1-to-1 `TextDelegate` per `(RenderParagraph, TextPlugin)` pair (#6)**
   * **Why P2:** `@chunhtai` asked if `backgroundPainter` should be a list so multiple plugins can inject painters ([r4297197815](https://github.com/flutter/rfc/pull/35#discussion_r4297197815)). Since each plugin already gets its own dedicated `TextDelegate` instance per `RenderParagraph`, multiple plugins *don't* overwrite each other's painter.
   * **Action:** Reply to clarify the 1-to-1 `(RenderParagraph, TextPlugin) -> TextDelegate` cardinality, and make that relationship more prominent near the `TextDelegate` class definition.
8. **Optimize `SearchInPagePlugin` example for single-delegate updates (#8)**
   * **Why P2:** In the example code, `didUpdateText(delegate)` re-scans and re-sorts *all* delegates ([r4297149464](https://github.com/flutter/rfc/pull/35#discussion_r4297149464)).
   * **Action:** Update the `SearchInPagePlugin` snippet in the RFC so `didUpdateText(delegate)` only updates matches for the changed `delegate` instead of rebuilding every delegate's matches.
9. **Add a custom `TextPainter` / non-`Text` widget example in Section 6 (#13)**
   * **Why P2:** Explicitly requested by reviewer ([r4297809096](https://github.com/flutter/rfc/pull/35#discussion_r4297809096), [r4297817749](https://github.com/flutter/rfc/pull/35#discussion_r4297817749)) to prove `TextDelegate` isn't tightly coupled to `RenderParagraph`.
   * **Action:** Add a short 15–20 line snippet in Section 6 showing a custom `RenderBox` with a `TextPainter` implementing/providing a `TextDelegate`.

### P3: Minor Discussion / Non-Blocking Notes
These are conversational questions or reminders that only need a brief reply or a 1-sentence note in the doc.

10. **LCA sorting performance note (#9)** ([r4297782876](https://github.com/flutter/rfc/pull/35#discussion_r4297782876)) — Acknowledge and note complexity / caching strategies in Section 5.1.2.
11. **`SpoilerMaskPlugin` delimiter (`||`) rendering (#11)** ([r4297236275](https://github.com/flutter/rfc/pull/35#discussion_r4297236275)) — Clarify that plugins are non-mutating overlays (so syntax markers in raw strings remain unless hidden via styling/custom span or opaque cover).
12. **`LinkifyPlugin` hover tooltip/popup (#12)** ([r4297572438](https://github.com/flutter/rfc/pull/35#discussion_r4297572438)) — Reply that `handleEvent` (`PointerEnterEvent` / `PointerHoverEvent` / `PointerExitEvent`) + `getBoxesForSelection` + `OverlayPortal`/`OverlayEntry` enables hover popups/tooltips without needing extra core API.
