import AVFoundation
import Foundation

// Enters through the coalescer's public request path, injecting only AVPlayer's
// completion boundary. No media is opened and no actual seek or app is launched.
@MainActor
private final class SeekRecorder {
    struct Call {
        let player: AVPlayer
        let time: CMTime
        let complete: @MainActor (Bool) -> Void
    }
    var calls: [Call] = []
    lazy var coalescer = SeekCoalescer { [unowned self] player, time, completion in
        calls.append(Call(player: player, time: time, complete: completion))
    }
    func request(_ seconds: Double, on player: AVPlayer) {
        coalescer.request(CMTime(seconds: seconds, preferredTimescale: 600), on: player)
    }
    var targets: [Double] { calls.map { CMTimeGetSeconds($0.time) } }
}

@main
struct SeekCoalescerTests {
    @MainActor
    static func main() {
        let player = AVPlayer()
        let r = SeekRecorder()
        r.request(1, on: player)
        r.request(2, on: player)
        r.request(3, on: player)
        precondition(r.targets == [1], "only one seek can be in flight")
        precondition(CMTimeGetSeconds(r.coalescer.pendingTarget(on: player)!) == 3)
        r.calls[0].complete(true)
        precondition(r.targets == [1, 3], "intermediate target must be dropped")
        r.calls[1].complete(true)
        precondition(r.coalescer.pendingTarget(on: player) == nil)
        r.request(3, on: player)
        precondition(r.targets == [1, 3, 3], "a later explicit same-target seek must work")
        r.request(4, on: player)
        r.request(3, on: player)
        r.calls[2].complete(true)
        precondition(r.targets == [1, 3, 3], "returning to successful in-flight target needs no extra seek")

        let failed = SeekRecorder()
        failed.request(1, on: player)
        failed.calls[0].complete(false)
        precondition(failed.calls.count == 1 && failed.coalescer.pendingTarget(on: player) == nil,
                     "failure alone must not loop forever")
        failed.request(2, on: player)
        failed.request(3, on: player)
        failed.calls[1].complete(false)
        precondition(failed.targets == [1, 2, 3], "failure must still chase newer input")
        failed.request(3, on: player)
        failed.calls[2].complete(false)
        precondition(failed.targets == [1, 2, 3, 3], "explicit repeated failed target gets one new attempt")
        failed.calls[3].complete(true)

        let reset = SeekRecorder()
        reset.request(1, on: player)
        reset.request(2, on: player)
        reset.coalescer.reset()
        precondition(reset.coalescer.pendingTarget(on: player) == nil)
        reset.request(3, on: player)
        precondition(reset.targets == [1], "reset must not forget an outstanding same-player seek")
        reset.calls[0].complete(true)
        precondition(reset.targets == [1, 3], "new lifecycle request drains after old flight")
        reset.calls[0].complete(false)
        precondition(reset.targets == [1, 3], "duplicate stale callback cannot release current flight")
        reset.calls[1].complete(true)
        reset.request(4, on: player)
        reset.request(5, on: player)
        reset.coalescer.reset()
        reset.calls[2].complete(true)
        precondition(reset.targets == [1, 3, 4], "teardown drops queued targets")

        let held = SeekRecorder()
        for _ in 0..<100 {
            let base = held.coalescer.pendingTarget(on: player).map(CMTimeGetSeconds) ?? 0
            held.request(base + 1, on: player)
        }
        precondition(held.targets == [1])
        precondition(CMTimeGetSeconds(held.coalescer.pendingTarget(on: player)!) == 100,
                     "relative repeated input must advance from pending intent")
        held.calls[0].complete(true)
        precondition(held.targets == [1, 100])
        held.calls[1].complete(true)

        let replacement = SeekRecorder()
        let other = AVPlayer()
        replacement.request(1, on: player)
        replacement.request(2, on: player)
        replacement.request(10, on: other)
        replacement.calls[0].complete(true)
        precondition(replacement.targets == [1, 10], "old player completion cannot resume its obsolete queue")
        replacement.calls[1].complete(true)
        let switched = SeekRecorder()
        switched.request(1, on: player)
        switched.request(10, on: other)
        switched.request(2, on: player)
        precondition(switched.targets == [1, 10], "switching back must preserve the original flight barrier")
        switched.calls[1].complete(true)
        precondition(switched.targets == [1, 10], "other player completion cannot drain current player")
        switched.calls[0].complete(true)
        precondition(switched.targets == [1, 10, 2])
        switched.calls[2].complete(true)

        let items = SeekRecorder()
        items.request(1, on: player)
        items.request(2, on: player)
        // Composition is an in-memory item; replacing it performs no file/network access.
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        precondition(items.coalescer.pendingTarget(on: player) == nil)
        items.calls[0].complete(true)
        precondition(items.targets == [1], "replacement item must not receive an old queued target")
        items.request(10, on: player)
        player.replaceCurrentItem(with: nil)
        items.request(20, on: player)
        precondition(items.targets == [1, 10], "item replacement cannot stack seeks on the same player")
        items.calls[1].complete(false)
        precondition(items.targets == [1, 10, 20])
        items.calls[2].complete(true)
        print("Seek coalescer tests passed (one-flight/latest, repeated targets, failures, reset, stale callbacks, player/item replacement)")
    }
}
