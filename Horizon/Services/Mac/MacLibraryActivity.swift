#if os(macOS)
import Foundation
import Observation

/// Serializes library transactions independently of their loading presentation.
/// Background refreshes never dim the UI; subsequent actions retain FIFO order.
@MainActor @Observable final class MacLibraryActivity {
    private(set) var busy = false
    @ObservationIgnored private var occupied = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(showsActivity: Bool, operation: () async -> Bool) async -> Bool {
        if occupied {
            await withCheckedContinuation { waiters.append($0) }
        } else { occupied = true }
        defer {
            busy = false
            if waiters.isEmpty { occupied = false }
            else { waiters.removeFirst().resume() }
        }
        guard !Task.isCancelled else { return false }
        busy = showsActivity
        return await operation()
    }
}
#endif
