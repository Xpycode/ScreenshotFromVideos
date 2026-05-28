# Implementation Plan — Phase 5 (Thumbnail Strip with Zoom-Density Coupling)

> Persists across sessions. Regenerate if reality diverges; don't patch.
> Built from three parallel research streams: Explore agent (codebase map),
> general-purpose agent (community + Apple/SDK + open-source references),
> direct apple-doc-mcp lookups (API surface confirmation).

## Goal
Below the AVPlayer in the left pane, render a horizontal **thumbnail strip** of the video. Default density **1 thumb/sec** (cheap on long clips). User pinches to zoom; **density AND thumb size grow together** — premise: zooming = hunting a specific frame, bigger + denser helps spot it. Tap a thumb to seek the player; ⌘-tap (or hover-pin) adds the time to `vm.manualTimes`. Background-render aggressively **while the user is zooming**, only-visible **while scrolling** — leveraging the macOS 15 `ScrollPhase` API.

## Acceptance Criteria
- [ ] Load a video → a horizontal thumbnail strip appears below the AVPlayer, ≥1 thumb visible at default zoom (1/sec, ~80 pt wide)
- [ ] Pinch-to-zoom on the strip: thumbs grow in size **and** more thumbs appear (density rises) **together**, smoothly, with no visible re-layout judder
- [ ] At max zoom, density approaches per-frame for the video's nominal FPS (capped at 30/sec for any source)
- [ ] Scrolling the strip horizontally only renders thumbs as they enter view (`ScrollPhase.interacting | .decelerating` path); idle/zooming triggers a wider prefetch window
- [ ] Playhead bar (1–2 pt vertical line, `Theme.accent`) follows the AVPlayer's current time live (~30 Hz)
- [ ] Click a thumb → AVPlayer seeks to that time (frame-accurate: `toleranceBefore/After: .zero`)
- [ ] ⌘-click a thumb → time appended to `vm.manualTimes` (existing manual-mode path); a small dot/pin appears over that thumb cell
- [ ] Memory ceiling: scrubbing a 60-minute clip at max zoom keeps the process under 500 MB resident (NSCache evicts under pressure)
- [ ] Cancel-replace on zoom changes: rapid zoom doesn't pile up generator work; only the latest target survives
- [ ] `xcodebuild clean build` with zero strict-concurrency warnings
- [ ] Visual smoke test passes on a real video (per `feedback_lifted_graphics_coords`): thumbs are right-side-up, correct aspect, current time bar aligned to the right thumb

## Non-Goals (deferred)
- Range-select scrubbing (highlight a [start, end] band on the strip → batch-add to manual list). Could be Phase 6.
- Audio waveform overlay on the strip
- Per-thumb scene-change detection ("smart" filmstrip)
- Configurable thumb cache size in UI (start with a fixed ProcessInfo-tiered ceiling)
- Cmd+scroll-wheel zoom for users without a trackpad (Wave 7+ if requested — trivial `NSViewRepresentable` add-on)

## Research Anchors

