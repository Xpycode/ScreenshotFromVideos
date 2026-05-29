//
//  Preferences.swift
//  ScreenshotFromVideos
//
//  UserDefaults-backed persistence for the user-facing settings on
//  ExtractionViewModel. Reads on init; writes from the model's didSet.
//  Per-clip state (sourceURL, player, metadata, manualTimes) and transient
//  status (progress, isRunning, lastError) are intentionally NOT persisted.
//
//  Output folder is stored as a path string. The app is non-sandboxed so
//  no security-scoped bookmark is needed; on read we validate the path
//  still exists and drop the value if it doesn't (folder was deleted /
//  external disk unmounted).
//

import Foundation
import CoreGraphics

enum Preferences {

    // UserDefaults is documented thread-safe (atomic writes) but Foundation
    // doesn't conform it to Sendable, so Swift 6 strict mode flags the cache.
    // The escape hatch is appropriate here — no shared mutable state of our
    // own, just delegating to a thread-safe Apple type.
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    private enum Key {
        static let outputFolderPath  = "outputFolderPath"
        static let tab               = "tab"
        static let intervalUnit      = "intervalUnit"
        static let intervalSeconds   = "intervalSeconds"
        static let intervalFrames    = "intervalFrames"
        static let overlayEnabled    = "overlay.enabled"
        static let overlayPosition   = "overlay.position"
        static let overlayFontSize   = "overlay.fontSize"
        static let numberingEnabled  = "numbering.enabled"
        static let numberingPattern  = "numbering.pattern"
        static let numberingStart    = "numbering.startIndex"
        static let numberingPadding  = "numbering.zeroPadding"
        static let exportFormat      = "exportFormat"
        static let exportQuality     = "exportQuality"
        static let exportLossless    = "exportLossless"
    }

    // MARK: - Reads (used in ExtractionViewModel.init)

    static func outputFolder() -> URL? {
        guard let path = defaults.string(forKey: Key.outputFolderPath) else { return nil }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    static func tab() -> ExtractionTab {
        ExtractionTab(rawValue: defaults.string(forKey: Key.tab) ?? "") ?? .interval
    }

    static func intervalUnit() -> IntervalUnit {
        IntervalUnit(rawValue: defaults.string(forKey: Key.intervalUnit) ?? "") ?? .seconds
    }

    static func intervalSeconds() -> Double {
        let v = defaults.double(forKey: Key.intervalSeconds)
        return v > 0 ? v : 2
    }

    static func intervalFrames() -> Int {
        let v = defaults.integer(forKey: Key.intervalFrames)
        return v > 0 ? v : 60
    }

    static func overlay() -> OverlaySettings {
        var s = OverlaySettings()
        if defaults.object(forKey: Key.overlayEnabled) != nil {
            s.enabled = defaults.bool(forKey: Key.overlayEnabled)
        }
        if let raw = defaults.string(forKey: Key.overlayPosition),
           let pos = OverlayPosition(rawValue: raw) {
            s.position = pos
        }
        let fontSize = defaults.double(forKey: Key.overlayFontSize)
        if fontSize > 0 { s.fontSize = CGFloat(fontSize) }
        return s
    }

    static func numbering() -> NumberingSettings {
        var s = NumberingSettings()
        if defaults.object(forKey: Key.numberingEnabled) != nil {
            s.enabled = defaults.bool(forKey: Key.numberingEnabled)
        }
        if let pattern = defaults.string(forKey: Key.numberingPattern), !pattern.isEmpty {
            s.templater.pattern = pattern
        }
        let startIndex = defaults.integer(forKey: Key.numberingStart)
        if startIndex > 0 { s.templater.startIndex = startIndex }
        let padding = defaults.integer(forKey: Key.numberingPadding)
        if padding > 0 { s.templater.zeroPadding = padding }
        return s
    }

    static func exportFormat() -> ExportFormat {
        ExportFormat(rawValue: defaults.string(forKey: Key.exportFormat) ?? "") ?? .png
    }

    static func exportQuality() -> Double {
        // 0.0 is a valid (worst-quality) value but our slider clamps to 0.1;
        // treat missing/zero as the default 0.85 since the default was never written.
        let v = defaults.double(forKey: Key.exportQuality)
        return v > 0 ? v : 0.85
    }

    static func exportLossless() -> Bool {
        // Missing key → false, which is the right default (lossy WebP).
        defaults.bool(forKey: Key.exportLossless)
    }

    // MARK: - Writes (used in ExtractionViewModel didSet handlers)

    static func setOutputFolder(_ url: URL?) {
        defaults.set(url?.path, forKey: Key.outputFolderPath)
    }

    static func setTab(_ t: ExtractionTab) {
        defaults.set(t.rawValue, forKey: Key.tab)
    }

    static func setIntervalUnit(_ u: IntervalUnit) {
        defaults.set(u.rawValue, forKey: Key.intervalUnit)
    }

    static func setIntervalSeconds(_ v: Double) {
        defaults.set(v, forKey: Key.intervalSeconds)
    }

    static func setIntervalFrames(_ v: Int) {
        defaults.set(v, forKey: Key.intervalFrames)
    }

    static func setOverlay(_ o: OverlaySettings) {
        defaults.set(o.enabled, forKey: Key.overlayEnabled)
        defaults.set(o.position.rawValue, forKey: Key.overlayPosition)
        defaults.set(Double(o.fontSize), forKey: Key.overlayFontSize)
    }

    static func setNumbering(_ n: NumberingSettings) {
        defaults.set(n.enabled, forKey: Key.numberingEnabled)
        defaults.set(n.templater.pattern, forKey: Key.numberingPattern)
        defaults.set(n.templater.startIndex, forKey: Key.numberingStart)
        defaults.set(n.templater.zeroPadding, forKey: Key.numberingPadding)
    }

    static func setExportFormat(_ f: ExportFormat) {
        defaults.set(f.rawValue, forKey: Key.exportFormat)
    }

    static func setExportQuality(_ q: Double) {
        defaults.set(q, forKey: Key.exportQuality)
    }

    static func setExportLossless(_ v: Bool) {
        defaults.set(v, forKey: Key.exportLossless)
    }
}
