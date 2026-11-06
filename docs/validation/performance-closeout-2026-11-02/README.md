# Wave 4 performance closeout — November 2

## Scope and artifact
Coordinator owns task 4.2 measurement and task 4.4 records serially. Fresh-context `refresh_review` independently inspected the refresh contract read-only; no source edits, builds or app input.

Accepted artifact: `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app`, executable PID 32749 verified using read-only `ps`. `shasum -a 256 -c docs/validation/viewport-demand-2026-11-01/retry-source-artifact.sha256` passed all seven entries (six source/test files and executable). These checks were repeated November 2; no launch or rebuild performed.

## Explicit criterion revision
User chose to retain progressive fill and revise the requirement. The original approximately ten-total refreshes per 256 images was not met (historical 17–18). It is superseded, not retroactively passed.

Revised contract: each batch publishes its first stored image immediately; later in-loop cache-version increments are at least 100 ms apart. Completion/cancellation flushes once only if stored images remain unpublished. A batch with no stores emits none. Clocks reset per batch and final flushes bypass the interval: neither global ten-per-second nor ten-total is promised.

Independent review and coordinator inspection confirm this policy in current `StripModel.scheduleRender`. `ThumbnailCellView` equality includes cacheVersion, and its change handler reads the cache. Historical measurement and November 1 progressive-fill acceptance are retained; no new live count or actual SwiftUI evaluation-count claim. A hard total cap could delay slow-arriving thumbnails, so code remains unchanged.

## CPU measurement preparation
User agreed to participate in two finite measurements: held Right Arrow (10 seconds), then paused default-to-maximum zoom (10 seconds idle plus 20 seconds transition). Setup/readiness and action confirmation are required; readiness is not proof of sustained input.

`collect-cpu.py` is a copy of the inspected historical read-only collector with the accepted artifact path and a required explicit PID. It writes a new evidence JSON beside itself, refuses overwrite, verifies process identity on every sample and retains executable SHA-256. Python compile-only syntax check passed. It does not launch/control the app or modify preferences. Source and old measurements remain unchanged. Actual samples have not yet run.

Retain earlier a/b/c CPU results with original artifact/unpaired-comparison limits. October 29 d is provisional; e includes failed fill and cannot establish a performance win. November 1 manual matrix is accepted and is not being repeated.

## November 6 continuation — rebuilt artifact and CPU samples

The accepted temporary executable was missing; all six source/test entries in the November 1 manifest still matched. Rebuilt the same source using the recorded xcodebuild command, complete concurrency, Debug/ad-hoc signing, and existing package cache. Build exited 0; only the AppIntents metadata warning appeared. Full log: [rebuild-2026-11-06.log](rebuild-2026-11-06.log). New identity: [rebuilt-source-artifact-2026-11-06.sha256](rebuilt-source-artifact-2026-11-06.sha256). This is a new binary, not a claim that the old executable checksum passed.

No existing target process was running. Under standing fresh-build handoff authorization, launched `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app`; verified PID 39345 at that exact executable and version 0.1 (1). No quit, automated test input, profile change or clipboard change. Coordinator handles dependent samples serially; no independent agent work.

User confirmed the prescribed clip setup: paused/default zoom, filled thumbnails, selection away from ends. Collector commands used `python3 docs/validation/performance-closeout-2026-11-02/collect-cpu.py CASE --seconds N --pid 39345` from the repository root. Each read-only ps collection verified process identity throughout and wrote only new evidence JSON.

| Case | Seconds | Average CPU | Range | Evidence/state |
|---|---:|---:|---:|---|
| Held Right Arrow | 10.010 | 49.94% | 45.2–56.5% | [raw](held-arrow-2026-11-06.json); user confirmed sustained movement throughout, release and paused/default zoom afterward |
| Paused idle | 10.006 | 13.65% | 12.2–15.0% | [raw](paused-idle-2026-11-06.json); instructed untouched paused baseline |
| Paused zoom window | 20.010 | 12.595% | 10.7–16.6% | [raw](paused-zoom-2026-11-06.json); EXCLUDED as transition evidence: user confirmed no zoom occurred |

The zoom collector started before the action cue, so its aggregate includes pre-action time. Low CPU alone does not prove zoom/fill occurred. Do not claim a zoom improvement until state is confirmed; no cold-cache claim. Held-arrow historical baseline was 72.3%, versus 49.94% now, but hardware/toolchain/cache/action timing are not paired controls. Earlier a/b/c and October 29 invalid/provisional d/e retain their original limits.

### Zoom retry and task 4.2 outcome

The first commentary cue did not reach the user clearly; they explicitly reported no zoom. Retained that JSON as idle-only evidence. Repeated the 20-second collector, then issued a visible question-box cue. User confirmed moving to maximum zoom within 1–2 seconds of seeing the cue and that all visible thumbnails filled. Reply arrival was after collection ended; timing is user-reported, not independently timestamped UI telemetry.

[Retry raw evidence](paused-zoom-retry-2026-11-06.json): 20.006 seconds, average **13.98%**, range **5.9–16.6%**, peak RSS 174128 KiB. The window includes pre-cue time and reflects this session's cache state, which was not instrumented or reset. Do not interpret the low value as a measured cold-decode cost or a controlled improvement over historical zoom CPU. No further manual matrix repeat.

Task **4.2 complete** with the new confirmed d/e samples and retained historical a/b/c evidence under their existing comparison limits. No blanket performance-win claim. Task 4.4 remains for final documentation/checkpoint; this invocation handled the next measurement task only. No source changes or commits; overlapping existing integration work remains for a deliberate combined checkpoint.

## Final closeout — November 6

Task 4.4 complete. Fresh-context read-only `closeout_review` inspected current source diffs, SeekCoalescer and retained evidence: no concrete source defect. Playback named-body isolation is directly measured in the earlier trace; shuttle isolation is supported by the shared source path, not a separate body-count trace. No new source change or profiling claim.

[Completed plan](../../sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md): 14 completed tasks, one intentionally reverted experiment. [Archived evidence index](../../sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_EVIDENCE.md). Existing evidence retained in place; no new manual matrix or app control needed.
