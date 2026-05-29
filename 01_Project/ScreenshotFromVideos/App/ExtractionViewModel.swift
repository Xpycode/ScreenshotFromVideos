//
//  ExtractionViewModel.swift
//  ScreenshotFromVideos
//
//  Single @MainActor view-model owning the full UI state for one extraction
//  job. Concurrency shape mirrors CropBatch/Models/AppState.swift: one
//  Task<Void, Never>, cancelled before any new launch; progress hops back
//  to the main actor via the @MainActor callback that ExtractionPipeline
//  invokes per frame.
//
//  Stores the discrete UI fields (tab + interval unit + per-unit values +
//  manual list) and resolves them into a locked ExtractionRequest at the
//  moment Export is pressed. This avoids the redundancy of also keeping a
//  separate `mode: ExtractionMode` in sync.
//

import Foundation
import AVFoundation
import CoreMedia
import Observation

/// Top-level mode picker on the right pane.
enum ExtractionTab: String, CaseIterable, Identifiable {
    case interval
    case manual
    var id: String { rawValue }
}

/// Sub-picker for the Interval tab.
enum IntervalUnit: String, CaseIterable, Identifiable {
    case seconds
    case frames
    var id: String { rawValue }
}

@MainActor
@Observable
final class ExtractionViewModel {

    // MARK: Source (per-clip, not persisted)
    var sourceURL: URL?
    var player: AVPlayer?
    var metadata: VideoMetadata?

    // MARK: Output (persisted)
    var outputFolder: URL? {
        didSet { Preferences.setOutputFolder(outputFolder) }
    }

    // MARK: Mode & parameters (persisted, except manualTimes which is per-clip)
    var tab: ExtractionTab {
        didSet { Preferences.setTab(tab) }
    }
    var intervalUnit: IntervalUnit {
        didSet { Preferences.setIntervalUnit(intervalUnit) }
    }
    var intervalSeconds: Double {
        didSet { Preferences.setIntervalSeconds(intervalSeconds) }
    }
    var intervalFrames: Int {
        didSet { Preferences.setIntervalFrames(intervalFrames) }
    }
    var manualTimes: [CMTime] = []

    // MARK: Options (persisted)
    var overlay: OverlaySettings {
        didSet { Preferences.setOverlay(overlay) }
    }
    var numbering: NumberingSettings {
        didSet { Preferences.setNumbering(numbering) }
    }
    var exportFormat: ExportFormat {
        didSet { Preferences.setExportFormat(exportFormat) }
    }
    var exportQuality: Double {
        didSet { Preferences.setExportQuality(exportQuality) }
    }
    var exportLossless: Bool {
        didSet { Preferences.setExportLossless(exportLossless) }
    }

    // MARK: Status (transient)
    var progress: ExtractionPipeline.Progress?
    var statusMessage: String = ""
    var isRunning: Bool = false
    var lastError: String?

