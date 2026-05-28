# Implementation Plan — Phase 4 (Production UI)

> Persists across sessions. Regenerate if reality diverges; don't patch.
> Built from PROJECT_STATE.md "Next Actions" + three parallel research agents
> (cookbook archaeology, sibling-app archaeology, Apple SDK + web).

## Goal
Grow the smoke-test `ContentView` into a production HSplitView app: left pane is an `AVPlayer` with a "Capture this frame" button (feeds manual-timestamp mode), right pane is settings (mode picker, overlay/numbering toggles with an Options disclosure, output folder, Export + progress + cancel). Adopt the cookbook's mandatory App Shell Standard (Theme, dark scheme, hidden title bar, autosave divider).

## Acceptance Criteria
- [ ] Drop or pick a video → it loads in an `AVPlayerView`-backed scrubber on the left pane
- [ ] "Capture this frame" reads `player.currentTime()` and appends it to a manual-timestamps list
- [ ] Mode picker switches between **Interval** (seconds *or* frames) and **Manual** (uses captured list)
- [ ] Interval-frames uses the video's nominal FPS (loaded from `AVAssetTrack`) to compute `[CMTime]`
- [ ] Overlay toggle + numbering toggle in the main pane; position / font-size / filename-pattern hidden behind an "Options…" disclosure
- [ ] Output folder shown with path; "Change…" button reopens `NSOpenPanel`
- [ ] Export button launches one cancellable `Task` on the view-model; progress bar + per-frame URL surface live; Cancel preserves partial PNGs
- [ ] HSplitView divider position persists across launches (`.autosaveSplitView(named:)`)
- [ ] App-shell modifiers applied: `.windowStyle(.hiddenTitleBar)`, `.preferredColorScheme(.dark)`, `.toolbarRole(.editor)`, `UIDesignRequiresCompatibility = true`
- [ ] `xcodebuild clean build` succeeds **with zero strict-concurrency warnings** (the ~30 `NSOpenPanel` warnings in `FilePickers.swift` / `DropHandling.swift` are gone)

## Non-Goals (deferred to a later phase)
- Thumbnail strip with zoom-controlled stride (architecture must not preclude it — covered by keeping selection as `[CMTime]` and using `AVAssetImageGenerator.images(for:)` for the future strip)
- Multi-video batch
- Trim / convert / re-encode
- Custom overlay typography beyond the four-corner positions

## Research Anchors (from background agents)

| Topic | Source | Decision |
|---|---|---|
| App Shell Standard | cookbook `00-app-shell.md` (MANDATORY) | Theme + FCPToolbarButtonStyle + `.hiddenTitleBar` + `.preferredColorScheme(.dark)` + `.toolbarRole(.editor)` + Info.plist `UIDesignRequiresCompatibility = YES` |
| Layout archetype | cookbook `02-layout-templates.md` (Editor / Template B) | HSplitView, left = player + transport + (no timeline yet), right = inspector. `.autosaveSplitView(named:)` from `01-window-layouts.md` |
| Segmented picker | cookbook `03-appkit-controls.md` | Custom `FCPSegmented` (HStack of styled Buttons), not `Picker.segmented` |
| Timecode display | cookbook `07-timecode-typography.md` | `.font(.system(size: ..., weight: .thin).monospacedDigit())` |
| Progress + cancel UI | cookbook `12-activity-progress.md` | `ProgressView(value:).progressViewStyle(.linear)` + Cancel button inline in right pane footer |
| AVPlayer in SwiftUI | Apple SDK research (A) — `AVPlayerView` wrapped in `NSViewRepresentable`; **not** `VideoPlayer` (no `currentTime` binding on macOS) | AppKit `AVPlayerView` + `.inline` controls. QuickTime-style chrome (incl. frame-step arrows) for free. |
| Frame-accurate seek | Apple SDK research (B), QA1820 | `player.seek(to:, toleranceBefore: .zero, toleranceAfter: .zero)`. Single discrete seeks per Capture click — no queue needed. AVPlayer decodes forward from nearest GOP keyframe transparently. |
| Nominal FPS | Apple SDK research (C) | `try await videoTrack.load(.nominalFrameRate)` — `loadValuesAsynchronously` is deprecated since macOS 13 |
| `@MainActor` on `enum FilePickers` | Apple SDK research (D) | Annotate the **enum** (`@MainActor enum FilePickers { ... }`), not per-func. `MainActor.assumeIsolated` is a runtime escape hatch — wrong tool here |
| ViewModel pattern | Apple SDK research (E) + CropBatch `Models/AppState.swift:36–37,470–511` | `@MainActor @Observable final class`, single `Task<Void, Never>?`, cancels prior before launching new; per-iter `await MainActor.run` for progress |
| DisclosureGroup | sibling: `VideoWallpaper/.../ConsolidatedPlaylistView.swift:459` | Native SwiftUI `DisclosureGroup`, no cookbook conflict |
| FCPToolbarButtonStyle | sibling: `CropBatch/.../Views/FCPToolbarButtonStyle.swift` (32 lines) | Lift verbatim |
| 2-pane shell reference | sibling: `CropBatch/.../ContentView.swift:1–40` (HStack + Divider + fixed 420-wide sidebar) | Use as **shape** reference, but adopt HSplitView + autosave per cookbook (sibling predates the rule) |

