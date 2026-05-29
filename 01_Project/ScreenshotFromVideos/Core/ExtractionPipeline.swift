//
//  ExtractionPipeline.swift
//  ScreenshotFromVideos
//
//  Glue: one cancellable Task<[URL], Error> that pulls N frames via
//  AVAssetImageGenerator.images(for:), optionally overlays a timestamp,
//  optionally numbers the filename, and writes each as PNG.
//
//  Per-frame failures inside the AsyncSequence are logged and skipped — they
//  don't abort the batch. Task cancellation triggers cancelAllCGImageGeneration
//  and leaves already-written PNGs on disk.
//

import Foundation
import AVFoundation
import CoreGraphics

enum ExtractionPipeline {

    struct Progress: Sendable {
        let completed: Int
        let total: Int
        let lastWritten: URL?
    }

    /// AVAssetImageGenerator is non-Sendable, but cancelAllCGImageGeneration()
    /// is thread-safe per Apple DTS — wrap only for the @Sendable onCancel hop.
    private struct CancellableGenerator: @unchecked Sendable {
        let raw: AVAssetImageGenerator
    }

    static func run(
        _ request: ExtractionRequest,
        onProgress: @escaping @MainActor (Progress) -> Void
    ) async throws -> [URL] {
        // 1. Metadata — also surfaces "no video track" as a typed error early.
        let metadata = try await VideoMetadataLoader.load(request.sourceURL)

        // 2. Resolve the requested mode to a sorted [CMTime].
        let times = TimeListGenerator.times(
            for: request.mode,
            duration: metadata.duration,
            fps: metadata.nominalFrameRate
        )
        guard !times.isEmpty else { return [] }

        // 3. Build the generator.
        let asset = AVURLAsset(url: request.sourceURL)
        let generator = FrameExtractor.makeGenerator(for: asset, tolerance: request.tolerance)
        let cancelBox = CancellableGenerator(raw: generator)

        let originalName = request.sourceURL.deletingPathExtension().lastPathComponent
        let total = times.count

        // 4. Consume images(for:) with cooperative cancellation.
        return try await withTaskCancellationHandler {
            var written: [URL] = []

            for try await result in generator.images(for: times) {
                try Task.checkCancellation()

                switch result {
                case .success(requestedTime: let requested, image: let image, actualTime: _):
                    let final: CGImage
                    if request.overlay.enabled {
                        final = ImageExportService.applyTextOverlay(
                            image,
                            text: TimestampFormatter.string(from: requested),
                            position: request.overlay.position,
                            fontSize: request.overlay.fontSize
                        )
                    } else {
                        final = image
                    }

                    let basename: String
                    if request.numbering.enabled {
                        basename = request.numbering.templater.filename(
                            originalName: originalName,
                            index: written.count
                        )
                    } else {
                        basename = TimestampFormatter.string(from: requested)
                            .replacingOccurrences(of: ":", with: "-")
                    }

                    let url = ImageExportService.nextAvailableURL(
                        folder: request.outputFolder,
                        basename: basename,
                        ext: request.format.fileExtension
                    )

                    // NSBitmapImageRep + CGImageDestination are Obj-C and may
                    // emit autoreleased buffers — wrap the encode step only.
                    var writeError: Error?
                    autoreleasepool {
                        do {
                            try ImageExportService.writeImage(
                                final,
                                to: url,
                                format: request.format,
                                quality: request.quality,
                                lossless: request.lossless
                            )
                        } catch {
                            writeError = error
                        }
                    }
                    if let writeError {
                        print("write failed for \(url.lastPathComponent): \(writeError)")
                        continue
                    }

                    written.append(url)
                    let progress = Progress(completed: written.count, total: total, lastWritten: url)
                    await onProgress(progress)

                case .failure(requestedTime: let requested, error: let error):
                    // Per-frame failure — log and continue, mirroring CropBatch's
                    // partial-batch tolerance.
                    print("frame failed at \(CMTimeGetSeconds(requested))s: \(error)")
                }
            }

            return written
        } onCancel: {
            cancelBox.raw.cancelAllCGImageGeneration()
        }
    }
}
