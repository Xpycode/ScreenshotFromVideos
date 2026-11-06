# Window-width acceptance — 2026-10-29

User reported “all pass” in response to the remaining manual batch: border alignment at zoom 1/6/12 and two window widths, unload/reload, and continuous playback/follow at default and maximum zoom. This is user-reported acceptance; no CPU samples, body-evaluation counts, clip identity or timed run were independently collected in this session.

- `minimum-window.png`: active border fits its thumbnail; footer labels wrap severely (Unload, timecode, Copy and Capture this frame).
- `maximum-window.png`: active border fits its thumbnail; footer fits in a single row.

Footer source: `01_Project/ScreenshotFromVideos/UI/LeftPaneView.swift`, `footer` HStack. All controls and readouts share one row, allowing labels to compress and wrap. Proposed compact icon-only actions at narrow widths, retaining location, timecode and count; user approved. Implemented horizontal ViewThatFits with non-wrapping intrinsic labels/readouts; strict-concurrency build passed and footer artifact launched. Loaded narrow/wide visual/action acceptance pending. Build log `/private/tmp/sfv-footer-build.log`.


## Compact footer acceptance
User reported “pass” with `compact-footer-pass.png`. Screenshot shows the narrow loaded window with icon-only Unload/Copy/Capture actions, readable single-line timecode and captured count, and no footer wrapping. Narrow layout accepted; no separate wide-return or tooltip/action report inferred from this screenshot.
