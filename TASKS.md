# Tasks

## Active plan
None. [Strip/player performance completed](docs/sessions/_archive/2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md) November 6: 14 tasks complete, one reverted; evidence limitations retained.

## Standalone follow-up
None. Compact footer and native hover tooltips accepted November 6; strict build and all finite user checks passed. See [evidence](docs/validation/window-width-2026-10-29/README.md).

## Backlog
- Thumbnail drag scrubbing (2026-10-29): holding the mouse button and dragging across thumbnails leaves the original selected frame active. User clarification confirms the symptom; source currently supports click-to-seek only (`ThumbnailCellView.onTapGesture`), with no drag-selection handler. Add continuous selection/seek while dragging as a future interaction improvement; preserve plain-click and Command-click capture. Not implemented or runtime-reproduced by agent.

- Video information status bar: show useful loaded-video metadata (duration, resolution, frame rate, codec); user suggested 2026-10-28. Address after thumbnail slowness; placement/content need design review.

- At every-frame zoom, playback can reach uncached thumbnails and show black cells. User accepted this as a deferred limitation on 2026-10-28; eventual fill after pausing was not explicitly confirmed in that final check. The separately promoted paused slider-zoom failure (2026-10-29) was fixed by measured demand plus bounded decode retry and user-passed on 2026-11-01 (task 4.1). Retain this older playback catch-up limitation separately; do not reopen the accepted paused-fill case.
- Continuous zoom density produces mostly distinct timestamp cache keys; consider a reusable sampling ladder only if further performance work is requested.

- About-panel Website link: `apps.lucesumbrarum.com/stillsfromvideo` 404s until the app gets a portal page at release (its `apps.json` row is `portalPage: false`). Feedback and tips already work: both read the live `apps.json` roster, which lists `stillsfromvideo`. `/privacy` fixed 2026-11-09 (App-Websites `89a8fc0`).

## Inbox
- Existing zoom-out redraw slowness: distinguish cache eviction from never-cached frames (see archived performance plan’s July 19 evidence).
