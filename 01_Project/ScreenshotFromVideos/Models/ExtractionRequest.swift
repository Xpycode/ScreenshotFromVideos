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
    var fontSize: CGFloat = 36
}

struct NumberingSettings {
    var enabled: Bool = true
    var templater: FilenameTemplater = .init()
}
