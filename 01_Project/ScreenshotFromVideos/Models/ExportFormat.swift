//
//  ExportFormat.swift
//  ScreenshotFromVideos
//
//  Image output format for extracted frames. PNG/JPG/HEIC only.
//  Lifted shape from CropBatch/Models/ExportSettings.swift (TIFF + WebP
//  dropped — WebP has no ImageIO write support on macOS through 26.5;
//  see docs/decisions.md / POLISH_PLAN_post_phase5.md).
//

import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png  = "PNG"
    case jpeg = "JPG"
    case heic = "HEIC"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }

    /// Hardcoded — `UTType.jpeg.preferredFilenameExtension` returns "jpeg" but
    /// macOS/Finder convention is "jpg".
    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    var supportsCompression: Bool {
        switch self {
        case .jpeg, .heic: return true
        case .png:         return false
        }
    }
}
