import AVFoundation

/// Exact navigation seeks, with one flight per player and only the latest input
/// retained. All bookkeeping and the injected completion seam run on MainActor.
@MainActor
final class SeekCoalescer {
    typealias Completion = @MainActor (Bool) -> Void
    typealias Seek = @MainActor (AVPlayer, CMTime, @escaping Completion) -> Void

    private struct Target {
        let player: AVPlayer
        let item: AVPlayerItem?
        let time: CMTime
        let revision = UUID()
        let lifetime: UUID
    }
    private struct Flight {
        let id = UUID()
        let target: Target
    }

    private let seek: Seek
    private var latest: Target?
    // Reset/replacement drops intent, not knowledge of an outstanding seek.
    // Retaining its player also prevents ObjectIdentifier reuse before completion.
    private var flights: [ObjectIdentifier: Flight] = [:]
    private var lifetime = UUID()

    init(seek: @escaping Seek = { player, time, completion in
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor in completion(finished) }
        }
    }) {
        self.seek = seek
    }

    func request(_ time: CMTime, on player: AVPlayer) {
        guard time.isNumeric else { return }
        latest = Target(player: player, item: player.currentItem, time: time, lifetime: lifetime)
        startLatestIfIdle()
    }

    /// Relative keyboard input uses pending intent until the seek completes;
    /// playback remains the source of truth whenever no navigation is pending.
    func pendingTarget(on player: AVPlayer) -> CMTime? {
        guard let latest, latest.player === player,
              latest.item === player.currentItem else { return nil }
        return latest.time
    }

    func reset() {
        latest = nil
        lifetime = UUID()
    }

    private func startLatestIfIdle() {
        guard let target = latest else { return }
        guard target.item === target.player.currentItem else {
            latest = nil
            return
        }
        let key = ObjectIdentifier(target.player)
        guard flights[key] == nil else { return }
        let flight = Flight(target: target)
        flights[key] = flight
        seek(target.player, target.time) { [weak self] finished in
            self?.completed(flight, finished: finished)
        }
    }

    private func completed(_ flight: Flight, finished: Bool) {
        let key = ObjectIdentifier(flight.target.player)
        guard flights[key]?.id == flight.id else { return }
        flights[key] = nil
        guard let target = latest, target.player === flight.target.player else { return }
        guard target.item === target.player.currentItem else {
            latest = nil
            return
        }
        let sameScope = target.lifetime == flight.target.lifetime && target.item === flight.target.item
        // Success at the latest time satisfies even A→B→A input. An interrupted
        // seek is retried only for fresh explicit input, never in an endless loop.
        if sameScope && ((finished && CMTimeCompare(target.time, flight.target.time) == 0)
                         || target.revision == flight.target.revision) {
            latest = nil
        } else {
            startLatestIfIdle()
        }
    }
}
