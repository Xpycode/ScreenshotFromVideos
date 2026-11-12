# Tasks

## Active plan
**v0.1 release** (from `/check ship`, 2026-11-09). Done-for-v0.1 criteria live in `docs/PROJECT_STATE.md`.
- [ ] **Report export failures (#4)** — *implemented 2026-11-09 (`ExtractionPipeline.Outcome` + folder pre-check); awaiting user test, see [Resume](docs/sessions/2026-11-12.md#resume).* Per-frame decode/write failures are only `print`ed and skipped; status still says "Done — wrote N" (`Core/ExtractionPipeline.swift:113,124`, `App/ExtractionViewModel.swift:279`). A stale persisted output folder would yield "Done — wrote 0" with no error. Surface failed count / first error; validate the output folder before starting. Found by code reading, not runtime-reproduced.
- [ ] **About Website link (#6).** `apps.lucesumbrarum.com/stillsfromvideo` 404s (`apps.json` row `portalPage: false`). Publish the portal page, or drop `websiteURL` for v0.1. Feedback, tips and `/privacy` already work.
- [ ] **Notarized DMG (gate 1).** Build from the release commit via `scripts/release.sh`; record source commit.
- [ ] **Sparkle-signed appcast item (gate 2).** Needs the Mac holding the `o388…` key (`release.sh` refuses on this Mac) — or explicitly ship v0.1 without auto-update.
- [ ] **Artifact smoke test (gate 3).** Install the signed DMG on a clean account/fresh prefs; run Interval and Manual exports and check frame counts.

## Standalone follow-up
None. Compact footer and native hover tooltips accepted November 6; strict build and all finite user checks passed. See [evidence](docs/validation/window-width-2026-10-29/README.md).

## Backlog
- Thumbnail drag scrubbing (2026-10-29): holding the mouse button and dragging across thumbnails leaves the original selected frame active. User clarification confirms the symptom; source currently supports click-to-seek only (`ThumbnailCellView.onTapGesture`), with no drag-selection handler. Add continuous selection/seek while dragging as a future interaction improvement; preserve plain-click and Command-click capture. Not implemented or runtime-reproduced by agent.

- Video information status bar: show useful loaded-video metadata (duration, resolution, frame rate, codec); user suggested 2026-10-28. Address after thumbnail slowness; placement/content need design review.

- At every-frame zoom, playback can reach uncached thumbnails and show black cells. User accepted this as a deferred limitation on 2026-10-28; eventual fill after pausing was not explicitly confirmed in that final check. The separately promoted paused slider-zoom failure (2026-10-29) was fixed by measured demand plus bounded decode retry and user-passed on 2026-11-01 (task 4.1). Retain this older playback catch-up limitation separately; do not reopen the accepted paused-fill case.
- Continuous zoom density produces mostly distinct timestamp cache keys; consider a reusable sampling ladder only if further performance work is requested.

- [v1.1] Diagnostic logging (#5): replace the 3 production `print()` calls (`ExtractionPipeline.swift:113,124`, `ThumbnailRenderer.swift:69`) with `Logger`; no `os.Logger` exists yet.
- [v1.1] CHANGELOG / release notes (#7): none exists; write v0.1 notes for the appcast item and GitHub release (do this alongside the DMG).
- [v1.1] Split `Thumbnail/ThumbnailStripView.swift` (720 lines, over the 500 guideline) (#8).
- [v1.1] Command-Comma opens nothing — no Settings scene; arguably correct since settings live in the inspector (#9). Decide, don't build by default.
- [v1.1] Build-number scheme (#10): currently `CURRENT_PROJECT_VERSION: "1"`; house scheme would be e.g. 100 for v0.1. Decide before the first appcast item — numbers only go up.
- [v1.1] Add a justification comment to `CancellableGenerator` `@unchecked Sendable` in `Thumbnail/ThumbnailRenderer.swift:16` (pipeline copy has one) (#11).
- [v1.1] Delete the unused `Assets.xcassets/AppIcon.appiconset` — the app icon is now `02_Design/StillsFromVideos-icon.icon` (2026-11-12).

## Inbox
- Existing zoom-out redraw slowness: distinguish cache eviction from never-cached frames (see archived performance plan’s July 19 evidence).
