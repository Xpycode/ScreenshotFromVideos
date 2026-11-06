# Paused zoom pipeline trace — 2026-10-29

Status: focused trace captured/analyzed 2026-11-01. Final demand targets frames about ten seconds before selected cell; decode/store/refresh for that wrong range succeed. Product fix and manual F6 acceptance remain open. No product fix or F6 pass claimed. User operates app; no launch, quit, UI input, preferences or profile changes performed by agent. Preserve accepted uninstrumented CPU evidence; this probe is not a performance benchmark.

## Source path

Zoom entry points in StripModel update density/width and schedule a render. ThumbnailStripView observes density/width and reprojects raw viewport geometry; changed demand schedules another render. scheduleRender cancels the predecessor, respects the shared 80 ms zoom deadline, filters exact cache hits, prioritizes the visible center and caps requests at 256. A fresh AVAssetImageGenerator per batch returns requested-time keys. The model stores these images and bumps cacheVersion at most about every 100 ms plus a pending final bump. Equatable cells include cacheVersion; their lookup order is exact key, same time in another width bucket, last displayed image, placeholder. No source-only proof of the paused failure was found.

## Temporary instrumentation

Compile condition `SFV_ZOOM_DIAGNOSTICS` enables a bounded per-process trace at `/private/tmp/sfv-zoom-events-<PID>.log`. Filename uses actual process ID; startup does not overwrite an earlier process's trace. All string interpolation/file access is disabled in default builds. Helper resides in ThumbnailRenderer.swift so standalone renderer diagnostics remain compilable without another source dependency. No generator reuse, tolerance, cache policy, debounce or refresh policy change.

Events connect:
- `zoom`, `viewport`: density, bucket, actual geometry/projection and demand range.
- `selection`: recomputed index, requested key, player time, density and bucket; emitted when the selected key or bucket changes, including same-index zoom transitions.
- `schedule`, `cancel-request`, `batch-end`: reason, batch ID, demand, cancellation and stored count.
- `cache-scan`, `decode-start`: missing count and complete capped requested key list.
- `decode-success`, `decode-failure`, `decode-catch`, `decode-cancel`, `decode-finish`, `stream-termination`: delivered keys, actual times, dimensions, errors and producer/stream lifecycle. A cancellation event after normal stream finish can arise from existing termination cleanup; it alone does not mean demand was lost.
- `cache-store`, `refresh`: stored key/bucket, immediate retention, and published version including final pending flush.
- `cell-read`, `cell-sync`: cell key, bucket, received version and selected image source/exact availability. These establish SwiftUI lookup activity, not proof of compositor pixels or nonblack decoded content.

Cell events are filtered to within 100 ms of the selected key. Selection key/bucket changes update this focus; reads before focus installation may be omitted. Absence of a cell event alone is not proof of no evaluation.

Limitations: synchronous diagnostic I/O and extra cache reads perturb timing/cache recency; use one app launch and one clip load because batch IDs reset per model. No eviction delegate/history is installed. After 100,000 events a `TRACE-LIMIT` marker is written; missing later events prove nothing. Decoder success alone does not prove an image contains nonblack pixels. A changed symptom under instrumentation needs follow-up, not inferred acceptance.

## Validation

