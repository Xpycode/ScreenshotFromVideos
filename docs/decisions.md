# Decisions — ScreenshotFromVideos

Long-form rationale for architectural and design decisions. PROJECT_STATE.md's "Key Decisions" section is the TL;DR index pointing here.

Decisions appear in roughly chronological order within each topic so the path of thinking is visible. Older entries that have been superseded are retained with a note rather than deleted.

---

## 1. Project Foundation

### Build tooling: xcodegen
**Date:** project start (Phase 0); regen-requirement claim corrected 2026-05-28
**Decision:** Drive `.xcodeproj` from `01_Project/project.yml` via xcodegen. Regenerate with `cd 01_Project && xcodegen generate` after any structural change — including adding or moving a `.swift` file.
**Why:** A pbxproj is unreviewable in PRs and merges badly. `project.yml` is human-readable, regenerable, and the source of truth.
**Consequences:** Never hand-edit pbxproj — changes vanish on next regen. **The sources glob is resolved at `xcodegen generate` time, not at `xcodebuild` time** — so new files do NOT auto-include in the build. An earlier note in this project (and in `POLISH_PLAN_post_phase5.md`) claimed otherwise; the polish-Item-2 build failure on 2026-05-28 (`cannot find type 'ExportFormat'` on the first build after creating `Models/ExportFormat.swift`) disproved it. Any session that adds/moves a file in `ScreenshotFromVideos/` subtrees must run `xcodegen generate` before the next `xcodebuild`, or accept a build failure first.

### macOS 15.0 / Swift 6.0 / SwiftUI / notarized non-sandboxed
**Date:** project start
**Decision:** Target macOS 15.0+, Swift 6.0 strict concurrency, SwiftUI, hardened runtime, notarized but not sandboxed.
**Why:** This is a personal tool first, distribution-ready second. Non-sandboxed avoids the security-scoped-bookmark dance for output folders. Swift 6 because that's what the sibling apps already use. macOS 15 because `onModifierKeysChanged`, `onScrollPhaseChange`, and the AsyncSequence form of `images(for:)` all need it.

### Bundle ID: `com.lucesumbrarum.ScreenshotFromVideos`, team FDMSRXXN73
**Date:** project start
**Note:** Internal identifiers (bundle ID, repo folder, Xcode target, scheme) intentionally kept as `ScreenshotFromVideos` even after the user-facing rename to "Stills From Video" (Phase 4.5). Internal ≠ marketing.

---

## 2. Code Lineage and Lift Strategy

### Lift strategy: distill, don't copy whole
**Date:** Phase 1
**Decision:** When pulling code from sibling apps (VideoWallpaper, CropBatch), write small focused files (≤120 lines) rather than copy-pasting whole files.
**Why:** The sibling apps have their own assumptions (sandbox state, view-model shapes, target macOS) that don't all transfer. Copying whole files drags in dead code and confuses future-me about what's actually in use here.
**Consequences:** Each lifted file gets a header comment naming its source. Some lifts produce a fraction of the original.

### Graphics lifts need a visual smoke
**Date:** Phase 4.5 (icon work)
**Decision:** Graphics code (CGContext, coordinate transforms, image generation) must be visually verified after lift — clean build is not enough.
**Why:** Context type, coordinate origin, and color-space defaults can differ from the original. The icon generator caught this — looked fine at compile time, would have produced an upside-down filmstrip if not visually checked.

---

## 3. Extraction Pipeline

