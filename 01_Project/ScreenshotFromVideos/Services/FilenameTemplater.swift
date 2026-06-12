//
//  FilenameTemplater.swift
//  ScreenshotFromVideos
//
//  Distilled from CropBatch/Models/ExportSettings.swift (RenameSettings.processPattern).
//

import Foundation
import CoreMedia

struct FilenameTemplater: Equatable {
    var pattern: String = "{name}_{timecode}"
    var startIndex: Int = 1
    var zeroPadding: Int = 4

    /// Available tokens for `pattern`:
    /// `{name}` — source video filename (no extension)
    /// `{counter}` — zero-padded sequential counter (0001, 0002, …)
    /// `{index}` — un-padded 1-based index
    /// `{timecode}` — source-clip frame timecode, filename-safe (00-01-23-15)
    /// `{frame}` — absolute source frame number from the start of the clip
    /// `{seconds}` — source-clip timestamp, filename-safe (00-01-23-456)
    /// `{date}` — YYYY-MM-DD at the moment of formatting
    /// `{time}` — HH-MM-SS at the moment of formatting
    ///
    /// `time`/`fps` describe the source frame this export came from, so the
    /// time-based tokens read identically to the strip's transport bar.
    func filename(originalName: String, index: Int, time: CMTime, fps: Float) -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: now)
        formatter.dateFormat = "HH-mm-ss"
        let timeString = formatter.string(from: now)

        let paddedCounter = String(format: "%0\(zeroPadding)d", startIndex + index)

        // ─── YOUR CONTRIBUTION ───────────────────────────────────────────────
        // Build the three source-time token strings. These must be filename-safe
        // (no ":" — macOS shows it as "/" in Finder and it's illegal on some
        // volumes). Helpers already available (see TimestampFormatter.swift):
        //
        //   TimestampFormatter.timecode(from: time, fps: fps) -> "HH:MM:SS:FF"
        //       frame-accurate; has colons that need sanitizing.
        //   TimestampFormatter.frameNumber(from: time, fps: fps) -> Int
        //       absolute 0-based frame index from clip start.
        //   TimestampFormatter.string(from: time) -> "MM:SS.mmm" / "HH:MM:SS.mmm"
        //       millisecond timestamp; has ":" and "." to sanitize.
        //
        // Decisions to make:
        //   • Sanitization: which characters → "-"? (at least ":"; for {seconds}
        //     also "."). `.replacingOccurrences(of:with:)` chains, or a
        //     CharacterSet, are both fine.
        //   • {frame} width: raw "2703", or zero-padded to `zeroPadding` so frames
        //     sort lexically? (Use `String(format: "%0\(zeroPadding)d", n)` to pad.)
        let timecodeString = TimestampFormatter.timecode(from: time, fps: fps)
            .replacingOccurrences(of: ":", with: "-")
        let frameNumber = TimestampFormatter.frameNumber(from: time, fps: fps)
        let frameString = String(format: "%0\(zeroPadding)d", frameNumber)
        let secondsString = TimestampFormatter.string(from: time)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        // ─────────────────────────────────────────────────────────────────────

        return pattern
            .replacingOccurrences(of: "{name}", with: originalName)
            .replacingOccurrences(of: "{counter}", with: paddedCounter)
            .replacingOccurrences(of: "{index}", with: "\(index + 1)")
            .replacingOccurrences(of: "{timecode}", with: timecodeString)
            .replacingOccurrences(of: "{frame}", with: frameString)
            .replacingOccurrences(of: "{seconds}", with: secondsString)
            .replacingOccurrences(of: "{date}", with: dateString)
            .replacingOccurrences(of: "{time}", with: timeString)
    }
}
