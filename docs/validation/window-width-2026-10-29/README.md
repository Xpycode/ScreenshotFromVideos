# Window-width acceptance — 2026-10-29

User reported “all pass” in response to the remaining manual batch: border alignment at zoom 1/6/12 and two window widths, unload/reload, and continuous playback/follow at default and maximum zoom. This is user-reported acceptance; no CPU samples, body-evaluation counts, clip identity or timed run were independently collected in this session.

- `minimum-window.png`: active border fits its thumbnail; footer labels wrap severely (Unload, timecode, Copy and Capture this frame).
- `maximum-window.png`: active border fits its thumbnail; footer fits in a single row.

Footer source: `01_Project/ScreenshotFromVideos/UI/LeftPaneView.swift`, `footer` HStack. All controls and readouts share one row, allowing labels to compress and wrap. Proposed compact icon-only actions at narrow widths, retaining location, timecode and count; user approved. Implemented horizontal ViewThatFits with non-wrapping intrinsic labels/readouts; strict-concurrency build passed and footer artifact launched. Loaded narrow/wide visual/action acceptance pending. Build log `/private/tmp/sfv-footer-build.log`.


## Compact footer acceptance
User reported “pass” with `compact-footer-pass.png`. Screenshot shows the narrow loaded window with icon-only Unload/Copy/Capture actions, readable single-line timecode and captured count, and no footer wrapping. Narrow layout accepted; no separate wide-return or tooltip/action report inferred from this screenshot.

## Follow-up inspection — 2026-11-06

- Read-only inspection verified running PID 39345 at `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos`. Its executable SHA-256 matches `../performance-closeout-2026-11-02/rebuilt-source-artifact-2026-11-06.sha256`; all six source/test entries in that manifest also match. That manifest does not include `LeftPaneView.swift`; no new footer source-to-binary hash claim is made.
- Live screenshot: wide footer shows Unload, Copy and Capture this frame, readable timecode and `0 captured`, all in one row without wrapping. This verifies the current wide appearance, not the narrow-to-wide transition.
- Live accessibility inspection: all three action names and their expected help strings are present. This does not verify hover presentation.
- Source review: wide/compact variants share the same Unload, Copy and Capture handlers; compact icons have accessibility labels. `git diff --check` passed. No source edits, rebuild, clicks, clipboard changes or window resizing performed.
- Remaining finite user batch: resize narrow then wide and confirm labels return; hover compact actions and confirm help; Capture an uncaptured paused frame and confirm count increases; Copy and paste to confirm image; Unload last and confirm empty view. Copy replaces the clipboard; Unload clears the capture queue. Runtime results pending; do not mark accepted or checkpoint as complete until reported.

## User results and tooltip correction — 2026-11-06

- User reported “all but 2 passed, no tooltips”: resize/label return, Capture, Copy and Unload passed. Hover help failed. Prior accessibility help text was not proof of visible tooltip behavior.
- Added a private native `NSView.toolTip` background to each footer button, retaining accessibility hints, existing layout and action handlers. The view does not accept clicks or first-responder focus; unchanged tooltip strings are not reassigned during view updates. This is a fallback for the observed failure, not a confirmed diagnosis of SwiftUI internals.
- Remaining acceptance after rebuilding: hover each compact footer button and verify visible help, resize back to wide and verify help remains available. One Capture click checks that the native background does not intercept input; broader action semantics already passed.
- Strict-concurrency Debug/ad-hoc build passed (exit 0); only AppIntents metadata warning. Initial sandboxed attempt exited 74 because compiler/package caches were inaccessible; authorized retry succeeded. Exact build invocation and output: [build log](tooltip-build-2026-11-06.log). Footer source and executable hashes: [manifest](tooltip-source-artifact-2026-11-06.sha256).
- Fresh-build handoff: old app was empty/idle; requested Quit through its menu. UI observation timed out after quit, but process inspection confirmed no target process remained. Launched `/private/tmp/sfv-footer-tooltip-build/Build/Products/Debug/ScreenshotFromVideos.app`; verified PID 59679 at that exact executable path, version 0.1 (1). Empty view visible. No force quit, save-prompt dismissal, clipboard changes or test clicks. Hover validation remains user-operated.

## Final acceptance — 2026-11-06

User reported “pass” for all three compact hover tips, wide-layout hover tips and one Capture click on the fresh tooltip build. Together with the previously passed resize/label return, Copy and Unload checks, the finite footer acceptance batch is complete. Source and executable manifest rechecked successfully at closeout.
