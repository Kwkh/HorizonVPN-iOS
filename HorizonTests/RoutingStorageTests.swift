import Foundation
import Testing
@testable import Horizon

@MainActor struct RoutingStorageTests {
    @Test func revisionIOLeavesMainThreadAndStillRejectsStaleCommits() async throws {
        let storage = RoutingThreadCheckedStorage()
        let repository = SubscriptionRepository(storage: storage)
        let original = try PrototypeConfiguration.prepare(Data(PrototypeSelfCheck.fixture.utf8))
        let id = try repository.add(.init(source: original.source, choices: original.catalog.choices), fileName: "Example.yaml",
            nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: true)
        let expected = try repository.record(id)
        let changed = try PrototypeConfiguration.prepare(original.source + Data("\n# revised\n".utf8))
        storage.checkBackground = true
        let worker = ConfigurationImportWorker.shared
        try await worker.checkRevision(id, expected: expected, repository: repository)
        try await worker.replaceRevision(id, expected: expected, prepared: changed, sourceURL: nil, verifiedAt: nil, repository: repository)
        try await worker.confirmStartup(id, source: changed.source, choices: changed.catalog.choices, repository: repository)
        let consent = try await worker.certificateConsentDigest(id, prepared: changed, repository: repository)
        #expect(consent == nil)
        let committed = try await worker.readRecord(id, repository: repository)
        #expect(committed.source == changed.source && committed.startupConfirmed == true)
        let loaded = try await worker.loadLibrary(repository)
        #expect(loaded.configurationID == RuntimeIdentity.fingerprint(source: changed.source, choices: changed.catalog.choices))
        #expect(loaded.sourceDigest == ConfigurationResourceStore.digest(changed.source))
        do {
            try await worker.replaceRevision(id, expected: expected, prepared: original, sourceURL: nil, verifiedAt: nil, repository: repository)
            Issue.record("Stale revision overwrote the committed configuration")
        } catch SubscriptionError.staleRevision { }
        let after = try await worker.readRecord(id, repository: repository)
        #expect(after.revisionID == committed.revisionID)
        #expect(storage.checkedCalls > 0)
    }
}

nonisolated private final class RoutingThreadCheckedStorage: SubscriptionStorage, @unchecked Sendable {
    private let memory = MemorySubscriptionStorage()
    private let lock = NSLock()
    private var checking = false
    private var calls = 0
    var checkBackground: Bool {
        get { lock.withLock { checking } }
        set { lock.withLock { checking = newValue } }
    }
    var checkedCalls: Int { lock.withLock { calls } }
    private func check() {
        let enabled = lock.withLock { if checking { calls += 1 }; return checking }
        if enabled { #expect(!Thread.isMainThread, "Revision storage must not block UI rendering") }
    }
    func keys() throws -> [String] { check(); return try memory.keys() }
    func read(_ key: String) throws -> Data? { check(); return try memory.read(key) }
    func write(_ data: Data, for key: String) throws { check(); try memory.write(data, for: key) }
    func remove(_ key: String) throws { check(); try memory.remove(key) }
}
