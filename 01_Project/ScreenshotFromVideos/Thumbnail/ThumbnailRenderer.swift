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

    private let asset: AVAsset

    init(asset: AVAsset) {
        self.asset = asset
    }

    func render(
        times: [CMTime],
        targetWidth: Int,
        tolerance: CMTime
    ) -> AsyncStream<(CMTime, CGImage)> {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // 2× targetWidth for Retina; height 0 lets AVF preserve aspect ratio.
        generator.maximumSize = CGSize(width: CGFloat(targetWidth) * 2, height: 0)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let box = CancellableGenerator(raw: generator)

        return AsyncStream { continuation in
            let task = Task {
                // `cancelAllCGImageGeneration` drops in-flight decodes immediately;
                // without it, `images(for:)` keeps churning past `task.cancel()`,
                // and stacked-up tasks during fast pinch saturate VTDecoderXPCService.
                await withTaskCancellationHandler {
                    do {
                        for try await result in box.raw.images(for: times) {
                            try Task.checkCancellation()
                            switch result {
                            case .success(requestedTime: let requested, image: let image, actualTime: _):
                                continuation.yield((requested, image))
                            case .failure(requestedTime: let requested, error: let error):
                                print("strip frame failed at \(CMTimeGetSeconds(requested))s: \(error)")
                            }
                        }
                    } catch {
                        // Cancellation or upstream failure — close the stream.
                    }
                    continuation.finish()
                } onCancel: {
                    box.raw.cancelAllCGImageGeneration()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
