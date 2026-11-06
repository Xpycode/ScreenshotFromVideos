// Headless tests of the production render loop using a decoder double. These
// cover retry/cancellation policy, not AVFoundation decoding or UI reachability.
import Foundation
import AVFoundation
import CoreGraphics

final class AVAssetImageGenerator: @unchecked Sendable {
    enum Result {
        case success(requestedTime: CMTime, image: CGImage, actualTime: CMTime)
        case failure(requestedTime: CMTime, error: Error)
    }
    enum Plan { case success, partial, omitted, failure, cancelled, thrown, hanging }
    struct Call {
        let times: [CMTime]
        let size: CGSize
        let before: CMTime
        let after: CMTime
        let transform: Bool
    }
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var plans: [Plan] = []
        var calls: [Call] = []
        var cancellations = 0
        func reset(_ plans: [Plan]) {
            lock.withLock { self.plans = plans; calls = []; cancellations = 0 }
        }
    }
    static let state = State()
    var appliesPreferredTrackTransform = false
    var maximumSize = CGSize.zero
    var requestedTimeToleranceBefore = CMTime.zero
    var requestedTimeToleranceAfter = CMTime.zero
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Result, Error>.Continuation?
    init(asset: AVAsset) {}
    func images(for times: [CMTime]) -> AsyncThrowingStream<Result, Error> {
        let plan = Self.state.lock.withLock {
            Self.state.calls.append(Call(times: times, size: maximumSize,
                before: requestedTimeToleranceBefore, after: requestedTimeToleranceAfter,
                transform: appliesPreferredTrackTransform))
            return Self.state.plans.removeFirst()
        }
        return AsyncThrowingStream { output in
            lock.withLock { continuation = output }
            for (index, time) in times.enumerated() {
                switch plan {
                case .hanging: return
                case .thrown: output.finish(throwing: NSError(domain: "test", code: 1)); return
                case .cancelled:
                    output.yield(.failure(requestedTime: time, error: AVError(.operationCancelled)))
                case .failure:
                    output.yield(.failure(requestedTime: time, error: NSError(domain: "test", code: 1)))
                case .partial where index == 1:
                    output.yield(.failure(requestedTime: time, error: NSError(domain: "test", code: 1)))
                case .omitted where index == 1: continue
                default:
                    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    // Deliberately different actual time: cache identity must stay requested.
                    output.yield(.success(requestedTime: time, image: context.makeImage()!, actualTime: .zero))
                }
            }
            output.finish()
        }
    }
    func cancelAllCGImageGeneration() {
        Self.state.lock.withLock { Self.state.cancellations += 1 }
        lock.withLock { continuation?.finish() }
    }
}

@main struct RetryTests {
    static let times = [CMTime(value: 100, timescale: 30), CMTime(value: 101, timescale: 30), CMTime(value: 102, timescale: 30)]
    static let tolerance = CMTime(value: 1, timescale: 60)
    static func render() -> AsyncStream<(CMTime, CGImage)> {
        ThumbnailRenderer(asset: AVMutableComposition()).render(times: times, targetWidth: 240, tolerance: tolerance)
    }
    static func collect() async -> [CMTime] {
        var result: [CMTime] = []
        for await (time, _) in render() { result.append(time) }
        return result
    }
    static func waitUntil(_ condition: @Sendable () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for renderer cancellation")
            await Task.yield()
        }
    }
    static func main() async {
        let state = AVAssetImageGenerator.state
        state.reset([.success])
        let collected = await collect()
        precondition(collected == times)
        precondition(state.calls.count == 1)
        for plan in [AVAssetImageGenerator.Plan.partial, .omitted] {
            state.reset([plan, .success])
            let output = await collect()
            precondition(output == [times[0], times[2], times[1]])
            precondition(state.calls.count == 2 && state.calls[1].times == [times[1]])
            precondition(state.calls.allSatisfy { $0.size.width == 480 && $0.before == tolerance && $0.after == tolerance && $0.transform })
        }
        state.reset([.failure, .failure])
        let failed = await collect()
        precondition(failed.isEmpty)
        precondition(state.calls.count == 2)
        state.reset([.thrown, .success])
        let recovered = await collect()
        precondition(recovered == times)
        precondition(state.calls.count == 2)
        state.reset([.cancelled])
        let cancelled = await collect()
        precondition(cancelled.isEmpty)
        precondition(state.calls.count == 1)
        for plans in [[AVAssetImageGenerator.Plan.hanging], [.failure, .hanging]] {
            state.reset(plans)
            let consumer = Task { await collect() }
            await waitUntil { state.lock.withLock { state.calls.count == plans.count } }
            consumer.cancel()
            _ = await consumer.value
            // onTermination cancels the producer; let its cancellation handler run.
            await waitUntil { state.lock.withLock { state.cancellations > 0 } }
            precondition(state.lock.withLock { state.calls.count == plans.count && state.cancellations == 1 })
        }
        print("PASS: renderer success, missing-only retry, omitted results, bounded failure, thrown failure, cancellation in either pass, requested identity and configuration")
    }
}
