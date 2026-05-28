//
//  TimeListGenerator.swift
//  ScreenshotFromVideos
//
//  Resolves an ExtractionMode + clip duration to a sorted [CMTime] that
//  AVAssetImageGenerator.images(for:) can consume.
//

import Foundation
import CoreMedia

enum TimeListGenerator {
    /// Standard timescale for inter-frame timing across the pipeline.
    static let timescale: CMTimeScale = 600

    static func times(for mode: ExtractionMode, duration: Double, fps: Float = 30) -> [CMTime] {
        guard duration > 0 else { return [] }

        switch mode {
        case .interval(let seconds):
            guard seconds > 0 else { return [] }
            return stride(from: 0.0, through: duration, by: seconds)
                .map { CMTime(seconds: $0, preferredTimescale: timescale) }

        case .intervalFrames(let count):
            guard count > 0, fps > 0 else { return [] }
            let step = Double(count) / Double(fps)
            return stride(from: 0.0, through: duration, by: step)
                .map { CMTime(seconds: $0, preferredTimescale: timescale) }

        case .timestamps(let list):
            let clamped = list
                .map { CMTimeGetSeconds($0) }
                .filter { $0.isFinite && $0 >= 0 && $0 <= duration }
                .sorted()

            // Dedupe within 1ms.
            var result: [Double] = []
            for s in clamped {
                if let last = result.last, abs(s - last) < 0.001 { continue }
                result.append(s)
            }
            return result.map { CMTime(seconds: $0, preferredTimescale: timescale) }
        }
    }
}
