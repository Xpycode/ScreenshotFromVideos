# Implementation Plan — Strip & Player Navigation Performance

> **Persists across sessions.** Written 2026-07-10 from a verified 3-agent performance audit
> (code audit + AVFoundation research + SwiftUI research; every finding below was re-verified
> against source by the planning session — file:line references are confirmed, not guesses).
> Regenerate when wrong rather than patching.

## Closeout — November 6, 2026

**Complete: 14 tasks completed; task 1.4 attempted and reverted, with fresh generators retained intentionally.** No open performance acceptance gates. Task 4.4 records decisions 11–15, the independent closeout review and final evidence limits. The related accepted grid/navigation/timecode/pin-dot follow-ups are included in the checkpoint; the separate compact-footer change remains uncommitted with its own verification gap.

Evidence is archived in place under `docs/validation/` to preserve historical paths and manifests. The [archive evidence index](2026-11-06_STRIP_PLAYER_PERFORMANCE_EVIDENCE.md) maps retained evidence and its limits. Local checkpoint subject: **Complete strip and player performance pass with validated navigation fixes** (tasks 2.1–2.4 follow-ups, 3.1–3.2, 4.1–4.4). No push or merge is part of this closeout.

## Goal
Make thumbnail-strip and player navigation feel snappier by eliminating the SwiftUI
invalidation storms (whole-grid re-evaluation at 30 Hz + 256×/batch) and adopting the
canonical AVPlayer seek-coalescing pattern — no visual or behavioral changes.

## Acceptance Criteria
- [x] During playback/shuttle, the grid's cells no longer re-evaluate on every 1/30 s time tick (accepted November 6: retained playback trace records 360 transport updates and zero named outer-strip/cell updates over 12 seconds; current source review confirms shuttle shares the isolated observation path. Shuttle body counts and the final artifact were not separately profiled; CPU samples alone do not establish body counts.)
- [x] **Revised with user approval 2026-11-02:** within each render batch, publish the first stored thumbnail immediately; subsequent in-loop cache refresh signals are at least 100 ms apart. On completion/cancellation, publish one final signal only if stored images remain unpublished. Empty batches publish none. This is not a global rate limit or a ten-total batch cap. Source inspection, independent review, historical 17–18-signal measurement and accepted progressive-fill behavior support this policy; no fresh grid-body count is claimed. See [closeout evidence](../../validation/performance-closeout-2026-11-02/README.md).
- [x] Held arrow-key navigation never stacks seeks (at most one in flight; latest target wins)
- [x] **NEW (found in Wave 0):** the strip auto-scrolls to keep the active cell visible during ordinary continuous playback, not just on seeks — the border must never walk off-screen while playing
- [x] All existing behavior unchanged: border tracks playhead (no off-by-one), timecode ticks, seek auto-scroll centers, ⌘-click captures, M/Q capture, J/K/L shuttle, zoom paths, pinned dots
- [x] Clean build, zero SFV-code warnings under `SWIFT_STRICT_CONCURRENCY=complete`

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
3. **[SUPERSEDED 2026-07-19 — the batch-ID guard does not work. See Operational Learnings; task 1.4
   was reverted. Kept for context.]** **Generator reuse has a cancellation race the current code accidentally avoids.** Today each
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

### Wave 1 — Model + renderer (no view changes; app behaves identically) — **CLOSED 2026-07-19**
- [x] **1.1**: Memoize thumbnail times + closed-form count → `Thumbnail/StripModel.swift`
  - Index-based generation (decision 2); memoized full-duration array invalidated only when
    `density` changes (`@ObservationIgnored private var cachedTimes: (density: Double, times: [CMTime])?`);
    new `var thumbnailCount: Int` (closed-form, no array); `thumbnailTimes(in:)` for the prefetch
    range becomes an index-range slice of the memoized array
  - Success: no `while t <= upper` loop remains; `scheduleRender` + view share one array instance
  - Backpressure: clean build; app runs, grid populates at every zoom level
- [x] **1.2**: Throttle `cacheVersion` → `Thumbnail/StripModel.swift:190-198`
  - Inside the `for await` loop bump at most every ~100 ms (`ContinuousClock` guard); always bump
    once after the loop completes so the final image is never stranded
  - Success (revised with user approval 2026-11-02): immediate first publication, subsequent streaming publications at least 100 ms apart within a batch, and a pending-only completion/cancellation flush. Original approximately ten-total criterion was not met; historical fill measured 17–18 bumps.
  - Backpressure: clean build; thumbnails still appear progressively during a fill
