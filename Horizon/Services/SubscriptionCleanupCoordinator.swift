import Foundation

/// Foreground maintenance only: coalesce requests, never overlap storage work,
/// and back off instead of spinning when Keychain remains unavailable.
@MainActor final class SubscriptionCleanupCoordinator {
    private let delays: [Duration]
    private let action: @MainActor () async -> Bool
    private var active = false
    private var pending = false
    private var task: Task<Void, Never>?
    var isScheduled: Bool { task != nil }

    init(delays: [Duration] = [.seconds(1), .seconds(5), .seconds(30)],
         action: @escaping @MainActor () async -> Bool) {
        self.delays = delays
        self.action = action
    }

    func setActive(_ value: Bool) {
        active = value
        if value { startIfNeeded() }
        else { task?.cancel() }
    }

    func request() {
        pending = true
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard active, pending, task == nil else { return }
        pending = false
        task = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        defer {
            task = nil
            startIfNeeded()
        }
        for delay in delays {
            do { try await Task.sleep(for: delay) }
            catch { pending = true; return }
            guard active, !Task.isCancelled else { pending = true; return }
            let completed = await action()
            // Detached storage work may finish after backgrounding. Keep the
            // slot reserved until it returns so foreground entry cannot overlap it.
            if completed { return }
            guard active, !Task.isCancelled else { pending = true; return }
        }
        // No timer loop after the bounded attempts. Foreground/unlock or a new
        // deletion starts another series; the durable deletion ledger survives exit.
    }
}
