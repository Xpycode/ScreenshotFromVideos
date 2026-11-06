# Measured viewport demand — 2026-11-01

Status: viewport fix plus bounded decoder retry built; V1–V3 and remaining manual matrix user-passed; performance evidence/batch-count acceptance pending. Latest artifact and retest are in “Bounded decoder retry” below. Earlier artifact/checksums are retained historical evidence. Wave 4 task 4.1 remains open; 11/15 complete, one reverted.

## Change and evidence

The focused zoom trace established that final requests were about ten seconds before the selected/rendered cells. The fix resolves existing indexed cell anchors in a ScrollView-sized overlay and requests the range of cells with positive-area viewport intersections, including clipped neighbors. Playback-follow rows use these measured bounds too. Analytical offsets now set column count only and cannot overwrite measured demand. Measurements carry model, density, width and column identity; unchanged ranges do not reschedule. Initial measured demand is sent once even if it equals the model default.

Temporary ZoomTrace hooks were removed from all four instrumented source files by reversing the retained diagnostic delta (view hooks removed during implementation). Saved trace evidence is preserved. Debounce, request cap, renderer, tolerance, cache refresh and seek policies are unchanged. [Session-only source delta](session-source.diff) separates this work from earlier overlapping dirty changes.

Assignments: fresh-context `viewport_fix` owned the coupled view/helper/regression files serially; coordinator owned probe removal, build and records. Fresh-context read-only `viewport_review` found no concrete issues after checking geometry coordinates, preference propagation, identity guards, zoom demand and follow behavior. Source review cannot prove runtime preference delivery or CPU behavior.

## Validation

Working directory: `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`.

- `bash scripts/tests/run-thumbnail-viewport-tests.sh`: exit 0, [output](viewport-headless.log). Inspected headless Foundation/CoreGraphics executable, temporary compile output only; no app host, media, preferences, network or desktop control. Fixtures reproduce the old deep-offset omission and check visible neighbors, clipped/touching boundaries, density remapping, capped-density column repacking, empty geometry and duration bounds. Fixtures stand in for SwiftUI callbacks and do not test callback delivery.
- Agent also reports RED against an analytical stub (assertion exit 133) and GREEN under Swift 6 complete concurrency with warnings-as-errors. The first RED preparation needed CoreGraphics imported for CGRect constructors; that compiler failure was not treated as the regression result.
- Build command below: initial sandbox attempt exit 74 because Xcode/SwiftPM cache writes were denied ([log](build.log)); cache-authorized retry exit 0 ([log](build-authorized.log)). Only AppIntents metadata warning; no application-source warnings. Project has no custom shell build phases; generated scheme build only. Startup would read preferences and start Sparkle, but startup was not executed.

```sh
xcodebuild -project 01_Project/ScreenshotFromVideos.xcodeproj -scheme ScreenshotFromVideos -configuration Debug -derivedDataPath /private/tmp/sfv-viewport-demand-build -clonedSourcePackagesDirPath /Users/sim/Library/Developer/Xcode/DerivedData/ScreenshotFromVideos-cucpispgpnspddadwxkzflnyrvmm/SourcePackages -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- SWIFT_STRICT_CONCURRENCY=complete build
```

Artifact: `/private/tmp/sfv-viewport-demand-build/Build/Products/Debug/ScreenshotFromVideos.app`, version 0.1 (1), arm64 executable. [Source/artifact hashes](source-artifact.sha256). No app launch/quit/input/profile changes; user-operated scope retained. No commit/push: fix overlaps uncommitted Wave 2/3 integration; a standalone source commit would carry their unreviewed checkpoint scope. All earlier dirty source, docs and design preserved.

## Focused user acceptance (not yet run)

Quit the existing app normally when idle; stop on an unsaved-work prompt or refusal. In Finder Go to Folder, open `/private/tmp/sfv-viewport-demand-build/Build/Products/Debug`, then open `ScreenshotFromVideos.app`.

Use `/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4`:

| ID | Action | Expected |
|---|---|---|
| V1 | Pause near 00:25:08–00:25:30, reset zoom to 1, move slider to maximum; wait 20 seconds | Selected thumbnail and visible neighbors fill; border aligns. Report timecode/screenshot if any stay black. |
| V2 | While paused, scroll a few rows, zoom out/in with keys or pinch, and resize the window | Newly visible cells fill and the selected border remains aligned when visible. |
| V3 | Play normally at maximum zoom for at least 30 seconds after fill | Active border stays visible and follows playback without repeated unnecessary recentering. |

