//
//  ThumbnailStripView.swift
//  ScreenshotFromVideos
//
//  Contact-sheet grid: vertical ScrollView + LazyVGrid with adaptive columns.
//  Cells wrap to as many rows as fit the container; vertical scroll reveals more.
//  The active cell (containing currentTime) gets a Theme.accent border —
//  the filmstrip-style vertical playhead bar makes no sense in a grid.
//

import SwiftUI
import AVFoundation
import CoreMedia
import AppKit

struct ThumbnailStripView: View {
    let model: StripModel
    let player: AVPlayer?
    let vm: ExtractionViewModel

    @State private var currentTime: CMTime = .zero
    // Drives keyboard focus for the grid. The +/-/0/m/arrow handlers only fire
    // while the strip holds focus, so we claim it on cell-tap and re-claim it
    // after a zoom-button click (which would otherwise steal focus).
    @FocusState private var stripFocused: Bool
    // Set by the periodic time observer when a "seek-sized" delta is detected
    // (vs the small per-tick deltas of natural playback). Read by the
    // ScrollViewReader-side onChange below to bring the active cell into view.
    @State private var seekScrollTarget: Int? = nil
    // Columns visible per row, tracked from scroll geometry so ↑/↓ arrow
    // navigation can step a whole row instead of a single cell.
    @State private var cellsPerRow: Int = 1
    // Reflects player.timeControlStatus so the transport bar's play/pause icon
    // stays correct even when playback stops on its own (reaches end).
    @State private var isPlaying: Bool = false
    // Debounces the seek-driven auto-scroll so a scrub storm (many >0.5s jumps
    // in a row) resolves to a single scrollTo once the playhead settles,
    // instead of stacking interrupted animations + render churn. See
    // observePlayerTime().
    @State private var seekScrollWork: Task<Void, Never>? = nil

    private var cellW: CGFloat { model.thumbWidth }
    private var cellH: CGFloat { cellW * 9.0 / 16.0 }
    private var rowH: CGFloat { cellH + 1 }
    private var times: [CMTime] { model.thumbnailTimes(in: 0...model.duration) }

    var body: some View {
        VStack(spacing: 0) {
            transportBar
            grid
            zoomControlRow
        }
    }

    // MARK: - Transport bar (play/pause · selected-frame timecode · zoom scale)

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(Theme.primaryText)
            .help("Play/Pause (Space) · J/K/L shuttle · ⌥←→ jump 30s · ⇧←→ jump 1min")