---

## Tasks

### Wave 1 — Foundations (parallel, no inter-deps)

- [ ] **1.1**: Create dark `Theme` struct → `01_Project/ScreenshotFromVideos/App/Theme.swift`
  - Content: `primaryBackground` (white 0.10), `secondaryBackground` (white 0.15), `accent`, `primaryText`, `secondaryText`. Inject via `EnvironmentValues` + `EnvironmentKey` so views can read `@Environment(\.theme)`.
  - Success: file compiles standalone; `Theme.dark` static available.
  - Backpressure: `xcodebuild build -scheme ScreenshotFromVideos -destination 'platform=macOS'` succeeds.

- [ ] **1.2**: Lift `FCPToolbarButtonStyle` → `01_Project/ScreenshotFromVideos/App/FCPToolbarButtonStyle.swift`
  - Copy from `/Users/sim/ProgrammingProjects/1-macOS/_Published/CropBatch/01_Project/CropBatch/Views/FCPToolbarButtonStyle.swift` (≈32 lines). Adjust any direct `Theme` refs to read from environment instead of CropBatch's globals.
  - Success: file compiles; preview shows pressed-state highlight.
  - Backpressure: build succeeds.

- [ ] **1.3**: Build `FCPSegmented<T: Hashable>` picker → `01_Project/ScreenshotFromVideos/App/FCPSegmented.swift`
  - HStack of `Button`s styled via `FCPButtonStyle(isOn:)`. Per cookbook `03-appkit-controls.md`. Generic over selection type.
  - Success: a `#Preview` shows a working two-option picker.
  - Backpressure: build succeeds; preview renders.

- [ ] **1.4**: Fix strict-concurrency warnings → `01_Project/ScreenshotFromVideos/UI/FilePickers.swift` + `UI/DropHandling.swift`
  - `FilePickers.swift`: add `@MainActor` at the enum level (`@MainActor enum FilePickers { ... }`).
  - `DropHandling.swift`: annotate `VideoDropModifier` `@MainActor` and replace the `DispatchQueue.main.async { onFolder(url) }` hop with a `Task { @MainActor in onFolder(url) }` so the actor isolation is provable.
  - Success: `xcodebuild build` reports **zero** warnings on these two files.
  - Backpressure: `xcodebuild clean build 2>&1 | grep -c warning` returns `0` for these files.

