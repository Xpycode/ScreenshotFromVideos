# Grid-column acceptance failure — 2026-10-28

User-operated transport build: `/private/tmp/sfv-transport-build/Build/Products/Debug/ScreenshotFromVideos.app`.

User passed the transport icon retest, then reported diagonal Up/Down Arrow navigation at high zoom (starting before maximum zoom), and thumbnails remaining blank after waiting. These are acceptance failures, distinct from the previously deferred decode lag during continuous playback.

Four supplied screenshots are preserved alongside this file. They show four actual columns, selected frames 211/213/216/217, and blank visible cells. A five-index vertical stride on a four-column grid changes the column. Source independently estimates columns for navigation and visible decode demand while LazyVGrid adaptively chooses its packing. At deep rows, a one-column disagreement shifts demand far outside the visible cells.

Fix: pass `cellsPerRow` as an explicit array of fixed GridItems. Layout, navigation and demand now share the same count. Actual-cell anchor bounds still draw the border. Capture dot enlarged from 4 to 7 points with 3-point inset at the user's request.

Validation: Foundation-only projection tests cover the four/five-column boundary at 240-point cells, deep-scroll demand coverage, and vertical column preservation. These tests do not execute SwiftUI layout or decoding; live acceptance is required to establish whether the blank-cell failure is resolved.

Pending manual batch: at the formerly failing zoom and maximum zoom, pause near 8 seconds, let visible thumbnails fill, use Up/Down Arrow repeatedly, then check at a second window width. Border must remain in the same column except at clip boundaries, and visible thumbnails must fill while idle. Confirm larger capture-dot visibility. Broader Wave 2 performance checks remain open.

## Follow-up: fixed-grid intrinsic-width regression
User reports the navigation/rendering change works, but supplied `fixed-columns-overflow.png` shows controls/sidebar pushed outside the window. Read-only AX evidence showed main divider at 3165 points (previously 1223). Fixed columns momentarily retain the prior column count when zoom grows cells; their intrinsic minimum width can enlarge the pane and feed the enlarged width back into column calculation. Added a GeometryReader around the grid viewport and explicitly framed the ScrollView to the parent-proposed size, preventing content width from determining the viewport. Strict-concurrency build passed; live loaded/zoomed layout still requires manual retest. No app profile reset or split-divider manipulation was performed.

## Final manual result
User explicitly reported timecode/capture and navigation pass on the navigation build. `navigation-timecode-pass.png` shows transport/footer/captured row agreeing at 00:00:04:18, visible larger capture dots, filled cells and contained sidebar/controls. Home/End and Page Up/Page Down user-passed. Full prescribed zoom1/6/12 at two widths and sustained30-second playback were not explicitly established; performance was not sampled.