    @ObservationIgnored
    private var job: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Read persisted settings from UserDefaults. Properties have no
        // default values, so these assignments are first-time inits and
        // do NOT trigger didSet — no redundant write-back on launch.
        self.outputFolder    = Preferences.outputFolder()
        self.tab             = Preferences.tab()
        self.intervalUnit    = Preferences.intervalUnit()
        self.intervalSeconds = Preferences.intervalSeconds()
        self.intervalFrames  = Preferences.intervalFrames()
        self.overlay         = Preferences.overlay()
        self.numbering       = Preferences.numbering()
        self.exportFormat    = Preferences.exportFormat()
        self.exportQuality   = Preferences.exportQuality()
        self.exportLossless  = Preferences.exportLossless()
    }

    // MARK: - Computed

    var canExport: Bool {
        guard !isRunning, sourceURL != nil, outputFolder != nil else { return false }
        switch tab {
        case .interval:
            return intervalUnit == .seconds ? intervalSeconds > 0 : intervalFrames > 0
        case .manual:
            return !manualTimes.isEmpty
        }
    }

    var progressFraction: Double {
        guard let p = progress, p.total > 0 else { return 0 }
        return Double(p.completed) / Double(p.total)
    }

    var capturedCount: Int { manualTimes.count }

    /// Resolves the discrete UI fields (tab/intervalUnit/...) into the locked
    /// ExtractionMode used by both the export request and the frame-count
    /// preview. Returns nil when the current selection wouldn't produce any
    /// frames (zero interval, empty manual list, etc.).
    var currentMode: ExtractionMode? {
        switch tab {
        case .interval:
            switch intervalUnit {
            case .seconds:
                return intervalSeconds > 0 ? .interval(seconds: intervalSeconds) : nil
            case .frames:
                return intervalFrames > 0 ? .intervalFrames(count: intervalFrames) : nil
            }
        case .manual:
            return manualTimes.isEmpty ? nil : .timestamps(manualTimes)
        }
    }

    /// Number of frames the current settings would export. 0 when no clip is
    /// loaded or the mode is incomplete.
    var previewFrameCount: Int {
        guard let metadata, let mode = currentMode else { return 0 }
        return TimeListGenerator.count(for: mode, duration: metadata.duration, fps: metadata.nominalFrameRate)
    }

    // MARK: - Source loading

    func load(_ url: URL) async {
        statusMessage = "Loading…"
        lastError = nil
        do {
            let meta = try await VideoMetadataLoader.load(url)
            sourceURL = url
            metadata = meta
            player = AVPlayer(url: url)
            // New source → drop the previous manual-capture list; those
            // timestamps no longer make sense.
            manualTimes = []
            progress = nil
            statusMessage = ""
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    func setOutputFolder(_ url: URL) {
        outputFolder = url
    }

    /// Unload the current video. Cancels any in-flight extraction first so
    /// the user can drop a new clip without leaving a zombie task running.
    /// Output folder + options are intentionally preserved across clears.
    func clear() {
        job?.cancel()
        player?.pause()
        sourceURL = nil
        player = nil
        metadata = nil
        manualTimes = []
        progress = nil
        statusMessage = ""
        lastError = nil
        isRunning = false
    }

    // MARK: - Manual capture

    func captureCurrentFrame() {
        guard let player else { return }
        insertManualTime(player.currentTime())
    }

    func captureFrame(at time: CMTime) {
        insertManualTime(time)
    }

    // Sorted insert: the right-pane list is a destination preview, so its
    // row order must match what export writes to disk (which sorts ascending
    // in TimeListGenerator before feeding images(for:)).
    private func insertManualTime(_ time: CMTime) {
        guard time.isValid, time.isNumeric else { return }
        if manualTimes.contains(time) { return }
        let i = manualTimes.firstIndex {
            CMTimeGetSeconds($0) > CMTimeGetSeconds(time)
        } ?? manualTimes.count
        manualTimes.insert(time, at: i)
    }

    func removeManualTime(at index: Int) {
        guard manualTimes.indices.contains(index) else { return }
        manualTimes.remove(at: index)
    }

    // MARK: - Extraction lifecycle

    func startExtraction() {
        guard !isRunning, let request = buildRequest() else { return }

        // Defensive: cancel any prior job before launching (cancel() also
        // runs naturally when isRunning flips off, but a stale Task could
        // exist if the previous launch errored without resetting state).
        job?.cancel()

        progress = nil
        lastError = nil
        statusMessage = "Extracting…"
        isRunning = true

        job = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let urls = try await ExtractionPipeline.run(request) { update in
                    self.progress = update
                }
                self.statusMessage = "Done — wrote \(urls.count) \(request.format.rawValue)\(urls.count == 1 ? "" : "s")"
            } catch is CancellationError {
                self.statusMessage = "Cancelled — partial frames remain on disk"
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Failed: \(error.localizedDescription)"
            }
            self.isRunning = false
            self.job = nil
        }
    }

    func cancel() {
        job?.cancel()
    }

    // MARK: - Request builder

    private func buildRequest() -> ExtractionRequest? {
        guard let sourceURL, let outputFolder, let mode = currentMode else { return nil }
        return ExtractionRequest(
            sourceURL: sourceURL,
            outputFolder: outputFolder,
            mode: mode,
            overlay: overlay,
            numbering: numbering,
            format: exportFormat,
            quality: exportQuality,
            lossless: exportLossless
        )
    }
}
