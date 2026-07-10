# Implementation Plan — Strip & Player Navigation Performance

> **Persists across sessions.** Written 2026-07-10 from a verified 3-agent performance audit
> (code audit + AVFoundation research + SwiftUI research; every finding below was re-verified
> against source by the planning session — file:line references are confirmed, not guesses).
> Regenerate when wrong rather than patching.

## Goal
Make thumbnail-strip and player navigation feel snappier by eliminating the SwiftUI
invalidation storms (whole-grid re-evaluation at 30 Hz + 256×/batch) and adopting the
canonical AVPlayer seek-coalescing pattern — no visual or behavioral changes.

## Acceptance Criteria
- [ ] During playback/shuttle, the grid's cells no longer re-evaluate on every 1/30 s time tick (verify: Instruments SwiftUI template or CPU sampling — see Wave 0 baseline vs Wave 4 re-measure)
- [ ] A 256-thumbnail batch fill causes ≤ ~10 grid invalidations, not 256
- [ ] Held arrow-key navigation never stacks seeks (at most one in flight; latest target wins)
- [ ] **NEW (found in Wave 0):** the strip auto-scrolls to keep the active cell visible during ordinary continuous playback, not just on seeks — the border must never walk off-screen while playing
- [ ] All existing behavior unchanged: border tracks playhead (no off-by-one), timecode ticks, seek auto-scroll centers, ⌘-click captures, M/Q capture, J/K/L shuttle, zoom paths, pinned dots
- [ ] Clean build, zero SFV-code warnings under `SWIFT_STRICT_CONCURRENCY=complete`

## Background — verified findings (2026-07-10)

