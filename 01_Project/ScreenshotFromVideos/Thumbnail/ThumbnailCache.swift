//
//  ThumbnailCache.swift
//  ScreenshotFromVideos
//
//  Sundell-style NSCache wrapper for the thumbnail strip.
//  Value-type ThumbKey, CGImage payload, tiered RAM budget.
//

import Foundation
import CoreGraphics

struct ThumbKey: Hashable {
    let timeMillis: Int64
    let widthBucket: Int
}

private final class WrappedKey: NSObject {
    let key: ThumbKey
    init(_ key: ThumbKey) { self.key = key }
    override var hash: Int { key.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? WrappedKey)?.key == key
    }
}

private final class Entry {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

final class ThumbnailCache: @unchecked Sendable {
    // NSCache is documented thread-safe (Apple Foundation docs); the WrappedKey/Entry helpers are immutable.
    private let storage = NSCache<WrappedKey, Entry>()

    init(totalCostLimit: Int) {
        storage.totalCostLimit = totalCostLimit
    }

    func image(for key: ThumbKey) -> CGImage? {
        storage.object(forKey: WrappedKey(key))?.image
    }

    func store(_ image: CGImage, for key: ThumbKey, cost: Int) {
        storage.setObject(Entry(image), forKey: WrappedKey(key), cost: cost)
    }

    static func tier() -> Int {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb: UInt64 = 1024 * 1024 * 1024
        if bytes < 8 * gb { return 200 * 1024 * 1024 }
        if bytes < 32 * gb { return 300 * 1024 * 1024 }
        return 500 * 1024 * 1024
    }

    static func cost(of cgImage: CGImage) -> Int {
        cgImage.bytesPerRow * cgImage.height
    }

    static func bucket(for displayWidth: CGFloat) -> Int {
        if displayWidth <= 60 { return 60 }
        if displayWidth <= 120 { return 120 }
        return 240
    }
}