Reply with V1/V2/V3 pass/fail. This limited repeat is justified by the geometry change. It does not close the remaining original [Wave 4 matrix](../final-verification-2026-10-29/README.md), held-arrow confirmation or total batch-refresh criterion. Retain prior CPU samples with their original-artifact limits; no new performance-win claim. A short-clip initial-load/zoom check also remains part of final regression acceptance.

## First user feedback — transient placeholder, wait not tested

User supplied [before Right Arrow](user-before-arrow.png) and [after Right Arrow](user-after-arrow.png). First screenshot: paused every-frame zoom at 00:20:52:26, frame 37,586; selected cell is placeholder-dark while neighbors contain images. Second: 00:20:52:27, frame 37,587; selection has moved one cell and the previously dark cell now contains an image. User clarified: “Right Arrow, but without waiting 20 seconds.”

V1 is inconclusive, not a demonstrated persistent failure or a pass. The images do not establish whether time alone or navigation caused the fill. No decoder/cache/refresh cause inferred, no new source change or rebuild justified. Read-only source inspection confirms unsuccessful decode requests have no automatic retry, but these screenshots do not establish a decode failure. Next: reproduce paused zoom, leave any black selected cell untouched for 20 seconds, report whether it fills without navigation. V2/V3 and other acceptance gates remain unreported. App identity was not reverified from these screenshots; no app control occurred.

## Second user feedback and recoverable decoder hole

User supplied [paused before wait/navigation](user-wait-before-arrow.png), then reported “Then I waited 20s and used the right arrow key,” with [after navigation](user-wait-after-arrow.png). Before: 00:27:16:25/frame 49,105, selected right-column cell filled; lower-left neighboring cell placeholder-dark. After: 00:27:16:26/frame 49,106 selected and filled. There is no separate screenshot immediately before the arrow after the wait, so the images do not alone prove which event caused recovery. Paused fill acceptance remains open; no pass inferred.

Independent source diagnosis `remaining_fill_diagnosis` found that failed/unreturned decode requests have no retry. A paused unchanged measured range does not reschedule; navigation can trigger a new batch through centering/scroll phase. Cache publication and measured-demand omission remain alternative live causes without a trace.

The coordinator then tested the unchanged production renderer headlessly on indices 49100...49111 from the same local baseline clip (width 240, 30 fps half-gap tolerance). **11/12 delivered; exact neighbor index 49106/key 1636865 failed with AVFoundation -11821 / OSStatus -12911.** A second experiment reproduced the same hole, then retried only that missing requested time using a fresh generator: **12/12 after retry**. [Initial fixture](decode-neighbor-check.swift), [output](decode-neighbor-check.log), [retry fixture](decode-neighbor-retry.swift), [output](decode-neighbor-retry.log). This establishes a recoverable decoder failure independently; it does not prove the full live screenshot pipeline cause.

Compile commands (working directory repository root), both exit 0:

```sh
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -module-cache-path /private/tmp/sfv-neighbor-decode-module-cache 01_Project/ScreenshotFromVideos/Thumbnail/ThumbnailRenderer.swift docs/validation/viewport-demand-2026-11-01/decode-neighbor-check.swift -o /private/tmp/sfv-neighbor-decode-check
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -module-cache-path /private/tmp/sfv-neighbor-decode-module-cache 01_Project/ScreenshotFromVideos/Thumbnail/ThumbnailRenderer.swift docs/validation/viewport-demand-2026-11-01/decode-neighbor-retry.swift -o /private/tmp/sfv-neighbor-retry-check
```

Ran each executable with output redirected to its linked log, both exit 0. Inspected headless media-read-only diagnostic, no app startup/preferences/network/desktop interaction; authorized decoder-service access outside sandbox because prior sandbox decoder restrictions invalidate results. Exit zero means completed diagnostic; the initial 11/12 result is a failure, not full decode success. No app launch/control. Next implementation: one bounded fresh-generator retry of failed/unreturned requests, preserving exact requested keys/tolerance and cancellation, with no repeated retry loop.

## Bounded decoder retry — current artifact

