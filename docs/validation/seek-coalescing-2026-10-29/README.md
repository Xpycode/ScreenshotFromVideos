# Wave 3 — seek coalescing

## Implemented and checked

- Task 3.1: ordinary MainActor `SeekCoalescer` retained in view State; no observable hot state. All three navigation paths (cell tap, relative jump, cell navigation including Home/End/Page keys) issue exact, zero-tolerance seeks through it. One outstanding seek per player; only latest intent retained. Relative input uses pending target, otherwise the player's current time so it cannot lag the periodic observer after completion.
- Reset discards intent while preserving outstanding per-player barriers. Player/item identities, request revision and lifecycle scope prevent stale completions resuming obsolete intent. Failed completion advances to newer input but does not retry forever.
- `bash scripts/tests/run-seek-coalescer-tests.sh`: Swift 6, complete strict concurrency, warnings as errors; exit 0. Deterministic injected-completion cases include 100 rapid relative requests producing seeks [1, 100], repeated/revisited target, failure/new input, reset, duplicate callback and player/item replacement. Empty AVPlayers/in-memory composition; no app host, media file, preferences, UI, network or real AVPlayer seeks. This does not exercise SwiftUI event delivery or AVFoundation decoding.
- `bash scripts/tests/run-thumbnail-viewport-tests.sh`: exit 0, existing geometry regressions pass.
- Fresh-context independent read-only review: no remaining concrete findings; reviewer independently ran the seek suite. A completion-before-periodic-observer gap was identified and the implementation's direct-currentTime fallback resolves it.
- `xcodegen generate` completed before build. Integrated strict-concurrency Debug build exit 0; no application-source warnings. Only AppIntents metadata warning. Initial sandbox build failed (exit 74) on Xcode/SwiftPM cache permissions; cache-authorized build and final incremental build succeeded.
- `git diff --check` passed. Existing Wave 2 dirty work preserved. No commit/push while runtime gates and temporary instrumentation remain open.

## Build and temporary probe

Exact build command from repository root `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`:

```sh
xcodebuild -project 01_Project/ScreenshotFromVideos.xcodeproj -scheme ScreenshotFromVideos -configuration Debug -derivedDataPath /private/tmp/sfv-wave3-build -clonedSourcePackagesDirPath /Users/sim/Library/Developer/Xcode/DerivedData/ScreenshotFromVideos-cucpispgpnspddadwxkzflnyrvmm/SourcePackages -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- SWIFT_STRICT_CONCURRENCY=complete SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG SFV_SEEK_DIAGNOSTICS' build
```

Artifact: `/private/tmp/sfv-wave3-build/Build/Products/Debug/ScreenshotFromVideos.app`, bundle version 0.1 (1). Build-only: app startup and Sparkle updater not executed by validation. Final incremental log: [build.log](build.log); full initial dependency build log: `/private/tmp/sfv-wave3-build.log`. Source/executable checksums: [source-artifact.sha256](source-artifact.sha256); Wave 3-only view diff: [strip-wave3.diff](strip-wave3.diff); [seek-tests.log](seek-tests.log).

Temporary `SFV_SEEK_DIAGNOSTICS` compile condition records navigation targets, actual SwiftUI scroll phase/isScrolling, schedule debounce flag and render-ready events to `/private/tmp/sfv-wave3-scroll-events.log`. It truncates on first event in each app process, stops at 10,000 events, and touches no preferences. File I/O adds diagnostic overhead; use it to answer phase/debounce wiring, not CPU or speed benchmarks. Default builds exclude the probe. Remove the helper and all conditional hooks after collecting task 3.2 evidence, then build the final uninstrumented artifact. No debounce behavior change without runtime evidence.

## Runtime handoff — 2026-10-29

User requested “runtime validation” in reply to the exact-target lifecycle question. Identified old footer-build PID 66283; accessibility inspection showed paused, 0 captures, Export disabled. Normal Command-Q sent through CUA. Post-quit AX lookup returned procNotFound; independent process check confirmed PID 66283 exited and no target app remained. Launched the exact diagnostic artifact through CUA; verified PID 76619 executable `/private/tmp/sfv-wave3-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos`, bundle 0.1 (1), empty picker visible. Source/artifact SHA-256 verification passed before launch. No force quit, prompt dismissal, test keys/clicks, clipboard or profile changes. The initial AX inspection took ~951 seconds; subsequent calls completed normally. User operates the test batch below.