            // Selected frame: frame-accurate timecode + absolute frame index.
            // The frame number rides in a worst-case-width field (hidden
            // template) so the right-hand scale doesn't jitter as it ticks.
            HStack(spacing: 6) {
                Text(timecodeString)
                Text("·")
                    .foregroundStyle(Theme.secondaryText)
                ZStack(alignment: .leading) {
                    Text("frame \(totalFrames)").hidden()
                    Text("frame \(frameNumber)")
                }
                .foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 14, weight: .thin).monospacedDigit())

            Spacer()

            // Zoom scale: how many source frames fall between two thumbnails,
            // plus the real-time gap. Collapses to "every frame · 1:1" at max.
            HStack(spacing: 5) {
                Image(systemName: "ruler")
                    .font(.system(size: 10))
                Text(scaleString)
            }
            .font(.system(size: 11, weight: .regular).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .help("Spacing between thumbnails at the current zoom")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.secondaryBackground)
    }

    private var timecodeString: String {
        TimestampFormatter.timecode(from: currentTime, fps: model.nominalFPS)
    }

    private var frameNumber: Int {
        TimestampFormatter.frameNumber(from: currentTime, fps: model.nominalFPS)
    }

    private var totalFrames: Int {
        TimestampFormatter.frameNumber(
            from: CMTime(seconds: model.duration, preferredTimescale: 600),
            fps: model.nominalFPS
        )
    }

    private var scaleString: String {
        let n = model.framesPerThumbnail
        if n <= 1 { return "every frame · 1:1" }
        let secs = model.secondsPerThumbnail
        let gap = secs < 1
            ? String(format: "%.0fms", secs * 1000)
            : String(format: "%.2fs", secs)
        return "every \(n) fr · \(gap)"
    }

    private func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        stripFocused = true
    }

    // MARK: - Transport: J/K/L shuttle + jump

    // Forward speed ladder for the shuttle. J mirrors it in reverse.
    private static let shuttleLadder: [Float] = [1, 2, 4]

    /// L / J — NLE-style shuttle. First press starts 1× in that direction; each
    /// further press steps up the ladder (2×, 4×). Reverse depends on the codec,
    /// so if the item can't play (fast-)reverse we beep and hold the current
    /// rate rather than stall the player silently at rate 0.
    private func shuttle(forward: Bool) {
        guard let player else { return }
        let r = player.rate
        let next: Float
        if forward {
            next = r <= 0 ? 1 : (Self.shuttleLadder.first { $0 > r } ?? Self.shuttleLadder.last!)
        } else if r >= 0 {
            next = -1
        } else {
            let mag = -r
            next = -(Self.shuttleLadder.first { $0 > mag } ?? Self.shuttleLadder.last!)
        }
        let item = player.currentItem
        if next > 1, item?.canPlayFastForward != true { NSSound.beep(); return }
        if next < 0 {
            let ok = next < -1 ? (item?.canPlayFastReverse == true) : (item?.canPlayReverse == true)
            if !ok { NSSound.beep(); return }
        }
        player.rate = next
        stripFocused = true
    }

    /// ⌥←/→ (±30 s) and ⇧←/→ (±1 min) — seek relative to the current playhead,
    /// clamped to the clip. The seek detector in observePlayerTime() then
    /// recenters the strip on the landing spot (debounced).
    private func jump(by seconds: Double) {
        guard let player else { return }
        let cur = CMTimeGetSeconds(player.currentTime())
        let target = max(0, min(model.duration, cur + seconds))
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        stripFocused = true
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cellW, maximum: cellW), spacing: 1)],
                    spacing: 1
                ) {
                    let activeIdx = activeIndex
                    ForEach(Array(times.enumerated()), id: \.offset) { idx, time in
                        ThumbnailCellView(
                            time: time,
                            widthBucket: model.widthBucket,
                            displaySize: CGSize(width: cellW, height: cellH),
                            cache: model.cache,
                            cacheVersion: model.cacheVersion,
                            onTap: { tappedTime in
                                player?.seek(
                                    to: tappedTime,
                                    toleranceBefore: .zero,
                                    toleranceAfter: .zero
                                )
                                stripFocused = true
                            },
                            onCmdTap: { tappedTime in
                                vm.captureFrame(at: tappedTime)
                            },
                            manualPinned: isPinned(at: time)
                        )
                        .frame(width: cellW, height: cellH)
                        .id(idx)
                        .overlay(
                            // Decorative — allowsHitTesting(false) so the full-rect
                            // overlay doesn't swallow taps on the active cell.
                            Rectangle()
                                .strokeBorder(Theme.accent, lineWidth: idx == activeIdx ? 2 : 0)
                                .allowsHitTesting(false)
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: seekScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                seekScrollTarget = nil
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.secondaryBackground)
        .focusable()
        .focused($stripFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.init("="), .init("+")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            model.zoomIn()
            return .handled
        }
        .onKeyPress(keys: [.init("-")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            model.zoomOut()
            return .handled
        }
        .onKeyPress(keys: [.init("0")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            model.resetZoom()
            return .handled
        }
        .onKeyPress(keys: [.init("m"), .init("M"), .init("q"), .init("Q")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            vm.captureCurrentFrame()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow]) { press in
            if press.modifiers.contains(.command) || press.modifiers.contains(.control) { return .ignored }
            if press.modifiers.contains(.option) { jump(by: -30); return .handled }   // ⌥← : −30 s
            if press.modifiers.contains(.shift)  { jump(by: -60); return .handled }   // ⇧← : −1 min
            navigate(by: -1)
            return .handled
        }
        .onKeyPress(keys: [.rightArrow]) { press in
            if press.modifiers.contains(.command) || press.modifiers.contains(.control) { return .ignored }
            if press.modifiers.contains(.option) { jump(by: 30); return .handled }    // ⌥→ : +30 s
            if press.modifiers.contains(.shift)  { jump(by: 60); return .handled }    // ⇧→ : +1 min
            navigate(by: 1)
            return .handled
        }
        .onKeyPress(keys: [.upArrow]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            navigate(by: -cellsPerRow)
            return .handled
        }
        .onKeyPress(keys: [.downArrow]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            navigate(by: cellsPerRow)
            return .handled
        }
        // J/K/L shuttle transport + Space toggle. Same modifier guard as the
        // zoom/capture keys so they only fire on the bare key while the strip
        // holds focus (letters allow Shift for their capitalized variants).
        .onKeyPress(keys: [.init("l"), .init("L")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            shuttle(forward: true)
            return .handled
        }
        .onKeyPress(keys: [.init("j"), .init("J")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            shuttle(forward: false)
            return .handled
        }
        .onKeyPress(keys: [.init("k"), .init("K")]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            player?.pause()
            stripFocused = true
            return .handled
        }
        .onKeyPress(keys: [.space]) { press in
            guard !press.modifiers.contains(.command),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control) else { return .ignored }
            togglePlayPause()
            return .handled
        }
        .onScrollGeometryChange(for: Int.self) { geom in
            max(1, Int((geom.containerSize.width - 16) / (cellW + 1)))
        } action: { _, new in
            cellsPerRow = new
        }
        .onScrollGeometryChange(for: ClosedRange<Double>.self) { geom in
            let count = times.count
            guard count > 0, model.density > 0 else { return 0...0 }
            let cellsPerRow = max(1, Int((geom.containerSize.width - 16) / (cellW + 1)))
            let firstRow = max(0, Int(geom.contentOffset.y / rowH))
            let lastRow = Int((geom.contentOffset.y + geom.containerSize.height) / rowH)
            let firstIdx = min(count - 1, firstRow * cellsPerRow)
            let lastIdx = min(count - 1, (lastRow + 1) * cellsPerRow - 1)
            let lower = Double(firstIdx) / model.density
            let upper = Double(lastIdx + 1) / model.density
            let lo = max(0, min(model.duration, lower))
            let hi = max(lo, min(model.duration, upper))
            return lo...hi
        } action: { _, new in
            model.onVisibleRangeChange(new)
        }
        .onScrollPhaseChange { _, new in
            model.onScrollPhaseChange(isScrolling: new.isScrolling)
        }
        .task(id: playerIdentity) {
            await observePlayerTime()
        }
        .task(id: playerIdentity) {
            await observePlaybackStatus()
        }
        .task {
            await monitorCmdScrollWheel()
        }
        }
    }

    private var zoomControlRow: some View {
        HStack(spacing: 10) {
            Button {
                model.zoomOut()
                stripFocused = true
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(Theme.secondaryText)
            .help("Zoom out (−)")

            Slider(
                value: Binding(
                    get: { model.zoomLevel },
                    set: { model.setZoom($0) }
                ),
                in: 1.0...12.0
            )
            .controlSize(.mini)

            Button {
                model.zoomIn()
                stripFocused = true
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(Theme.secondaryText)
            .help("Zoom in (+)")

            Button {
                model.resetZoom()
                stripFocused = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(Theme.secondaryText)
            .help("Reset zoom (⌘0)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.primaryBackground)
    }

    private func monitorCmdScrollWheel() async {
        let m = model
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let isCmd = event.modifierFlags.contains(.command)
            let dy = event.scrollingDeltaY
            guard isCmd, dy != 0 else { return event }
            Task { @MainActor in m.applyZoomDelta(dy) }
            return nil
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        do {
            try await Task.sleep(nanoseconds: .max)
        } catch {
            // cancelled — defer removes the monitor
        }
    }

    // A cell is "pinned" if any manual time falls within half a cell-interval
    // of its timestamp. Linear contains is fine — the manual list is small.
    private func isPinned(at time: CMTime) -> Bool {
        guard !vm.manualTimes.isEmpty, model.density > 0 else { return false }
        let halfInterval = 0.5 / model.density
        let t = CMTimeGetSeconds(time)
        return vm.manualTimes.contains { abs(CMTimeGetSeconds($0) - t) < halfInterval }
    }

    // Arrow-key navigation: step the active cell by `offset` (±1 for ←/→,
    // ±cellsPerRow for ↑/↓), seek the player to that cell's time, and bring it
    // into view. Anchors off the current active cell so it tracks player state.
    private func navigate(by offset: Int) {
        let allTimes = times
        let count = allTimes.count
        guard count > 0, offset != 0 else { return }
        let cur = max(0, activeIndex)
        let target = max(0, min(count - 1, cur + offset))
        guard target != cur else { return }
        player?.seek(to: allTimes[target], toleranceBefore: .zero, toleranceAfter: .zero)
        seekScrollTarget = target
    }

    private var activeIndex: Int {
        guard model.density > 0, !times.isEmpty else { return -1 }
        // Round to nearest, not floor. With sample-accurate seek + irrational
        // density (e.g. pow(2, 0.6) ≈ 1.516), AVPlayer reports currentTime as
        // the landed frame's *start* time, which is generally < the seek
        // target — floor then drops to the previous cell. Round-to-nearest
        // tolerates that ε and gives "the cell whose timestamp is closest."
        let raw = Int((CMTimeGetSeconds(currentTime) * model.density).rounded())
        return max(0, min(times.count - 1, raw))
    }

    // MARK: - Player time observation

    private var playerIdentity: ObjectIdentifier? {
        player.map { ObjectIdentifier($0) }
    }

    private func observePlayerTime() async {
        guard let player else { return }
        let interval = CMTime(value: 1, timescale: 30)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { @Sendable time in
            Task { @MainActor in
                let prevSec = CMTimeGetSeconds(currentTime)
                currentTime = time
                // A seek shows up as a >0.5 s jump (natural per-tick deltas are
                // ≤1/30 s at this observer interval). Bring the active cell into
                // view so player-side seeking and the strip stay synced — but
                // *debounced*: dragging the scrubber emits a storm of such jumps,
                // and animating a scrollTo on every one makes the grid flail and
                // thrashes the render queue. Reschedule on each jump; the scroll
                // fires ~150 ms after the last one, i.e. once the drag settles.
                if abs(CMTimeGetSeconds(time) - prevSec) > 0.5 {
                    seekScrollWork?.cancel()
                    seekScrollWork = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        if Task.isCancelled { return }
                        seekScrollTarget = activeIndex
                    }
                }
            }
        }
        defer { player.removeTimeObserver(token) }
        do {
            try await Task.sleep(nanoseconds: .max)
        } catch {
            // cancelled — defer cleans up
        }
    }

    // Mirror AVPlayer's play/pause state into `isPlaying` via KVO so the
    // transport icon is correct even when playback ends on its own (the
    // periodic time observer stops firing once the timebase halts).
    private func observePlaybackStatus() async {
        guard let player else { return }
        isPlaying = player.timeControlStatus == .playing
        for await status in player.publisher(for: \.timeControlStatus).values {
            isPlaying = status == .playing
        }
    }
}
