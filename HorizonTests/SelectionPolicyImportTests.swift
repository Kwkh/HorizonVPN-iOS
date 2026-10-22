import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct SelectionPolicyImportTests {
    private func source(_ names: [String], filter: String = "^US") throws -> Data {
        let nodes = names.map { ["name": $0, "type": "trojan", "server": "node.example.invalid", "port": 443, "password": "FICTIONAL-ONLY"] as [String: Any] }
        return try JSONSerialization.data(withJSONObject: [
            "proxy-providers": ["P": ["type": "inline", "payload": nodes, "override": ["additional-prefix": "TEST-", "skip-cert-verify": true]]],
            "proxy-groups": [["name": "SELECT", "type": "select", "use": ["P"], "filter": (filter == "[" ? "[" : "^TEST-" + filter.dropFirst())]],
            "rules": ["MATCH,SELECT"]])
    }
    @Test func effectiveNodesReachNativePreflightAndConsent() async throws {
        let raw = try source(["US-A", "JP-B"])
        let checked = try await ConfigurationImportWorker.shared.validate(raw)
        #expect(checked.report.canUse)
        #expect(checked.prepared.catalog.groups[0].members == ["TEST-US-A"])
        #expect(checked.prepared.insecureNodeCount == 2)
        #expect(!checked.prepared.runtimeJSON.contains("\"override\""))
        #expect(checked.prepared.source == raw)
        #expect(throws: (any Error).self) { try StoredConfiguration(source: raw).requireCertificateConsent(for: checked.prepared) }
    }
    @Test func refreshAndRollbackUseEffectiveMembership() async throws {
        let before = try source(["US-old", "US-stay"]), after = try source(["US-new", "US-stay"])
        let retained = try await ConfigurationImportWorker.shared.validate(after, choices: ["SELECT": "TEST-US-stay"])
        #expect(retained.prepared.catalog.choices["SELECT"] == "TEST-US-stay")
        let removed = try await ConfigurationImportWorker.shared.validate(after, choices: ["SELECT": "TEST-US-old"])
        #expect(removed.prepared.catalog.choices["SELECT"] == "TEST-US-new")
        let rollback = try await ConfigurationImportWorker.shared.validate(before, choices: ["SELECT": "TEST-US-old"])
        #expect(rollback.prepared.catalog.choices["SELECT"] == "TEST-US-old")
        #expect(try SubscriptionChangeSummary.compare(before, after).contains("策略组：已改变"))
    }
    @Test func httpsSnapshotUsesSamePolicyOffline() async throws {
        let original = Data("""
        proxy-providers:
          P:
            type: http
            url: https://subscription.example.invalid/provider.yaml
            filter: '^US'
            override: {additional-prefix: 'P-'}
        proxy-groups:
          - {name: SELECT, type: select, include-all-providers: true, filter: '^P-US'}
        rules: ['MATCH,SELECT']
        """.utf8)
        let body = Data("""
        proxies:
          - {name: US-EXAMPLE, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
          - {name: JP-EXAMPLE, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        """.utf8)
        let staged = try ConfigurationResourceStore.stage([("proxy:P", body)], original: original)
        let checked = try await ConfigurationImportWorker.shared.validate(staged)
        #expect(checked.report.canUse)
        #expect(checked.prepared.catalog.nodes.map(\.name) == ["P-US-EXAMPLE"])
        #expect(checked.prepared.catalog.groups[0].members == ["P-US-EXAMPLE"])
        #expect(try ConfigurationSnapshot.original(staged) == original)
        #expect(!checked.prepared.runtimeJSON.contains("https://subscription.example.invalid"))
    }
    @Test func emptyAndInvalidPatternsNeverBecomeDirect() async throws {
        for pattern in ["^NOT-PRESENT", "["] {
            let raw = try source(["US-A"], filter: pattern)
            do {
                _ = try await ConfigurationImportWorker.shared.validate(raw)
                Issue.record("Invalid/empty policy accepted")
            } catch let failure as ConfigurationImportWorker.Failure { #expect(!failure.report.canUse) }
        }
    }
}
