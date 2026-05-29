//
//  WebPEncoder.swift
//  ScreenshotFromVideos
//
//  WebP write path. ImageIO on macOS 26.5 has no WebP encoder, so this routes
//  through SDWebImageWebPCoder 0.15.0 (SPM). @preconcurrency on both modules
//  because the ObjC headers are not Sendable-audited and SFV builds under
//  SWIFT_STRICT_CONCURRENCY=complete.
//
//  AVAssetImageGenerator returns CGImages tagged with the video's color space
//  (Rec.709 for SDR, BT.2020 for HDR). libwebp writes pixels as-is, so we
//  convert to sRGB via a transient CGContext before handing off — matches what
//  CGImageDestination does implicitly for the PNG/JPG/HEIC paths. 0.15.0 then
//  embeds the resulting sRGB ICC profile so color-managed viewers stay correct.
//
//  method=6 is hardcoded per SDWebImageWebPCoder issue #116 (default method=4
//  is visibly worse than the cwebp CLI at the same quality). The 2–3× CPU cost
//  is fine for SFV's 30 s–2 min design target.
//

import AppKit
import CoreGraphics
import Foundation
@preconcurrency import SDWebImage
@preconcurrency import SDWebImageWebPCoder

enum WebPEncoder {
    /// Encodes `cgImage` as WebP at `url`. `quality` (0…1) maps to libwebp's
    /// 0–100; in lossless mode libwebp reuses it as encoding effort. Throws
    /// `ImageExportError.failedToWriteImage` on encode or write failure.
    static func encode(_ cgImage: CGImage, to url: URL, quality: Double, lossless: Bool) throws {
        let srgb = try srgbImage(from: cgImage)
        let nsImage = NSImage(cgImage: srgb, size: .zero)

        var options: [SDImageCoderOption: Any] = [
            .encodeCompressionQuality: NSNumber(value: max(0, min(1, quality))),
            .encodeWebPMethod: NSNumber(value: 6),
        ]
        if lossless {
            options[.encodeWebPLossless] = NSNumber(value: true)
        }

        guard let data = SDImageWebPCoder.shared.encodedData(
            with: nsImage,
            format: .webP,
            options: options
        ) else {
            throw ImageExportError.failedToWriteImage
        }

        try data.write(to: url)
    }

    /// Redraws `cgImage` into an sRGB-backed context and snapshots the result.
    private static func srgbImage(from cgImage: CGImage) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: cgImage.width,
                  height: cgImage.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGImageByteOrderInfo.order32Big.rawValue
              ) else {
            throw ImageExportError.failedToWriteImage
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard let converted = context.makeImage() else {
            throw ImageExportError.failedToWriteImage
        }
        return converted
    }
}