- [x] **1.3**: Half-gap tolerance → `Thumbnail/StripModel.swift:95-97` (decision 7)
  - Success: `tolerance` never returns `.zero`; adjacent cells still visually distinct at zoom 4–6
  - Backpressure: clean build; visual check at density ≈ 5
- [~] **1.4**: Generator reuse with batch-ID guard → `Thumbnail/ThumbnailRenderer.swift` (decision 3)
  - **ATTEMPTED AND REVERTED 2026-07-19** (`c0c8609`, reverted by `79a4d5a`). Decision 3 above is
    **wrong** — see Operational Learnings. Do not retry without the serialisation described there.

### Wave 2 — View restructuring (depends on 1.1; one file pass over strip + cell)

**2026-10-29: Wave 2 complete; tasks 2.1–2.4 accepted (8/15 complete; one reverted).** Startup/zoom, capture, transport, navigation, timecodes, border zoom/two-width matrix, unload/reload and sustained playback/follow user-passed. Default/max playback CPU averages: 35.9%/33.5% over 30 seconds each. SwiftUI playback stable window: transport body-accessor 30/s, zero outer strip/cell body-accessor events; paused stable window: zero named outer custom-view body-accessor events. Profiling scope/late-attach limitations and raw/reduced evidence in [performance validation](../../validation/performance-2026-10-29/README.md). Minimum-width footer fix built/launched and narrow layout user-passed; [window evidence](../../validation/window-width-2026-10-29/README.md). Border uses indexed actual-cell bounds; shared fixed columns and parent-sized viewport retained. Wave 3 not started.

- [x] **2.1**: Rework time observation → `Thumbnail/ThumbnailStripView.swift:475-505` (decision 1)
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
- **Acceptance finding (2026-10-28):** transport keys and Play/Pause icon now user-passed after the subscription fix. Task 2.2 measured view-update verification passed 2026-10-29; direction-specific icons are not currently implemented.
- [x] **2.2**: Extract transport bar into a leaf view (same file) with its own periodic observer +
  local `currentTime`/`isPlaying`; parent passes `model`, `player`, play/pause closure, and the
  `FocusState` binding for focus re-claim
  - Success: timecode/frame readout ticks at 30 Hz while *only* the bar's body re-evaluates
  - Backpressure: clean build; Space/K/L/J still work (strip handlers call the same closure)
- [x] **2.3**: Extract active-cell border to a single positioned overlay (decision 5); remove the
  per-cell `.overlay(strokeBorder…)` (`:215-221`)
  - Success: border pixel-identical at zoom 1 / 6 / 12 and at two window widths; no off-by-one
  - Backpressure: clean build; visual check vs pre-change screenshots
- [x] **2.4**: Cell cleanup → `Thumbnail/ThumbnailCellView.swift`
  - Add `Equatable` + `.equatable()` (decision 4 — `cacheVersion` stays in `==`); drop
    `isCommandHeld` + `onModifierKeysChanged` (keep the `NSEvent.modifierFlags` check);
    `cellIdentity` string → small `Equatable` struct; drop the no-op `let _ = cacheVersion`;
    in the strip, `ForEach(times.indices, id: \.self)` instead of `Array(times.enumerated())`,
    and the scroll-geometry transform uses `model.thumbnailCount` (no array access)
  - Success: ⌘-click capture and plain-click seek both still work; pinned dots update on capture
  - Backpressure: clean build; interactive check of both click paths

### Wave 3 — Seek path

**2026-10-29: Wave 3 complete — tasks 3.1–3.2 accepted (10/15 complete; one reverted).** User passed held-arrow release, click/jump/capture and unload/reload batch. Trace: 31 animating phases all report isScrolling=true; all 293 scrolling schedules debounce=true. Task 3.2 closes as no-op. Temporary probe removed; final uninstrumented strict-concurrency build passed and exact artifact launched/verified. See [Wave 3 validation](../../validation/seek-coalescing-2026-10-29/README.md).
- [x] **3.1**: `SeekCoalescer` (decision 6) → new small type (suggest `Thumbnail/SeekCoalescer.swift`
  — xcodegen regen REQUIRED for new files, see decisions.md) + route the three call sites
  (`onTap`, `jump(by:)`, `navigate(by:)`) through it
  - Success: holding → for 5 s then releasing lands on the final target promptly (no queued
    catch-up seeking); single clicks behave exactly as before
  - Backpressure: clean build; held-key test
