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

    @State private var activeIndex: Int = -1
    @State private var visibleRows: ClosedRange<Int> = 0...0
    @State private var scrollViewport = ThumbnailViewport(size: .zero, offsetY: 0)
    @State private var viewportSize: CGSize = .zero
    @State private var followScrollWork: Task<Void, Never>?
    @State private var playbackScrollTarget: Int?
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
    // Debounces the seek-driven auto-scroll so a scrub storm (many >0.5s jumps
    // in a row) resolves to a single scrollTo once the playhead settles,
    // instead of stacking interrupted animations + render churn. See
    // observePlayerTime().
    @State private var seekScrollWork: Task<Void, Never>? = nil

    private var cellW: CGFloat { model.thumbWidth }
    private var cellH: CGFloat { cellW * 9.0 / 16.0 }
    private var times: [CMTime] { model.thumbnailTimes(in: 0...model.duration) }

    var body: some View {
        VStack(spacing: 0) {
            StripTransportBar(model: model, player: player,
                              togglePlayPause: togglePlayPause, stripFocused: $stripFocused)
            grid
            zoomControlRow
        }
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
                    let allTimes = times
                    ForEach(allTimes.indices, id: \.self) { idx in
                        let time = allTimes[idx]
                        ThumbnailCellView(
                            time: time,
                            widthBucket: model.widthBucket,
                            displaySize: CGSize(width: cellW, height: cellH),
                            cache: model.cache,
                            cacheVersion: model.cacheVersion,
                            playerIdentity: playerIdentity,
                            captureOwnerIdentity: ObjectIdentifier(vm),
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
                        .equatable()
                        .frame(width: cellW, height: cellH)
                        .id(idx)
                        .anchorPreference(key: ActiveCellBoundsKey.self, value: .bounds) {
                            idx == activeIndex ? $0 : nil
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlayPreferenceValue(ActiveCellBoundsKey.self) { anchor in
                    GeometryReader { geometry in
                        if let anchor {
                            let bounds = geometry[anchor]
                            Rectangle()
                                .strokeBorder(Theme.accent, lineWidth: 2)
                                .frame(width: bounds.width, height: bounds.height)
                                .position(x: bounds.midX, y: bounds.midY)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: seekScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                seekScrollTarget = nil
            }
            .onChange(of: playbackScrollTarget) { _, target in
                guard let target else { return }
                // Continuous following must not stack/restart scroll animations.
                proxy.scrollTo(target, anchor: .center)
                playbackScrollTarget = nil
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
        // Track raw geometry once. Model/zoom changes must also recompute the
        // range: they need not cause a scroll-geometry event on a short clip.
        .onScrollGeometryChange(for: ThumbnailViewport.self) { geometry in
            ThumbnailViewport(size: geometry.containerSize, offsetY: geometry.contentOffset.y)
        } action: { _, viewport in
            scrollViewport = viewport
            refreshViewport(viewport)
        }
        // A short contact sheet may never scroll. Measure the actual viewport
        // independently so the initial split-view layout starts its render too.
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { size in
            viewportSize = size
            refreshViewport(scrollViewport)
        }
        .onChange(of: ObjectIdentifier(model), initial: true) { _, _ in
            refreshViewport(scrollViewport, forceRender: true)
        }
        .onScrollPhaseChange { _, new in
            model.onScrollPhaseChange(isScrolling: new.isScrolling)
        }
        .task(id: playerIdentity) {
            await observePlayerTime()
        }
        .onChange(of: model.density) { _, _ in
            refreshViewport(scrollViewport)
            updateActiveIndex(at: player?.currentTime() ?? .zero)
        }
        .onChange(of: model.thumbWidth) { _, _ in
            refreshViewport(scrollViewport)
        }
        .onChange(of: activeIndex) { _, _ in
            schedulePlaybackFollow()
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
            .help("Reset zoom (Command-0)")
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

    private func refreshViewport(_ raw: ThumbnailViewport, forceRender: Bool = false) {
        // The view's own size is authoritative once layout has measured it;
        // scroll callbacks can still contain transient container dimensions.
        let viewport = ThumbnailViewport(
            size: viewportSize.width > 0 && viewportSize.height > 0 ? viewportSize : raw.size,
            offsetY: raw.offsetY
        )
        guard let projection = viewport.project(
            cellWidth: cellW, density: model.density,
            duration: model.duration, count: model.thumbnailCount
        ) else { return }
        cellsPerRow = projection.columns
        visibleRows = projection.fullyVisibleRows
        if forceRender || model.visibleTimeRange != projection.timeRange {
            model.onVisibleRangeChange(projection.timeRange)
        }
    }

    private func updateActiveIndex(at time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard model.thumbnailCount > 0, seconds.isFinite else {
            if activeIndex != -1 { activeIndex = -1 }
            return
        }
        let raw = (max(0, min(model.duration, seconds)) * model.density).rounded()
        let index = min(model.thumbnailCount - 1, Int(raw))
        if activeIndex != index { activeIndex = index }
    }

    private func schedulePlaybackFollow() {
        guard activeIndex >= 0, seekScrollWork == nil, followScrollWork == nil,
              !visibleRows.contains(activeIndex / cellsPerRow) else { return }
        // Throttle, not trailing debounce: later playback ticks update activeIndex
        // without restarting this timer, even at one thumbnail per video frame.
        followScrollWork = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(80)) }
            catch { return }
            followScrollWork = nil
            guard seekScrollWork == nil, activeIndex >= 0,
                  !visibleRows.contains(activeIndex / cellsPerRow) else { return }
            playbackScrollTarget = activeIndex
        }
    }

    // MARK: - Player time observation

    private var playerIdentity: ObjectIdentifier? {
        player.map { ObjectIdentifier($0) }
    }

    private func observePlayerTime() async {
        guard let player else { activeIndex = -1; return }
        var previousTime = player.currentTime()
        let lifetime = TimeObservationLifetime()
        updateActiveIndex(at: previousTime)
        let update: @MainActor (CMTime) -> Void = { time in
            guard lifetime.isActive else { return }
            let delta = abs(CMTimeGetSeconds(time) - CMTimeGetSeconds(previousTime))
            previousTime = time
            updateActiveIndex(at: time)
            // Preserve seek-sized jump detection and the 150 ms trailing debounce.
            if delta > 0.5 {
                followScrollWork?.cancel()
                followScrollWork = nil
                seekScrollWork?.cancel()
                seekScrollWork = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(150)) }
                    catch { return }
                    seekScrollWork = nil
                    seekScrollTarget = activeIndex
                }
            }
        }
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { @Sendable time in
            MainActor.assumeIsolated { update(time) }
        }
        defer {
            lifetime.isActive = false
            player.removeTimeObserver(token)
            seekScrollWork?.cancel()
            seekScrollWork = nil
            followScrollWork?.cancel()
            followScrollWork = nil
        }
        do { try await Task.sleep(nanoseconds: .max) }
        catch { /* Cancellation removes the observer and pending scrolling. */ }
    }
}

/// Shared only on the main actor; queued observer callbacks become inert on teardown.
@MainActor
private final class TimeObservationLifetime {
    var isActive = true
}

/// Resolve the selected cell's actual bounds, preserving adaptive-grid packing
/// and alignment at fractional widths without duplicating SwiftUI layout math.
private struct ActiveCellBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// Owns the 30 Hz readout state so time ticks never invalidate the grid.
private struct StripTransportBar: View {
    let model: StripModel
    let player: AVPlayer?
    let togglePlayPause: () -> Void
    let stripFocused: FocusState<Bool>.Binding
    @State private var currentTime: CMTime = .zero
    @State private var isPlaying = false

    // MARK: - Transport bar (play/pause · selected-frame timecode · zoom scale)

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayPause()
                stripFocused.wrappedValue = true
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(Theme.primaryText)
            .help("Play/Pause (Space) · J/K/L shuttle · Option-Left/Right Arrow jump 30s · Shift-Left/Right Arrow jump 1min")

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
        .task(id: playerIdentity) { await observePlayerTime() }
        .task(id: playerIdentity) { await observePlaybackStatus() }
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

    private var playerIdentity: ObjectIdentifier? {
        player.map { ObjectIdentifier($0) }
    }

    private func observePlayerTime() async {
        guard let player else { currentTime = .zero; return }
        currentTime = player.currentTime()
        let lifetime = TimeObservationLifetime()
        let update: @MainActor (CMTime) -> Void = { time in
            guard lifetime.isActive else { return }
            if currentTime != time { currentTime = time }
        }
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { @Sendable time in
            MainActor.assumeIsolated { update(time) }
        }
        defer {
            lifetime.isActive = false
            player.removeTimeObserver(token)
        }
        do { try await Task.sleep(nanoseconds: .max) }
        catch { /* Cancellation removes the observer. */ }
    }

    // Mirror AVPlayer's play/pause state into `isPlaying` via KVO so the
    // transport icon is correct even when playback ends on its own (the
    // periodic time observer stops firing once the timebase halts).
    private func observePlaybackStatus() async {
        guard let player else { isPlaying = false; return }
        isPlaying = player.timeControlStatus == .playing
        for await status in player.publisher(for: \.timeControlStatus).values {
            isPlaying = status == .playing
        }
    }
}
