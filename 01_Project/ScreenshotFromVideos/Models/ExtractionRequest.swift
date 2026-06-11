//
//  ExtractionRequest.swift
//  ScreenshotFromVideos
//
//  Value types describing one extraction job. No logic.
//

import Foundation
import CoreMedia
import CoreGraphics

struct ExtractionRequest {
    var sourceURL: URL
    var outputFolder: URL
    var mode: ExtractionMode
    var overlay: OverlaySettings
    var numbering: NumberingSettings
    var format: ExportFormat = .png
    var quality: Double = 0.85
    var lossless: Bool = false  // WebP only; ignored by PNG/JPG/HEIC
    var tolerance: CMTime = .zero
}

enum ExtractionMode {
    case interval(seconds: Double)
    case intervalFrames(count: Int)
    case timestamps([CMTime])
}

struct OverlaySettings {
    var enabled: Bool = false
    var position: OverlayPosition = .bottomLeft
    /// Burn-in font height as a fraction of the frame height, so the timestamp
    /// stays legible at any resolution (an absolute point size is invisibly
    /// small on a 4K frame). Resolved to pixels at render time. Default 3.5%.
    var fontPercent: Double = 0.035
}

struct NumberingSettings {
    var enabled: Bool = true
    var templater: FilenameTemplater = .init()
}
