import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct SubscriptionCleanupTests {
    @Test func cleanupDoesNotReloadOrInvalidateCurrentConfiguration() async throws {
        let storage = CleanupTestStorage()
        let (repository, tunnel, active, retired) = try await fixture(storage)
        let entries = tunnel.subscriptions
        let identity = tunnel.configurationID
        let selected = tunnel.selectedNode
        storage.memory.failingRemovals = []
        // Cleanup may conservatively retain resources if a live record cannot be
        // read. That must not invalidate the already prepared configuration.
        storage.failedReadKey = SubscriptionRepository.recordKey(active)
        let message = tunnel.message
        #expect(await tunnel.cleanupSubscriptionsIfNeeded())
        #expect(tunnel.pendingCleanupCount == 0)
        #expect(!tunnel.isBusy && tunnel.message == message)
        #expect(tunnel.libraryReady && tunnel.hasConfiguration)
        #expect(tunnel.subscriptions == entries && tunnel.activeSubscriptionID == active)
        #expect(tunnel.configurationID == identity && tunnel.selectedNode == selected)
        #expect(try storage.memory.read(SubscriptionRepository.recordKey(retired)) == nil)
        storage.failedReadKey = nil
        #expect(try repository.activeRecord() != nil)
    }

    @Test func failedRemovalRemainsRetryable() async throws {
        let storage = CleanupTestStorage()
        let (_, tunnel, active, _) = try await fixture(storage)
        #expect(!(await tunnel.cleanupSubscriptionsIfNeeded()))
        #expect(tunnel.pendingCleanupCount == 1)
        #expect(tunnel.canManageSubscriptions)
        #expect(tunnel.hasConfiguration && tunnel.activeSubscriptionID == active)
    }

    @Test func cleanupDoesNotDisableControlsOrPublishProgressAndPreventsDuplicateOperations() async throws {
        let storage = CleanupTestStorage()
        let (_, tunnel, _, _) = try await fixture(storage)
        storage.memory.failingRemovals = []
        storage.arm()
        defer { storage.release() }
        let message = tunnel.message
        let cleanup = Task { await tunnel.cleanupSubscriptionsIfNeeded() }
        for _ in 0..<100 {
            if storage.entered { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(storage.entered)
        #expect(!tunnel.isBusy && tunnel.canManageSubscriptions)
        #expect(!tunnel.showsSubscriptionProgress, "Cleanup must not show VPN operation feedback")
        #expect(!(await tunnel.cleanupSubscriptionsIfNeeded()))
        #expect(storage.pausedRemovalCount == 1)
        storage.release()
        #expect(await cleanup.value)
        #expect(!tunnel.showsSubscriptionProgress && tunnel.message == message)
        #expect(tunnel.canManageSubscriptions && tunnel.pendingCleanupCount == 0)
    }

    @Test func foregroundAutomaticallyRetriesPersistedDeletion() async throws {
        let storage = CleanupTestStorage()
        let (_, tunnel, active, retired) = try await fixture(storage)
        storage.memory.failingRemovals = []
        tunnel.setSubscriptionCleanupActive(true)
        defer { tunnel.setSubscriptionCleanupActive(false) }
        for _ in 0..<200 {
            if tunnel.pendingCleanupCount == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(tunnel.pendingCleanupCount == 0)
        #expect(tunnel.activeSubscriptionID == active && tunnel.hasConfiguration)
        #expect(try storage.memory.read(SubscriptionRepository.recordKey(retired)) == nil)
    }

    private func fixture(_ storage: CleanupTestStorage) async throws -> (SubscriptionRepository, TunnelController, UUID, UUID) {
        let repository = SubscriptionRepository(storage: storage)
        let source = Data(PrototypeSelfCheck.fixture.utf8)
        let retired = try repository.add(StoredConfiguration(source: Data("# retired\n".utf8) + source),
            fileName: "Retired.yaml", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
        let active = try repository.add(StoredConfiguration(source: source), fileName: "Current.yaml",
            nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: true)
        storage.memory.failingRemovals = [SubscriptionRepository.recordKey(retired)]
        _ = try repository.delete([retired])
        let tunnel = TunnelController(repository: repository, permitsNetwork: false,
            network: NetworkAvailability(initialStatus: .available, monitorSystem: false))
        await tunnel.refresh()
        try #require(tunnel.pendingCleanupCount == 1 && tunnel.hasConfiguration)
        return (repository, tunnel, active, retired)
    }
}

nonisolated private final class CleanupTestStorage: SubscriptionStorage, @unchecked Sendable {
    let memory = MemorySubscriptionStorage()
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var armed = false
    private var paused = 0
    private var readFailure: String?
    var entered: Bool { lock.withLock { paused > 0 } }
    var pausedRemovalCount: Int { lock.withLock { paused } }
    var failedReadKey: String? {
        get { lock.withLock { readFailure } }
        set { lock.withLock { readFailure = newValue } }
    }
    func arm() { lock.withLock { armed = true } }
    func release() { gate.signal() }
    func keys() throws -> [String] { try memory.keys() }
    func read(_ key: String) throws -> Data? {
        if key == failedReadKey { throw PrototypeError.keychain }
        return try memory.read(key)
    }
    func write(_ data: Data, for key: String) throws { try memory.write(data, for: key) }
    func remove(_ key: String) throws {
        let pause = lock.withLock {
            if armed { armed = false; paused += 1; return true }
            return false
        }
        if pause {
            #expect(!Thread.isMainThread)
            _ = gate.wait(timeout: .now() + 5)
        }
        try memory.remove(key)
    }
}
