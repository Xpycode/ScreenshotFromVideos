# Wave 4 final verification — 2026-10-29

Status: manual matrix complete (task 4.1 user-passed 2026-11-01); remaining performance evidence and batch-count criterion unresolved. User operates the app; agent performs read-only measurement and records results. No automated app input, launch, preferences, clipboard, export or network operations by this verification run.

## Identity and retained evidence

- App: `/private/tmp/sfv-wave3-final-build/Build/Products/Debug/ScreenshotFromVideos.app`, version 0.1 (1). PID 93956 reverified by exact executable path and start time before measurement.
- `shasum -a 256 -c docs/validation/seek-coalescing-2026-10-29/final-source-artifact.sha256` from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos` passed all four entries: coalescer, strip, model, executable. `git diff --check` passed. No source edits or rebuild required for verification.
- Retain [Wave 3](../seek-coalescing-2026-10-29/README.md) strict-concurrency build, headless tests, independent review, runtime seek acceptance and debounce trace. Runtime acceptance was on diagnostic build; final build removed the probe and was launch-verified. Final artifact manual matrix remains below.
- Retain [Wave 2 SwiftUI traces](../performance-2026-10-29/README.md) for optional 4.3: playback transport 30 body-accessor updates/s, no named outer strip/cell updates; paused no named custom-view updates. Limits: late attach, named custom views only, earlier artifact. Wave 3 did not reintroduce raw-time state or cell dependencies. No new Instruments recording needed absent a regression.

## Finite final manual matrix (4.1)

Use `/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4`, away from clip ends. Focus the grid by clicking a thumbnail before keys. One pass on the final artifact; report case IDs and failures, or “all pass.” Existing every-frame black-cell/decode limitation and drag scrubbing remain separate Backlog items.

| ID | Actions | Expected result | Status |
|---|---|---|---|
| F1 | Normal playback at default zoom for at least 30 seconds; repeat at maximum zoom after fill | Readouts tick; active border stays aligned and visible, following as needed | User-passed 2026-11-01; prior default-follow evidence retained |
| F2 | K to pause; L three times for 4× forward; K then J three times for 4× reverse; Space/K to stop | Shuttle/readouts progress in correct direction; playback toggles correctly | User-passed 2026-11-01 on combined viewport/retry build |
| F3 | While paused, hold each of Left, Right, Up, Down Arrow briefly and release | Correct cell/row direction; prompt final target, no catch-up queue; offscreen seek centers selection | User-passed 2026-11-01 on combined viewport/retry build |
| F4 | Option-Left/Right Arrow and Shift-Left/Right Arrow; click separated cells | 30-second/one-minute jumps; exact selected border/frame without off-by-one | User-passed 2026-11-01 on combined viewport/retry build |
| F5 | Command-click capture, then M and Q at distinct positions | Capture count increases and corresponding pinned dots appear | User-passed 2026-11-01 on combined viewport/retry build |
| F6 | Pinch, bare plus/minus keys, Command-scroll wheel, slider; include zoom 1/6/12 | Each path changes zoom; thumbnails refill; border remains aligned | User-passed 2026-11-01 on combined viewport/retry build |
| F7 | Pause, Unload and reload, click/seek once | Clean reset, new clip responds, no stale navigation resumes | User-passed 2026-11-01 on combined viewport/retry build |

Completion requires all seven cases explicitly passed on the final app. Earlier accepted checks are supporting evidence, not an inferred final matrix pass.

## CPU remeasurement (4.2)

Same baseline clip; user sets each state on cue. Read-only `ps` at 1 Hz; record PID/path/start identity, UTC, raw samples, exit status and source hashes. No diagnostic probe. CPU is a historical comparison, not a paired controlled benchmark or proof of body evaluation rate.

| State | Wave 0 CPU average | Final app | Status |
|---|---:|---:|---|
| a: 1× default zoom, 30 s | 91.8% | 39.08% (33.0–42.9%) | Complete; confirmed playback, first idle attempt excluded |
| b: 1× maximum zoom, 30 s | 68.1%, invalid offscreen-follow baseline | 53.403% (50.7–58.6%) | CPU complete on earlier artifact; maximum follow passed 2026-11-01 on combined build |
| c: 4× forward shuttle, default zoom, 30 s | 104.7% | 121.2% (104.9–146.4%) | Complete; forward behavior report pending |
| d: held Right Arrow, default zoom, 10 s | 72.3% | 68.95% (18.4–104.8%), provisional | Collection complete; sustained movement/release report pending |
| e: paused default→maximum slider transition/fill, 20 s (10 s idle first) | 120.9%, peak 188.1%; idle 14.6% | 33.585%, peak 98.3%; idle 17.2% | Action confirmed; rendering FAILED, no performance-win claim |

Do not compare b against the invalid 68.1% as an improvement. Retained Wave 2 a/b averages 35.883%/33.543% belong to the earlier footer artifact.

## Acceptance discrepancy retained

The plan's batch-count criterion says at most approximately ten invalidations per 256-image fill, but accepted Wave 1 evidence records 17–18 total bumps. Current implementation limits streaming bumps to approximately ten **per second**, plus completion, not ten per batch. The original total-count criterion is not established by that evidence. Resolve this explicitly at final acceptance; do not silently mark it passed or change renderer behavior during verification.


## First default-playback attempt — state unconfirmed

User requested “default-playback CPU sample.” Command from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`: `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py default-playback --seconds 30`. Read-only process access escalation succeeded. Producer exit 0; 30 samples over 30.011 s, UTC start 2026-10-29T12:06:16.831817+00:00. PID/start/executable identity remained stable and executable SHA-256 matches final build.

