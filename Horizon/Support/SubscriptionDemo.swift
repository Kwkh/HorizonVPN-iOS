import Foundation

#if DEBUG
/// Opt-in UI checks use an isolated in-memory library and cannot start a VPN.
@MainActor enum SubscriptionDemo {
    static func controller() -> TunnelController {
        let storage = MemorySubscriptionStorage()
        let repository = SubscriptionRepository(storage: storage)
        let fixtures = ProcessInfo.processInfo.environment["CLASH_STARTUP_AUDIT"] == "empty"
            ? [] : [PrototypeSelfCheck.fixture, CompatibilityFixture.yaml]
        for (index, yaml) in fixtures.enumerated() {
            if let prepared = try? PrototypeConfiguration.prepare(Data(yaml.utf8)) {
                _ = try? repository.add(.init(source: prepared.source, choices: prepared.catalog.choices),
                    fileName: index == 0 ? "示例订阅 A.yaml" : "示例订阅 B.yaml",
                    nodeCount: prepared.catalog.nodes.count, groupCount: prepared.catalog.groups.count,
                    ruleCount: prepared.ruleCount, makeCurrent: index == 0)
            }
        }
        let audit = ProcessInfo.processInfo.environment["CLASH_NETWORK_AUDIT"]
        let network = NetworkAvailability(initialStatus: audit == "offline" || audit == "recover" ? .offline : .available,
                                          monitorSystem: false)
        if audit == "recover" || audit == "drop" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(audit == "recover" ? 12 : 8))
                network.setPreviewStatus(audit == "recover" ? .available : .offline)
            }
        }
        return TunnelController(repository: repository, permitsNetwork: false, network: network)
    }
}
#endif
