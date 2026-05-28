//
//  TimestampFormatter.swift
//  ScreenshotFromVideos
//
//  Formats CMTime as a human-readable timestamp for the overlay.
//

import Foundation
import CoreMedia

enum TimestampFormatter {
    /// Formats as "MM:SS.mmm" — or "HH:MM:SS.mmm" when the clip is ≥ 1 hour.
    static func string(from time: CMTime) -> String {
        let total = CMTimeGetSeconds(time)
        guard total.isFinite, total >= 0 else { return "00:00.000" }

        let whole = Int(total)
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let seconds = whole % 60
        let millis = Int((total - floor(total)) * 1000)

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
        }
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }
}