- [ ] **1.5**: Extend `VideoMetadata` with FPS → `01_Project/ScreenshotFromVideos/Core/VideoMetadataLoader.swift`
  - Add `nominalFrameRate: Float` to the struct; load via `try await videoTrack.load(.nominalFrameRate)`. Guard `>0` (some containers report 0; fall back to a conservative default like 30 with a logged warning).
  - Success: `VideoMetadataLoader.load(url).nominalFrameRate` returns a sane value for an .mp4 sample.
  - Backpressure: build succeeds; smoke-test ContentView still runs (no API break — it's an additive field).

- [ ] **1.6**: Add frame-interval mode → `01_Project/ScreenshotFromVideos/Models/ExtractionRequest.swift` + `Core/TimeListGenerator.swift`
  - Add `case intervalFrames(count: Int)` to `ExtractionMode`. `TimeListGenerator.times(for:duration:)` signature changes to also accept `fps: Float` (or wrap the three args in a `Context` struct — choose whichever keeps existing callers minimal).
  - Resolve `.intervalFrames(count: n)` to `stride(from: 0.0, through: duration, by: Double(n) / Double(fps))`.
  - Success: unit-style sanity in the smoke ContentView — change the test request to `.intervalFrames(count: 60)` on a 30fps clip and confirm one frame every 2s lands.
  - Backpressure: build succeeds; smoke test produces the expected count.

- [ ] **1.7**: Set `UIDesignRequiresCompatibility` in Info.plist → `01_Project/project.yml`
  - Add `INFOPLIST_KEY_UIDesignRequiresCompatibility: YES` under the target's `settings.base`. Regenerate with `cd 01_Project && xcodegen generate`.
  - Success: the produced Info.plist contains the key set to `YES`.
  - Backpressure: `plutil -p 01_Project/Build/.../Info.plist | grep UIDesign` (after a build) shows the key.

### Wave 2 — Player + ViewModel (depends on 1.5)

- [x] **2.1**: Build `PlayerView` wrapping `AVPlayerView` → `01_Project/ScreenshotFromVideos/UI/PlayerView.swift`
  - `NSViewRepresentable` over `AVPlayerView`. Inputs: `player: AVPlayer` (or `nil`); set `controlsStyle = .inline`, `showsFrameSteppingButtons = true`, `videoGravity = .resizeAspect`. Do **not** apply `.clipShape` on the representable (known hit-test bug per Apple SDK research A).
  - Success: a `#Preview` (or live ContentView) loads a sample video and the QuickTime chrome works (play/pause/step).
  - Backpressure: visually verify in a Debug build; capture a screenshot via `~/XcodePreviews/scripts/preview` if helpful.

- [x] **2.2**: Create `ExtractionViewModel` → `01_Project/ScreenshotFromVideos/App/ExtractionViewModel.swift`
  - `@MainActor @Observable final class ExtractionViewModel`.
  - State: `sourceURL: URL?`, `player: AVPlayer?`, `metadata: VideoMetadata?`, `outputFolder: URL?`, `mode: ExtractionMode = .interval(seconds: 2)`, `intervalUnit: IntervalUnit = .seconds`, `intervalSeconds: Double = 2`, `intervalFrames: Int = 60`, `manualTimes: [CMTime] = []`, `overlay: OverlaySettings = .init(enabled: true)`, `numbering: NumberingSettings = .init(enabled: true)`, `progress: ExtractionPipeline.Progress?`, `statusMessage: String = ""`, `isRunning: Bool = false`, `lastError: String?`, `job: Task<Void, Never>?`.
  - Methods: `load(_ url: URL) async`, `setOutputFolder(_:)`, `captureCurrentFrame()` (reads `player.currentTime()`, appends to `manualTimes`), `removeManualTime(at: Int)`, `startExtraction()`, `cancel()`. Internal `buildRequest() -> ExtractionRequest?` resolves the current UI state into the locked request.
  - Cancellation/progress shape per Apple SDK research E and CropBatch `AppState.processAndExport`.
  - Success: a tiny harness (or temporarily-modified ContentView) drives a full extraction through the view-model.
  - Backpressure: build succeeds; smoke harness produces PNGs.

### Wave 3 — Panes (depends on Wave 2; 3.1 & 3.2 parallel)

- [x] **3.1**: Build the left pane → `01_Project/ScreenshotFromVideos/UI/LeftPaneView.swift`
  - Two states, switched on `vm.player == nil`:
    - **Empty:** large drop zone with hint text + "Pick video…" button (calls `FilePickers.pickVideos()`).
    - **Loaded:** `PlayerView(player: vm.player!)` filling the pane; below it, a footer row: current-time label (`.monospacedDigit()` per cookbook 07, updated via `addPeriodicTimeObserver(forInterval: CMTime(seconds: 1/30, ...), queue: .main)` or `TimelineView(.periodic(from: .now, by: 1.0/30))` — pick one and stick with it), then "Capture this frame" button (`.keyboardShortcut("c")`), then captured-count label ("3 captured").
  - Drop modifier (`.videoDropTarget`) lives at the parent (ContentView), not here.
  - Success: drop a video → player loads → scrubbing updates the time label → capture click increments the count.
  - Backpressure: manual verification.

- [x] **3.2**: Build the right pane → `01_Project/ScreenshotFromVideos/UI/RightPaneView.swift`
  - Sections (each separated by `Divider().padding(.vertical, 8)`):
    1. **Mode** — `FCPSegmented` over `enum Tab { case interval, manual }`.
    2. **Interval** (visible when `tab == .interval`): inline `FCPSegmented` for `IntervalUnit { .seconds, .frames }`; an integer/decimal `TextField` bound to `vm.intervalSeconds` or `vm.intervalFrames`. Show a derived "≈ N frames" or "≈ Xs" hint using `vm.metadata?.nominalFrameRate`.
    3. **Manual timestamps** (visible when `tab == .manual`): `List` of `vm.manualTimes` rendered as `HH:MM:SS.mmm` rows with a trailing × button; empty state hints "Scrub the player and press ⌘C to capture frames."
    4. **Output** — `Text(vm.outputFolder?.path ?? "no folder chosen")` + "Change…" button.
    5. **Options** (toggles always; details inside `DisclosureGroup("Options…")`):
       - `Toggle("Burn timestamp into image", isOn: $vm.overlay.enabled)`
       - `Toggle("Number filenames sequentially", isOn: $vm.numbering.enabled)`
       - Inside the disclosure: 4-corner position picker (FCPSegmented of `OverlayPosition`), font-size `Slider(value: $vm.overlay.fontSize, in: 16...96)`, filename-pattern `TextField` bound to `vm.numbering.templater.pattern` with a `.help()` listing the tokens.
    6. **Export footer** (sticky, bottom of pane): `ProgressView(value: vm.progressFraction).progressViewStyle(.linear)` (only when `isRunning`), per-frame caption (`"\(p.completed)/\(p.total) — \(p.lastWritten?.lastPathComponent ?? "")"`), then row: `Button("Export", action: vm.startExtraction)` disabled if `!vm.canExport`, plus a destructive `Button("Cancel", action: vm.cancel)` shown only while running.
  - Pane has a fixed `frame(minWidth: 320, idealWidth: 360, maxWidth: 480)`.
  - Success: every control read/writes `vm` correctly; disabled states behave (Export disabled until source + output set; Manual-mode export disabled with empty list).
  - Backpressure: manual exercise of each control while watching `vm` via a Debug overlay or print.

### Wave 4 — Shell + integration (depends on Wave 3)

- [x] **4.1**: Apply App Shell modifiers → `01_Project/ScreenshotFromVideos/ScreenshotFromVideosApp.swift`
  - On the `WindowGroup`: `.windowStyle(.hiddenTitleBar)`, `.preferredColorScheme(.dark)`. On the root view: `.toolbarRole(.editor)` + `.environment(\.theme, .dark)`. Set `defaultSize(width: 980, height: 620)`.
  - Success: launching the app shows a hidden-title-bar dark window with the new layout.
  - Backpressure: visual.

- [x] **4.2**: Rewrite `ContentView` as the HSplitView shell → `01_Project/ScreenshotFromVideos/ContentView.swift`
  - Owns the `@State private var vm = ExtractionViewModel()` (or `@Bindable` if exposing to children).
  - Body: `HSplitView { LeftPaneView(vm: vm); RightPaneView(vm: vm) }.autosaveSplitView(named: "MainSplit")`.
  - Attach `.videoDropTarget(onFolder: { vm.setOutputFolder($0) }, onVideos: { if let u = $0.first { Task { await vm.load(u) } } })` here.
  - The smoke-test inline state goes away — everything is in the view-model now.
  - Note: `.autosaveSplitView(named:)` must exist; if it's a cookbook helper not yet copied, lift it from cookbook `01-window-layouts.md` and add as `App/SplitViewAutosave.swift` (≤30 lines).
  - Success: divider drag → close app → reopen → divider position remembered.
  - Backpressure: manual verification + `defaults read com.lucesumbrarum.ScreenshotFromVideos` shows the autosave key.

### Wave 5 — Verification (depends on all)

- [x] **5.1**: Clean build, zero warnings — **PASSED 2026-05-27**
  - Commands: `cd 01_Project && xcodegen generate && xcodebuild clean -scheme ScreenshotFromVideos -destination 'platform=macOS' && xcodebuild build -scheme ScreenshotFromVideos -destination 'platform=macOS' 2>&1 | tee /tmp/sfv-build.log`
  - Success: `grep -c warning: /tmp/sfv-build.log` returns `0`.
  - Result: `** BUILD SUCCEEDED **`. One raw `warning:` line was the AppIntents.framework boilerplate excluded by Operational Learnings; real source warnings = 0.

- [x] **5.2**: Manual test matrix — **ALL PASSED 2026-05-27**
  - [x] **(a) Interval-seconds happy path:** drop a 30s clip → Interval / seconds / 2 → Export → ~15 PNGs land, overlay reads correct timestamps.
  - [x] **(b) Interval-frames happy path:** same clip → Interval / frames / 60 → Export → PNG count matches `ceil(30 * fps / 60)`.
  - [x] **(c) Manual capture flow:** drop a clip → switch to Manual tab → scrub player → press ⌘C three times at different positions → list shows three rows → Export → exactly 3 PNGs land at the captured times (within 1 frame).
  - [x] **(d) Options disclosure:** open Options → set overlay position to top-right and size to 64 → Export → overlay visible at top-right with bigger font.
  - [x] **(e) Cancel mid-run:** start a long extraction → Cancel → partial PNGs preserved on disk, `isRunning == false`, app responsive, no zombie task.
  - [x] **(f) Divider autosave:** drag divider → quit app → reopen → divider in same position.
  - [x] **(g) Drop-zone visual:** on an empty window, drag a video over → drop zone highlights → release outside → highlight clears.

**UX gap surfaced during 5.2:** No way to unload a loaded video — to re-test the drop zone we had to quit and relaunch the app. Candidate fixes: (i) "Clear" button in the left-pane footer, (ii) accept a fresh video drop over the loaded state (replaces current), (iii) both. Flagged for the post-phase polish list, not blocking 5.3.

- [ ] **5.3**: Update `docs/PROJECT_STATE.md` — flip "Current Focus" to next-phase candidate (e.g. polish + distribution, or the thumbnail-strip Phase 5 prototype), append session log entry `docs/sessions/2026-MM-DD.md`, archive this `IMPLEMENTATION_PLAN.md` to `docs/sessions/_archive/` or delete per the template footer.

---

## Operational Learnings
<!-- Populated during execution. Examples to expect: -->
- `addPeriodicTimeObserver` returns a token that **must** be removed on view-disappear or you'll leak the closure (capturing the AVPlayer cycle).
- `AVPlayerView.controlsStyle = .inline` requires the wrapping `NSView` to be at least ~60pt tall or the chrome clips.
- Frame-step buttons only appear if the source has a known frame rate at load time — for clips that come back with `nominalFrameRate == 0`, fall back to "no step buttons + a manual ±1-frame stepper" via Capture's neighbors.
- Wave 2: dropped the redundant `mode: ExtractionMode` field the plan listed alongside `tab/intervalUnit/intervalSeconds/intervalFrames/manualTimes`. The discrete UI fields are the source of truth; `buildRequest()` resolves them into the locked `ExtractionMode` at Export time.
- Wave 2: SourceKit reported "Cannot find type X in scope" for cross-file refs right after `Write` — that's the LSP looking at the not-yet-regenerated `.xcodeproj`. `xcodegen generate` (and a build) resolves it. Don't chase phantom diagnostics until xcodegen has run.
- Wave 3: chose `TimelineView(.periodic(from: .now, by: 1.0/30))` over `addPeriodicTimeObserver` for the live time label — the AVPlayer-observer path needs token cleanup on view-disappear (otherwise it captures `self` and leaks). TimelineView has no lifecycle to manage; it just re-reads `player.currentTime()` on each SwiftUI tick.
- Wave 3: corner-picker labels use Unicode arrows (U+2196..U+2199) rather than emoji. Compact, clear, and they survive the "no emoji" rule because they're geometric shapes, not pictographs.
- Wave 3: the `appintentsmetadataprocessor` "No AppIntents.framework dependency found" warning is a Xcode boilerplate emitted on every macOS build that doesn't use AppIntents. It does NOT count against the zero-warnings acceptance criterion.
- Wave 4: skipped the planned `.environment(\.theme, .dark)` modifier. Wave 1.1 shipped `Theme` as a static enum (not an `EnvironmentKey`-backed struct), and the panes read `Theme.primaryBackground` etc. directly — the environment hop would be ceremony for no payoff. If runtime-customizable themes become a real requirement, revisit Theme.swift first.
- Wave 4: `.preferredColorScheme(.dark)` is a View modifier on macOS — must go on the root view inside `WindowGroup { … }`, not on the Scene chain. Putting it after `.windowStyle(.hiddenTitleBar)` compiles but no-ops in some SDK versions.
- Wave 4: lifted `SplitViewAutosaveHelper` verbatim from cookbook `01-window-layouts.md` § "Autosave Divider Positions". The cookbook spec is correct as-is; no adaptation needed.

## Blocked Tasks
<!-- Move here with reason + workaround if anything wedges. -->

---

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 |  |  |  |
| 2 | 2026-05-27 | 2026-05-27 | (uncommitted) |
| 3 | 2026-05-27 | 2026-05-27 | (uncommitted) |
| 4 | 2026-05-27 | 2026-05-27 | (uncommitted) |
| 5 |  |  |  |

---
*Delete or archive to `docs/sessions/` when all tasks complete.*
