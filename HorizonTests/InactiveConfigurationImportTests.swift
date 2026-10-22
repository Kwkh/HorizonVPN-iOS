import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct InactiveConfigurationImportTests {
    private var sample: Data {
        Data(CompatibilitySamples.all.first { $0.id == "disabled-options" }!.yaml.utf8)
    }

    @Test func disabledBlocksAndEmptyDefaultsReachNativeCore() async throws {
        let checked = try await ConfigurationImportWorker.shared.validate(sample)
        #expect(checked.report.canUse)
        #expect(checked.prepared.source == sample)
        let runtime = try #require(JSONSerialization.jsonObject(with: Data(checked.prepared.runtimeJSON.utf8)) as? [String: Any])
        #expect((runtime["tun"] as? [String: Any])?["enable"] as? Bool == true)
        #expect(runtime["sniffer"] == nil && runtime["hosts"] == nil && runtime["listeners"] == nil)
        let node = try #require((runtime["proxies"] as? [[String: Any]])?.first)
        #expect(node["network"] as? String == "tcp")
        #expect(node["packet-encoding"] == nil && node["smux"] == nil && node["tfo"] == nil)
        #expect(checked.report.findings.contains { $0.level == .adapted && $0.detail.contains("sniffer.enable: false") })
    }

    @Test func remoteSnapshotReceivesSameAdaptationAndPreservesSource() async throws {
        let source = Data("""
        proxy-providers:
          P: {type: http, url: 'https://example.invalid/nodes'}
        proxy-groups:
          - {name: SELECT, type: select, use: [P]}
        rules: ['MATCH,SELECT']
        sniffer: {enable: false}
        """.utf8)
        let body = Data("""
        proxies:
          - {name: EXAMPLE, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL, network: '', smux: {enabled: false}, tfo: false}
        """.utf8)
        let snapshot = try ConfigurationResourceStore.stage([("proxy:P", body)], original: source)
        let checked = try await ConfigurationImportWorker.shared.validate(snapshot)
        #expect(checked.report.canUse)
        #expect(try ConfigurationSnapshot.original(checked.prepared.source) == source)
        #expect(!checked.prepared.runtimeJSON.contains("\"smux\""))
        #expect(checked.prepared.catalog.resolvedTarget() == "EXAMPLE")
        // Rollback/revalidation follows the same immutable bytes and selected member.
        let again = try await ConfigurationImportWorker.shared.validate(snapshot, choices: ["SELECT": "EXAMPLE"])
        #expect(again.prepared.runtimeJSON == checked.prepared.runtimeJSON)
    }

    @Test func enabledOrAmbiguousOptionsNeverBecomeDisabled() async throws {
        for suffix in ["tun: {enable: true}", "sniffer: {enable: 'false'}", "sniffer: {}",
                       "tun: null", "hosts: {example.invalid: invalid-address}", "listeners: [{}]"] {
            let raw = Data((PrototypeSelfCheck.fixture + "\n" + suffix).utf8)
            do {
                _ = try await ConfigurationImportWorker.shared.validate(raw)
                Issue.record("Unsupported active or ambiguous option accepted")
            } catch let failure as ConfigurationImportWorker.Failure { #expect(!failure.report.canUse) }
        }
    }

    @Test func allSupportedProtocolFixturesKeepExplicitlyDisabledOptionsOff() async throws {
        let nodes = ExtendedCompatibilitySelfCheck.nodes.map { node in
            var value = node
            value["smux"] = ["enabled": false, "protocol": "smux"]
            value["tfo"] = false; value["mptcp"] = false
            return value
        }
        let raw = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
        let checked = try await ConfigurationImportWorker.shared.validate(raw)
        #expect(checked.prepared.catalog.nodes.count == nodes.count)
        #expect(checked.prepared.source == raw)
        #expect(!checked.prepared.runtimeJSON.contains("\"smux\""))
    }
}
