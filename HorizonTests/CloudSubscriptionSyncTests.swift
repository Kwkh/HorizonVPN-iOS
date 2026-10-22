import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct CloudSubscriptionSyncTests {
    private func version(_ source: String = "first") -> CloudSubscriptionVersion {
        let bytes = Data(source.utf8)
        return CloudSubscriptionVersion(id: UUID(), title: "Example", sourceURL: "https://example.invalid/sub?token=FICTIONAL",
            originalDigest: ConfigurationResourceStore.digest(bytes), originalBytes: bytes.count)
    }
    private func cache(_ account: String = "test") throws -> CloudAssetCache {
        try CloudAssetCache(account: account, root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    private func repository() -> SubscriptionRepository { .init(storage: MemorySubscriptionStorage()) }
    private func add(_ repository: SubscriptionRepository, current: Bool = false) throws -> UUID {
        try repository.add(.init(source: Data(PrototypeSelfCheck.fixture.utf8)), fileName: "Example.yaml",
            nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: current)
    }

    @Test func committedImportIsAcknowledgedWithoutErasingNewerRemoteChanges() throws {
        let installed = version()
        var newer = installed; newer.title = "New remote revision"; newer.version = UUID()
        var journal = CloudSyncJournal()
        journal.entries[installed.id] = .init(localID: installed.id, incoming: installed)
        #expect(journal.hasPendingTransfers)
        let mutation = UUID()
        journal.acknowledgeInstallation(installed.id, value: installed, mutation: mutation)
        #expect(!journal.hasPendingTransfers)
        #expect(journal.entries[installed.id]?.observedMutation == mutation)
        journal.entries[installed.id]?.incoming = newer
        journal.acknowledgeInstallation(installed.id, value: installed, mutation: mutation)
        #expect(journal.entries[installed.id]?.incoming == newer && journal.hasPendingTransfers)
        journal.fetched[installed.id] = newer
        #expect(journal.remoteVersions[installed.id] == newer.version)
        let storage = MemorySubscriptionStorage()
        try journal.save(account: "SYNTHETIC", storage: storage)
        let restored = try CloudSyncJournal.load(account: "SYNTHETIC", storage: storage)
        #expect(restored.entries[installed.id]?.installed == installed && restored.hasPendingTransfers)
    }

    @Test func metadataAndContentMergeWithoutClockOrdering() throws {
        let base = version()
        var local = base; local.title = "Renamed locally"; local.version = UUID()
        var remote = base; remote.originalDigest = ConfigurationResourceStore.digest(Data("new".utf8)); remote.originalBytes = 3; remote.version = UUID()
        let merged = try #require(CloudSubscriptionVersion.merge(base: base, local: local, remote: remote))
        #expect(merged.title == local.title && merged.originalDigest == remote.originalDigest)
        #expect(merged.parent == remote.version)
        var other = base; other.title = "Other rename"
        #expect(CloudSubscriptionVersion.merge(base: base, local: local, remote: other) == nil)
        var deleted = base; deleted.deleted = true; deleted.originalDigest = nil; deleted.originalBytes = 0; deleted.sourceURL = nil
        #expect(CloudSubscriptionVersion.merge(base: base, local: local, remote: deleted) == nil)
    }

    @Test func offlineConflictSurvivesJournalReloadAndDoesNotResurrectDeletion() throws {
        let storage = MemorySubscriptionStorage()
        let base = version()
        var local = base; local.title = "Offline edit"; local.version = UUID()
        var remote = base; remote.deleted = true; remote.version = UUID(); remote.originalDigest = nil; remote.originalBytes = 0; remote.sourceURL = nil
        var journal = CloudSyncJournal()
        journal.entries[base.id] = CloudSyncEntry(localID: base.id, installed: local, base: base, outgoing: local)
        journal.fetched[base.id] = remote
        try journal.save(account: "A", storage: storage)
        var restored = try CloudSyncJournal.load(account: "A", storage: storage)
        restored.reconcileFetched()
        #expect(restored.entries[base.id]?.review == .conflict)
        #expect(restored.entries[base.id]?.outgoing == local)
        #expect(restored.entries[base.id]?.incoming == remote)
        restored.fetched[base.id] = remote
        restored.reconcileFetched()
        #expect(restored.entries[base.id]?.review == .conflict)
        #expect(restored.outgoingVersion(base.id) == nil)
        #expect(try CloudSyncJournal.load(account: "B", storage: storage).entries.isEmpty)
        #expect(CloudSubscriptionVersion.conflictCopyID(base.id, remote.version) == CloudSubscriptionVersion.conflictCopyID(base.id, remote.version))
    }

    @Test func serverChangesAndUnknownSchemasBlockUploadsUntilReconciled() throws {
        let base = version()
        var journal = CloudSyncJournal()
        journal.entries[base.id] = CloudSyncEntry(localID: base.id, installed: base, outgoing: base)
        #expect(journal.outgoingVersion(base.id) != nil)
        journal.fetched[base.id] = base
        #expect(journal.outgoingVersion(base.id) == nil)
        journal.reconcileFetched()
        #expect(journal.outgoingVersion(base.id) == nil)
        journal.entries[base.id]?.outgoing = base
        journal.quarantined[base.id] = Data("future schema".utf8)
        #expect(journal.outgoingVersion(base.id) == nil)
        #expect(CloudSyncJournal.key("Development:A") != CloudSyncJournal.key("Production:A"))
    }

    @Test func acknowledgmentsAreIdempotentAndSameNamesDoNotDeduplicate() throws {
        let base = version()
        var journal = CloudSyncJournal()
        journal.entries[base.id] = CloudSyncEntry(localID: base.id, installed: base, outgoing: base)
        journal.fetched[base.id] = base
        journal.reconcileFetched()
        journal.fetched[base.id] = base
        journal.reconcileFetched()
        #expect(journal.entries[base.id]?.outgoing == nil && journal.entries[base.id]?.incoming == nil)
        var other = version("different"); other.title = base.title
        journal.fetched[other.id] = other; journal.reconcileFetched()
        #expect(journal.entries[other.id]?.localID == other.id)
        var identical = base; identical.id = UUID()
        journal.fetched[identical.id] = identical; journal.reconcileFetched()
        #expect(journal.entries[identical.id]?.localID == base.id)
    }

    @Test func localCommitAndDeletionLedgerAreAtomicAndDurable() throws {
        let storage = MemorySubscriptionStorage(), repository = SubscriptionRepository(storage: storage)
        let id = try add(repository)
        let generation = try #require(repository.index()?.syncMutations?[id.uuidString])
        storage.failingWriteKey = SubscriptionRepository.indexKey
        #expect(throws: (any Error).self) { try repository.rename(id, title: "Must not commit") }
        storage.failingWriteKey = nil
        #expect(try repository.index()?.syncMutations?[id.uuidString] == generation)
        #expect(try repository.index()?.entries.first?.title == "Example")
        try repository.rename(id, title: "Committed")
        #expect(try repository.index()?.syncMutations?[id.uuidString] != generation)
        _ = try repository.delete([id])
        let reopened = SubscriptionRepository(storage: storage)
        #expect(try reopened.index()?.entries.isEmpty == true)
        #expect(try reopened.index()?.syncDeletedIDs?.contains(id) == true)
        #expect(try reopened.index()?.pendingDeletion.isEmpty == true)
    }

    @Test func concurrentLibraryWritesDoNotLoseSubscriptions() async throws {
        let repository = repository()
        let source = Data(PrototypeSelfCheck.fixture.utf8)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    var record = StoredConfiguration(source: source + Data("\n# \(index)\n".utf8))
                    record.sourceURL = "https://example.invalid/\(index)"
                    _ = try repository.add(record, fileName: "\(index).yaml", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
                }
            }
            try await group.waitForAll()
        }
        #expect(try repository.index()?.entries.count == 12)
        #expect(try repository.index()?.syncMutations?.count == 12)
    }

    @Test func currentSubscriptionCannotBeReplacedOrDeletedInBackground() async throws {
        let repository = repository(), cache = try cache()
        let id = try add(repository, current: true)
        var value = try await ConfigurationImportWorker.shared.exportCloud(id, repository: repository, cache: cache)
        value.title = "Cloud name"
        let expected = try repository.index()?.syncMutations?[id.uuidString]
        do {
            try await ConfigurationImportWorker.shared.installCloud(value, localID: id, expectedMutation: expected,
                allowCurrent: false, repository: repository, cache: cache)
            Issue.record("Background sync replaced the selected subscription")
        } catch SubscriptionError.staleRevision { }
        #expect(throws: SubscriptionError.self) { try repository.deleteReplica(id, expectedMutation: expected, allowCurrent: false) }
        #expect(try repository.index()?.activeID == id)
        #expect(try repository.index()?.entries.first?.title == "Example")
    }

    @Test func portableRestoreValidatesAndRetainsHistoryWithoutApprovals() async throws {
        let a = repository(), b = repository(), cache = try cache()
        let id = try add(a)
        var cloud = try await ConfigurationImportWorker.shared.exportCloud(id, repository: a, cache: cache)
        try await ConfigurationImportWorker.shared.installCloud(cloud, localID: id, expectedMutation: nil,
            allowCurrent: false, repository: b, cache: cache)
        #expect(try b.index()?.activeID == nil)
        #expect(try b.record(id).source == a.record(id).source)
        #expect(try b.record(id).certificateConsentDigest == nil)
        #expect(try b.record(id).verifiedAt == nil && b.record(id).startupConfirmed != true)
        cloud.title = "Cloud update"; cloud.version = UUID()
        let expected = try b.index()?.syncMutations?[id.uuidString]
        try await ConfigurationImportWorker.shared.installCloud(cloud, localID: id, expectedMutation: expected,
            allowCurrent: false, repository: b, cache: cache)
        #expect(try b.record(id).history?.count == 1)
        #expect(try b.index()?.entries.first?.title == "Cloud update")
    }

    @Test func deviceRoutingAndChoicesStayLocalAndStaleChoiceCommitsAreRejected() async throws {
        let a = repository(), b = repository(), cache = try cache()
        let original = Data(PrototypeSelfCheck.fixture.replacingOccurrences(of: "proxies: [TEST-HY2]", with: "proxies: [TEST-HY2, DIRECT]").utf8)
        let smart = try await ConfigurationImportWorker.shared.resources(original, permitsNetwork: false,
            routing: .smart, deadline: .now.advanced(by: .seconds(30)))
        let local = StoredConfiguration(source: smart, choices: ["TEST-SELECT": "DIRECT"])
        let id = try a.add(local, fileName: "Local.yaml", nodeCount: 1, groupCount: 1, ruleCount: 3, makeCurrent: false)
        ConfigurationResourceStore.discardPending()
        var value = try await ConfigurationImportWorker.shared.exportCloud(id, repository: a, cache: cache)
        #expect(value.resources.isEmpty)
        #expect(try cache.read(value.originalDigest!, bytes: value.originalBytes) == original)
        try await ConfigurationImportWorker.shared.installCloud(value, localID: id, expectedMutation: nil,
            allowCurrent: false, repository: b, cache: cache)
        #expect(try ConfigurationRouting.mode(in: b.record(id).source) == .subscription)
        #expect(try b.record(id).choices["TEST-SELECT"] != "DIRECT")

        let before = try a.record(id)
        let mutation = try a.index()?.syncMutations?[id.uuidString]
        value.title = "Renamed in cloud"; value.version = UUID()
        try await ConfigurationImportWorker.shared.installCloud(value, localID: id, expectedMutation: mutation,
            allowCurrent: false, repository: a, cache: cache)
        #expect(try ConfigurationRouting.mode(in: a.record(id).source) == .smart)
        #expect(try a.record(id).choices["TEST-SELECT"] == "DIRECT")
        try a.activate(id)
        let current = try a.record(id)
        let generation = try a.index()?.syncMutations?[id.uuidString]
        try a.saveChoices(["TEST-SELECT": "TEST-HY2"], for: id)
        #expect(try a.index()?.syncMutations?[id.uuidString] == generation)
        #expect(throws: SubscriptionError.self) {
            try a.installReplica(id: id, title: value.title, fileName: value.fileName, record: before,
                nodeCount: 1, groupCount: 1, ruleCount: 3, expectedMutation: generation,
                allowCurrent: true, expectedRecord: current, resources: a.storage)
        }
        #expect(try a.record(id).choices["TEST-SELECT"] == "TEST-HY2")
    }

    @Test func dependencyChunksArePortableAndDoNotShareImportPending() throws {
        let cache = try cache(), storage = MemorySubscriptionStorage()
        let bytes = Data(repeating: 0x35, count: ConfigurationResourceStore.chunkBytes + 123)
        let digest = ConfigurationResourceStore.digest(bytes)
        try cache.put(bytes, digest: digest)
        let resource = ConfigurationSnapshot.Resource(key: "rule:Example", digest: digest, bytes: bytes.count)
        let reader = CloudResourceStorage(cache: cache, resources: [resource], destination: storage)
        #expect(try reader.read(ConfigurationResourceStore.key(digest, 0))?.count == ConfigurationResourceStore.chunkBytes)
        #expect(try reader.read(ConfigurationResourceStore.key(digest, 1))?.count == 123)
        #expect(try reader.read(ConfigurationResourceStore.key(digest, Int.max)) == nil)
        let source = try ConfigurationSnapshot(original: Data("original".utf8), resources: [resource]).encoded()
        ConfigurationResourceStore.discardPending()
        try ConfigurationResourceStore.persist(source, storage: storage, sourceStorage: reader)
        #expect(try ConfigurationResourceStore.load(resource, storage: storage) == bytes)
        #expect(throws: CloudSyncFailure.self) { try cache.put(Data("wrong".utf8), digest: digest) }
        #expect(throws: CloudSyncFailure.self) { try cache.url("../secret") }
        try FileManager.default.removeItem(at: cache.url(digest))
        #expect(throws: CloudSyncFailure.self) { try cache.read(digest, bytes: bytes.count) }
    }

    @Test func malformedPayloadAndCorruptJournalFailClosed() throws {
        var value = version()
        value.schema = 2
        #expect(throws: CloudSyncFailure.self) { try value.validate() }
        value.schema = 1; value.sourceURL = "http://example.invalid/token"
        #expect(throws: CloudSyncFailure.self) { try value.validate() }
        value.sourceURL = nil; value.resources = [.init(key: "rule:test", digest: String(repeating: "0", count: 64), bytes: Int.max)]
        #expect(throws: CloudSyncFailure.self) { try value.validate() }
        let storage = MemorySubscriptionStorage()
        try storage.write(Data("corrupt".utf8), for: CloudSyncJournal.key("A"))
        #expect(throws: CloudSyncFailure.self) { try CloudSyncJournal.load(account: "A", storage: storage) }
    }

    @Test func providerSubscriptionRestoresOfflineWithAllBytes() async throws {
        let a = repository(), b = repository(), cache = try cache()
        let original = Data(PrototypeSelfCheck.fixture.replacingOccurrences(of: "rules: [\"MATCH,TEST-SELECT\"]", with: """
        rule-providers:
          Domains: {type: http, behavior: domain, url: 'https://example.invalid/rules.yaml'}
        rules: ['RULE-SET,Domains,TEST-SELECT', 'MATCH,TEST-SELECT']
        """).utf8)
        let bytes = Data("payload:\n  - example.invalid\n".utf8)
        let digest = ConfigurationResourceStore.digest(bytes)
        let resource = ConfigurationSnapshot.Resource(key: "rule:Domains", digest: digest, bytes: bytes.count)
        try cache.put(bytes, digest: digest)
        // Model a normal import: uncommitted bytes live in import staging until
        // add commits the index. Unreferenced vault chunks are intentionally GC'd.
        let source = try ConfigurationResourceStore.stage([(resource.key, bytes)], original: original)
        let id = try a.add(.init(source: source), fileName: "Providers.yaml", nodeCount: 1, groupCount: 1, ruleCount: 2, makeCurrent: false)
        ConfigurationResourceStore.discardPending()
        let value = try await ConfigurationImportWorker.shared.exportCloud(id, repository: a, cache: cache)
        #expect(value.resources == [resource])
        ConfigurationResourceStore.discardPending()
        try await ConfigurationImportWorker.shared.installCloud(value, localID: id, expectedMutation: nil,
            allowCurrent: false, repository: b, cache: cache)
        #expect(try ConfigurationSnapshot.original(b.record(id).source) == original)
        #expect(try ConfigurationResourceStore.load(resource, storage: b.storage) == bytes)
        _ = try b.cleanup()
        #expect(try ConfigurationResourceStore.load(resource, storage: b.storage) == bytes)
    }

    @Test func syncDefaultsOffAndDoesNotStartNetwork() async throws {
        let name = "CloudSyncTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = MemorySubscriptionStorage()
        let store = ICloudSubscriptionSyncStore(defaults: defaults, repository: .init(storage: storage))
        #expect(!store.enabled)
        await store.observe(tunnel: TunnelController(repository: .init(storage: storage), permitsNetwork: false), allowed: false)
        store.enable()
        #expect(!store.enabled && storage.items.isEmpty)
    }

    @Test func supportedYAMLAndURIFormatsRestoreWithoutChangingSourceOrRuntime() async throws {
        let links = """
        vless://11111111-1111-4111-8111-111111111111@node.example.invalid:443?security=tls&type=grpc&serviceName=example#VLESS
        hysteria2://FICTIONAL-ONLY@node.example.invalid:443?sni=node.example.invalid#HY2
        tuic://11111111-1111-4111-8111-111111111111:FICTIONAL-ONLY@node.example.invalid:443?sni=node.example.invalid&congestion_control=bbr&udp_relay_mode=native#TUIC
        """
        let fixtures = CompatibilitySamples.all.filter(\.usable).map { ($0.id, Data($0.yaml.utf8)) }
            + [("URI-list", Data(links.utf8)), ("Base64-list", Data(Data(links.utf8).base64EncodedString().utf8))]
        for (name, original) in fixtures {
            let a = repository(), b = repository(), cache = try cache()
            defer { try? FileManager.default.removeItem(at: cache.directory) }
            let prepared = try PrototypeConfiguration.prepare(original)
            var record = StoredConfiguration(source: original, choices: prepared.catalog.choices)
            record.sourceURL = "https://example.invalid/sub?token=FICTIONAL"
            let id = try a.add(record, fileName: name, nodeCount: prepared.catalog.nodes.count,
                groupCount: prepared.catalog.groups.count, ruleCount: prepared.ruleCount, makeCurrent: false)
            let value = try await ConfigurationImportWorker.shared.exportCloud(id, repository: a, cache: cache)
            try await ConfigurationImportWorker.shared.installCloud(value, localID: id, expectedMutation: nil,
                allowCurrent: false, repository: b, cache: cache)
            let restored = try b.record(id)
            #expect(restored.source == original, "Original bytes changed: \(name)")
            #expect(restored.sourceURL == record.sourceURL)
            let after = try PrototypeConfiguration.prepare(restored.source, choices: restored.choices)
            let beforeJSON = try #require(JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as? NSDictionary)
            let afterJSON = try #require(JSONSerialization.jsonObject(with: Data(after.runtimeJSON.utf8)) as? NSDictionary)
            #expect(beforeJSON == afterJSON, "Runtime meaning changed: \(name)")
            #expect(try b.index()?.activeID == nil)
            #expect(restored.certificateConsentDigest == nil)
        }
    }
}
