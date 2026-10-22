import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct PriorityCompatibilityTests {
    @Test func pluginsHostsPoliciesAndLoadBalanceReachIOSCore() async throws {
        for id in ["ss-plugins-balance", "dns-policy-hosts", "node-connection-options"] {
            let sample = try #require(CompatibilitySamples.all.first { $0.id == id })
            let raw = Data(sample.yaml.utf8)
            let result = try await ConfigurationImportWorker.shared.validate(raw)
            #expect(result.report.canUse)
            #expect(result.prepared.source == raw)
            if id == "ss-plugins-balance" {
                #expect(result.prepared.catalog.groups[0].kind == "load-balance")
                #expect(!result.prepared.catalog.groups[0].allowsSelection)
                #expect(result.prepared.insecureNodeCount == 1)
            }
        }
    }
    @Test func largeImportRetainsAllMembersAndSavedSelection() async throws {
        let nodes: [[String: Any]] = (0..<512).map { i in
            ["name": "N\(i)", "type": "ss", "server": "node.example.invalid", "port": 443,
             "cipher": "aes-128-gcm", "password": "FICTIONAL-ONLY"]
        }
        let groups: [[String: Any]] = (0..<64).map { i in
            ["name": "G\(i)", "type": "select", "include-all-proxies": true, "filter": "^N"]
        }
        let rules = (0..<8191).map { "DOMAIN,d\($0).example.invalid,DIRECT" } + ["MATCH,G0"]
        let raw = try JSONSerialization.data(withJSONObject: ["proxies": nodes, "proxy-groups": groups, "rules": rules])
        let start = ContinuousClock.now
        let result = try await ConfigurationImportWorker.shared.validate(raw, choices: ["G0": "N511"])
        print("Large iOS simulator import, including full diagnostics + preflight: \(start.duration(to: .now))")
        #expect(result.report.canUse)
        #expect(result.prepared.catalog.nodes.count == 512)
        #expect(result.prepared.catalog.groups.count == 64)
        #expect(result.prepared.catalog.groups.allSatisfy { $0.members.count == 512 })
        #expect(result.prepared.ruleCount == 8192)
        #expect(result.prepared.catalog.choices["G0"] == "N511")
    }
}
