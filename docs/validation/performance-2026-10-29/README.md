# Wave 2 performance — 2026-10-29

Artifact: `/private/tmp/sfv-footer-build/Build/Products/Debug/ScreenshotFromVideos.app`, version 0.1 (1), verified executable PID 66283. User loaded `/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4`, reset zoom with Command-0 and reported “playing.” Agent collected read-only `ps` samples; no playback input sent.

## Default zoom, 1× playback
- 30 samples at 1 Hz over 30.005 seconds; average CPU 35.883%, range 22.1–74.3%; peak sampled RSS 183472 KiB (~179 MiB).
- Raw timestamped samples: `default-playback.json` (UTC start 2026-10-29T02:10:49.067074+00:00; timestamps copied from machine clock).
- Historical Wave 0 default playback average: 91.8%. New result is lower, but this is a historical comparison, not a controlled paired run; CPU does not prove individual SwiftUI body evaluation rates or follow behavior.
- During collection, an Instruments template-discovery attempt failed immediately under sandbox restrictions (cache directory not writable); no profiling recording or app input occurred. Discovery retry requested after sample.

## Maximum zoom, 1× playback
- User reported “playing at max” after being instructed to pause, choose maximum zoom and wait for visible thumbnails to fill.
- 30 samples at 1 Hz over 30.001 seconds; average CPU 33.543%, range 26.0–42.2%; peak sampled RSS 212032 KiB (~207 MiB).
- Raw timestamped samples: `maximum-playback.json` (UTC start 2026-10-29T02:12:16.623683+00:00).
- No valid historical maximum-zoom comparison: Wave 0 maximum-zoom sample was invalidated by the old off-screen follow bug. Do not use its 68.1% as a valid improvement baseline.

## Pending
Measured SwiftUI body-update isolation for tasks 2.1–2.2. Installed `xctrace` provides a SwiftUI template (template discovery succeeds with cache access); recording/export CLI inspected. User coordinating playback manually. CPU measurements do not establish body evaluation rates.


## Default-zoom SwiftUI playback trace
- AX verified no picker, Pause icon, zoom slider 1, 30-minute clip progressing before capture. Command: `xcrun xctrace record --template SwiftUI --attach 66283 --time-limit 15s --output /private/tmp/sfv-swiftui-default-2026-10-29.trace`. Producer exit 0; trace saved and `swiftui-updates` export completed exit 0.
- Raw trace: `/private/tmp/sfv-swiftui-default-2026-10-29.trace`; raw event export: `/private/tmp/sfv-swiftui-default-updates.xml` (~174 MB, kept outside repository). Durable reduced evidence: `swiftui-playback-summary.json`, `swiftui-playback-custom-events.csv`, `swiftui-playback-record.log`.
- Stable event window [2,14) seconds: **360 StripTransportBar body-accessor updates / 12 seconds = 30/s**, **0 ThumbnailStripView, ThumbnailCellView or LeftPaneView body-accessor updates recorded**. This supports transport isolation and absence of per-tick outer strip/cell re-evaluation. Nested GeometryReader/overlay/framework views and footer TimelineView are not claimed idle.
- Late-attach caveat: existing custom view hierarchy is unknown; named body-accessor events appear under Other Updates rather than View Body Updates. Counts use the body-accessor descriptions. Export includes events through 19.991 seconds despite nominal 15-second request; use the stated stable window, not a nominal-duration denominator.
- Task 2.2 measured isolation accepted; task 2.1 still awaits paused-idle measurement. No new source change/build/app input.


## Paused SwiftUI trace — final Wave 2 gate
- User reported paused; AX verified Play icon/native playback off, zoom 1, timecode 00:17:22:07. After recording, AX tree unchanged.
- Command: `xcrun xctrace record --template SwiftUI --attach 66283 --time-limit 10s --output /private/tmp/sfv-swiftui-idle-2026-10-29.trace`. Recording/save and update export completed exit 0.
- Stable [2,9) second window: **0 body-accessor updates for ThumbnailStripView, ThumbnailCellView, StripTransportBar and LeftPaneView**. The recorder was active: 839 framework TimelineView schedule/filter events in that window. Playback trace is a positive capture control (360 named transport body-accessor events in 12 seconds).
- Idle export spans 0.581–14.149 seconds (stop/save instrumentation includes more than nominal duration); denominator remains the stated 7-second stable window. Scope is named custom-view bodies, not all framework/layout/TimelineView work.
- Durable evidence: `swiftui-idle-summary.json`, `swiftui-idle-updates.xml`, `swiftui-idle-record.log`. Raw trace at `/private/tmp/sfv-swiftui-idle-2026-10-29.trace`.
- Task 2.1 accepted with retained user manual follow/border evidence and completed CPU/playback/idle profiling. **Wave 2 complete; plan remains active, 8/15 complete and one reverted.** Wave 3 not started. Optional Wave 4.3 was not separately promoted: final verification wave remains future work.
