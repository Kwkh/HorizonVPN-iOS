import Foundation

/// Adds deterministic storage latency without using the real Keychain.
nonisolated final class DelayedDeletionStorage: SubscriptionStorage, @unchecked Sendable {
    let base = MemorySubscriptionStorage()
    private let lock = NSLock()
    private var delayed = false
    private var enumerations = 0
    func enableDelay() { lock.withLock { delayed = true; enumerations = 0 } }
    var keyScans: Int { lock.withLock { enumerations } }
    private func delay() { if lock.withLock({ delayed }) { Thread.sleep(forTimeInterval: 0.08) } }
    func keys() throws -> [String] { lock.withLock { enumerations += 1 }; delay(); return try base.keys() }
    func read(_ key: String) throws -> Data? { delay(); return try base.read(key) }
    func write(_ data: Data, for key: String) throws { delay(); try base.write(data, for: key) }
    func remove(_ key: String) throws { delay(); try base.remove(key) }
}

@MainActor final class DeletionHeartbeat { var ticks = 0 }
@main struct DeletionCheck {
    @MainActor static func main() async throws {
        let storage = DelayedDeletionStorage(), repo = SubscriptionRepository(storage: storage)
        func add(_ name: String, active: Bool) throws -> UUID {
            try repo.add(StoredConfiguration(source: Data("FICTIONAL-NOT-A-CONFIG".utf8)), fileName: name, displayTitle: name,
                         nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: active)
        }
        let a = try add("A", active: true)
        // Different source is required to avoid ordinary byte-identical import deduplication.
        let b = try repo.add(StoredConfiguration(source: Data("FICTIONAL-B".utf8)), fileName: "B", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
        storage.enableDelay()
        let heartbeat = DeletionHeartbeat()
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                heartbeat.ticks += 1
            }
        }
        defer { ticker.cancel() }
        let committed = try await SubscriptionDeletionWorker.commit([b], repository: repo)
        precondition(heartbeat.ticks >= 3, "storage commit blocked MainActor")
        precondition(storage.keyScans == 0, "delete commit scanned the library")
        precondition(committed.activeID == a && committed.entries.map(\.id) == [a] && committed.pendingDeletion == [b])
        precondition(storage.base.items[SubscriptionRepository.recordKey(b)] != nil, "credentials removed before committed publication")
        let before = heartbeat.ticks
        let cleaned = try await SubscriptionDeletionWorker.cleanup(repository: repo)
        precondition(heartbeat.ticks > before + 3, "resource cleanup blocked MainActor")
        precondition(cleaned.cleanupCount == 0 && storage.keyScans == 2, "cleanup repeated")
        precondition(storage.base.items[SubscriptionRepository.recordKey(b)] == nil && storage.base.items[SubscriptionRepository.recordKey(a)] != nil)
        storage.base.failingWriteKey = SubscriptionRepository.indexKey
        do { _ = try await SubscriptionDeletionWorker.commit([a], repository: repo); preconditionFailure("commit failure accepted") }
        catch { }
        storage.base.failingWriteKey = nil
        let afterFailure = try repo.index()
        precondition(afterFailure?.activeID == a)
        _ = try await SubscriptionDeletionWorker.commit([a], repository: repo)
        storage.base.failingRemovals = [SubscriptionRepository.recordKey(a)]
        let pending = try await SubscriptionDeletionWorker.cleanup(repository: repo)
        precondition(pending.entries.isEmpty && pending.activeID == nil && pending.cleanupCount == 1)
        storage.base.failingRemovals = []
        let recovered = try await SubscriptionDeletionWorker.cleanup(repository: repo)
        precondition(recovered.cleanupCount == 0)
        print("PASS: delayed commit/cleanup leave MainActor responsive; no pre-commit scan, one cleanup pass, retained configuration untouched, failed commit retained, cleanup retry succeeds; fictional memory storage only")
    }
}