[Raw sample](default-playback.json): average 0.00333%, range 0–0.1%, peak RSS 73712 KiB. This is effectively idle and is **excluded from the playback benchmark**: the user's request did not explicitly confirm visibly advancing video, and the agent did not inspect live UI. No playback/follow pass inferred. Asked user to load baseline clip, reset zoom, start playback, verify advancing timecode and reply “playing default.” Repeat under a new filename (`default-playback-confirmed`) to preserve the original evidence. This repeat is justified by unconfirmed state, not a product regression. No app input/lifecycle/data changes performed.


## Confirmed default playback — CPU state a complete

User replied “playing default.” Command from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`: `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py default-playback-confirmed --seconds 30`. Producer exit 0; [raw samples](default-playback-confirmed.json) retain 30 measurements over 30.101 s, UTC start 2026-10-29T12:09:49.925224+00:00. PID 93956/start/executable identity remained stable; SHA-256 matches final artifact.

CPU average **39.08%**, range **33.0–42.9%**; peak sampled RSS **153200 KiB** (~149.6 MiB). Approximately 57.4% below historical Wave 0 91.8%, with historical/non-paired limitations retained. Playback state is user-confirmed; no automated UI inspection/input. Default follow/border observation separately requested, not inferred from CPU. Next: maximum zoom, fill, normal 1× playback; await user “playing max.”


## Maximum playback — CPU state b complete; default follow passed

User replied “default follow pass; playing max.” F1 default-zoom follow accepted; maximum-zoom follow still awaits explicit report. Command from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`: `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py maximum-playback --seconds 30`. Producer exit 0; [raw samples](maximum-playback.json): 30 samples over 30.037 s, UTC start 2026-10-29T12:12:30.348849+00:00. PID 93956/start/path remained stable; executable hash matches final artifact.

Average CPU **53.403%**, range **50.7–58.6%**; peak RSS **199904 KiB** (~195.2 MiB). Higher than current default playback (39.08%); no improvement claim against invalid Wave 0 maximum-zoom 68.1%. Retained earlier Wave 2 maximum 33.543% is a separate earlier-artifact run, not a controlled paired comparison. No source regression inferred from CPU alone. No app input/control by agent. Next user cue: maximum-follow observation, then pause/reset/fill/default-zoom 4× forward shuttle; reply “max follow pass; shuttle 4×.”


## Forward 4× shuttle — CPU state c complete

