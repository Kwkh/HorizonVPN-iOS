import Foundation

/// Shared by both Metal surfaces during the guide/cinematic handoff.
/// Pausing preserves phase; transferring ownership does not restart rotation.
final class HorizonSceneClock {
    private var started = Date()
    private var accumulated: TimeInterval = 0
    private var running = false
    func setRunning(_ next: Bool, now: Date = Date()) {
        guard next != running else { return }
        accumulated = elapsed(at:now)
        started = now
        running = next
    }
    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (running ? max(0,date.timeIntervalSince(started)) : 0)
    }
}