- [x] **3.2**: Settle the debounce-bypass question empirically (temporary logging in
  `onScrollPhaseChange` + `scheduleRender`, held-arrow test): does animated `scrollTo` set
  `isScrolling` via the `.animating` phase? If yes → close as no-op. If no → route seek-driven
  visible-range changes through the same 80 ms debounce (small change in `StripModel.scheduleRender`
  gating). Remove the logging either way.
  - Success: question answered + logged here; code only if answer is "no"

### Wave 4 — Verification

**2026-10-29: incomplete — F6 blocked by a persistent black selected cell after paused zoom.** Serial coordinator ownership: one live app, user-driven states and dependent measurements; no independent task work to delegate. Final executable/source checksum verification and read-only PID/path verification passed. Finite final-artifact matrix and remaining CPU samples are pending (states a/b/c complete: 39.08%/53.403%/121.2% averages, 30 samples each; default follow user-passed) in [Wave 4 evidence](../../validation/final-verification-2026-10-29/README.md). Original batch-count criterion remains unresolved: Wave 1 measured 17–18 total bumps; implemented throttle is ~10/s, not ≤~10 per batch. The subsequent traced mismatch required the 2026-11-01 measured-demand fix; see below.
**2026-11-01 update:** measured cell bounds now drive demand and playback-follow rows; analytical offset only selects columns. Temporary trace hooks removed. Fresh-context implementation and independent review complete; headless regressions and complete-concurrency build pass. 4.1 complete: V1–V3 and remaining original manual matrix user-passed; 4.2/4.4 gates unchanged. [Fix, artifact and finite retest](../../validation/viewport-demand-2026-11-01/README.md). No scoped commit because of overlapping uncommitted Wave 2/3 integration; no push. Follow-up screenshot showed an isolated neighboring hole; unchanged production decode reproduced exact frame 49106 failure (11/12), fresh retry recovered it. Bounded one-retry renderer now delivers12/12 automatically; policy/cancellation tests, real fixture, independent review and strict build pass. Combined artifact `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app` was launched with explicit authorization; user then reported “pass” for the requested untouched paused-fill check. V1/paused-fill portion of F6 accepted; V2/V3 subsequently user-passed; user subsequently reported “all pass” for the remaining explicit F2–F7 batch. Task 4.1 accepted; historical CPU-state confirmation and batch-refresh criterion remain separate. 12/15 complete, one reverted.

- [x] **4.1**: Full manual smoke matrix (single session, one pass): playback, 4× shuttle fwd/rev,
  held arrows all four directions, ⌥/⇧ jumps, click-seek, ⌘-click capture, M/Q capture, all four
  zoom paths (pinch / keys / ⌘-wheel / slider), seek auto-scroll centering, transport readouts,
  pinned dots, Unload + reload, **continuous-playback auto-follow at default AND max zoom for 30s+
  (Wave 0 bug fix — border must never scroll off-screen)**
- [x] **4.2**: Re-run the Wave 0 CPU sampling, same clip + states; record before/after in the
  Execution Log. Expect (a) to drop the most. **State (b) is expected to go UP, not down** — once
  auto-follow is fixed (Wave 2.1), max-zoom playback will actually keep decoding new cells
  continuously instead of stalling on a static off-screen view, so (b) becomes a true measurement
  for the first time; compare it against (a)/(c), not against Wave 0's artifact-depressed 68.1%.