### Batch API: `AVAssetImageGenerator.images(for: [CMTime])`
**Date:** Phase 1
**Decision:** Use the macOS 13+ AsyncSequence API. The older callback API (`generateCGImagesAsynchronously(forTimes:completionHandler:)`) is banned.
**Why:** The callback API crashes under Swift 6 strict concurrency (Apple DTS #761194). The AsyncSequence form is safe and integrates cleanly with structured concurrency.

### Cancellation: `withTaskCancellationHandler { generator.cancelAllCGImageGeneration() }`
**Date:** Phase 1 (export pipeline), reaffirmed Phase 5 Wave 6.1 (thumbnail renderer)
**Decision:** Any consumer of `images(for:)` MUST wrap the loop in `withTaskCancellationHandler` with `onCancel: { generator.cancelAllCGImageGeneration() }`.
**Why:** `images(for:)` does NOT honor Swift `Task` cancellation promptly. `task.cancel()` flips the flag but the AsyncSequence keeps yielding while VTDecoderXPCService keeps decoding. Confirmed twice in this project — once during export, once when fast pinch on a 5-min clip saturated VTDecoderXPCService at 430% CPU and made the Mac unresponsive (2026-05-28 Wave 6.1).
**Consequences:** Belt-and-suspenders. `Task.checkCancellation()` inside the loop is still useful but it's not sufficient on its own.

### Concurrency shape: `@MainActor @Observable` view-model with one `Task<Void, Never>`
**Date:** Phase 2
**Decision:** No custom actor. No AsyncStream wrapping. The view-model is `@MainActor`, owns one render task, and updates progress via a `@MainActor` callback per iteration.
**Why:** A custom actor is overkill for a single user-driven export task. The hop-to-main-actor cost per progress update is negligible. AsyncStream wrapping adds backpressure machinery we don't need.

### `TaskGroup` rejected for frame extraction
**Date:** Phase 2
**Decision:** Do not parallelize frame extraction with `TaskGroup`.
**Why:** `images(for:)` already exploits sequential GOP decoding internally. Multiple concurrent generators on the same asset hurt more than they help (re-decoding overlapping keyframes).

### Times sorted ascending before passing to `images(for:)`
**Date:** Phase 2; manual list also sorted on insert from 2026-05-28
**Decision:** `TimeListGenerator.times(for: .timestamps(_:))` sorts ascending; filename indices are assigned in delivery order so on-disk numbering is chronological by clip time. The right-pane manual list also sorts on insert (added 2026-05-28) so UI row order matches export order.
**Why:** `images(for:)` benefits from sequential GOP decoding when times are sorted. The earlier "filename index preserves *requested* order" aspiration was overridden in practice by this upstream sort; aligning the UI to that is simpler than removing the sort.

### Filename collisions: `_1`, `_2`, … suffix; never overwrite
**Date:** Phase 2
**Decision:** Append `_N` suffix on filename collision.

### `autoreleasepool` only around the PNG encode
**Date:** Phase 2
**Decision:** Wrap only the PNG encode step in `autoreleasepool`. Swift Concurrency handles the rest on Darwin.

### Default seek tolerance `.zero` (export); per-zoom for the strip
**Date:** Phase 2 (export); Phase 5 Wave 3 (strip)
**Decision:** Export pipeline always uses `.zero / .zero` (sample-accurate). Strip uses `.zero` when density ≥ 5/sec, else `±0.5s` (snaps to nearest I-frame, faster).

---

## 4. UI Architecture

### Discrete UI fields are the source of truth
**Date:** Phase 2 Wave 2
**Decision:** The view-model exposes `tab`, `intervalUnit`, `intervalSeconds`, `intervalFrames`, `manualTimes` separately; `buildRequest()` resolves them into a locked `ExtractionMode` at Export time. No redundant `mode` field on the view-model.

### TimelineView over periodic time observer for current-time label
**Date:** Phase 3
**Decision:** Use `TimelineView(.periodic)` for the visible current-time label. Use `addPeriodicTimeObserver` only when other code (e.g., strip auto-scroll) needs the actual playback callback.
**Why:** No observer token to manage, no leak risk for purely-cosmetic time displays.

### `SplitViewAutosaveHelper` lifted from cookbook
**Date:** Phase 4 Wave 4
**Decision:** Persist split-view divider positions via `NSSplitView.autosaveName`. Lifted verbatim from `cookbook/01-window-layouts.md`. Used for both horizontal (`MainSplit`) and vertical (`LeftPaneVSplit`) splits.

### `Theme` stays a static enum (for now)
**Date:** Phase 4 Wave 4
**Decision:** `Theme` is a static enum read via `Theme.primaryBackground`, not an `EnvironmentKey`. Skipped from the original plan.
**Why:** No per-scheme tokens needed yet (dark-mode-only app). When the deferred light-mode toggle ships, this is the time to revisit and convert `Theme` to an `EnvironmentKey`-backed struct.

### `@State var vm` at App level, not in ContentView
**Date:** Phase 4.5
**Decision:** The root view-model lives on the App struct, not ContentView.
**Why:** The `Commands { ... }` block on `WindowGroup` needs to capture the same view-model instance for menu actions to work. Single-window app — multi-window would need `@FocusedValue` instead.

### App renamed user-facing to "Stills From Video"
**Date:** 2026-05-27 (Phase 4.5)
**Decision:** `CFBundleName` and `CFBundleDisplayName` → "Stills From Video". All internal identifiers kept as `ScreenshotFromVideos`.
**Why:** "Screenshot" implies screen capture, but the app accepts arbitrary video files. "Still" is the established cinematography term for an extracted frame. The macOS menu bar reads `CFBundleName` — both bundle strings must match for the rename to read clean.

### No ⌘⇧O for output folder
**Date:** Phase 4.5
**Decision:** Skip the dedicated keyboard shortcut for output-folder selection.
**Why:** The right-pane "Choose folder" button is right there. Users set output folder once per session — a menu duplicate is redundant.

### Preferences pattern: dedicated enum + UserDefaults
**Date:** Phase 4.5
**Decision:** `App/Preferences.swift` enum with static read/write functions. View-model properties declared without default values, populated in `init()` from `Preferences.*()`, write-throughs via `didSet`. `manualTimes` left transient.
**Why:** The no-default trick avoids spurious writes during init (Swift skips `didSet` on first assignment in init). `nonisolated(unsafe) static let defaults = UserDefaults.standard` is the Swift-6 strict-concurrency escape hatch — `UserDefaults` is documented thread-safe but Foundation doesn't conform it to `Sendable`.

---

## 5. Phase 5 — Thumbnail Strip

### Contact-sheet grid over horizontal filmstrip
**Date:** 2026-05-27 (Wave 2 pivot)
**Decision:** Strip is a `LazyVGrid(.adaptive)` with active-cell border indicator, not a single-row `LazyHStack` with vertical playhead bar.
**Why:** Original plan called for iMovie/FCP-style filmstrip. User asked for multi-row wrapping after seeing empty vertical space. Grid pattern matches QuickTime's keyframe-export UI and the Photos browser — valid prior art.
**Consequences:** Playhead bar removed; active-cell border replaces it. Visible time range derived from `firstRow × cellsPerRow → lastRow × cellsPerRow`.

### Player ↔ strip split is user-adjustable
**Date:** 2026-05-27 (Wave 2)
**Decision:** Player and strip wrapped in `VSplitView` with `autosaveSplitView(named: "LeftPaneVSplit")`. Player `minHeight: 120`, strip `minHeight: 100, idealHeight: 320`. Footer stays outside the split.

### `.frame(maxWidth: .infinity)` on vertical-scroll containers in `VSplitView`
**Date:** 2026-05-27 (Wave 2 bugfix)
**Decision:** Any `ScrollView(.vertical)` containing a `LazyVGrid` inside a `VSplitView` must explicitly fill horizontally.
**Why:** Without it, `ScrollView(.vertical)` reports a narrow intrinsic content width (= one cell), and `VSplitView` matches both panes to that — entire split column collapses.

### `MagnifyGesture`: snapshot the baseline, don't compound
**Date:** 2026-05-27 (Wave 3 bugfix)
**Decision:** Apply `MagnifyGesture.value.magnification` against `zoomBaseline` (captured in `onMagnifyStart` and `commitZoom`), NOT against the live `zoomLevel`.
**Why:** `magnification` is **absolute** from gesture start (1.0 at start), not a per-tick delta. Multiplying `zoomLevel * magnification` per tick compounds: even tiny pinches send zoom straight to the max clamp within ~50ms. Symptom of the wrong pattern is unmistakable once seen.

### All zoom input paths converge on `setZoom(_:)`
**Date:** 2026-05-27 (Wave 3+)
**Decision:** Menu commands, keyboard, scroll-wheel, and slider all route through `StripModel.setZoom(_:)`. `setZoom` clamps to [1, 12] AND re-syncs `zoomBaseline` to the new value.
**Why:** Without baseline sync, pinching after a slider/menu/wheel zoom snaps back to the baseline at last `onMagnifyStart`. `onZoomChange` is pinch-only and not a sufficient choke point.

### `@FocusedValue` for view-scoped menu commands
**Date:** 2026-05-27 (Wave 3+)
**Decision:** `LeftPaneView` publishes a `StripZoomActions` struct via `.focusedSceneValue(\.stripZoom, …)`; `ZoomCommands` reads via `@FocusedValue(\.stripZoom)` and `.disabled(zoom == nil)` greys the menu out when no video is loaded.
**Why:** `StripModel` lives inside `LeftPaneView` as `@State private var stripModel: StripModel?`. Hoisting it to App level just to feed menu commands would force the metadata-driven lifecycle up there too. `@FocusedValue` is the cleaner indirection.

### `⌘`+scroll-wheel via `NSEvent.addLocalMonitorForEvents`
**Date:** 2026-05-27 (Wave 3+)
**Decision:** Catch `⌘`+scroll-wheel via `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` in a `.task` on the strip, not via NSViewRepresentable.
**Why:** NSViewRepresentable overlay would need `nextResponder?.scrollWheel(with:)` pass-through, which is fragile in SwiftUI's responder chain. Local monitor returns the event by default (pass-through), returns nil to consume (when ⌘ held). Lifecycle: monitor removed in `defer` of the task.

### `.onKeyPress(keys:)` form for modifier-filterable handlers
**Date:** 2026-05-27 (Wave 3+)
**Decision:** Use `.onKeyPress(keys: [.init("+"), …])` over `.onKeyPress(_:)` when the handler needs to read modifier flags.
**Why:** The single-key form defaults to a zero-arg action closure; the keys-array form only has the `(KeyPress) -> Result` overload, which disambiguates cleanly.

### Cell-side fallback cascade for zoom-transition flash
**Date:** 2026-05-27 (Wave 3+)
**Decision:** `ThumbnailCellView.bestImage()` resolves: exact `(time, bucket)` → same time at other buckets `[240, 120, 60]` → `@State lastImage: CGImage?` (kept across cell rebinds via `.onChange(of: cellIdentity) { syncLastImage() }`).
**Why:** Both `widthBucket` and density-driven `timeMillis` change at most zoom transitions → new cache key misses entirely → placeholder flash. Alternatives rejected: snap timestamps to 100ms grid (only helps zoom-out); centralized nearest-time lookup (NSCache doesn't support iteration).
**Consequences:** ~5 MB extra resident for 100 visible cells. Cell-scoped, evaporates on LazyVGrid unload.

### `.allowsHitTesting(false)` on decorative overlays
**Date:** 2026-05-27 (Wave 4.1)
**Decision:** Active-cell border overlay (`Rectangle().strokeBorder(...)`) gets `.allowsHitTesting(false)`. As a general rule: any decorative overlay inside a tap-handling view.
**Why:** SwiftUI hit-tests by **layout shape, not visual shape**. A `strokeBorder` has a full-rect hit region despite painting only the border line — without the modifier, taps on the active cell would be swallowed.

### `.rounded()` not `.rounded(.down)` in `activeIndex`
**Date:** 2026-05-27 (Wave 4.1 bugfix)
**Decision:** `activeIndex = (currentTime × density).rounded()`.
**Why:** AVPlayer's sample-accurate seek lands on the frame *containing* the target time and reports `currentTime()` as that frame's *start* time — ε below the target whenever target doesn't align to a frame boundary (common at fractional density). `.rounded(.down)` pushed the border one cell left of the clicked cell. Round-to-nearest tolerates the undershoot.

### Sample-accurate seek (`.zero/.zero`) for click-to-seek
**Date:** 2026-05-27 (Wave 4.1)
**Decision:** Click-to-seek uses `seek(to:toleranceBefore:.zero, toleranceAfter:.zero)`.
**Why:** User clicked a *specific* thumb — they expect to land on its frame, not the nearest keyframe minus 0.5s. The decoding-delay cost cited in Apple's *"Controlling the transport behavior of a player"* article only matters for continuous-scrub UIs.

### `onModifierKeysChanged` over `TapGesture.modifiers(.command)`
**Date:** 2026-05-27 (Wave 4 plan rewrite)
**Decision:** Detect ⌘-held state via `onModifierKeysChanged(mask: .command, initial: false)` (macOS 15+) tracked into `@State`, branched inside `.onTapGesture`. Fallback: synchronous `NSEvent.modifierFlags.contains(.command)` at tap time.
**Why:** `TapGesture.modifiers(_:)` has been flaky on macOS for years (Apple DevForums #654154, ongoing 2024–2025 reports).
**Consequences:** Wave 4.2 used both APIs simultaneously — state-tracked variable for the normal case, in-closure NSEvent read for focus-race edge cases.

### Manual list sorted by clip time on insert
**Date:** 2026-05-28 (after Wave 4.2)
**Decision:** `captureCurrentFrame()` and `captureFrame(at:)` both route through a private `insertManualTime(_:)` helper that finds sorted position via `firstIndex { CMTimeGetSeconds($0) > CMTimeGetSeconds(time) }` and `insert(_:at:)`.
**Why:** Right-pane manual list is a destination preview — row N corresponds to filename `_N`. The aspirational "filename index preserves *requested* order" decision was overridden in practice by the existing ascending sort in `TimeListGenerator`. Aligning the UI to that is simpler than removing the upstream sort.
**Side effect:** `captureCurrentFrame()` now also dedupes (it didn't before; `captureFrame(at:)` already did). Trade-off: "remove the last row to undo the last capture" affordance is gone — strip cell-dot + footer-count already signal capture.

### Bare `M` on focused strip routes to `captureCurrentFrame()`
**Date:** 2026-05-28
**Decision:** `.onKeyPress(keys: [.init("m"), .init("M")])` with the same `⌘/⌥/⌃` modifier-filter guards as the +/-/0 zoom keys.
**Why:** Scoped to strip focus so it doesn't shadow `M` typed into right-pane interval TextFields. App-wide via Commands would.

### Placeholder visually distinct from strip background
**Date:** 2026-05-28 (Wave 5)
**Decision:** Empty cell placeholder is `Color(white: 0.07)`. Strip background remains `Theme.secondaryBackground`.
**Why:** Both had been `Theme.secondaryBackground` (~0.15 grey), making empty cells invisible against the strip. Now the 1pt cell-spacing gap shows the lighter strip background through — empty grid reads as "many dark cells separated by lighter dividers" → "loading", not "void".

### Debounce only while actively interacting
**Date:** 2026-05-28 (Wave 5)
**Decision:** `StripModel.scheduleRender()` gates its 80ms `Task.sleep` on `isScrolling || isMagnifying`.
**Why:** During continuous scroll/pinch the debounce prevents render thrash. The moment a phase ends, the next `scheduleRender` call reads both flags false → no sleep → renders within one frame.

### Player-seek auto-scroll via delta-detection
**Date:** 2026-05-28 (Wave 5)
**Decision:** A delta > 0.5s between consecutive periodic-time-observer ticks counts as a seek; `seekScrollTarget = activeIndex` then triggers `ScrollViewReader.scrollTo(target, anchor: .center)` over 0.15s.
**Why:** Brings the active cell into view when the user clicks elsewhere in AVPlayer's seek bar or click-to-seeks on an off-screen thumb. Natural per-tick deltas (≤33ms) don't trigger it, so manual scroll position is respected during playback.

### Design target: 30s–2min clips; long-clip optimization out of scope
**Date:** 2026-05-28 (Wave 5)
**Decision:** The app targets short clips (30s to 2min). Multi-hour clips work but visible rendering lag is acknowledged-imperfect and explicitly NOT on the optimization roadmap.
**Why:** Use case is screen-recording context for Claude Code. Mitigations that would help long clips (hot+cold task split, virtualized rows, coarser default density at high duration) are documented but not planned.

### In-flight decode cap: 256, prioritized by visible center
**Date:** 2026-05-28 (Wave 6.1 fix — mid-matrix)
**Decision:** `StripModel.scheduleRender` caps the requested times list at 256 per render batch, sorted by `abs(CMTimeGetSeconds(time) - visibleCenter)` ascending. Off-center prefetch loses first when the cap bites.
**Why:** During fast pinch, `visibleTimeRange` is stale (it's set by scroll-geometry callback, lags zoom by frames), so `prefetchRange × new density` can compute hundreds of cells. Combined with the AVF cancellation bug above, this saturated VTDecoderXPCService at 430% CPU on a 5-min clip (within design target) and made the Mac unresponsive — user had to force-quit.
**Emergent UX:** Cells render outward from the viewport center, which reads as a "blooming" effect — accidentally nicer than uniform fill.

---

## 6. Post-Phase-5 Polish — Frame-Count Preview, Multi-Format Export, Unload Clarity

Three small items shipped on branch `polish/post-phase-5` on 2026-05-28. Planning, execution, and smoke all happened the same day. See `sessions/_archive/2026-05-28_POLISH_PLAN_post_phase5.md` for the original plan and `sessions/2026-05-28.md` for the execution log.

### WebP omitted from SFV's format list — load-bearing
**Date:** 2026-05-28 (planning) — confirmed in execution
**Decision:** SFV ships PNG / JPG / HEIC. No WebP. Not now, possibly never.
**Why:** ImageIO has no WebP write support on macOS through 26.5. Triangulated from four sources during planning:
1. **Apple docs.** The WebP documentation collection (`developer.apple.com/documentation/imageio/webp-data`) exposes only *read* metadata keys (`kCGImagePropertyWebP*`). No write key.
2. **Runtime probe on this Mac.** `swift /tmp/probe.swift` calling `CGImageDestinationCopyTypeIdentifiers()` returned 22 writable types. `org.webmproject.webp` was NOT among them. `public.heic`, `public.jpeg`, `public.png`, `public.tiff` were all present. Definitive for the version actually running here.
3. **Apple Developer Forum #688001** reports `CGImageDestinationCreateWithURL(..., UTType.webP.identifier, …, nil)` returning nil on macOS 11 → 15. Unresolved by Apple. No mention of a WebP encoder in the macOS 14 / 15 / 26 release notes.
4. **CropBatch audit.** When the user fairly pushed back ("how does CropBatch get WebP export?"), I dug: `Package.resolved` lists only Sparkle 2.8.1. No `libwebp` / `SDWebImage` / `WebPKit` / vendored xcframework / bridging header anywhere. Recursive `grep -i webp` finds only ImageIO calls. No pre-export interception, no fallback. The error from `CGImageDestinationCreateWithURL` returning nil is logged at `CropBatchApp.swift:368` and execution silently continues — **no `.webp` file is ever written.** CropBatch's README claim of WebP support is hollow. We are not replicating that bug.
**Consequences:** If WebP becomes non-negotiable later, vendor [SDWebImageWebPCoder](https://github.com/SDWebImage/SDWebImageWebPCoder) (~200 KB libwebp), accept the notarization / hardened-runtime cost, and route only `.webp` through it while keeping ImageIO for the other three. Documented but not planned. Future-me reading this: the runtime-probe finding is the load-bearing evidence — re-run the probe before assuming Apple has fixed this.

### `ExportFormat` enum with `.jpg` extension override
**Date:** 2026-05-28
**Decision:** `ExportFormat.fileExtension` hardcodes `.jpeg → "jpg"`. Other cases use the preferred extension as-is.
**Why:** `UTType.jpeg.preferredFilenameExtension` returns `"jpeg"`, but macOS Finder, web upload forms, and human convention all expect `.jpg`. Confirmed in smoke — exported files are `*.jpg`. The override is cleaner than rewriting elsewhere.

### Single shared quality across JPG and HEIC
**Date:** 2026-05-28
**Decision:** One `exportQuality: Double` value persisted in Preferences, shared between JPG and HEIC. Not per-format.
**Why:** Simpler UI (one slider), simpler Preferences (one key), simpler mental model. Alternative would be `{ jpeg: 0.85, heic: 0.75 }` since HEIC's quality scale produces visibly different file sizes from JPEG's at the same value, but: (a) the typical use case is "pick a format, then tune quality once", not constant switching; (b) HEIC files at 0.85 came out reasonable in smoke. Revisit only if HEIC files come out too big in real use.

### PNG default; quality slider hidden (not disabled) when PNG
**Date:** 2026-05-28
**Decision:** First-run default is PNG. Quality slider row is hidden via `if vm.exportFormat.supportsCompression { ... }`, not just `.disabled(...)`-grey'd.
**Why (PNG default):** Preserves prior behavior on first launch — pre-existing users see no behavior change.
**Why (hidden, not disabled):** A grey'd-out slider invites the question "what value would that be if I could move it?" — but the answer is "nothing, PNG is always lossless." Removing the row entirely is unambiguous. The layout shift is small (one row) and the slider's quality value is preserved in Preferences regardless of visibility, so switching PNG → JPG → PNG → JPG doesn't reset it.

### Format section sits between Output and Options
**Date:** 2026-05-28
**Decision:** `formatSection` is a top-level section in `RightPaneView`'s scroll stack, between `outputSection` and `optionsSection`. NOT nested inside the existing Options DisclosureGroup.
**Why:** Read top-to-bottom as "what / when / where / how": Mode → Params → Output → Format → Options. Format materially changes file size and on-disk extension; it belongs alongside the destination folder, not nested under "Options" (which is about cosmetic post-processing like overlay and numbering).

### "Unload" label, no menu item, no confirmation dialog
**Date:** 2026-05-28
**Decision:** Footer ✕ icon → `Label("Unload", systemImage: "xmark.circle.fill")` with `.labelStyle(.titleAndIcon)`. No `File > Close Video` menu item. No confirmation dialog.
**Why (label):** "Unload" is the standard term in media tools. "Close Video" would conflict with ⌘W (window close). "Remove" sounds destructive to the source file. Tooltip explicitly clarifies "The source file is not deleted."
**Why (no menu item):** ⌘W is already taken. A menu item without a shortcut is pure clutter; the labeled footer button is discoverable enough.
**Why (no confirmation dialog):** The operation is non-destructive by design — `manualTimes` is intentionally transient (output folder, options, overlay, etc. all persist). A dialog would be friction without value.

### Frame-count preview placement and pluralization
**Date:** 2026-05-28
**Decision:** New `Text("\(n) frame\(n == 1 ? "" : "s") will be exported")` row at the *top* of `exportFooter`'s VStack, gated on `vm.metadata != nil && !vm.isRunning`. Native English pluralization via ternary — no `String.localizedStringWithFormat`.
**Why (placement):** First child of the footer, so the magnitude reads immediately before the Export button. During export, the existing progress UI takes that space and the count row hides; on launch, no metadata means no row.
**Why (visible at 0):** The "0 frames will be exported" state is informative (it tells the user *why* the Export button is disabled — empty Manual list, or interval = 0). Hiding it would force the user to guess.
**Why (no localization):** App is English-only.

### Factor mode resolution into a `currentMode` computed
**Date:** 2026-05-28
**Decision:** `ExtractionViewModel.currentMode: ExtractionMode?` is the single resolver for "do the UI fields currently describe a valid mode?". Both `previewFrameCount` and `buildRequest()` read from it.
**Why:** Item 1 added the count preview, which needed the same `tab / intervalUnit / intervalSeconds / intervalFrames / manualTimes` → `ExtractionMode` resolution that `buildRequest()` was already doing inline. Factoring out the resolver collapsed `buildRequest()` from ~20 lines to 9 and made the two paths impossible to drift. Returns `nil` for incomplete selections (zero interval, empty manual list) — both callers handle nil the same way (no count / no request).