## Finite acceptance batch — user-passed

1. Open this exact diagnostic build, load `/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4`, pause, zoom to maximum and wait for fill. Click a thumbnail away from a clip boundary to focus the grid. Hold Right Arrow for five seconds, release and wait two seconds. Report whether selection stops promptly without a queue of catch-up seeks. Repeat with Down Arrow to force several offscreen row transitions. Both runs must advance targets and include actual auto-scrolling for the debounce verdict.
2. Click three separated thumbnails: landed frame/border must match. Test one Option-Right Arrow jump (30 seconds) and one Shift-Left Arrow jump (one minute). Command-click must still add a pinned capture.
3. Unload and reload the clip while paused; click once and verify no old navigation resumes. This checks the changed lifecycle path only; accepted Wave 2 broader tests are retained.
4. Save/read the probe file before reopening the app, correlate navigate → phase `.animating` → schedule debounce flags. If `.animating` sets isScrolling=true and relevant schedules debounce, close 3.2 as no-op; otherwise implement the smallest shared 80 ms gating fix and recheck. A trace without scrolling cannot answer the question.

Tasks 3.1 and 3.2 are complete (10/15 plan tasks complete; one reverted). Wave 4 remains outside this request. Initial inspection rejection was resolved by the user’s runtime-validation reply; subsequent lifecycle actions are recorded above and below.

## Acceptance and task 3.2 verdict

User replied **“pass”** to the numbered held Right/Down Arrow, plain-click, Option-Right Arrow, Shift-Left Arrow, Command-click capture and unload/reload batch. This is user-observed behavior, not automated input or instrumented seek latency. Deterministic headless tests separately establish the one-flight/latest-target invariant; this trace measures scroll-phase/debounce wiring, not actual AVPlayer in-flight counts.

Saved [scroll-events.log](scroll-events.log) contains 542 events, 90 navigation events, and 31 `phase animating scrolling=true` events. All 293 `schedule scrolling=true` events recorded `debounce=true`; 46 idle schedules appropriately recorded false. At uptime 986803.841607 navigation index 30 is followed at 986803.859499 by animating/scrolling=true, then at 986803.859561 by a debounced schedule. Repeated row navigation 68→298 also shows sustained debounced schedules, followed by idle and immediate render-ready. [scroll-summary.json](scroll-summary.json) retains complete event counts. The captured file was saved before diagnostic-app quit/relaunch and is below the 10,000-event cap.

**3.2 closes as no-op:** seek-driven animated scrolling already engages the shared 80 ms debounce. No extra gating or tolerance change. All temporary hooks/helper removed from source; StripModel is byte-identical to the pre-Wave 3 source. Existing headless and independent-review evidence remains valid: coalescer/navigation logic did not change after accepted diagnostic build; final source differs only by removal of instrumentation.

## Final uninstrumented build and handoff

Same build command as above, with derivedDataPath `/private/tmp/sfv-wave3-final-build` and the `SWIFT_ACTIVE_COMPILATION_CONDITIONS` override omitted. Build exit 0, complete strict concurrency, zero app-code warnings; only AppIntents metadata warning. [final-build.log](final-build.log) and [final-source-artifact.sha256](final-source-artifact.sha256) retain exact command/output and artifact identity. `git diff --check` passed; no diagnostic symbols/hooks remain in source.

Before replacement AX showed diagnostic app paused at 00:00, 0 captures. Normal Command-Q; post-quit AX lookup returned procNotFound and independent process check confirmed PID 76619 absent/no target app running. Launched `/private/tmp/sfv-wave3-final-build/Build/Products/Debug/ScreenshotFromVideos.app`; verified PID **93956** executable `/private/tmp/sfv-wave3-final-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos`, bundle **0.1 (1)**, empty picker visible. Left final app running. No force quit, prompt dismissal, acceptance inputs, clipboard/profile changes or outstanding restoration. Accepted runtime tests belong to the diagnostic artifact; final build verifies probe removal/integration and launch, without claiming a repeated full manual matrix.

No commit/push or branch change: integration overlaps pre-existing uncommitted Wave 2 navigation/layout source, so a coherent combined checkpoint needs to preserve that earlier work deliberately. Wave 4 final matrix/CPU remeasurement remain future work.
