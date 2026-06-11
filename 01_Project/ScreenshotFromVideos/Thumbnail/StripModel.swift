//
//  StripModel.swift
//  ScreenshotFromVideos
//
//  Owns the strip's zoom/scroll state and the render task.
//  Single source of truth; ThumbnailStripView reads, doesn't mutate.
//

import Foundation
import AVFoundation
import CoreGraphics
import Observation

@MainActor
@Observable
final class StripModel {
    var zoomLevel: Double = 1.0
    var isMagnifying: Bool = false
    var isScrolling: Bool = false
    var visibleTimeRange: ClosedRange<Double> = 0...1
    let duration: Double
    let nominalFPS: Float
    let cache: ThumbnailCache
    let renderer: ThumbnailRenderer
    var cacheVersion: Int = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var zoomBaseline: Double = 1.0

    init(duration: Double, nominalFPS: Float, cache: ThumbnailCache, renderer: ThumbnailRenderer) {
        self.duration = max(0, duration)
        self.nominalFPS = nominalFPS > 0 ? nominalFPS : 30
        self.cache = cache
        self.renderer = renderer
    }

    var density: Double {
        let cap = min(Double(nominalFPS), 30.0)
        let value = pow(2.0, zoomLevel * 0.6)
        return min(cap, max(0.5, value))
    }

    var thumbWidth: CGFloat {
        let t = max(0, min(1, (zoomLevel - 1) / 9))
        let smooth = t * t * (3 - 2 * t)
        return 60 + (240 - 60) * smooth
    }

    var widthBucket: Int { ThumbnailCache.bucket(for: thumbWidth) }

    var pointsPerSecond: CGFloat { thumbWidth * CGFloat(density) }

    /// Source frames skipped between two adjacent thumbnails at the current
    /// zoom (≥ 1). At max zoom this reaches 1 ("every frame") for any source,
    /// since `density` caps at the clip's frame rate.
    var framesPerThumbnail: Int {
        guard density > 0 else { return 1 }
        return max(1, Int((Double(nominalFPS) / density).rounded()))
    }

    /// Real-time gap between two adjacent thumbnails, in seconds.
    var secondsPerThumbnail: Double { density > 0 ? 1.0 / density : 0 }

    var totalContentWidth: CGFloat { CGFloat(duration) * pointsPerSecond }

    func thumbnailTimes(in range: ClosedRange<Double>) -> [CMTime] {
        guard density > 0, range.upperBound > range.lowerBound else { return [] }
        let step = 1.0 / density
        let lower = max(0, range.lowerBound)
        let upper = min(duration, range.upperBound)
        var times: [CMTime] = []
        var t = (lower / step).rounded(.down) * step
        while t <= upper {
            if t >= 0 { times.append(CMTime(seconds: t, preferredTimescale: 600)) }
            t += step
        }
        return times
    }

    var prefetchRange: ClosedRange<Double> {
        let span = max(0, visibleTimeRange.upperBound - visibleTimeRange.lowerBound)
        let pad: Double
        if isMagnifying { pad = span * 0.5 }
        else if isScrolling { pad = 0 }
        else { pad = span * 0.2 }
        let lo = max(0, visibleTimeRange.lowerBound - pad)
        let hi = min(duration, visibleTimeRange.upperBound + pad)
        return lo...max(lo, hi)
    }

    var tolerance: CMTime {
        density < 5 ? CMTime(seconds: 0.5, preferredTimescale: 600) : .zero
    }

    func onZoomChange(magnification: Double) {
        // `magnification` is absolute (1.0 at gesture start), so apply against
        // the baseline captured in onMagnifyStart — multiplying zoomLevel
        // directly would compound on every tick.
        let next = max(1.0, min(12.0, zoomBaseline * magnification))
        zoomLevel = next
        scheduleRender()
    }

    func commitZoom(_ magnification: Double) {
        zoomBaseline = zoomLevel
    }

    func onMagnifyStart() {
        isMagnifying = true
        zoomBaseline = zoomLevel
        scheduleRender()
    }

    func onMagnifyEnd() {
        isMagnifying = false
        scheduleRender()
    }

    func onVisibleRangeChange(_ range: ClosedRange<Double>) {
        visibleTimeRange = range
        scheduleRender()
    }

    func onScrollPhaseChange(isScrolling: Bool) {
        self.isScrolling = isScrolling
        scheduleRender()
    }

    // MARK: - Zoom (keyboard / scroll-wheel / slider entry points)

    private let zoomStep: Double = 0.5

    func zoomIn() { setZoom(zoomLevel + zoomStep) }
    func zoomOut() { setZoom(zoomLevel - zoomStep) }
    func resetZoom() { setZoom(1.0) }

    func setZoom(_ value: Double) {
        let next = max(1.0, min(12.0, value))
        guard next != zoomLevel else { return }
        zoomLevel = next
        zoomBaseline = next
        scheduleRender()
    }

    func applyZoomDelta(_ delta: CGFloat) {
        // scrollingDeltaY: positive = scroll up = zoom in (Preview/Maps idiom).
        // 0.03 multiplier covers the [1, 12] range in ~10 scroll-unit gestures.
        setZoom(zoomLevel + Double(delta) * 0.03)
    }

    // Hard cap on concurrent decode requests per render batch. During fast
    // pinch the visibleTimeRange is stale (set by scroll geometry, lags zoom)
    // so `prefetchRange × new density` can compute hundreds of cells; without
    // a cap, AVAssetImageGenerator fans out enough decodes to saturate
    // VTDecoderXPCService and lock up the system.
    private static let maxInFlight = 256

    func scheduleRender() {
        task?.cancel()
        let bucket = widthBucket
        let tol = tolerance
        let range = prefetchRange
        let allTimes = thumbnailTimes(in: range)
        let visibleCenter = (visibleTimeRange.lowerBound + visibleTimeRange.upperBound) / 2
        let shouldDebounce = isScrolling || isMagnifying
        task = Task { [weak self] in
            if shouldDebounce {
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            let missing = allTimes.filter { time in
                let key = ThumbKey(
                    timeMillis: Int64((CMTimeGetSeconds(time) * 1000).rounded()),
                    widthBucket: bucket
                )
                return self.cache.image(for: key) == nil
            }
            if missing.isEmpty { return }
            // Prioritize cells closest to the visible center, then cap.
            // Off-center prefetch loses first when we have to drop.
            let prioritized = missing.sorted {
                abs(CMTimeGetSeconds($0) - visibleCenter) < abs(CMTimeGetSeconds($1) - visibleCenter)
            }
            let capped = Array(prioritized.prefix(Self.maxInFlight))
            for await (time, image) in self.renderer.render(times: capped, targetWidth: bucket, tolerance: tol) {
                if Task.isCancelled { return }
                let key = ThumbKey(
                    timeMillis: Int64((CMTimeGetSeconds(time) * 1000).rounded()),
                    widthBucket: bucket
                )
                self.cache.store(image, for: key, cost: ThumbnailCache.cost(of: image))
                self.cacheVersion &+= 1
            }
        }
    }
}