| # | Finding | Evidence | Sev |
|---|---------|----------|-----|
| F1 | Whole strip body re-evals at 30 Hz (playback) via `currentTime` `@State`; each pass rebuilds the full-clip `times` array **3×** (`activeIndex` reads it twice + `ForEach` once); scroll-geometry transform rebuilds it again per scroll tick just for `.count` | `ThumbnailStripView.swift:45,192-193,334,458-467,478-481`; `StripModel.swift:70-82` | HIGH |
| F2 | `cacheVersion &+= 1` per streamed image inside the `for await` loop → up to 256 full-grid invalidations per batch; per-cell `.onChange(of: cacheVersion)` amplifies to visibleCells × images redundant cache lookups | `StripModel.swift:197`; `ThumbnailCellView.swift:59` | HIGH |
| F3 | Every navigation seek is `.zero`-tolerance fire-and-forget, no coalescing; key auto-repeat stacks max-cost seeks (Apple QA1820 names this exact failure) | `ThumbnailStripView.swift:177-181,201-205,454` | MED-HIGH |
| F4 | Fresh `AVAssetImageGenerator` per render batch → decoder session teardown/renegotiation on every scroll/zoom settle | `ThumbnailRenderer.swift:31-36` | MED |
| F5 | Thumbnail tolerance flips to `.zero` at density ≥ 5 — priciest decode mode exactly when request volume peaks (WWDC22 #110379 recommends wide tolerances for thumbnails) | `StripModel.swift:95-97` | LOW-MED |
| F6 | Small wins: per-cell `onModifierKeysChanged` (one global-⌘ observer per visible cell; `NSEvent.modifierFlags` check at `ThumbnailCellView.swift:69` already covers the tap path); `Array(times.enumerated())` alloc; string `cellIdentity` | `ThumbnailCellView.swift:65-67,85`; `ThumbnailStripView.swift:193` | LOW |

**Already correct — do NOT "fix":** `maximumSize` (2× bucket width, `ThumbnailRenderer.swift:34`);
decode off-MainActor; `Image(decorative: CGImage)` in cells; 256 in-flight cap + center-priority;
viewport-scoped `prefetchRange`; `cancelAllCGImageGeneration()` in the cancellation handler; the
80 ms scroll/magnify debounce and 150 ms seek-auto-scroll debounce; NSCache cost accounting.
Ruled out: `AVSampleBufferGenerator`, `AVPlayerVideoOutput` (scope mismatch — not thumbnail APIs).

**Corrected agent claim:** "keyboard nav bypasses the 80 ms debounce" is *unconfirmed* — animated
`proxy.scrollTo` likely reports the `.animating` scroll phase, which sets `isScrolling` and engages
the debounce. Wave 3.2 settles it empirically before any code is written for it.

---

## Load-bearing design decisions (read before executing)

1. **No strip-level `@State` for raw time.** A `@State` write invalidates the *owning view's whole
   body* regardless of what body reads. So the fix for F1 is not "read `currentTime` less" — it's
   that the strip stops *storing* it. The periodic observer keeps the previous time in a local
   `var` captured by the observer closure; it writes only two `@State`s, both rare:
   `activeIndex: Int` (written **only when the derived index changes**) and `seekScrollTarget`
   (only on >0.5 s jumps, existing debounce logic unchanged). The 30 Hz timecode readout moves
   into a leaf view with its own observer (precedent: `LeftPaneView` already isolates its
   timecode via `TimelineView(.periodic)` — same idea, observer flavor).
2. **Index-based time generation.** Replace the accumulating `while t <= upper { t += step }`
   loop with `(0...count).map { CMTime(seconds: Double($0) / density, ...) }`. Kills FP drift,
   makes `times[i] == i/density` exact (so `activeIndex = round(seconds × density)` is exact),
   and makes `thumbnailCount` closed-form. Side effect: cache keys (timeMillis) shift slightly
   vs the drifted values → session cache re-fills once. Acceptable; cache is per-session.
3. **Generator reuse has a cancellation race the current code accidentally avoids.** Today each
   batch owns a private generator, so a *stale* stream's `onTermination → cancelAllCGImageGeneration()`
   can only kill its own batch. With one shared generator, a late-firing termination from batch N
   would cancel batch N+1's decodes. **Guard required:** renderer keeps a monotonically increasing
   `batchID`; the `onCancel`/`onTermination` closure captures its own ID and only calls
   `cancelAllCGImageGeneration()` if `capturedID == currentBatchID`. Recreate the generator only
   when the width bucket changes (tolerance is mutable; safe to update between batches because
   `scheduleRender` cancels the prior consuming task synchronously before starting the next).
   `ThumbnailRenderer` becomes a `@MainActor final class` (currently a struct) — it's created and
   called only from `StripModel` (`@MainActor`), so no new Sendable surface.
4. **`.equatable()` on `ThumbnailCellView` must include `cacheVersion` in `==`.** Closure props
   defeat SwiftUI's reflection diff (closures compare as always-changed), so without `Equatable`
   every parent body pass re-bodies every visible cell. Custom `==` over
   `(timeMillis, widthBucket, displaySize, cacheVersion, manualPinned)` — *excluding* the closures —
   restores skipping. `cacheVersion` **must** stay in `==`: if equal-compare skips the body, the
   `.onChange(of: cacheVersion)` never sees the new value and images stop refreshing. With F2's
   throttling, version bumps ≤ ~10/s during a fill — that's the intended refresh signal.
5. **Border overlay offset math must match LazyVGrid's real layout.** Single border rectangle in a
   `ZStack(alignment: .topLeading)` *inside* the ScrollView content (so it scrolls with the grid):
   `row = activeIndex / cellsPerRow`, `col = activeIndex % cellsPerRow`,
   `x = 8 + col×(cellW+1)`, `y = 4 + row×(cellH+1)` — constants are the grid's `.padding(.horizontal, 8)`
   / `.padding(.vertical, 4)` and 1 pt spacing. `cellsPerRow` uses the **same formula** the ↑/↓
   arrow nav already trusts (`max(1, Int((width − 16) / (cellW + 1)))`, `ThumbnailStripView.swift:329`)
   — if the border ever misaligns, both are wrong together and the smoke test catches it.
6. **Seek coalescing (QA1820 chase-latest):** small `@MainActor final class SeekCoalescer` —
   `request(_ time: CMTime, on player: AVPlayer)` stores `latestTarget`; if none in flight, issues
   `seek(to:toleranceBefore:.zero,toleranceAfter:.zero,completionHandler:)`; on completion, if a
   newer target arrived, re-issues; intermediate targets are dropped. Keep `.zero` tolerance —
   coalescing alone fixes the stacking, and loose tolerance risks the landed frame rounding to a
   *different* cell than the one navigated to (border off-by-one regression — the exact bug fixed
   on 2026-05-27). Do **not** loosen navigation-seek tolerance.
7. **F5 thumbnail tolerance:** replace the hard `.zero`-at-density≥5 with half the inter-thumbnail
   gap: `CMTime(seconds: 0.5 / density, preferredTimescale: 600)` at every density. Windows of
   adjacent targets touch but don't overlap → cells stay distinct. (This is generator tolerance
   for *strip thumbnails* only — export/extraction tolerances are untouched.)

