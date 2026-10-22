import Foundation
import Testing
@testable import Horizon

@MainActor @Suite struct SubscriptionCleanupCoordinatorTests {
    @Test func failuresBackOffWithBoundedAttemptsAndCanResumeOnUnlock() async throws {
        var attempts = 0
        var available = false
        let cleanup = SubscriptionCleanupCoordinator(delays: [.zero, .milliseconds(5), .milliseconds(10)]) {
            attempts += 1
            return available
        }
        cleanup.request()
        #expect(!cleanup.isScheduled && attempts == 0)
        cleanup.setActive(true)
        try await wait { attempts == 3 && !cleanup.isScheduled }
        try await Task.sleep(for: .milliseconds(30))
        #expect(attempts == 3, "Persistent failure must not spin indefinitely")
        available = true
        cleanup.request() // Protected data became available.
        try await wait { attempts == 4 && !cleanup.isScheduled }
    }

    @Test func foregroundReturnCannotOverlapCancelledInFlightStorageWork() async throws {
        var calls = 0
        var finish: CheckedContinuation<Bool, Never>?
        let cleanup = SubscriptionCleanupCoordinator(delays: [.zero]) {
            calls += 1
            if calls == 1 { return await withCheckedContinuation { finish = $0 } }
            return true
        }
        cleanup.setActive(true)
        cleanup.request()
        try await wait { finish != nil }
        cleanup.setActive(false)
        cleanup.setActive(true)
        cleanup.request()
        cleanup.request()
        await Task.yield()
        #expect(calls == 1)
        finish?.resume(returning: false)
        try await wait { calls == 2 && !cleanup.isScheduled }
    }

    @Test func backgroundCancelsDelayedRetryAndRetainsItForForeground() async throws {
        var calls = 0
        let cleanup = SubscriptionCleanupCoordinator(delays: [.milliseconds(30)]) {
            calls += 1
            return true
        }
        cleanup.setActive(true)
        cleanup.request()
        cleanup.setActive(false)
        try await wait { !cleanup.isScheduled }
        #expect(calls == 0)
        cleanup.setActive(true)
        try await wait { calls == 1 && !cleanup.isScheduled }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), "Maintenance did not reach the expected state")
    }
}
