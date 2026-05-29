//
//  ExportFormat.swift
//  ScreenshotFromVideos
//
//  Image output format for extracted frames. PNG/JPG/HEIC via ImageIO; WebP
//  added in the webp-support polish (uses SDWebImageWebPCoder, not ImageIO —
//  ImageIO has no WebP write support on macOS through 26.5). Lifted shape from
//  CropBatch/Models/ExportSettings.swift (TIFF dropped).
//

import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png  = "PNG"
    case jpeg = "JPG"
    case heic = "HEIC"
    case webp = "WebP"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .webp: return .webP  // kept for completeness; WebP write goes via WebPEncoder, not ImageIO
        }
    }

    /// Hardcoded — `UTType.jpeg.preferredFilenameExtension` returns "jpeg" but
    /// macOS/Finder convention is "jpg".
    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .webp: return "webp"
        }
    }

    var supportsCompression: Bool {
        switch self {
        case .jpeg, .heic, .webp: return true
        case .png:                return false
        }
    }

    /// WebP is the only format exposing a lossless toggle. Gates the UI control
    /// and the Quality↔Effort label flip in RightPaneView.
    var hasLosslessOption: Bool { self == .webp }
}
