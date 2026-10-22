import Foundation
import NetworkExtension
import Network
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct ProbeExperienceTests {
    // Closed loopback port: no credentials, public DNS, external server or VPN.
    private func source(insecure: Bool = false, secondPort: UInt16 = 9) -> Data {
        Data("""
        proxies:
          - {name: A, type: trojan, server: 127.0.0.1, port: 9, password: SYNTHETIC, skip-cert-verify: \(insecure)}
          - {name: B, type: trojan, server: 127.0.0.1, port: \(secondPort), password: SYNTHETIC, skip-cert-verify: \(insecure)}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [A, B]}
        rules: ['MATCH,SELECT']
        """.utf8)
    }
    private func controller(insecure: Bool = false, secondPort: UInt16 = 9,
                            storage: MemorySubscriptionStorage = MemorySubscriptionStorage()) async throws -> (TunnelController, SubscriptionRepository, UUID) {
        let repo = SubscriptionRepository(storage: storage)
        let id = try repo.add(StoredConfiguration(source: source(insecure: insecure, secondPort: secondPort)), fileName: "A.yaml",
            nodeCount: 2, groupCount: 1, ruleCount: 1, makeCurrent: true)
        let tunnel = TunnelController(repository: repo, permitsNetwork: true,
            network: NetworkAvailability(initialStatus: .available, monitorSystem: false))
        await tunnel.refresh()
        #expect(tunnel.hasConfiguration && tunnel.canTestBatch && tunnel.canTestPing)
        #expect(!tunnel.hasProfile && !tunnel.isTunnelActive)
        return (tunnel, repo, id)
    }
    private func finish(_ store: BatchProbeStore) async throws {
        for _ in 0..<300 {
            if !store.isRunning { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Loopback tests failed to finish within six seconds")
    }
    @Test func selectingDuringBatchKeepsCompletedAndInFlightResults() async throws {
        let server = try StalledProbeServer()
        defer { server.stop() }
        let port = try await server.readyPort()
        let (tunnel, repo, _) = try await controller(secondPort: port)
        let store = tunnel.batchProbes
        store.start(using: tunnel)
        for _ in 0..<200 {
            if store.finishedCount == 1 && store.results[1].state == .testing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.isRunning && store.finishedCount == 1)
        let date = store.date, completedAt = store.results[0].testedAt
        let identity = tunnel.configurationID
        #expect(tunnel.canSelectMember)
        #expect(await tunnel.selectMember(group: 0, member: 1, expectedConfigurationID: identity))
        #expect(tunnel.selectedNode == "B" && tunnel.configurationID != identity)
        #expect(store.isRunning && store.isTestingAllNodes && store.targetCount == 2)
        #expect(store.date == date && store.results[0].testedAt == completedAt)
        #expect(store.finishedCount == 1 && store.results[1].state == .testing)
        #expect(await tunnel.selectMember(group: 0, member: 0, expectedConfigurationID: tunnel.configurationID))
        #expect(store.isRunning && store.results[0].testedAt == completedAt)
        // A real subscription change still clears this run and ignores late completions.
        let other = try repo.add(StoredConfiguration(source: source()), fileName: "Other.yaml",
            nodeCount: 2, groupCount: 1, ruleCount: 1, makeCurrent: false)
        await tunnel.activateSubscription(other, reconnect: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.phase == .idle && store.date == nil && store.targetCount == 0)
        #expect(store.results.allSatisfy { $0.testedAt == nil && $0.state == .waiting })
        #expect(!tunnel.hasProfile && !tunnel.isTunnelActive)
    }
    @Test func failedSelectionDoesNotCancelRunningBatch() async throws {
        let server = try StalledProbeServer()
        defer { server.stop() }
        let storage = MemorySubscriptionStorage()
        let (tunnel, _, id) = try await controller(secondPort: await server.readyPort(), storage: storage)
        let store = tunnel.batchProbes
        store.start(using: tunnel)
        storage.failingWriteKey = SubscriptionRepository.recordKey(id)
        #expect(!tunnel.isTunnelActive && tunnel.canSelectMember)
        let identity = tunnel.configurationID, date = store.date
        #expect(!(await tunnel.selectMember(group: 0, member: 1, expectedConfigurationID: identity)))
        #expect(tunnel.configurationID == identity && tunnel.selectedNode == "A")
        #expect(store.isRunning && store.date == date && store.targetCount == 2)
        #expect(tunnel.canSelectMember)
        store.cancel(using: tunnel)
        #expect(store.phase == .cancelled)
    }
    @Test func individualRequestsAppendAndDoNotBecomeAnAllNodesRun() async throws {
        let (tunnel, _, _) = try await controller()
        let store = tunnel.batchProbes
        store.start(using: tunnel, node: 0)
        #expect(!tunnel.canTestBatch && tunnel.canEnqueueNodeProbe)
        #expect(!store.canEnqueue(0) && store.canEnqueue(1))
        store.start(using: tunnel, node: 1)
        store.start(using: tunnel, node: 0) // duplicate must not reset the first request
        #expect(store.targetCount == 2 && store.runScope == .selectedNodes)
        #expect(!store.isTestingAllNodes)
        try await finish(store)
        #expect(store.finishedCount == 2)
        #expect(store.results.allSatisfy { $0.testedAt != nil })
        #expect(!tunnel.hasProfile && !tunnel.isTunnelActive)
    }
    @Test func cancellingQueuedIndividualsDoesNotOverwriteNextRun() async throws {
        let (tunnel, _, _) = try await controller()
        let store = tunnel.batchProbes
        store.start(using: tunnel, node: 0)
        store.start(using: tunnel, node: 1)
        store.cancel(using: tunnel)
        store.start(using: tunnel, node: 1)
        try await finish(store)
        #expect(store.targetCount == 1 && store.runScope == .node(1))
        #expect(store.results[0].state == .cancelled)
        #expect(store.results[1].testedAt != nil)
    }
    @Test func disconnectedSingleBatchAndHomeNeverCreateVPN() async throws {
        let (tunnel, _, _) = try await controller()
        tunnel.batchProbes.start(using: tunnel, node: 1)
        #expect(!tunnel.batchProbes.isTesting(0))
        #expect(tunnel.batchProbes.isRunning && !tunnel.batchProbes.isTestingAllNodes)
        try await finish(tunnel.batchProbes)
        #expect(tunnel.batchProbes.runScope == .node(1))
        #expect(tunnel.batchProbes.finishedCount == 1 && tunnel.batchProbes.targetCount == 1)
        #expect(tunnel.batchProbes.results[0].testedAt == nil)
        #expect(tunnel.batchProbes.results[1].state == .failed)
        tunnel.batchProbes.start(using: tunnel)
        #expect(tunnel.batchProbes.isTestingAllNodes)
        try await finish(tunnel.batchProbes)
        #expect(!tunnel.batchProbes.isTestingAllNodes)
        #expect(tunnel.batchProbes.results.allSatisfy { $0.state == .failed && $0.testedAt != nil })
        #expect(tunnel.batchProbes.runScope == .allNodes)
        #expect(tunnel.batchProbes.finishedCount == 2 && tunnel.batchProbes.targetCount == 2)
        // A single retest must not count the other node's retained result as this run's work.
        let previousDate = tunnel.batchProbes.results[0].testedAt
        tunnel.batchProbes.start(using: tunnel, node: 1)
        #expect(tunnel.batchProbes.finishedCount == 0 && tunnel.batchProbes.targetCount == 1)
        try await finish(tunnel.batchProbes)
        #expect(tunnel.batchProbes.runScope == .node(1) && tunnel.batchProbes.finishedCount == 1)
        #expect(tunnel.batchProbes.results[0].testedAt == previousDate)
        await tunnel.testPing()
        #expect(tunnel.pingReport?.outcome == .failed)
        #expect(!tunnel.hasProfile && !tunnel.isTunnelActive)
        await tunnel.refresh() // Reopening/reloading while disconnected keeps the measured result.
        #expect(tunnel.pingReport?.outcome == .failed)
    }
    @Test func configurationAndRevisionScopeClearButSelectionRetainsResults() async throws {
        let (tunnel, repo, first) = try await controller()
        tunnel.batchProbes.start(using: tunnel)
        try await finish(tunnel.batchProbes)
        let date = tunnel.batchProbes.date
        let changed = await tunnel.selectMember(group: 0, member: 1, expectedConfigurationID: tunnel.configurationID)
        #expect(changed && tunnel.selectedNode == "B")
        #expect(tunnel.batchProbes.date == date)
        #expect(tunnel.batchProbes.results.allSatisfy { $0.testedAt != nil })
        var sameContent = StoredConfiguration(source: source())
        sameContent.sourceURL = "https://subscription.example.invalid/not-fetched"
        let other = try repo.add(sameContent, fileName: "B.yaml", nodeCount: 2, groupCount: 1, ruleCount: 1, makeCurrent: false)
        #expect(first != other)
        await tunnel.activateSubscription(other, reconnect: false)
        #expect(tunnel.activeSubscriptionID == other)
        #expect(tunnel.batchProbes.date == nil && tunnel.batchProbes.phase == .idle)
        #expect(tunnel.batchProbes.runScope == nil && tunnel.batchProbes.targetCount == 0)
        #expect(tunnel.batchProbes.results.allSatisfy { $0.testedAt == nil && $0.milliseconds == nil })
        tunnel.batchProbes.start(using: tunnel)
        await tunnel.activateSubscription(first, reconnect: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(tunnel.batchProbes.results.allSatisfy { $0.testedAt == nil }) // No late callback.
        let old = try repo.record(first)
        try repo.replace(first, expected: old, source: old.source + Data("\n# new revision\n".utf8),
            choices: old.choices, sourceURL: nil, nodeCount: 2, groupCount: 1, ruleCount: 1)
        await tunnel.refresh()
        #expect(tunnel.batchProbes.phase == .idle && tunnel.batchProbes.date == nil)
    }
    @Test func cancellationNetworkAndConsentHaveNoConnectionSideEffects() async throws {
        let (tunnel, repo, id) = try await controller(insecure: true)
        tunnel.batchProbes.start(using: tunnel, node: 1)
        let request = try #require(tunnel.certificateApproval)
        #expect(!request.connects && !tunnel.batchProbes.isRunning)
        #expect(try repo.record(id).certificateConsentDigest == nil)
        await tunnel.approveCertificates(request)
        try await finish(tunnel.batchProbes)
        #expect(tunnel.batchProbes.results[1].testedAt != nil)
        #expect(!tunnel.hasProfile && !tunnel.isTunnelActive)
        tunnel.batchProbes.start(using: tunnel)
        tunnel.cancelForegroundProbes()
        try await Task.sleep(for: .milliseconds(100))
        #expect(tunnel.batchProbes.phase == .cancelled)
        #expect(tunnel.batchProbes.results.allSatisfy { $0.state == .cancelled })
        tunnel.network.setPreviewStatus(.offline)
        #expect(!tunnel.canTestPing && !tunnel.canTestBatch)
        tunnel.batchProbes.start(using: tunnel)
        #expect(!tunnel.batchProbes.isRunning)
    }
    @Test func individualIPCDoesNotFallbackToLegacyAllNodes() throws {
        let id = UUID()
        func command(_ version: Int, _ index: Int?) -> BatchProbeCommand {
            .init(version: version, action: .start, batchID: id, sessionID: id, configurationID: "SYNTHETIC", nodeIndex: index)
        }
        #expect(command(1, nil).isSupported(nodeCount: 2))
        #expect(command(2, 1).isSupported(nodeCount: 2))
        for invalid in [command(1, 1), command(2, nil), command(2, -1), command(2, 2), command(3, 1)] {
            #expect(!invalid.isSupported(nodeCount: 2))
        }
        let roundTrip = try JSONDecoder().decode(BatchProbeCommand.self, from: JSONEncoder().encode(command(2, 1)))
        #expect(roundTrip.version == 2 && roundTrip.nodeIndex == 1)
    }
    @Test func providerOverridesAreUsedForStandaloneNodes() async throws {
        let raw = Data("""
        proxy-providers:
          P:
            type: inline
            payload:
              - {name: ORIGINAL, type: trojan, server: 127.0.0.1, port: 9, password: SYNTHETIC}
            override: {additional-prefix: 'P-', skip-cert-verify: true}
        proxy-groups:
          - {name: SELECT, type: select, use: [P]}
        rules: ['MATCH,SELECT']
        """.utf8)
        let prepared = try await ConfigurationImportWorker.shared.prepareStored(StoredConfiguration(source: raw))
        let nodes = try await ConfigurationImportWorker.shared.standaloneNodes(prepared)
        let value = try #require(try JSONSerialization.jsonObject(with: Data(nodes[0].utf8)) as? [String: Any])
        #expect(nodes.count == 1 && value["name"] as? String == "P-ORIGINAL")
        #expect(value["skip-cert-verify"] as? Bool == true)
    }
}

/// Accepts loopback TCP without answering TLS, keeping one test in flight deterministically.
nonisolated private final class StalledProbeServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "HorizonTests.stalled-probe")
    private let lock = NSLock()
    private var port: UInt16?
    private var connections: [NWConnection] = []
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            lock.withLock { self.port = self.listener.port?.rawValue }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            lock.withLock { self.connections.append(connection) }
            connection.start(queue: queue)
        }
        listener.start(queue: queue)
    }
    func readyPort() async throws -> UInt16 {
        for _ in 0..<200 {
            if let port = lock.withLock({ port }) { return port }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "StalledProbeServer", code: 1)
    }
    func stop() {
        listener.cancel()
        lock.withLock { for connection in connections { connection.cancel() }; connections = [] }
    }
}
