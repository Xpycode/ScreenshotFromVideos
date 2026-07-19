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

@MainActor
final class ThumbnailRenderer {

    // `AVAssetImageGenerator` is not Sendable. `withTaskCancellationHandler`'s
    // `onCancel` parameter is declared `@Sendable () -> Void`, and that
    // requirement propagates to every closure nested inside it — including
    // the `Task { @MainActor in ... }` hop below — even though that inner
    // closure only ever runs on the main actor. Boxing the generator as
    // `@unchecked Sendable` is what lets it cross into that closure at all;
    // this was verified against the strict-concurrency compiler, not assumed.
    private struct CancellableGenerator: @unchecked Sendable {
        let raw: AVAssetImageGenerator
    }

    private let asset: AVAsset
    private var generator: AVAssetImageGenerator?
    private var generatorWidth: Int?

    // One per `render(...)` call, cleared when the next batch starts. Lets a
    // batch's cancellation handler tell "I am still the newest batch" apart
    // from "a newer batch has already taken over the shared generator" — see
    // the guard in `onCancel` below. This is a token object rather than an
    // `Int` on the renderer so the cancel closure never has to capture `self`:
    // that closure is `@Sendable` and off-actor, and sending a main-actor
    // `self` into it is a strict-concurrency error.
    private final class BatchToken: @unchecked Sendable {
        // Written only on the main actor; read only after a main-actor hop.
        var isCurrent = true
    }

    private var currentToken: BatchToken?

    init(asset: AVAsset) {
        self.asset = asset
    }

    func render(
        times: [CMTime],
        targetWidth: Int,
        tolerance: CMTime
    ) -> AsyncStream<(CMTime, CGImage)> {
        currentToken?.isCurrent = false
        let token = BatchToken()
        currentToken = token

        let generator: AVAssetImageGenerator
        if let existing = self.generator, generatorWidth == targetWidth {
            generator = existing
        } else {
            // `maximumSize` is fixed at creation and cannot be changed mid-flight,
            // so a width-bucket change forces a fresh generator.
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // 2× targetWidth for Retina; height 0 lets AVF preserve aspect ratio.
            generator.maximumSize = CGSize(width: CGFloat(targetWidth) * 2, height: 0)
            self.generator = generator
            self.generatorWidth = targetWidth
        }
        // Safe to mutate tolerance on a reused generator: StripModel.scheduleRender()
        // synchronously cancels the prior consuming task before starting this one,
        // and tolerance is only consulted for requests issued from here on.
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
                    // The generator is now shared across batches, so an unconditional
                    // cancelAllCGImageGeneration() here would kill a newer batch's
                    // in-flight decodes if this handler fires after that batch has
                    // already started (a real race: onCancel can fire well after
                    // task.cancel() is requested). Hop to the main actor — this
                    // closure runs off-actor — and cancel only if this batch is
                    // still the current one.
                    //
                    // The pinch/scroll path that caused the 2026-05-28 decoder
                    // saturation still cancels as before: scheduleRender() cancels
                    // the prior task synchronously, then debounces 80 ms before
                    // calling render() again, so the stale batch's hop lands while
                    // its own token is still current.
                    Task { @MainActor in
                        guard token.isCurrent else { return }
                        box.raw.cancelAllCGImageGeneration()
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
