//
//  ImageExportService.swift
//  ScreenshotFromVideos
//
//  Distilled from CropBatch/Services/ImageCropService.swift —
//  kept only the PNG writer and text overlay, since this app neither crops
//  nor resizes. Per project decision, the text overlay accepts a
//  pre-formatted string instead of going through CropBatch's
//  TextWatermarkVariable token resolver.
//

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageExportError: LocalizedError {
    case failedToCreateDestination
    case failedToWriteImage

    var errorDescription: String? {
        switch self {
        case .failedToCreateDestination: return "Failed to create output file"
        case .failedToWriteImage: return "Failed to write image"
        }
    }
}

enum OverlayPosition: String, CaseIterable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

enum ImageExportService {

    /// Returns a URL inside `folder` for `basename.ext`. If that file already
    /// exists, appends `_1`, `_2`, … until the name is free. Lifted from
    /// CropBatch `ExportSettings.appendNumericSuffix`.
    static func nextAvailableURL(folder: URL, basename: String, ext: String) -> URL {
        let fm = FileManager.default
        let candidate = folder.appendingPathComponent("\(basename).\(ext)")
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        var n = 1
        while true {
            let next = folder.appendingPathComponent("\(basename)_\(n).\(ext)")
            if !fm.fileExists(atPath: next.path) { return next }
            n += 1
        }
    }

    /// Writes a CGImage to disk in the requested format. `quality` is honored
    /// only for `format.supportsCompression` (JPEG, HEIC); ignored for PNG.
    static func writeImage(_ cgImage: CGImage, to url: URL, format: ExportFormat, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else { throw ImageExportError.failedToCreateDestination }

        var options: [CFString: Any] = [:]
        if format.supportsCompression {
            options[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
        }
        CGImageDestinationAddImage(destination, cgImage, options.isEmpty ? nil : options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageExportError.failedToWriteImage
        }
    }

    /// Burns `text` into a copy of `cgImage` at `position`. Uses a white fill
    /// with a black stroke so the text reads on any background.
    static func applyTextOverlay(
        _ cgImage: CGImage,
        text: String,
        position: OverlayPosition = .bottomLeft,
        fontSize: CGFloat = 36
    ) -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        let imageSize = CGSize(width: width, height: height)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return cgImage }

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return cgImage }
        let cgContext = ctx.cgContext

        // CGContext is bottom-up; draw(cgImage:in:) already orients the image
        // correctly. No manual flip needed.
        cgContext.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))

        let savedContext = NSGraphicsContext.current
        NSGraphicsContext.current = ctx

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -3.0
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        let padding: CGFloat = fontSize * 0.4

        // Bottom-up coordinates: low Y = bottom of image.
        let origin: CGPoint
        switch position {
        case .bottomLeft:
            origin = CGPoint(x: padding, y: padding)
        case .bottomRight:
            origin = CGPoint(x: imageSize.width - textSize.width - padding, y: padding)
        case .topLeft:
            origin = CGPoint(x: padding, y: imageSize.height - textSize.height - padding)
        case .topRight:
            origin = CGPoint(x: imageSize.width - textSize.width - padding,
                             y: imageSize.height - textSize.height - padding)
        }

        attrString.draw(in: CGRect(origin: origin, size: textSize))

        NSGraphicsContext.current = savedContext

        return rep.cgImage ?? cgImage
    }
}