---

## Tasks

### Wave 0 — Baseline (no code; do FIRST, results go in Execution Log)
- [x] **0.1**: Measure baseline CPU → record numbers in this file
  - Build + launch current `main` (this Mac: ad-hoc sign, `CODE_SIGN_IDENTITY="-"`), load a long
    test clip (the 4K X-H2S MOV from Wave D works), then sample
    `ps -p <PID> -o %cpu` at 1 Hz for ~30 s in each state: (a) playback 1× default zoom,
    (b) playback 1× max zoom, (c) J/K/L shuttle 4×, (d) held → arrow repeat ~10 s, (e) zoom
    1→12 transition (batch fill)
  - Success: five numbers written into Execution Log below
  - Backpressure: none (measurement)

### Wave 1 — Model + renderer (no view changes; app behaves identically)
- [ ] **1.1**: Memoize thumbnail times + closed-form count → `Thumbnail/StripModel.swift`
  - Index-based generation (decision 2); memoized full-duration array invalidated only when
    `density` changes (`@ObservationIgnored private var cachedTimes: (density: Double, times: [CMTime])?`);
    new `var thumbnailCount: Int` (closed-form, no array); `thumbnailTimes(in:)` for the prefetch
    range becomes an index-range slice of the memoized array
  - Success: no `while t <= upper` loop remains; `scheduleRender` + view share one array instance
  - Backpressure: clean build; app runs, grid populates at every zoom level
- [ ] **1.2**: Throttle `cacheVersion` → `Thumbnail/StripModel.swift:190-198`
  - Inside the `for await` loop bump at most every ~100 ms (`ContinuousClock` guard); always bump
    once after the loop completes so the final image is never stranded
  - Success: full zoom-in batch fill produces ≤ ~10 bumps (add a temporary print to count, then remove)
  - Backpressure: clean build; thumbnails still appear progressively during a fill
- [ ] **1.3**: Half-gap tolerance → `Thumbnail/StripModel.swift:95-97` (decision 7)
  - Success: `tolerance` never returns `.zero`; adjacent cells still visually distinct at zoom 4–6
  - Backpressure: clean build; visual check at density ≈ 5
- [ ] **1.4**: Generator reuse with batch-ID guard → `Thumbnail/ThumbnailRenderer.swift` (decision 3)
  - Struct → `@MainActor final class`; keep generator across batches; recreate on bucket change;
    guarded `cancelAllCGImageGeneration()`
  - Success: rapid scroll-settle-scroll-settle does not cancel the *new* batch (thumbs fill in);
    fast pinch on a 5-min clip still does NOT saturate VTDecoderXPCService (regression guard for
    the 2026-05-28 fix)
  - Backpressure: clean build under strict concurrency (actor annotation is the risky part)

