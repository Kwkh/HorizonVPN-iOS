import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct GeneralCompatibilityImportTests {
    private let nodeYAML = """
    proxies:
      - {name: EXAMPLE, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
    """

    @Test func includesAndIntegerStatusReachNativePreflight() async throws {
        let data = Data((nodeYAML + """

        proxy-groups:
          - {name: SELECT, type: select, include-all-proxies: true, expected-status: 204}
        rules: ['MATCH,SELECT']
        dns: {listen: ':1053', nameserver: ['1.1.1.1']}
        """).utf8)
        let checked = try await ConfigurationImportWorker.shared.validate(data)
        #expect(checked.report.canUse)
        #expect(checked.prepared.catalog.groups[0].members == ["EXAMPLE"])
        #expect(checked.prepared.source == data)
        #expect(!checked.prepared.runtimeJSON.contains("include-all"))
        #expect(!checked.prepared.runtimeJSON.contains("\"listen\""))
        #expect(checked.prepared.runtimeJSON.contains("\"expected-status\":\"204\""))
    }

    @Test func nodeBundleDNSKeepsGeoDependencyAndOriginal() async throws {
        let data = Data((nodeYAML + """

        ipv6: false
        dns:
          nameserver: ['223.5.5.5']
          default-nameserver: ['1.1.1.1']
          fallback: ['https://1.1.1.1/dns-query']
          fallback-filter: {geoip: true, geoip-code: CN}
        """).utf8)
        let snapshot = try await ConfigurationImportWorker.shared.resources(data, permitsNetwork: false, deadline: .now.advanced(by: .seconds(30)))
        let checked = try await ConfigurationImportWorker.shared.validate(snapshot)
        #expect(checked.report.canUse)
        #expect(checked.prepared.catalog.groups.count == 1)
        #expect(checked.prepared.runtimeJSON.contains("223.5.5.5"))
        #expect(checked.prepared.runtimeJSON.contains("\"ipv6\":false"))
        #expect(try ConfigurationSnapshot.read(snapshot)?.resources.count == 1)
        #expect(try ConfigurationSnapshot.original(snapshot) == data)
    }
}
