//
//  ThumbnailCellView.swift
//  ScreenshotFromVideos
//
//  One cell in the thumbnail strip. Reads CGImage from ThumbnailCache by ThumbKey,
//  falls back to a placeholder. cacheVersion forces re-eval on cache writes.
//

import SwiftUI
import CoreMedia
import AppKit

struct ThumbnailCellView: View, Equatable {
    let time: CMTime
    let widthBucket: Int
    let displaySize: CGSize
    let cache: ThumbnailCache
    let cacheVersion: Int
    let playerIdentity: ObjectIdentifier?
    let captureOwnerIdentity: ObjectIdentifier
    let onTap: (CMTime) -> Void
    let onCmdTap: (CMTime) -> Void
    let manualPinned: Bool

    // Holds the last successfully-displayed exact-match image so the cell can
    // bridge zoom transitions (new bucket OR new density timestamps) without
    // flashing to a placeholder. Cell-scoped; evaporates on lazy unload.
    @State private var lastImage: CGImage?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.widthBucket == rhs.widthBucket && lhs.time == rhs.time &&
        lhs.displaySize == rhs.displaySize && lhs.cache === rhs.cache &&
        lhs.cacheVersion == rhs.cacheVersion && lhs.manualPinned == rhs.manualPinned &&
        lhs.playerIdentity == rhs.playerIdentity && lhs.captureOwnerIdentity == rhs.captureOwnerIdentity
    }

    var body: some View {
        Group {
            if let img = bestImage() {
                Image(decorative: img, scale: 2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .clipped()
            } else {
                // Distinct from the strip's secondaryBackground (0.15) so empty
                // cells read as "loading" rather than "void" while the renderer
                // catches up. The 1pt cell-spacing gap then shows through as
                // a lighter divider, giving the grid a visible structure.
                Color(white: 0.07)
                    .frame(width: displaySize.width, height: displaySize.height)
            }
        }
        .overlay(alignment: .topTrailing) {
            if manualPinned {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .padding(3)
            }
        }
        .onAppear { syncLastImage() }
        .onChange(of: cacheVersion) { _, _ in syncLastImage() }
        .onChange(of: cellIdentity) { _, _ in syncLastImage() }
        // contentShape pins the hit region to the full cell frame — SwiftUI
        // hit-tests by layout shape, but the conditional Group can collapse
        // its implicit hit region during the placeholder branch.
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onCmdTap(time)
            } else {
                onTap(time)
            }
        }
    }

    private var timeMillis: Int64 {
        Int64((CMTimeGetSeconds(time) * 1000).rounded())
    }

    private var exactKey: ThumbKey {
        ThumbKey(timeMillis: timeMillis, widthBucket: widthBucket)
    }

    private var cellIdentity: ThumbKey { exactKey }

    private func bestImage() -> CGImage? {
        if let img = cache.image(for: exactKey) { return img }
        // Same time at other buckets — SwiftUI's scaledToFill handles the resize.
        // Wider first: scaling down is visually free.
        for bucket in [240, 120, 60] where bucket != widthBucket {
            if let img = cache.image(for: ThumbKey(timeMillis: timeMillis, widthBucket: bucket)) {
                return img
            }
        }
        // Last resort: the image we showed before the cell rebound to new (time, bucket).
        // Almost certainly stale, but visually adjacent — beats a grey placeholder.
        return lastImage
    }

    private func syncLastImage() {
        if let exact = cache.image(for: exactKey) {
            lastImage = exact
        }
    }
}