### Wave 2 — View restructuring (depends on 1.1; one file pass over strip + cell)
- [ ] **2.1**: Rework time observation → `Thumbnail/ThumbnailStripView.swift:475-505` (decision 1)
  - Delete `@State currentTime`; observer keeps prev-time in a local var; write `@State activeIndex`
    only on change; keep the >0.5 s seek-detection + 150 ms debounce exactly as-is
  - **Bundled bug fix (found in Wave 0 baseline sampling):** ordinary continuous playback never
    auto-scrolls — only the >0.5 s seek-detection branch drives `scrollTo`, so the active cell walks
    off-screen during plain playback at any zoom (border "vanishes"). While rewiring `activeIndex`
    writes, also trigger a (coalesced/debounced — do not re-introduce a per-tick storm) `scrollTo`
    whenever the new `activeIndex` falls outside the currently visible row range, so continuous
    playback keeps the active cell in view without needing a >0.5 s jump
  - Success: paused + idle → zero body evaluations; playback at default zoom → grid body evals ≈
    density/s (~1.5), not 30/s; **active-cell border stays visible throughout 30s+ of continuous
    playback at every zoom level (default and max), auto-scrolling as needed**
  - Backpressure: clean build; border still tracks playhead during playback and after seeks; visible
    at max zoom too (regression check for the Wave 0 finding)
- [ ] **2.2**: Extract transport bar into a leaf view (same file) with its own periodic observer +
  local `currentTime`/`isPlaying`; parent passes `model`, `player`, play/pause closure, and the
  `FocusState` binding for focus re-claim
  - Success: timecode/frame readout ticks at 30 Hz while *only* the bar's body re-evaluates
  - Backpressure: clean build; Space/K/L/J still work (strip handlers call the same closure)
- [ ] **2.3**: Extract active-cell border to a single positioned overlay (decision 5); remove the
  per-cell `.overlay(strokeBorder…)` (`:215-221`)
  - Success: border pixel-identical at zoom 1 / 6 / 12 and at two window widths; no off-by-one
  - Backpressure: clean build; visual check vs pre-change screenshots
- [ ] **2.4**: Cell cleanup → `Thumbnail/ThumbnailCellView.swift`
  - Add `Equatable` + `.equatable()` (decision 4 — `cacheVersion` stays in `==`); drop
    `isCommandHeld` + `onModifierKeysChanged` (keep the `NSEvent.modifierFlags` check);
    `cellIdentity` string → small `Equatable` struct; drop the no-op `let _ = cacheVersion`;
    in the strip, `ForEach(times.indices, id: \.self)` instead of `Array(times.enumerated())`,
    and the scroll-geometry transform uses `model.thumbnailCount` (no array access)
  - Success: ⌘-click capture and plain-click seek both still work; pinned dots update on capture
  - Backpressure: clean build; interactive check of both click paths

### Wave 3 — Seek path
- [ ] **3.1**: `SeekCoalescer` (decision 6) → new small type (suggest `Thumbnail/SeekCoalescer.swift`
  — xcodegen regen REQUIRED for new files, see decisions.md) + route the three call sites
  (`onTap`, `jump(by:)`, `navigate(by:)`) through it
  - Success: holding → for 5 s then releasing lands on the final target promptly (no queued
    catch-up seeking); single clicks behave exactly as before
  - Backpressure: clean build; held-key test
- [ ] **3.2**: Settle the debounce-bypass question empirically (temporary logging in
  `onScrollPhaseChange` + `scheduleRender`, held-arrow test): does animated `scrollTo` set
  `isScrolling` via the `.animating` phase? If yes → close as no-op. If no → route seek-driven
  visible-range changes through the same 80 ms debounce (small change in `StripModel.scheduleRender`
  gating). Remove the logging either way.
  - Success: question answered + logged here; code only if answer is "no"

### Wave 4 — Verification
- [ ] **4.1**: Full manual smoke matrix (single session, one pass): playback, 4× shuttle fwd/rev,
  held arrows all four directions, ⌥/⇧ jumps, click-seek, ⌘-click capture, M/Q capture, all four
  zoom paths (pinch / keys / ⌘-wheel / slider), seek auto-scroll centering, transport readouts,
  pinned dots, Unload + reload, **continuous-playback auto-follow at default AND max zoom for 30s+
  (Wave 0 bug fix — border must never scroll off-screen)**
