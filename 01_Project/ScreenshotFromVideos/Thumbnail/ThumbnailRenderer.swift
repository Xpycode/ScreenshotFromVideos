//
//  ThumbnailRenderer.swift
//  ScreenshotFromVideos
//
//  Sibling of `ExtractionPipeline.swift` — strip-side variant.
//  No file I/O, no overlay, no filename templating. Yields CGImages
//  keyed by requestedTime for caching.
//

import Foundation
import AVFoundation
import CoreGraphics

struct ThumbnailRenderer {

    private struct CancellableGenerator: @unchecked Sendable {
        let raw: AVAssetImageGenerator
    }

    // AVAsset is read-only here and shared only to construct independent decoders.
    private struct RenderAsset: @unchecked Sendable {
        let raw: AVAsset
    }

    private let asset: AVAsset

    init(asset: AVAsset) {
        self.asset = asset
    }

    func render(
        times: [CMTime],
        targetWidth: Int,
        tolerance: CMTime
    ) -> AsyncStream<(CMTime, CGImage)> {
        let source = RenderAsset(raw: asset)
        return AsyncStream { continuation in
            let task = Task {
                var pending = times
                // One fresh-generator retry can recover an isolated decoder failure.
                // Each pass owns its cancellation handler; a cancelled old pass can
                // never cancel a newer generator.
                for _ in 0..<2 {
                    guard !Task.isCancelled, !pending.isEmpty else { break }
                    let generator = AVAssetImageGenerator(asset: source.raw)
                    generator.appliesPreferredTrackTransform = true
                    // 2× targetWidth for Retina; height 0 preserves aspect ratio.
                    generator.maximumSize = CGSize(width: CGFloat(targetWidth) * 2, height: 0)
                    generator.requestedTimeToleranceBefore = tolerance
                    generator.requestedTimeToleranceAfter = tolerance
                    let box = CancellableGenerator(raw: generator)
                    let passTimes = pending
                    var passCancelled = false

                    // Cancel the current decoder promptly when viewport demand ends.
                    await withTaskCancellationHandler {
                        do {
                            try Task.checkCancellation()
                            for try await result in box.raw.images(for: passTimes) {
                                try Task.checkCancellation()
                                switch result {
                                case .success(requestedTime: let requested, image: let image, actualTime: _):
                                    pending.removeAll { CMTimeCompare($0, requested) == 0 }
                                    continuation.yield((requested, image))
                                case .failure(requestedTime: let requested, error: let error):
                                    if error is CancellationError || (error as? AVError)?.code == .operationCancelled {
                                        passCancelled = true
                                    }
                                    print("strip frame failed at \(CMTimeGetSeconds(requested))s: \(error)")
                                }
                            }
                        } catch {
                            passCancelled = passCancelled || error is CancellationError
                                || (error as? AVError)?.code == .operationCancelled
                        }
                    } onCancel: {
                        box.raw.cancelAllCGImageGeneration()
                    }
                    if passCancelled || Task.isCancelled { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
