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

    /// Frame-accurate timecode "HH:MM:SS:FF" (non-drop). FF is the frame index
    /// within the current second. Used by the strip's transport bar so the user
    /// sees exactly which frame the playhead — and therefore Capture — will grab.
    static func timecode(from time: CMTime, fps: Float) -> String {
        let total = CMTimeGetSeconds(time)
        guard total.isFinite, total >= 0, fps > 0 else { return "00:00:00:00" }
        let f = Int(fps.rounded())
        let totalFrames = Int((total * Double(fps)).rounded())
        let frames = totalFrames % f
        let secs = (totalFrames / f) % 60
        let minutes = (totalFrames / (f * 60)) % 60
        let hours = totalFrames / (f * 3600)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }

    /// Absolute frame index from the start of the clip (0-based), rounded to the
    /// nearest frame so it matches the frame a sample-accurate seek lands on.
    static func frameNumber(from time: CMTime, fps: Float) -> Int {
        let total = CMTimeGetSeconds(time)
        guard total.isFinite, total >= 0, fps > 0 else { return 0 }
        return Int((total * Double(fps)).rounded())
    }
}
