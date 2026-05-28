//
//  VideoMetadataLoader.swift
//  ScreenshotFromVideos
//
//  Distilled from VideoWallpaper/Core/VideoMetadataLoader.swift —
//  reduced to a single-URL async loader, no playlist coupling.
//

import Foundation
import AVFoundation

struct VideoMetadata: Equatable {
    let duration: Double  // seconds
    let width: Int
    let height: Int
    let nominalFrameRate: Float  // fps; falls back to 30 when track reports 0
}

enum VideoMetadataError: LocalizedError {
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "File has no video track"
        }
    }
}

enum VideoMetadataLoader {
    /// Loads duration and the transform-applied dimensions for a video URL.
    /// Rotated videos report their post-transform (displayed) size.
    static func load(_ url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw VideoMetadataError.noVideoTrack }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)

        let rawFPS = try await videoTrack.load(.nominalFrameRate)
        let fps: Float = rawFPS > 0 ? rawFPS : 30

        return VideoMetadata(
            duration: durationSeconds.isNaN ? 0 : durationSeconds,
            width: Int(abs(transformed.width)),
            height: Int(abs(transformed.height)),
            nominalFrameRate: fps
        )
    }
}
