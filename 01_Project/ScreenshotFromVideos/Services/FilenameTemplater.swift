//
//  FilenameTemplater.swift
//  ScreenshotFromVideos
//
//  Distilled from CropBatch/Models/ExportSettings.swift (RenameSettings.processPattern).
//

import Foundation

struct FilenameTemplater: Equatable {
    var pattern: String = "{name}_{counter}"
    var startIndex: Int = 1
    var zeroPadding: Int = 4

    /// Available tokens for `pattern`:
    /// `{name}` — source video filename (no extension)
    /// `{counter}` — zero-padded sequential counter (0001, 0002, …)
    /// `{index}` — un-padded 1-based index
    /// `{date}` — YYYY-MM-DD at the moment of formatting
    /// `{time}` — HH-MM-SS at the moment of formatting
    func filename(originalName: String, index: Int) -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: now)
        formatter.dateFormat = "HH-mm-ss"
        let timeString = formatter.string(from: now)

        let paddedCounter = String(format: "%0\(zeroPadding)d", startIndex + index)

        return pattern
            .replacingOccurrences(of: "{name}", with: originalName)
            .replacingOccurrences(of: "{counter}", with: paddedCounter)
            .replacingOccurrences(of: "{index}", with: "\(index + 1)")
            .replacingOccurrences(of: "{date}", with: dateString)
            .replacingOccurrences(of: "{time}", with: timeString)
    }
}
