import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct HomeRoutingOptimizationTests {
    @Test func fastValidationMatchesReviewAndRetainsChoices() async throws {
        var root = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        var nodes = root["proxies"] as! [[String: Any]]
        var second = nodes[0]; second["name"] = "TEST-ALT"; nodes.append(second)
        root["proxies"] = nodes
        root["proxy-groups"] = [["name": "TEST-SELECT", "type": "select", "proxies": ["TEST-HY2", "TEST-ALT"]]]
        let source = try JSONSerialization.data(withJSONObject: root)
        let worker = ConfigurationImportWorker.shared
        let stored = StoredConfiguration(source: source, choices: ["TEST-SELECT": "TEST-ALT"])
        let candidate = try await worker.routingCandidate(.smart, stored: stored)
        let fast = try await worker.validateRouting(candidate, choices: stored.choices)
        let full = try await worker.validate(candidate, choices: stored.choices)
        #expect(fast.runtimeJSON == full.prepared.runtimeJSON)
        #expect(fast.catalog.choices["TEST-SELECT"] == "TEST-ALT")
        let reloaded = try await worker.prepareStored(.init(source: fast.source, choices: fast.catalog.choices))
        #expect(reloaded.runtimeJSON == fast.runtimeJSON)
        do {
            _ = try await worker.validateRouting(Data((PrototypeSelfCheck.fixture + "\nunsupported-example: true").utf8), choices: [:])
            Issue.record("Fast path accepted unsupported configuration")
        } catch { }
    }

    @Test func pendingSelectionPrecedesCommitAndRejectsRepeatedTaps() async throws {
        let (repository, store) = try await fixture(PrototypeSelfCheck.fixture)
        let before = try repository.record(store.id)
        store.changeRouting(.smart, applyImmediately: true)
        #expect(store.pendingRouting == .smart)
        #expect(store.routing == .subscription)
        #expect(store.working)
        store.changeRouting(.subscription, applyImmediately: true)
        #expect(store.pendingRouting == .smart)
        try await finish(store)
        #expect(store.pendingRouting == nil)
        #expect(store.routing == .smart)
        #expect(store.review == nil && store.message == nil)
        let saved = try repository.record(store.id)
        #expect(try ConfigurationRouting.mode(in: saved.source) == .smart)
        #expect((saved.revisionNumber ?? 1) == (before.revisionNumber ?? 1) + 1)
    }

    @Test func failureClearsIntentWithoutChangingSavedMode() async throws {
        let source = PrototypeSelfCheck.fixture.replacingOccurrences(of: "MATCH,TEST-SELECT", with: "MATCH,DIRECT")
        let (repository, store) = try await fixture(source)
        let before = try repository.record(store.id)
        store.changeRouting(.smart, applyImmediately: true)
        #expect(store.pendingRouting == .smart)
        try await finish(store)
        #expect(store.pendingRouting == nil && store.routing == .subscription)
        #expect(store.message != nil && store.review == nil)
        #expect(try repository.record(store.id).revisionID == before.revisionID)
        #expect(try repository.record(store.id).source == before.source)
    }

    private func fixture(_ yaml: String) async throws -> (SubscriptionRepository, SubscriptionMaintenanceStore) {
        let repository = SubscriptionRepository(storage: MemorySubscriptionStorage())
        let prepared = try PrototypeConfiguration.prepare(Data(yaml.utf8))
        _ = try repository.add(.init(source: prepared.source, choices: prepared.catalog.choices), fileName: "Example.yaml",
            nodeCount: prepared.catalog.nodes.count, groupCount: prepared.catalog.groups.count, ruleCount: prepared.ruleCount, makeCurrent: true)
        let tunnel = TunnelController(repository: repository, permitsNetwork: false)
        await tunnel.refresh()
        let id = try #require(tunnel.activeSubscriptionID)
        let store = SubscriptionMaintenanceStore(id: id, tunnel: tunnel)
        await store.loadRouting()
        return (repository, store)
    }
    private func finish(_ store: SubscriptionMaintenanceStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while store.working && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!store.working)
    }
}