- [x] **4.3** *(optional; retained Wave 2 evidence, scoped limits in Wave 4 README)*: Instruments SwiftUI template — confirm body-eval counts collapsed
- [x] **4.4**: Update `docs/decisions.md` (§ new: strip-performance pass — the @State-ownership
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

- (2026-07-19, Wave 1) **The batch-ID guard of decision 3 is unsound — task 1.4 reverted.** Sharing
  one `AVAssetImageGenerator` broke rendering outright: 191 of 204 batches requested images and got
  **zero**, with zero decode failures (the stream just finished empty). `cancelAllCGImageGeneration()`
  is all-or-nothing per generator, so a stale batch's cancel poisons a newer batch's requests on the
  shared instance. The guard cannot prevent this: at the moment the stale batch cancels, the newer
  batch has *not yet called* `render()`, so the stale token is still current and the cancel proceeds.
  **Why it survived review:** `scheduleRender()` only sleeps 80 ms when `isScrolling || isMagnifying`.
  Scroll- and pinch-driven renders are debounced and appeared to work; the zoom **slider** and
  keyboard zoom are *not* debounced, call `render()` immediately, and broke. Any future attempt must
  serialise — a new batch must not touch the shared generator until the previous stream has fully
  terminated — and must be tested on the **non-debounced** path specifically.
- (2026-07-19, Wave 1) **Temporary instrumentation paid for itself twice.** A throwaway
  `print("batch of N images -> M bumps")` in `scheduleRender` is what revealed the 1.4 breakage
  (requested count ≫ 0, bumps == 1 ⇒ zero images delivered) *and* a second bug in 1.2's own fix:
  cancelling a batch terminates the `AsyncStream`, so `for await` exits with **zero iterations** and
  the in-loop `if Task.isCancelled { return }` guard never runs — an unconditional post-loop bump
  therefore fired a whole-grid invalidation for every cancelled batch (94 in one session while
  dragging the zoom slider). Fixed with a `pendingSinceBump` flag. Neither bug was visible from
  reading the code or from a clean build.
- (2026-07-19, Wave 1) **Same-file tasks cannot be parallel subagents.** 1.1/1.2/1.3 all target
  `StripModel.swift`; three agents would each read the pre-edit file and clobber each other. Split
  the wave by *write target*, not by task number.
- (2026-07-19, Wave 1) **Cache-key design flaw found during smoke, not yet fixed.** `density =
  pow(2, zoomLevel × 0.6)` is continuous, and thumbnail times are `i / density`, so *every* slider or
  pinch zoom position generates an entirely fresh set of `timeMillis` cache keys — near-100% miss
  rate. Width is already bucketed to 60/120/240; density is not. Quantising density to a ladder
  would let nearby zoom levels share decoded frames. Keyboard zoom (`zoomStep = 0.5`) already lands
  on repeatable densities and does hit cache. **Open question:** user reports zooming back out to 1.0
  redraws slowly. Two candidate causes, untested — (A) eviction: `ThumbnailCache` is one 500 MB
  `NSCache` shared across all buckets, and bucket-240 images (~518 KB) are ~16× bucket-60 (~32 KB),
  so a zoomed-in session evicts the whole zoomed-out strip; (B) those frames were never cached, since
  zoom 1.0 spans far more timeline than was ever decoded. Opposite fixes (per-bucket budgets vs wider
  low-zoom prefetch) — settle it by tracking every stored `ThumbKey` and checking whether misses are
  on previously-stored keys.

## Gate resolution history
- **4.1 resolved:** measured viewport demand plus the bounded decoder retry fixed the paused-fill failure; the complete manual matrix was user-passed November 1. Earlier failure/trace details remain in the Wave 4 execution history and linked evidence.
- **4.2 complete (2026-11-06):** same-source rebuild; user-confirmed held-arrow average 49.94%, paused idle 13.65%, confirmed zoom retry 13.98% (peak 16.6%). First zoom window excluded because no zoom occurred. Retain a/b/c as historical earlier-artifact evidence; zoom cue timing is user-reported and cache state uncontrolled. See [closeout evidence](../../validation/performance-closeout-2026-11-02/README.md).
- **Batch-refresh discrepancy resolved by explicit user decision 2026-11-02:** preserve progressive fill and revise the criterion to the existing per-batch throttle/flush policy. Original ten-total requirement was not met; no new runtime count or global-rate claim. See closeout evidence.
- **4.4 complete (2026-11-06):** decisions 11–15 retained; independent read-only review found no concrete source defect, confirmed evidence limits and explicit reverted-task accounting. State, tracker, session and archive updated; evidence/link/checksum checks accompany the scoped local checkpoint. Deferred drag scrubbing stays in TASKS.


---

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 0 | 2026-07-10 | 2026-07-10 | baseline (user-driven live, `ps` @ 1Hz on this Mac; clip: `~/Movies/PenumbraSmoke/mp4-long-perf.mp4`, 1280×720 H.264, 30 min): (a) playback/default-zoom avg **91.8%** (range 28–105, n=30s) · (b) playback/max-zoom avg **68.1%** (range 65–72, n=30s) — **unreliable, see Operational Learnings scroll-bug note** · (c) JKL-shuttle-4×/default-zoom avg **104.7%** (range 103.6–105.8, n=30s) · (d) held-arrow-repeat avg **72.3%** (range 68.5–80, n=10s) · (e) zoom-1→12-transition: pre-drag idle avg 14.6% (n=10s) → during-fill avg **120.9%**, peak **188.1%** (n=20s) |
| 1 | 2026-07-19 | 2026-07-19 | `53b0ead` 1.1 memoized index-based times + closed-form count, 1.3 half-gap tolerance · `af453c4` 1.2 cacheVersion throttled to ~10/s (256-image batch → 17–18 bumps, cancelled batches → 0) · `c0c8609` 1.4 generator reuse, **reverted** by `79a4d5a` (broke rendering on the non-debounced zoom path — see Operational Learnings). User-smoked live on `mp4-long-perf.mp4`: slider/pinch zoom renders correctly, adjacent cells distinct at zoom 4–6, verdict "snappy". Playback CPU unchanged (~92%, matches Wave 0 (a)) — expected, F1 is Wave 2.1's job. |
| 2 | 2026-10-28 | 2026-10-29 | Tasks 2.1–2.4 implemented serially by one fresh-context agent because both files are coupled; coordinator integration and independent read-only review. Source commit `8c6f45c`; strict-concurrency build passes with zero application-source warnings. Manual follow-up fixes and keys/timecodes user-passed; latest navigation build passes strict concurrency, viewport tests pass. Follow-up source remains uncommitted; 2.1–2.4 accepted. Manual checks and CPU/playback/paused SwiftUI gates complete; evidence in docs/validation/performance-2026-10-29/. Measurement-only close leaves existing dirty source/docs uncommitted; no push. Wave 3 not started. See [session evidence](../2026-10-28.md). |
| 3 | 2026-10-29 | 2026-10-29 | Fresh-context `seek_implementation` owned coalescer/view integration/headless tests; coordinator owned temporary 3.2 probe, xcodegen/build/docs; coupled tasks serialized. Independent fresh-context `seek_review`: no remaining findings. Swift 6 complete-concurrency seek tests and viewport tests exit 0; strict-concurrency diagnostic Debug build exit 0 (only AppIntents metadata warning). User passed finite runtime batch. 3.2 trace confirms animating→isScrolling=true and existing debounce (31 animating phases; 293 debounced scrolling schedules), no-op. Probe removed; final strict build exit 0 and PID 93956 exact final executable/version 0.1 (1) verified after graceful diagnostic quit. No scoped commit: view integration depends on overlapping pre-existing uncommitted Wave 2 layout/navigation fixes; preserve those for a deliberate combined checkpoint rather than commit unrelated earlier work. No push or branch change. [Evidence and next test](../../validation/seek-coalescing-2026-10-29/README.md). |
| 4 | 2026-10-29 | 2026-11-06 | Serial verification; 4.3 satisfied by retained playback/idle SwiftUI traces. Final-app identity/checksums and diff check pass; 4.2 state a confirmed: 39.08% average (n=30/30.101 s), vs historical 91.8%; first idle attempt excluded. State b 53.403% average (50.7–58.6%, n=30/30.037 s); default follow user-passed. State c 121.2% average (104.9–146.4%, n=30/30.017 s), above historical 104.7% with unpaired-comparison limits. State d collected provisionally: 68.95% average (18.4–104.8%, n=10/10.038 s), sustained-movement/release report pending. State e action confirmed: idle 17.2%, transition 33.585% average/98.3% peak; F6 FAILED (selected thumbnail remains black while paused). No zoom performance win claimed. State d confirmation and remaining 4.1 results pending; 4.4 documentation in progress. Initial runtime trace exhausted before zoom; user screenshots confirm two-minute failure. Focused hooks rebuilt with strict concurrency and headless flood-check/review; focused capture now identifies wrong final demand (about ten seconds before selected key), with decode/store/refresh succeeding for earlier frames. Product fix implemented 2026-11-01 using measured viewport anchors; headless checks, independent review and strict build pass, runtime acceptance pending. See docs/validation/viewport-demand-2026-11-01/README.md. No commit/push; preserve overlapping earlier dirty work. [Evidence](../../validation/final-verification-2026-10-29/README.md). |

**2026-11-06 task 4.2:** coordinator collected dependent measurements serially; no independent agent work. Missing temporary artifact rebuilt from matching accepted sources, strict build passed, exact-path launch/version verified. Held-arrow movement and zoom/fill user-confirmed; first zoom attempt excluded. 13/15 complete, one reverted; 4.4 remains. No commit: measurement-only next-task scope with overlapping pre-existing integration work; no push. [Evidence](../../validation/performance-closeout-2026-11-02/README.md).

---
*Archived November 6, 2026. Historical execution entries above retain their original dates and provisional findings; this closeout supersedes their pending status.*

**Task 4.4 closeout:** coordinator owns archive/state/checkpoint serially; fresh-context `closeout_review` independently reviewed source diffs, SeekCoalescer and acceptance evidence read-only. No concrete defect found. Existing source/build/manual evidence reused; no source or app-control changes in this documentation closeout. Refreshed origin/main: local branch ahead two, behind zero before checkpoint. Preserve unrelated footer, design and entry-point guidance changes.
