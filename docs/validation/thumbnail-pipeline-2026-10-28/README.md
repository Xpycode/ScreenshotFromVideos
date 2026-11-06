# Thumbnail pipeline investigation — 2026-10-28

User reports initial 3-thumbnail grid remains mostly blank until zoom, including 1920×1280 copy. First two supplied screenshots are visually identical; all copied files have the same modification time (13:02:17), so elapsed delay cannot be inferred.

## Independent investigations
- Scheduling agent: viewport rendering depended only on scroll callback transformations; retained raw geometry and explicit layout/model/zoom projection now initialize demand independently. Source audit establishes fragility; live callback failure is not directly instrumented/proven.
- Decode agent: benchmarked same 34 requested timestamps, two runs each, fresh generators, 240-pixel width, half-gap tolerance, all success/zero failures. Original center-out 2.674/2.585 s vs chronological 2.482/2.391 s; converted center-out 1.590/1.480 s vs chronological 0.448/0.454 s. These are local headless decode measurements, not app latency guarantees. Logs and probe source alongside this file.
- Web agent: Apple recommends async images(for:), maximumSize and nonzero tolerance. No documented guarantee of initial scroll-geometry action or replay when a captured model changes. Sources below.

## Changes
1. Select nearest 256 missing timestamps as before, then decode that selection chronologically. Do not share generators across cancelled batches (prior failed experiment).
2. Flush pending cache publication in defer, including cancellation returns. Previously cached-but-unpublished images could be skipped by a successor and remain hidden.
3. One raw scroll snapshot plus independent viewport size measurement; explicit reprojection for new model, density and cell width. Ignore invalid dimensions and avoid identical-range restarts.
4. Preserve prior 80 ms zoom deadline across geometry rescheduling.

## Validation
- Production model/renderer/cache probe: converted initial34/34 in0.583s; after six rapid zoom changes final51/51 in0.587s; return to zoom1 all34 cached immediately. Original2.623s/3.991s/immediate respectively. This does not test SwiftUI layout delivery.
- Foundation-only production viewport helper tests pass: initial all-visible short clip, invalid/transient geometry, resize, scroll, exact boundaries, density/width changes and replacement clip.
- Independent model review: no blocking findings; cancellation defer does not bump batches without pending stored images.
- Xcodegen regenerated project. Strict-concurrency build exit0; no application-source warnings (tool-only AppIntents extraction warning). Raw build log `/private/tmp/sfv-pipeline-build.log`.
- Artifact `/private/tmp/sfv-pipeline-build/Build/Products/Debug/ScreenshotFromVideos.app`. Not launched; desktop-control connection unavailable and prior test app remains running.

## Remaining acceptance
Load the converted clip without touching zoom: all visible thumbnails should fill. Then zoom to every frame and back; thumbnails should finish and prior zoom reuse should be prompt. Repeat first-load on original6K clip. Record first image/full-visible-fill delays and any blank cells after settling. Existing Wave2 playback/click/highlight checks remain open.

## Primary sources
- https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset
- https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/cancelallcgimagegeneration()
- https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)

## Live result reported by user
Pipeline build launched and executable path verified. Converted clip: complete initial fill in <1 second without zoom; every-frame zoom and zoom-out both work. Original 6K clip: complete initial fill around 2 seconds; zoom faster, remaining delay explicitly accepted. These are user-observed timings, not instrumented measurements. Thumbnail regression accepted on both fixtures; other Wave 2 gates remain open.
