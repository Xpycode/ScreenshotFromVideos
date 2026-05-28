//
//  FrameExtractor.swift
//  ScreenshotFromVideos
//
//  Distilled from VideoWallpaper/Core/ThumbnailCache.swift —
//  just the async AVAssetImageGenerator call, no NSCache/dedup.
//

import Foundation
import AVFoundation
import CoreGraphics

enum FrameExtractor {
    /// Pulls a single frame at `time` from `asset`. `appliesPreferredTrackTransform`
    /// is on, so rotated source videos come out upright.
    ///
    /// Tolerance defaults to zero on both sides (exact seek). Loosen if exact
    /// seeking is too slow on a given file.
    static func generate(
        from asset: AVURLAsset,
        at time: CMTime,
        toleranceBefore: CMTime = .zero,
        toleranceAfter: CMTime = .zero
    ) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = toleranceBefore
        generator.requestedTimeToleranceAfter = toleranceAfter

        let (cgImage, _) = try await generator.image(at: time)
        return cgImage
    }

    /// Factory used by the batch pipeline. The actual `for await` over
    /// `images(for:)` lives in `ExtractionPipeline` so cancellation handling
    /// stays in one place.
    static func makeGenerator(
        for asset: AVURLAsset,
        tolerance: CMTime = .zero
    ) -> AVAssetImageGenerator {
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = tolerance
        g.requestedTimeToleranceAfter = tolerance
        return g
    }
}
