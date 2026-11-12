//
//  ExtractionPipeline.swift
//  ScreenshotFromVideos
//
//  Glue: one cancellable Task<[URL], Error> that pulls N frames via
//  AVAssetImageGenerator.images(for:), optionally overlays a timestamp,
//  optionally numbers the filename, and writes each as PNG.
//
//  The output folder is checked up front (missing / not a folder / not
//  writable → `ExtractionError.outputFolderUnavailable`, before any decode).
//  Per-frame failures inside the AsyncSequence are counted and skipped — they
//  don't abort the batch — and reported back in `Outcome` so the UI never
//  claims a clean run that wasn't. Task cancellation triggers
//  cancelAllCGImageGeneration and leaves already-written files on disk.
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

    /// What a finished (non-cancelled) run produced. `failedCount` covers both
    /// decode and write failures; `firstFailure` is the first one's message.
    struct Outcome: Sendable {
        let written: [URL]
        let total: Int
        let failedCount: Int
        let firstFailure: String?
    }

    enum ExtractionError: LocalizedError {
        case outputFolderUnavailable(name: String)

        var errorDescription: String? {
            switch self {
            case .outputFolderUnavailable(let name):
                return "Output folder \u{201C}\(name)\u{201D} is missing or not writable — choose another folder."
            }
        }
    }

    /// Fails fast when the persisted output folder was deleted, unmounted or
    /// made read-only since it was picked — otherwise every write would fail.
    static func validateOutputFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fm.isWritableFile(atPath: folder.path) else {
            throw ExtractionError.outputFolderUnavailable(name: folder.lastPathComponent)
        }
    }

    /// AVAssetImageGenerator is non-Sendable, but cancelAllCGImageGeneration()
    /// is thread-safe per Apple DTS — wrap only for the @Sendable onCancel hop.
    private struct CancellableGenerator: @unchecked Sendable {
        let raw: AVAssetImageGenerator
    }

    static func run(
        _ request: ExtractionRequest,
        onProgress: @escaping @MainActor (Progress) -> Void
    ) async throws -> Outcome {
        // 0. Output folder — before spending any time decoding.
        try validateOutputFolder(request.outputFolder)

        // 1. Metadata — also surfaces "no video track" as a typed error early.
        let metadata = try await VideoMetadataLoader.load(request.sourceURL)

        // 2. Resolve the requested mode to a sorted [CMTime].
        let times = TimeListGenerator.times(
            for: request.mode,
            duration: metadata.duration,
            fps: metadata.nominalFrameRate
        )
        guard !times.isEmpty else {
            return Outcome(written: [], total: 0, failedCount: 0, firstFailure: nil)
        }

        // 3. Build the generator.
        let asset = AVURLAsset(url: request.sourceURL)
        let generator = FrameExtractor.makeGenerator(for: asset, tolerance: request.tolerance)
        let cancelBox = CancellableGenerator(raw: generator)

        let originalName = request.sourceURL.deletingPathExtension().lastPathComponent
        let total = times.count

        // 4. Consume images(for:) with cooperative cancellation.
        return try await withTaskCancellationHandler {
            var written: [URL] = []
            var failedCount = 0
            var firstFailure: String?

            func recordFailure(_ error: Error) {
                failedCount += 1
                if firstFailure == nil { firstFailure = error.localizedDescription }
            }

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
                            // Fraction-of-height → absolute pixels for this frame.
                            fontSize: CGFloat(image.height) * CGFloat(request.overlay.fontPercent)
                        )
                    } else {
                        final = image
                    }

                    let basename: String
                    if request.numbering.enabled {
                        basename = request.numbering.templater.filename(
                            originalName: originalName,
                            index: written.count,
                            time: requested,
                            fps: metadata.nominalFrameRate
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
                        recordFailure(writeError)
                        await onProgress(Progress(completed: written.count + failedCount, total: total, lastWritten: written.last))
                        continue
                    }

                    written.append(url)
                    let progress = Progress(completed: written.count + failedCount, total: total, lastWritten: url)
                    await onProgress(progress)

                case .failure(requestedTime: let requested, error: let error):
                    // Per-frame failure — count and continue, mirroring CropBatch's
                    // partial-batch tolerance; reported in the Outcome.
                    print("frame failed at \(CMTimeGetSeconds(requested))s: \(error)")
                    recordFailure(error)
                    await onProgress(Progress(completed: written.count + failedCount, total: total, lastWritten: written.last))
                }
            }

            return Outcome(written: written, total: total, failedCount: failedCount, firstFailure: firstFailure)
        } onCancel: {
            cancelBox.raw.cancelAllCGImageGeneration()
        }
    }
}