Fresh-context `bounded_decode_retry` implemented two passes maximum, each with its own generator/cancellation handler. Successful requested times are removed from the pending set. Only failed/unreturned times are retried; task cancellation and cancellation errors suppress retries. Tolerances, size, exact requested-time identity and public render API are unchanged. Fresh-context `retry_review` found no blocking issues. The asset Sendable box assumes the current immutable AVURLAsset caller, not a concurrently mutated composition. The narrow cancellation-before-request-registration window is inherited and not covered by these tests; no demonstrated regression.

Validation:
- `bash scripts/tests/run-thumbnail-renderer-retry-tests.sh` exit 0: [policy test output](retry-policy-tests.log). Test double exercises the production render loop (success, partial/omitted delivery, bounded persistent failure, thrown error, cancellation in either pass, requested identity/configuration); no app, media, preferences or network. This double does not validate AVFoundation internals.
- Compiled the original 12-frame diagnostic with the modified renderer to `/private/tmp/sfv-neighbor-fixed-check` using the same Swift 6 complete-concurrency/warnings-as-errors flags and module-cache path above; compile exit 0. Ran headlessly with authorized local media/decoder access, exit 0: [real output](decode-neighbor-fixed.log) now **12/12**, with the exact original failure followed by automatic successful recovery of key 1636865. No manual second render in this fixture. This complements the policy tests but does not prove live SwiftUI behavior.
- `xcodebuild` using the earlier build command with derivedDataPath `/private/tmp/sfv-viewport-retry-build`: cache-authorized build exit 0; [log](retry-build.log). Only AppIntents metadata warning, no application-source warnings. No new app source files, so no project regeneration needed.
- [Retry-only delta](retry-source.diff), [current source/artifact hashes](retry-source-artifact.sha256). Earlier source-artifact.sha256 belongs to the viewport-only artifact, not current source.

Current app: `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app`, version 0.1 (1); displayed as **Stills From Video**. Not launched; no app control or live-state changes. No commit/push; preserve overlapping earlier dirty source/docs/design and deliberate combined checkpoint boundary.

User retest: quit the old app normally when idle (stop on refusal/unsaved prompt), Finder Go to Folder `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug`, open `ScreenshotFromVideos.app`. Use `/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4`, pause near 00:27:16, move from default to maximum zoom, then leave untouched 20 seconds. Both selected and neighboring visible thumbnails should fill. Report any remaining black cell before navigating. This repeat is justified by the reproduced decoder-hole fix; it does not close V2/V3, the original matrix or other open gates. No CPU rebenchmark or performance-win claim.

### Authorized quit-and-launch handoff

User explicitly requested “quit and run.” Identified old PID65504 at `/private/tmp/sfv-viewport-demand-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos`. UI showed paused playback, zero captured frames and disabled Export; no busy export or prompt. Sent normal Command-Q through computer-use API; subsequent AX lookup returned process-not-found. Read-only process checks confirmed old PID absent and no target app running before replacement. Launched exact `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app` through computer-use API; visible empty “Pick video…” window. Verified new PID32749 at exact fresh executable path, bundle version0.1(1), and all current source/artifact checksums. No force quit, prompt dismissal, media input, clipboard/profile change or test actions. Left fresh build running for user acceptance. Current scope authorizes this lifecycle handoff only; remaining manual gates stay open.

### Paused-fill accepted

After the explicit quit-and-launch handoff to the combined build (PID32749/path/version/checksum verified), user replied “pass” to the requested paused maximum-zoom, untouched 20-second fill check. Accept V1 (selected and neighboring visible fill) and the previously failing paused-fill portion of F6. Do not expand this report to V2/V3, other zoom paths, held-arrow state confirmation or the rest of the matrix. No new source edits, builds, tests or app control for recording this result.

### Scroll/zoom/resize and maximum playback follow accepted

User replied “pass” to the two explicitly requested checks on the same combined build: (1) scroll, zoom and resize with visible thumbnail fill; (2) normal playback at maximum zoom for30 seconds with selection staying visible and following playback. Accept V2 and V3, completing this fix's focused V1–V3 batch. V2 does not establish every separately specified pinch/key/Command-wheel/slider path. Broader original matrix, historical held-arrow sampling confirmation and total batch-refresh criterion remain open. No new app control, builds or source edits.

### Remaining manual matrix accepted

User replied “all pass” to explicitly listed shuttle, held arrows, jumps/clicks, captures/pins, all four zoom paths and unload/reload checks on the same combined build. Task4.1 complete; 12/15 plan tasks complete, one reverted. Historical CPU-state confirmation and total batch-refresh criterion remain separate; no new measurements or app control.
