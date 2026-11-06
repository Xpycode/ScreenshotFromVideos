# Strip/player performance evidence archive — November 6, 2026

The [completed plan](2026-11-06_STRIP_PLAYER_PERFORMANCE_PLAN.md) is closed with 14 completed tasks and one reverted experiment. Evidence is archived in its original directories to retain links, source-relative manifests, historical timestamps and raw results. No historical failed run is rewritten as a pass.

| Evidence | What it establishes / limits |
|---|---|
| [Thumbnail pipeline](../../validation/thumbnail-pipeline-2026-10-28/README.md) | Demand initialization and chronological decode follow-up |
| [Grid/navigation](../../validation/grid-columns-2026-10-28/README.md) | Accepted fixed columns, containment, navigation and frame timecodes |
| [Wave 2 profiling](../../validation/performance-2026-10-29/README.md) | Named body-accessor playback/idle isolation; late-attach and historical-artifact limits |
| [Seek coalescing](../../validation/seek-coalescing-2026-10-29/README.md) | Tests, independent review, accepted navigation and measured existing scroll debounce |
| [Final verification history](../../validation/final-verification-2026-10-29/README.md) | Earlier a/b/c CPU states; original failed/provisional d/e remain historical |
| [Zoom diagnosis](../../validation/zoom-trace-2026-10-29/README.md) | Historical trace and failure diagnosis; temporary instrumentation removed |
| [Viewport and decoder retry](../../validation/viewport-demand-2026-11-01/README.md) | Regression/retry tests, real fixture 12/12, independent review and user-passed final manual matrix |
| [CPU and refresh closeout](../../validation/performance-closeout-2026-11-02/README.md) | Explicitly revised refresh criterion; November 6 fresh build and confirmed d/e CPU samples, cue/cache/unpaired comparison limits |

Final independent review found no concrete source defect. Playback cell isolation has direct retained trace evidence; shuttle isolation is source-reviewed through the shared path, not independently profiled. Generator reuse remains reverted; per-pass fresh generators are intentional.

The unrelated [compact-footer evidence](../../validation/window-width-2026-10-29/README.md) remains outside performance acceptance: narrow layout passed, wide labels/tooltips/actions not separately reported. Its source changes are excluded from the performance checkpoint. The tested combined app includes that existing footer; the checkpoint stages only the accepted timecode hunk from LeftPaneView.

Raw validation files are enumerated in [evidence checksums](2026-11-06_STRIP_PLAYER_PERFORMANCE_EVIDENCE.sha256), relative to repository root. The manifest covers the performance evidence directories, excluding the unrelated footer directory.