| Topic | Source | Decision |
|---|---|---|
| Batch frame API for the strip | apple-doc-mcp: `AVAssetImageGenerator.images(for:)` AsyncSequence, `Images.Element.success(requestedTime:image:actualTime:)` | Same API the export pipeline uses — proven on Swift 6. **Separate generator instance** from `ExtractionPipeline`: relaxed tolerance + `maximumSize`, so a strip-cancel doesn't nuke an export. |
| Crash gotcha | Apple Forums #761194 (web research) | Crash is in the **legacy callback** API, *not* `images(for:)`. Safe to reuse. |
| Tolerance per zoom | Web research (Apple "Creating images from a video asset") | Sparse zoom (1–5/sec): `±0.5 s` (snaps to I-frame, fast). Dense zoom (≥10/sec): `.zero / .zero`. Export pipeline keeps `.zero` always. |
| `maximumSize` | Apple's example uses `CGSize(300, 0)` | `CGSize(width: maxBucketWidth × 2 (Retina), height: 0)` — capped at 480 pt → 960 px @2x. Decoder downsamples cheaply, RAM stays bounded. |
| MagnifyGesture | apple-doc-mcp: `MagnifyGesture` macOS 14+ | `init(minimumScaleDelta: 0.02)`, `@GestureState` for live scale, persistent `zoomLevel: Double` on the model. `value.magnification` starts at 1.0. |
| MagnifyGesture × ScrollView conflict | Web research (HWS forum #28798, Apple Forums #760035 + #794212) | **Attach the gesture to the parent VStack (outside the ScrollView), not on the cells.** `.simultaneousGesture` on the parent. `.highPriorityGesture` is regressed on macOS 15. |
| Scroll phase detection | apple-doc-mcp: `ScrollPhase` (idle/tracking/interacting/decelerating/animating) + `isScrolling` — macOS 15+ | `.onScrollPhaseChange { _, new in isScrolling = new.isScrolling }`. Native macOS 15, no NSEvent intercept needed. |
| Visible-window detection | apple-doc-mcp: `.onScrollGeometryChange(for:of:action:)` + `ScrollGeometry.contentOffset` / `containerSize` — macOS 15+ | Derive `visibleTimeRange: ClosedRange<Double>` from `contentOffset.x / pointsPerSecond`. |
| Per-cell visibility (optional) | apple-doc-mcp: `.onScrollVisibilityChange(threshold:)` macOS 15+ | Could drive cell-level lazy render, but `onScrollGeometryChange` at strip level is enough — cheaper, single subscription. |
| Playhead source | Web research (Apple Dev Blog: `addPeriodicTimeObserver`) | `player.addPeriodicTimeObserver(forInterval: CMTime(1, 30), queue: .main)` → `@State currentTime: CMTime`. Token must be removed on view disappear / player change. |
| Cache layer | Web research (Sundell, HWS, Andy Ibanez) | `NSCache` wrapped Sundell-style for `Sendable` + value-type keys. `totalCostLimit` ≈ 300 MB on 16 GB Macs, tiered by `ProcessInfo.physicalMemory`. Cost per entry = `cgImage.bytesPerRow * cgImage.height`. |
| Cache key | Web research (CMTime hashability + bucketing) | `struct ThumbKey { timeMillis: Int64; widthBucket: Int }`. Width buckets: **60, 120, 240** (pt). Display size is continuous (60–240); cache fetches the **smallest bucket ≥ display size**, downscaled in display — so zooming within a bucket band is *free*. |
| Storage format | Web research (RY's Blog, Swift Senpai) | Start with `CGImage` in cache (simplest, fastest draw). JPEG-`Data` secondary tier only if profiling shows pressure on long clips. |
| Industry precedent | Web research: iMovie zoom-slider; FCP timeline | iMovie has explicit density-zoom; FCP has size-zoom; **no shipping app couples both onto one gesture** — this design is novel. iMovie is the closest reference. |
| Codebase insertion point | Explore agent: `LeftPaneView.loadedView` (line 71-81) | VStack(spacing: 0) → PlayerView (`.infinity`) → **Strip slots HERE, ~120 pt tall** → footer. |
| AVPlayer access | Explore agent: `ExtractionViewModel.player` (line 42) | Already exposed to views; reuse for both seek and playhead. |
| Manual-time integration | Explore agent: `ExtractionViewModel.manualTimes: [CMTime]` (line 53), `captureCurrentFrame()` (line 114) | ⌘-tap on a thumb calls a new `vm.captureFrame(at: CMTime)` (mirrors existing). |
| New-file pickup | Explore agent: `project.yml` line 26-27 (`sources: - path: ScreenshotFromVideos`) | xcodegen auto-includes; no project.yml edits needed. **Re-run `xcodegen generate` once** after adding files so the `.xcodeproj` knows about them. |

---

## Architecture

### Data model (lives in `App/StripModel.swift`, `@MainActor @Observable`)

```
StripModel
├── zoomLevel: Double                     // persistent, 1.0 = default, max ≈ 30
├── isMagnifying: Bool                    // true while MagnifyGesture in flight
├── isScrolling: Bool                     // mirrors ScrollPhase.isScrolling
├── visibleTimeRange: ClosedRange<Double> // updated from .onScrollGeometryChange
├── duration: Double                      // from vm.metadata
├── nominalFPS: Float                     // from vm.metadata
├── cache: ThumbnailCache                 // injected; bounded by ProcessInfo tier
└── renderer: ThumbnailRenderer           // owns its own AVAssetImageGenerator
```

**Derived (computed):**
- `density: Double` (thumbs/sec) = `min(fps, baseDensity × log2-curve(zoom))` ≈ `1.0 × pow(2, zoomLevel/6)`, capped at `nominalFPS`
- `thumbWidth: CGFloat` = `60 + (240 - 60) × normalized(zoom)` in pt
- `widthBucket: Int` = smallest of {60, 120, 240} ≥ thumbWidth
- `pointsPerSecond: CGFloat` = `thumbWidth × density` — single source of truth for layout AND visible-range math
- `totalContentWidth: CGFloat` = `duration × pointsPerSecond`
- `thumbnailTimes(in: ClosedRange<Double>) -> [CMTime]` — quantized to the density grid

**Prefetch policy matrix (the heart of the feature):**

| `isMagnifying` | `isScrolling` | Render strategy |
|---|---|---|
| true  | any   | `visibleTimeRange ± visibleWidth × 0.5` — speculative |
| false | true  | `visibleTimeRange` strictly |
| false | false | `visibleTimeRange ± visibleWidth × 0.2` — small idle prefetch |

### Render pipeline (lives in `Core/ThumbnailRenderer.swift`)

```
ThumbnailRenderer
├── asset: AVAsset
├── generator: AVAssetImageGenerator     // OWN instance, NOT shared with ExtractionPipeline
│   ├── maximumSize: 480 pt × 0 (proportional)
│   ├── tolerance: ±0.5 s default; tightened by caller per zoom level
│   └── appliesPreferredTrackTransform = true
└── render(times: [CMTime], targetWidth: Int) -> AsyncStream<(CMTime, CGImage)>
    └── consumes generator.images(for: times), yields .success cases
        — same Swift 6-safe path as ExtractionPipeline uses
```

**Cancellation:** the consumer (`StripModel`) holds a `Task<Void, Never>?`; on zoom change, cancel old, launch new. The renderer's `images(for:)` cooperates with `Task` cancellation — no manual `cancelAllCGImageGeneration` needed (it's called automatically when the iterator drops).

### Cache (lives in `App/ThumbnailCache.swift`)

```
ThumbnailCache (Sundell-style NSCache wrapper)
├── ThumbKey: Hashable { timeMillis: Int64; widthBucket: Int }
├── NSCache<WrappedKey, Entry>
├── totalCostLimit: 200 MB (8 GB), 300 MB (16 GB), 500 MB (≥32 GB) — ProcessInfo tier
└── func image(for: ThumbKey) -> CGImage?     // sync, fast
    func store(_:for:cost:)                   // sync; cost = bytesPerRow * height
```

### View tree

```
LeftPaneView (modified)
├── PlayerView                        // existing, .infinity height share
├── ThumbnailStripView ← NEW           // 100–140 pt tall, full width
│   ├── ScrollView(.horizontal) {
│   │     ZStack(alignment: .leading) {
│   │       LazyHStack(spacing: 1) { ForEach(times) { ThumbnailCellView(...) } }
│   │       PlayheadOverlay              // 2pt accent line, positioned by currentTime
│   │       ManualPinsOverlay            // small dots over manualTimes positions
│   │     }
│   │   }
│   │   .onScrollGeometryChange(...)    // visibleTimeRange
│   │   .onScrollPhaseChange(...)       // isScrolling
│   └── // gesture attached to PARENT (LeftPaneView), see below
└── footer                            // existing
```

The **`MagnifyGesture` is attached to `LeftPaneView`'s outer VStack** via `.simultaneousGesture`, not to the ScrollView's children — this is the empirically-known way to avoid gesture-vs-scroll conflicts on macOS 15.

---

## Tasks

### Wave 1 — Foundations (parallel, no inter-deps) ✅ shipped 2026-05-27

> **Folder note:** all 5 Phase 5 files live under `Thumbnail/` (single-feature grouping per PROJECT_STATE's "Next Actions"), not scattered across `Core/App/UI` as originally drafted.

- [x] **1.1**: Create `Thumbnail/ThumbnailRenderer.swift` (60 lines, cap 90)
  - Pattern: distilled from `ExtractionPipeline.swift` lines 49–123, but no PNG write, no overlay, no filename templating.
  - API: `init(asset: AVAsset)`, `func render(times: [CMTime], targetWidth: Int, tolerance: CMTime) -> AsyncStream<(CMTime, CGImage)>`.
  - Internals: builds an `AVAssetImageGenerator` with `maximumSize = CGSize(width: CGFloat(targetWidth) * 2, height: 0)`, `requestedTimeToleranceBefore/After = tolerance`, `appliesPreferredTrackTransform = true`. Consumes `generator.images(for: times)` as AsyncSequence; yields only `.success` cases keyed by `requestedTime`; logs `.failure` and continues.
  - Cancellation: relies on parent `Task` cancellation propagating to `images(for:)` iterator (already proven in `ExtractionPipeline`).
  - Header comment: "Sibling of `ExtractionPipeline.swift` — strip-side variant. No file I/O, no overlay."
  - Success: file compiles; standalone `#Preview` or a `#if DEBUG` smoke call in `LeftPaneView.task` round-trips a single time → CGImage.
  - Backpressure: `xcodebuild clean build` succeeds; no warnings.

- [x] **1.2**: Create `Thumbnail/ThumbnailCache.swift` (64 lines, cap 80)
  - Sundell-pattern `Cache<Key: Hashable, Value: AnyObject>` (`WrappedKey: NSObject` + `Entry: NSObject`). Public init takes `totalCostLimit: Int`.
  - `ThumbKey: Hashable { timeMillis: Int64; widthBucket: Int }` — file-local nested type or sibling struct.
  - Helper: `static func tier() -> Int` returning bytes based on `ProcessInfo.processInfo.physicalMemory` (≤8 GB → 200 MB, 8–32 GB → 300 MB, ≥32 GB → 500 MB).
  - Helper: `static func cost(of cgImage: CGImage) -> Int` returning `cgImage.bytesPerRow * cgImage.height`.
  - Helper: `static func bucket(for displayWidth: CGFloat) -> Int` returning smallest of `[60, 120, 240]` ≥ `displayWidth`, clamped to 240.
  - Sendability: mark the wrapper `@unchecked Sendable` with a comment citing NSCache's documented thread-safety.
  - Success: a `#if DEBUG` quick check round-trips an image; `cache.totalCostLimit` matches expected tier on the dev machine.
  - Backpressure: build succeeds with zero warnings.

- [x] **1.3**: Create `Thumbnail/StripModel.swift` (140 lines, cap 140) — xcodebuild clean build PASSED, zero warnings under SWIFT_STRICT_CONCURRENCY=complete
  - `@MainActor @Observable final class StripModel`.
  - Stored: `var zoomLevel: Double = 1.0`, `var isMagnifying = false`, `var isScrolling = false`, `var visibleTimeRange: ClosedRange<Double> = 0...1`, `let duration: Double`, `let nominalFPS: Float`, `let cache: ThumbnailCache`, `let renderer: ThumbnailRenderer`, `@ObservationIgnored private var task: Task<Void, Never>?`.
  - Computed: `density`, `thumbWidth`, `widthBucket`, `pointsPerSecond`, `totalContentWidth`, `thumbnailTimes(in:)` (per architecture section above).
  - `func scheduleRender()` — cancels `task`, computes target times from policy matrix + visible range, debounces 80 ms via `Task.sleep`, iterates `renderer.render(...)` writing to cache.
  - `func onZoomChange(magnification: Double)` — recomputes `zoomLevel` (clamped), triggers `scheduleRender()`.
  - `func onVisibleRangeChange(_:)`, `func onScrollPhaseChange(_:)`, `func onMagnifyStart/End()`.
  - Header comment: "Owns the strip's zoom/scroll state and the render task. Single source of truth; ThumbnailStripView reads, doesn't mutate."
  - Success: instantiates from `VideoMetadata`; computed properties make sense (zoom 1.0 → density 1.0/sec → width 80 pt).
  - Backpressure: build succeeds; no warnings.

### Wave 2 — Static strip (no zoom, no interaction) — proves the rendering loop ✅ shipped 2026-05-27

> **Folder note:** same as Wave 1 — all Phase 5 files in `Thumbnail/`, not `UI/`.

- [x] **2.1**: Create `Thumbnail/ThumbnailCellView.swift` (44 lines, cap 60) — clean build
  - Input: `time: CMTime`, `widthBucket: Int`, `displaySize: CGSize`, `cache: ThumbnailCache`, `manualPinned: Bool` (default false).
  - Body: `Group { if let img = cache.image(for: ThumbKey(timeMillis: ..., widthBucket: ...)) { Image(decorative: img, scale: 2).resizable().scaledToFill().frame(width: displaySize.width, height: displaySize.height).clipped() } else { Theme.secondaryBackground } }` — placeholder rectangle on miss.
  - Optional: small dot in corner if `manualPinned`.
  - No tap, no hover yet.
  - Success: a `#Preview` with a hand-baked cache shows two cells (one filled, one placeholder).
  - Backpressure: build succeeds.

- [x] **2.2**: Create `Thumbnail/ThumbnailStripView.swift` (102 lines, cap 140) — clean build
  - Input: `model: StripModel`, `player: AVPlayer?`.
  - Body: `ScrollView(.horizontal, showsIndicators: false) { ZStack(alignment: .leading) { LazyHStack(spacing: 1) { ForEach(model.thumbnailTimes(in: 0...model.duration), id: \.value) { time in ThumbnailCellView(...) } } ; PlayheadBar(currentTime: $currentTime, pps: model.pointsPerSecond) } }`.
  - `@State private var currentTime: CMTime = .zero` plus an AVPlayer time observer wired in `.task(id: player)` — install observer, await suspension, remove on task cancellation.
  - `.onScrollGeometryChange(for: ClosedRange<Double>.self) { geom in ... } action: { model.onVisibleRangeChange(...) }`.
  - `.onScrollPhaseChange { _, new in model.onScrollPhaseChange(new) }`.
  - Height: 120 pt fixed (containerSize-relative thumb height = ~85 pt for 16:9 at 240 px).
  - Background: `Theme.secondaryBackground`.
  - No zoom gesture here — that's Wave 3, attached at parent.
  - Success: a sample video loads, strip shows placeholders for the visible window that fill in within ~1 sec.
  - Backpressure: build succeeds; running the app shows a strip below the player; scrolling left/right reveals more thumbs lazily.

- [x] **2.3**: Wire strip into `UI/LeftPaneView.swift` — clean build (visual smoke deferred — see PROJECT_STATE)
  - In `loadedView` (currently line 72–81), insert `ThumbnailStripView(model: stripModel, player: vm.player).frame(height: 120)` between `PlayerView` and `footer`.
  - Add `@State private var stripModel: StripModel?` — initialize in `.task(id: vm.metadata)` when metadata arrives (so `duration` and `nominalFPS` are known).
  - When `vm.metadata` clears (video unloaded), `stripModel = nil` and the strip disappears.
  - Success: video loads → strip appears; unloaded → strip gone; PlayerView is unaffected.
  - Backpressure: visual smoke test per `feedback_lifted_graphics_coords`. Check: thumbs are right-side-up (CGImage default has origin top-left; AVFoundation usually delivers in display orientation when `appliesPreferredTrackTransform = true` — VERIFY visually, do not trust the build).

### Wave 3 — Zoom-density coupling ✅ shipped 2026-05-27 (visual smoke pending)

- [x] **3.1**: Add MagnifyGesture in `UI/LeftPaneView.swift`
  - `@GestureState private var liveScale: Double = 1.0` (auto-resets on end).
  - `var pinch: some Gesture { MagnifyGesture(minimumScaleDelta: 0.02).updating($liveScale) { v,s,_ in s = v.magnification }.onChanged { v in if let m = stripModel, !m.isMagnifying { m.onMagnifyStart() }; stripModel?.onZoomChange(magnification: v.magnification) }.onEnded { v in stripModel?.commitZoom(v.magnification); stripModel?.onMagnifyEnd() } }`.
  - Attach `.simultaneousGesture(pinch)` to the **outer VStack** of `loadedView`, NOT to the strip's ScrollView children.
  - Success: pinching anywhere over the left pane changes the strip's thumb count and size *together*, smoothly.
  - Backpressure: build clean; manually verify: pinching does NOT break vertical/horizontal scrolling of the strip.

- [x] **3.2**: Implement zoom curves + prefetch policy in `App/StripModel.swift` (curves shipped with Wave 1.3; Wave 3 added baseline-snapshot fix for the gesture compounding bug)
  - `density` curve: `let exp = zoomLevel * 0.6; return min(Double(nominalFPS), pow(2, exp))` — at zoom 1.0 → density ≈ 1.0/sec; zoom 5.0 → ≈ 8/sec; zoom 8.0 → 27/sec; clamps to FPS.
  - `thumbWidth` curve: `60 + (240 - 60) * smoothstep(0, 10, zoomLevel)` (so width saturates at 240 pt before density does — looks better).
  - Prefetch policy implementation per matrix:
    ```swift
    var prefetchRange: ClosedRange<Double> {
        let pad: Double
        if isMagnifying { pad = (visibleTimeRange.upperBound - visibleTimeRange.lowerBound) * 0.5 }
        else if isScrolling { pad = 0 }
        else { pad = (visibleTimeRange.upperBound - visibleTimeRange.lowerBound) * 0.2 }
        return max(0, visibleTimeRange.lowerBound - pad)
            ... min(duration, visibleTimeRange.upperBound + pad)
    }
    ```
  - `scheduleRender()` debounces 80 ms (via `Task { try? await Task.sleep(for: .milliseconds(80)); guard !Task.isCancelled else { return }; ... }` pattern, cancel-replace on each call).
  - Tolerance: `density < 5 ? CMTime(seconds: 0.5, preferredTimescale: 600) : .zero`.
  - Success: rapid zoom doesn't pile up; only the latest target finishes; Instruments confirms generator activity correlates with zoom changes.
  - Backpressure: build clean.

### Wave 4 — Tap interactions

> **Updated 2026-05-27 (post-Wave 3, pre-implementation):** Paths corrected to `Thumbnail/` (folder consolidated in Wave 1). Success criteria updated for the contact-sheet grid pivot (no playhead bar — the active-cell border is now the visual cue). Research notes from Apple docs + community appended at the end of this section.

- [ ] **4.1**: Add seek-on-tap in `Thumbnail/ThumbnailCellView.swift` + `Thumbnail/ThumbnailStripView.swift`
  - **Cell** (`ThumbnailCellView`): add `let onTap: (CMTime) -> Void` (required prop — no default, so missing wiring fails at compile time). Append to the body chain:
    ```swift
    .contentShape(Rectangle())
    .onTapGesture { onTap(time) }
    ```
    `.contentShape(Rectangle())` is required because the cell body is a `Group { if image else placeholder }` — SwiftUI hit-tests against the layout shape, but conditional inner content can collapse the implicit hit region during placeholder render. The explicit `Rectangle()` content-shape pins it to the full cell frame.
  - **Strip** (`ThumbnailStripView`): pass `onTap: { time in player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) }` into each cell. `.zero / .zero` requests **sample-accurate seeking** — Apple's recommended pattern for precise jumps (*"Controlling the transport behavior of a player"*). The user clicked a *specific* thumb; they expect to land on that frame, not whatever keyframe is nearest. Decoding cost is borne once per click and is negligible for the short clips this app targets.
  - **Hit-testing fix:** the active-cell border overlay (`Rectangle().strokeBorder(...)` in the strip's `ForEach`) must get `.allowsHitTesting(false)`. SwiftUI hit-tests by *layout* shape, so the full-rect overlay would otherwise swallow taps on whichever cell is currently active. The border is purely decorative, so disabling its hit-testing is correct.
  - Success: clicking any thumb seeks the AVPlayer precisely to that thumb's `time`; on the next periodic-time-observer tick (≤33 ms at the strip's 1/30 s interval), `activeIndex` recomputes and the 2 pt accent border snaps to the clicked cell.
  - Backpressure: build clean; manual click test confirms seek + border-snap.

- [ ] **4.2**: Add ⌘-click capture in `Thumbnail/ThumbnailCellView.swift` + `App/ExtractionViewModel.swift`
  - **Recommended pattern (macOS-15-native):** add `@State private var isCommandHeld = false` to the cell, track via `.onModifierKeysChanged(mask: .command, initial: false) { _, new in isCommandHeld = new.contains(.command) }`, branch inside the tap closure: `.onTapGesture { isCommandHeld ? onCmdTap(time) : onTap(time) }`. Avoids `TapGesture.modifiers(.command)`, which is still reported flaky in 2025 (see Open Q 1).
  - **Fallback if `onModifierKeysChanged` misbehaves:** read `NSEvent.modifierFlags.contains(.command)` synchronously at tap time. NSEvent reads global modifier state on the calling thread; safe inside the tap closure on the main actor.
  - In `ExtractionViewModel`, add `func captureFrame(at time: CMTime)` mirroring `captureCurrentFrame()` (lines 159–164) but for an arbitrary time. Dedupe against `manualTimes` (linear `contains` is fine — list is small).
  - Strip passes `onCmdTap: { time in vm.captureFrame(at: time) }` and a `manualPinned: Bool` per cell, computed as `vm.manualTimes.contains { CMTimeAbsoluteValue(CMTimeSubtract($0, time)) < cellInterval/2 }`. Keep the cell vm-unaware — pass the resolved Bool, not the model.
  - Success: ⌘-clicking a thumb appends its time to the manual list (visible in right pane's manual tab); a 4 pt accent dot renders in the cell's top-right.
  - Backpressure: build clean.

#### Research notes (added 2026-05-27)

- **Sample-accurate seek tolerance** — Apple's [*"Controlling the transport behavior of a player"*](https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player) article specifies `seek(to:toleranceBefore:.zero, toleranceAfter:.zero)` for precise seeking. Cost is "additional decoding delay"; meaningful only for continuous-scrub UIs (not our case).
- **Overlay hit testing** — SwiftUI hit-tests by **layout shape, not visual shape** (community-confirmed via hackingwithswift.com + Apple DevForums). A `Rectangle().strokeBorder(...)` overlay has a full-rect hit region despite painting only a thin line. Decorative overlays inside tap-handling views need `.allowsHitTesting(false)`.
- **`onTapGesture` inside `LazyVGrid` + `ScrollView`** — works fine, but `.contentShape(Rectangle())` is the canonical fix when the inner content is conditional (e.g. our `Group { if image else placeholder }`) — without it, the hit region can collapse during placeholder rendering.
- **`TapGesture.modifiers(.command)` flakiness** — historically misbehaving on macOS (Apple DevForums thread #654154, ongoing 2024–2025 reports). The macOS-15 `onModifierKeysChanged(mask:initial:_:)` API is the cleaner replacement; `NSEvent.modifierFlags` is the second-tier fallback.
- **Pinch + tap coexistence** — `MagnifyGesture` lives on `LeftPaneView`'s outer VStack as `.simultaneousGesture(pinch)`. Cell-level `.onTapGesture` doesn't conflict: pinch is a two-finger trackpad gesture vs tap's one-finger click, and SwiftUI gesture arbitration explicitly permits simultaneous recognizers across the hierarchy.

### Wave 5 — Cache integration + render output → cache

- [ ] **5.1**: Wire renderer → cache in `App/StripModel.swift.scheduleRender()`
  - Inside the debounced task: compute `times`, filter out those already in cache (`cache.image(for: key) != nil`), call `renderer.render(times: missing, targetWidth: widthBucket, tolerance: ...)`, iterate `for await (time, image) in stream { cache.store(image, for: ThumbKey(timeMillis: ..., widthBucket: widthBucket), cost: ThumbnailCache.cost(of: image)) }`. After insertion, signal observation (set a counter `@Published var cacheVersion: Int` to force cell re-eval, since cells can't observe NSCache directly).
  - Cells re-read via `cache.image(for:)` on body re-eval triggered by `cacheVersion` change.
  - Success: cache fills as the user looks at the strip; re-zoom within the same bucket doesn't trigger any new generator work (verify by adding a temporary `print` in renderer init).
  - Backpressure: clean build. Instruments check: no thread explosions, generator count stays ≤2 in flight.

- [ ] **5.2**: Confirm memory ceiling
  - Load a 60-minute test video. Zoom in to max. Scrub left and right repeatedly.
  - Expectation: process resident memory stays under `cache.totalCostLimit + 200 MB overhead` (so ~500 MB on a 16 GB machine).
  - If it overruns: the most likely cause is `Image(decorative:)` retaining beyond cell off-screen — investigate cell teardown; in worst case, drop NSCache to half its current tier value.
  - Success: 60-minute clip @ max zoom stable for 30 sec of scrubbing under 500 MB.
  - Backpressure: visual smoke + Activity Monitor reading recorded in session log.

### Wave 6 — Verification matrix + polish

- [ ] **6.1**: Manual test matrix
  - (a) Load a 5-second clip → strip shows ~5 thumbs at default zoom; max zoom shows ~150 thumbs.
  - (b) Load a 60-minute clip → strip default 3600 thumbs (lazy — only visible window decodes). Open it cold; first paint <1 sec.
  - (c) Pinch in fast → no judder; final state matches gesture end.
  - (d) Scroll while paused → only visible thumbs decode (Instruments: `generateCGImageAsynchronously` calls correlate to scroll position).
  - (e) Pinch in (zoom) while paused, hold → strip pre-renders ±50% of visible window in background.
  - (f) Click a thumb → player seeks; playhead bar repositions; `vm.player?.currentTime()` matches the thumb's time (±tolerance).
  - (g) ⌘-click 3 thumbs at different times → right pane manual list shows 3 entries; 3 dots on strip.
  - (h) Export with the 3 manual times → PNGs produced at those exact frames (existing pipeline; should JustWork™).
  - (i) Unload video → strip disappears cleanly; no orphaned periodic time observer (verify by re-loading and re-checking).
  - (j) Cancel running export → strip and player both keep working; cancel doesn't affect strip rendering.
  - Update `docs/sessions/<today>.md` with results of each.

- [ ] **6.2**: Edge cases
  - Zero-duration / audio-only file → strip should be empty or hidden (decide in 6.1(a) review).
  - Very short clips (<1 sec) → density math doesn't divide by zero; widthBucket math doesn't underflow.
  - HDR videos (`dynamicRangePolicy`) — *out of scope* for this phase; keep default (SDR-clamp).

- [ ] **6.3**: Archive plan + rotate state
  - Move `PHASE5_PLAN_thumbnail_strip.md` → `docs/sessions/_archive/`.
  - Update `docs/PROJECT_STATE.md`: phase → "Phase 6 (next focus TBD)", clear Phase-5 items.
  - Log a decision in `docs/decisions.md` capturing: zoom-density curves, cache tier policy, MagnifyGesture-at-parent placement (these are non-obvious and worth recording).

---

## Open Questions to Resolve During Implementation

1. **Tap-modifier semantics on macOS 15+**: `TapGesture.modifiers(.command)` is still flaky per ongoing Apple DevForums reports (#654154, etc.) into 2025. Plan defaults to the macOS-15 `onModifierKeysChanged(mask: .command, initial: false)` API for tracking ⌘-held state, with `NSEvent.modifierFlags.contains(.command)` as the second-tier fallback. Final decision deferred to actual Wave 4.2 smoke test.
2. **`images(for:)` delivery order**: Apple says "exactly one callback per requested time" but doesn't explicitly guarantee request-order. Key the cache by `requestedTime` from the element (do this from day 1 — already in the plan).
3. **Speculative-during-zoom budget cap**: at extreme zoom on long video, even ±50% of visible could be hundreds of thumbs. The 80 ms debounce + cancel-replace should soft-cap this in practice; if Instruments shows generator queue growth, add a hard cap of e.g. 256 in-flight per render task.
4. **NSCache vs explicit memory-pressure source**: NSCache responds to macOS memory pressure, but if profiling shows it's slow to evict, add a `DispatchSourceMemoryPressure` listener that calls `cache.removeAllObjects()` on `.critical`.
5. **Visual smoke for graphics**: lift heritage notes for thumb orientation. `appliesPreferredTrackTransform = true` *usually* handles rotated source video correctly, but per `feedback_lifted_graphics_coords` this must be visually verified, not just compile-checked.

---

## File Manifest (new + modified)

**New files** (all under `01_Project/ScreenshotFromVideos/`):

| File | Wave | Cap | Role |
|---|---|---|---|
| `Core/ThumbnailRenderer.swift` | 1.1 | ≤90 lines | Strip-side variant of ExtractionPipeline |
| `App/ThumbnailCache.swift` | 1.2 | ≤80 lines | NSCache wrapper + ThumbKey + cost/tier helpers |
| `App/StripModel.swift` | 1.3 | ≤140 lines | @MainActor @Observable, zoom/scroll/render orchestration |
| `UI/ThumbnailCellView.swift` | 2.1, 4.1, 4.2 | ≤60 lines | One cell — cache lookup, tap, ⌘-tap, pin dot |
| `UI/ThumbnailStripView.swift` | 2.2 | ≤140 lines | Strip shell: ScrollView + LazyHStack + overlays + observers |

**Modified files:**

| File | Wave | Change |
|---|---|---|
| `UI/LeftPaneView.swift` | 2.3, 3.1 | Insert strip into loadedView; attach `.simultaneousGesture(MagnifyGesture)` to outer VStack; create stripModel in `.task(id: vm.metadata)` |
| `App/ExtractionViewModel.swift` | 4.2 | Add `captureFrame(at time: CMTime)` — dedupe-then-append to `manualTimes` |

**xcodegen:** run `cd 01_Project && xcodegen generate` once after Wave 1's files exist so the `.xcodeproj` references them. Subsequent files within the same `ScreenshotFromVideos/` tree are picked up automatically without a regen, but a final regen before Wave 6 is wise.

**No project.yml edit needed** — `sources: - path: ScreenshotFromVideos` (line 27) auto-includes all subdirs.