- [ ] **4.2**: Re-run the Wave 0 CPU sampling, same clip + states; record before/after in the
  Execution Log. Expect (a) to drop the most. **State (b) is expected to go UP, not down** — once
  auto-follow is fixed (Wave 2.1), max-zoom playback will actually keep decoding new cells
  continuously instead of stalling on a static off-screen view, so (b) becomes a true measurement
  for the first time; compare it against (a)/(c), not against Wave 0's artifact-depressed 68.1%.
- [ ] **4.3** *(optional)*: Instruments SwiftUI template — confirm body-eval counts collapsed
- [ ] **4.4**: Update `docs/decisions.md` (§ new: strip-performance pass — the @State-ownership
  pattern, equatable-with-cacheVersion trap, generator batch-ID guard) + PROJECT_STATE + session log

---

## Operational Learnings
<!-- Add during execution -->
- (2026-07-10, from planning) `@State` invalidation is declaration-scoped, not read-scoped — moving
  a hot value out of a big view's `@State` is worth more than optimizing reads of it.
- (2026-07-10, Wave 0) **Live-driven measurement, not automation.** Attempted to drive Wave 0 via
  `osascript`/System Events keystrokes; the user was concurrently interacting with the app by hand
  (playhead moved between two screenshots with no automation in between), so keystroke automation
  and live human input would have collided. Switched to: user performs each state on cue, I sample
  `ps -p <PID> -o %cpu=` at 1 Hz in the background. Works fine for this kind of measurement — no
  code/tooling needed beyond `ps`.
- (2026-07-10, Wave 0) **Found during (b) sampling, root-caused — real bug, not measurement noise:
  the thumbnail strip never auto-scrolls to follow ordinary continuous playback, at any zoom level.**
  `observePlayerTime()` (`ThumbnailStripView.swift:475-505`) only sets `seekScrollTarget` (which
  drives `proxy.scrollTo`) when a tick-to-tick delta exceeds 0.5 s — the seek-detection heuristic.
  Regular playback advances ~1/30 s per tick (more at shuttle speed, still well under 0.5 s in
  practice), so that branch never fires during plain playback. The active-cell border *does* keep
  tracking `activeIndex` correctly every tick — it just walks off-screen once playback carries it
  past the visible viewport, which reads as "the highlight vanishes." Confirmed zoom-independent
  (user report). This also explains the (a)/(b) CPU gap below: at max zoom the viewport covers far
  fewer seconds, so the active cell exits the viewport almost immediately, leaving most of state
  (b)'s 30 s window sampling a static view (no new prefetch/decode) — so (b)'s 68.1% is not a true
  max-zoom-playback number, more like a "playback that's already scrolled out of view" number.
  **Decision (2026-07-10, user): fold the fix into Wave 2.1**, which already rewrites this exact
  observer/activeIndex-wiring (decision 1) — patching it now would just get overwritten. See Wave 2.1
  and the new Acceptance Criterion below.

## Blocked Tasks
(none)

---

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 0 | 2026-07-10 | 2026-07-10 | baseline (user-driven live, `ps` @ 1Hz on this Mac; clip: `~/Movies/PenumbraSmoke/mp4-long-perf.mp4`, 1280×720 H.264, 30 min): (a) playback/default-zoom avg **91.8%** (range 28–105, n=30s) · (b) playback/max-zoom avg **68.1%** (range 65–72, n=30s) — **unreliable, see Operational Learnings scroll-bug note** · (c) JKL-shuttle-4×/default-zoom avg **104.7%** (range 103.6–105.8, n=30s) · (d) held-arrow-repeat avg **72.3%** (range 68.5–80, n=10s) · (e) zoom-1→12-transition: pre-drag idle avg 14.6% (n=10s) → during-fill avg **120.9%**, peak **188.1%** (n=20s) |
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | after: (a)__% (b)__% (c)__% (d)__% (e)__% |

---
*Delete this file when all tasks complete. Archive to docs/sessions/_archive/ per repo convention.*