Build-only, no app-hosted tests or startup. Scheme/project contain no custom build/test scripts; application startup initializes ordinary view model and Sparkle updater, neither executed by this build. Exact command from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`:

```sh
xcodebuild -project 01_Project/ScreenshotFromVideos.xcodeproj -scheme ScreenshotFromVideos -configuration Debug -derivedDataPath /private/tmp/sfv-zoom-focused-build -clonedSourcePackagesDirPath /Users/sim/Library/Developer/Xcode/DerivedData/ScreenshotFromVideos-cucpispgpnspddadwxkzflnyrvmm/SourcePackages -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- SWIFT_STRICT_CONCURRENCY=complete SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG SFV_ZOOM_DIAGNOSTICS' build
```

Initial broad-trace sandbox build exited 74 on Xcode/SwiftPM cache permissions. Cache-authorized build succeeded, then final incremental build after selection-trace correction succeeded (exit 0). Revised focused build also succeeded (exit 0). Only AppIntents metadata warning; no application-source warnings. [Focused build log](focused-build.log), [source/artifact checksums](source-artifact.sha256), [diagnostic-only delta](diagnostic-only.diff) retain evidence independent of overlapping prior dirty work.

Default-condition renderer typecheck also exited 0: `swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors -module-cache-path /private/tmp/sfv-zoom-trace-module-cache 01_Project/ScreenshotFromVideos/Thumbnail/ThumbnailRenderer.swift`. Headless probe compile/run with and without the flag passed Swift 6 complete concurrency, warnings-as-errors: 50,000 unrelated cell events produce zero message evaluations, five later selection/zoom/selected-cell events survive; default build creates no log. [Smoke source](probe-check.swift), [output](probe-check.log), [result/effects](probe-check-summary.txt). No app launch or media decode in smoke. No tests of unchanged playback/seek logic repeated. Independent fresh-context read-only review found selection-key attribution could combine old index/new density; corrected by logging after recomputation in updateActiveIndex. Focused-helper review found no concurrency/deadlock issues; focus-installation filtering limitation retained above. No concurrency/behavior findings otherwise; probe overhead/cap/model-reset limitations retained above. `git diff --check` passed. No commit/push: temporary probe overlaps preserved earlier dirty source; remove after runtime diagnosis.

## User-operated capture

1. Quit Stills From Video normally. Stop if busy or prompted about unsaved work; do not force quit.
2. Finder Go to Folder: `/private/tmp/sfv-zoom-focused-build/Build/Products/Debug`. Open `ScreenshotFromVideos.app` (bundle version 0.1 (1)). Agent has not launched it.
3. Load `/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4` once. Pause near the failed position (prior selected frame 45899, 00:25:29:29). Reset zoom, then move slider to maximum and leave paused for 20 seconds.
4. Report selected timecode and whether placeholder persists; keep app open. Agent then verifies actual executable PID/path and reads/copies that PID's trace into this folder before analysis. Do not infer runtime trace exists from a successful build.

Next: correlate selected key through final viewport demand → capped decode request → delivery → cache store → published version → cell read. If absent from demand investigate geometry; if absent from capped request inspect filtering/cap; if request fails inspect decode; if stored but not read inspect refresh delivery; if exact read but black inspect image content/display. Preserve F6 and other manual gates until actual evidence resolves them.


## First runtime reproduction — retained, trace insufficient

User supplied [immediate screenshot](paused-immediate.png) and [two-minutes-later screenshot](paused-two-minutes.png). Both show paused every-frame zoom at 00:25:29:09, frame 45,879, selected thumbnail still placeholder-dark while player shows test pattern. This confirms failure persists; screenshots do not establish decode/cache cause.

Read-only process inspection (sandbox denied, authorized retry exit 0): PID 13870, start Thu Oct 29 14:20:35 2026, exact executable `/private/tmp/sfv-zoom-trace-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos`. No lifecycle/UI/profile actions. Saved [raw trace](zoom-events-13870.log) before any relaunch. First event uptime 992078.5954; TRACE-LIMIT at 992100.8201, just 22.225 seconds later. 15,667 cell-read + 11,690 cell-sync entries = 27,357/30,000 payload events (91.19%). All 174 recorded schedules are default zoom; no zoom event recorded. Last selection is index1788/key1179640, prior to screenshot position. Therefore no inference about failed selected key1529300 request/decode/store/refresh is possible from this trace. Pre-zoom cancellation/delivery activity alone does not establish the paused failure cause.

Revised probe filters cell events to selected key ±100 ms, tracks selected key/bucket transitions even if numeric index remains unchanged, and raises the overall cap to100,000. All core pipeline events remain unfiltered. Independent review plus headless flood check address the capture failure. Retry is justified by missing zoom evidence, not a repeated acceptance matrix. Focused build is a separate artifact; old running app untouched. Current hashes/diff describe focused source; initial hashes/diff/build.log preserve the first diagnostic configuration. Do not combine the first trace with focused source as if identical.


## Focused capture — 2026-11-01: demand mismatch established

User replied “captured” after requested repeat. Read-only process inspection exit0 verifies PID37906/start Sun Nov1 04:19:29 2026 and exact executable `/private/tmp/sfv-zoom-focused-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos`. All four current instrumented sources plus executable match source-artifact.sha256. Saved [raw focused trace](zoom-events-37906.log) and [structured summary](focused-summary-37906.json). 10,204 events, no TRACE-LIMIT. No launch/quit/input/preferences/profile operations or new builds/tests by agent.

Evidence chain (this capture's position differs from the prior screenshot):
- Event10015: selected index45238, key1507933 (1507.933s), player1507.948333s, density30, width bucket240.
- Event10068: batch884 does request the selected key, but events10070–10074 cancel that batch when zoom9→9.5. No success or cache-store for key1507933 anywhere in this capture. Cancellation during zoom is expected; the missing successor demand is the relevant defect.
- Events10103–10110: zoom10/240-point cells, viewport696×315, offset3055853; analytic projection settles at1497.933...1498.133s, around ten seconds before selection. Zoom10→12 keeps identical cell width/density and inherits this range.
- Event10151: final batch894 at zoom12 requests prefetch1497.893...1498.173s. Event10154 decodes remaining keys1497900...1498167; one additional key1497865 was retained from batch892. All9 final requests deliver/store; no final batch failure. This is not selected-key failure or eviction: the final batch does not request the selected key at all.
- Events10157/10190 publish versions285/286. Events10194/10200 show selected cell key1507933 receiving version286, re-reading cache with source=placeholder/exact=false. Refresh delivery is working for this cell; filling another time range cannot replace its placeholder. Final batch ends normally (event10191). The producer's cleanup cancellation after stream finished is not evidence of failed final delivery.

Independent read-only causal review (`zoom_trace_review`) confirmed the chain and its visibility/geometry limits; no edits, app control, builds or tests by reviewer.

Supported conclusion: final demand is inconsistent with the selected/rendered cell identities, starving them while successfully caching earlier frames. The analytical contentOffset→row→time mapping in ThumbnailViewport/refreshViewport is not a reliable description of the grid after this deep zoom transition. LazyVGrid estimated layout/offset drift is a plausible underlying mechanism, not established by this instrumentation alone (actual cell positions/content-size estimates were not logged). Trace cell reads prove SwiftUI lookup activity, not exact viewport intersection/compositor pixels. No claim that AVFoundation never fails: earlier unrelated batches have decode errors, but those do not explain this selected-key chain.

Next implementation direction: derive visible decode demand from actual cell bounds intersecting the viewport (existing indexed anchors offer an integration point), rather than trusting only division of a deep lazy-grid offset by nominal row height. Cover selected and other visible cells, scrolling and zoom; an unconditional selected-key prefetch alone would hide the selected symptom while leaving neighboring demand incorrect. Preserve debounce/cap/cache refresh and seek behavior. Keep F6 open until the affected paused-zoom path fills in a user test; no new all-state CPU benchmark is warranted by diagnosis alone.