User replied “shuttle 4x playing.” Command from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`: `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py shuttle-forward-4x --seconds 30`. Producer exit 0; [raw samples](shuttle-forward-4x.json): 30 samples over 30.017 s, UTC start 2026-10-29T12:16:58.192551+00:00. PID 93956/start/path stable; executable hash matches final artifact.

CPU average **121.2%**, range **104.9–146.4%**; peak sampled RSS **237664 KiB** (~232.1 MiB). Approximately 15.8% higher than historical 104.7%, not evidence of a regression in isolation: unpaired run, changed follow behavior/cache demand, no matched playhead/cache/window control. This state did not improve against the historical sample; preserve that result without claiming an across-the-board CPU win. No source change or repeat sampling justified yet. Maximum follow and final forward/reverse shuttle behavior remain unreported. Next: user pauses at default zoom and focuses grid away from ends, reports “ready for arrows,” then agent cues a finite held-Right-Arrow sample. Do not start it after the user has already finished holding.


## Held Right Arrow — CPU state d collected, state confirmation pending

User replied “ready for arrows.” Agent cued holding immediately until release, allowing five seconds for app focus before the ten-second sample. Command from `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`: `sleep 5` then `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py held-right-arrow --seconds 10`. Producer exit 0; [raw samples](held-right-arrow.json): ten samples over 10.038 s, UTC start 2026-10-29T12:19:22.250488+00:00. PID 93956/start/path stable; executable hash matches final artifact. Agent sent release cue immediately on completion; no automated keys/input.

Average CPU **68.95%**, range **18.4–104.8%**; peak RSS **284192 KiB** (~277.5 MiB). Provisional pending user confirmation of sustained movement during the sample and prompt stop on release. Do not claim final state-d acceptance, held-key behavior or improvement against historical 72.3% until confirmed. Next request asks for that report plus paused/default/fill setup and “ready for zoom.” State e needs ten-second idle first, then an explicit move-slider cue and twenty-second transition/fill capture. Maximum follow/forward shuttle observations remain open.


## Zoom transition — action confirmed, thumbnail-fill acceptance failed

User replied “ready to zoom.” Kept playback paused/default zoom for idle collection. From `/Users/sim/ProgrammingProjects/1-macOS/ScreenshotFromVideos`, ran `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py zoom-idle --seconds 10` (exit 0), then `python3 docs/validation/final-verification-2026-10-29/collect-cpu.py zoom-transition --seconds 20` (exit 0). Transition collector started before “Move the zoom slider … now” cue. User explicitly confirmed **“moved on cue, still black”** after being asked whether the selected thumbnail fills after another 10–20 seconds paused.

- [Idle raw sample](zoom-idle.json): UTC 2026-10-29T12:20:38.063914+00:00; ten samples/10.030 s; CPU average 17.2%, range 14.2–18.8%; peak RSS 285248 KiB.
- [Transition raw sample](zoom-transition.json): UTC 2026-10-29T12:20:56.555287+00:00; twenty samples/20.026 s; CPU average 33.585%, range 14.9–98.3%; peak RSS 303552 KiB. PID/start/path/hash stable in both captures. Lower work while cells are missing cannot establish a successful performance improvement.
- [User screenshot](maximum-zoom-paused.png): paused, every-frame/1:1 zoom, player/footer 00:25:29:29, frame 45,899. Orange border visible around a black selected thumbnail; another image exists in the preceding row. This proves a visible placeholder, not a live cache miss/decode failure cause or alignment pass.
- State d sustained movement/release report, maximum playback follow and forward/reverse shuttle observations remain unreported. Do not infer them from readiness replies or this screenshot.

### Read-only decoder diagnostic and limits

Inspected production viewport demand, render scheduling/cancellation, cell cache identity and renderer. No obvious source-only proof of the live cause. [Headless diagnostic source](decode-check.swift) calls the unchanged production ThumbnailRenderer for indices 45894...45905 around selected 45899 at 30 fps, width bucket 240, half-gap tolerance. Reads the baseline clip and writes only diagnostic output; no app startup, preferences, network, app-hosted tests or desktop control.

Compile: `swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path /private/tmp/sfv-wave4-decode-module-cache 01_Project/ScreenshotFromVideos/Thumbnail/ThumbnailRenderer.swift /private/tmp/sfv-wave4-decode-check.swift -o /private/tmp/sfv-wave4-decode-check` (exit 0). Initial sandbox run returned zero images with decoder errors and restricted sysctl warning; invalid as product evidence. Retried inspected executable with decoder-service access outside sandbox: `/private/tmp/sfv-wave4-decode-check > /private/tmp/sfv-wave4-decode-check.log 2>&1`, preserving real exit (0). [Output](decode-check.log): 11/12 images returned, selected key 1529967 succeeded; neighbouring key 1529865 failed AVFoundation -11821 / underlying -12911. Process exit zero means diagnostic completed, not all frames decoded. This does not reproduce the live selected-cell failure or distinguish scheduling/demand/cache/decode/display causes. No renderer/tolerance/generator reuse change justified by this alone.

**Next blocker work:** trace actual visible-range demand, requested/delivered keys, task cancellation and refresh delivery around a paused zoom transition, with a short-lived diagnostic if needed. Preserve the accepted uninstrumented CPU evidence, and do not benchmark a diagnostic build. Keep final acceptance open until the selected visible thumbnail fills or the user explicitly defers this newly confirmed paused failure. Do not repeat the full accepted matrix or all CPU states without a relevant fix/configuration change.

## Paused-fill resolution — 2026-11-01

User reported “pass” after authorized launch/path/version/checksum verification of `/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app` and the requested untouched 20-second paused-fill retest. Accept only paused-fill portion of F6; other manual reports and batch-count criterion remain open. [Implementation, decoder evidence and acceptance](../viewport-demand-2026-11-01/README.md#paused-fill-accepted). Prior CPU measurements retain original artifact/failed-render limits; no performance-win claim inferred.

User subsequently passed V2 scroll/zoom/resize fill and V3 maximum-zoom30-second playback follow on the combined build. F1 maximum-follow observation accepted; prior default evidence retained. This is runtime behavior acceptance, not a new CPU measurement. Remaining finite matrix: F2 shuttle, F3 held arrows, F4 jumps/clicks, F5 captures/pins, explicit F6 zoom paths, F7 unload/reload.

## Manual matrix complete — 2026-11-01

User replied “all pass” to the remaining explicitly listed batch: J/K/L shuttle forward/reverse, held arrows/release, Option/Shift-arrow jumps and click-seek, Command-click/M/Q capture with pins, pinch/plus-minus/Command-scroll/slider zoom, unload/reload and seek. Combined with V1–V3 and retained default follow, this closes task4.1. Do not reinterpret current held-arrow behavior as confirmation of sustained input during the historical October29 CPU sampling interval. No new CPU sample or batch-invalidation measurement occurred; 4.2 and total-count criterion remain open.
