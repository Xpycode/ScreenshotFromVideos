//
//  WebPEncoder.swift
//  ScreenshotFromVideos
//
//  WebP write path. ImageIO on macOS 26.5 has no WebP encoder, so this routes
//  through SDWebImageWebPCoder 0.15.0 (SPM). @preconcurrency on both modules
//  because the ObjC headers are not Sendable-audited and SFV builds under
//  SWIFT_STRICT_CONCURRENCY=complete.
//
//  Wave A: stub body — type exists so the rest of the pipeline can be wired
//  in Wave B without breaking the build. Full encode (sRGB CGContext
//  conversion, options dict with method=6, optional lossless) lands in Wave B.
//

import CoreGraphics
import Foundation
@preconcurrency import SDWebImage
@preconcurrency import SDWebImageWebPCoder

enum WebPEncoder {
    static func encode(_ cgImage: CGImage, to url: URL, quality: Double, lossless: Bool) throws {
        throw ImageExportError.failedToWriteImage
    }
}
