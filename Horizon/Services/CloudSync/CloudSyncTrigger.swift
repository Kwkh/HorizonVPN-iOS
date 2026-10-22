import Foundation

/// Coalesces local edits without cancelling an in-flight CloudKit operation.
/// A change made during a send causes one more pass after that send finishes.
@MainActor final class CloudSyncTrigger {
    private let action: @MainActor () async -> Void
    private let clock = ContinuousClock()
    private var deadline: ContinuousClock.Instant?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var cancelled = false

    init(action: @escaping @MainActor () async -> Void) { self.action = action }

    func request(after delay: Duration = .milliseconds(500)) {
        guard !cancelled else { return }
        deadline = clock.now.advanced(by: delay)
        guard task == nil else { return }
        let ticket = generation
        task = Task { [weak self] in await self?.drain(ticket) }
    }

    func cancel() {
        cancelled = true
        generation = UUID()
        deadline = nil
        task?.cancel()
        task = nil
    }

    private func drain(_ ticket: UUID) async {
        defer { if generation == ticket { task = nil } }
        while let due = deadline, generation == ticket, !Task.isCancelled {
            do { try await clock.sleep(until: due) } catch { return }
            guard generation == ticket, !Task.isCancelled else { return }
            guard deadline == due else { continue }
            deadline = nil
            await action()
        }
    }
}
