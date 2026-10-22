import Foundation

/// Synthetic storage/parser regressions; no Keychain, network or VPN access.
enum SubscriptionMaintenanceSelfCheck {
    static func run() -> PrototypeSelfCheck.Result {
        var failures: [String] = [], total = 0
        func check(_ name: String, _ body: () throws -> Bool) {
            total += 1
            do { if try !body() { failures.append(name) } } catch { failures.append(name) }
        }
        let source = Data(CompatibilityFixture.yaml.utf8)
        func add(_ repo: SubscriptionRepository, url: String? = "https://example.invalid/sub?token=FICTIONAL") throws -> UUID {
            var record = StoredConfiguration(source: source)
            record.sourceURL = url
            return try repo.add(record, fileName: "example.yaml", nodeCount: 2, groupCount: 1, ruleCount: 5, makeCurrent: true)
        }
        func replace(_ repo: SubscriptionRepository, id: UUID, expected: StoredConfiguration, number: Int) throws {
            try repo.replace(id, expected: expected, source: source + Data("\n# revision \(number)\n".utf8), choices: expected.choices,
                sourceURL: expected.sourceURL, nodeCount: 2, groupCount: 1, ruleCount: 5)
        }
        for sample in CompatibilitySamples.all {
            check("fixture-" + sample.id) { ConfigurationCompatibility.inspect(Data(sample.yaml.utf8)).canUse == sample.usable }
        }
        check("desktop-controller-adapted-without-changing-proxy-runtime") {
            let sample = CompatibilitySamples.all.first { $0.id == "desktop-controller" }!
            let data = Data(sample.yaml.utf8)
            let prepared = try PrototypeConfiguration.prepare(data)
            let baseline = try PrototypeConfiguration.prepare(source)
            let report = ConfigurationCompatibility.inspect(data)
            let text = (prepared.adaptations + report.findings.map(\.detail)).joined()
            return prepared.runtimeJSON == baseline.runtimeJSON && prepared.source == data && report.canUse
                && text.contains("external-controller") && text.contains("secret")
                && !text.contains("FICTIONAL-CONTROLLER-ONLY") && !text.contains("127.0.0.1:19090")
                && !prepared.runtimeJSON.contains("FICTIONAL-CONTROLLER-ONLY")
        }
        for field in PrototypeConfiguration.desktopControllerFields {
            check("desktop-controller-empty-" + field) {
                let data = source + Data(("\n" + field + ": ''\n").utf8)
                return try PrototypeConfiguration.prepare(data).runtimeJSON == PrototypeConfiguration.prepare(source).runtimeJSON
            }
            check("desktop-controller-invalid-type-" + field) {
                let data = source + Data(("\n" + field + ": {private: PRIVATE-VALUE}\n").utf8)
                let report = ConfigurationCompatibility.inspect(data)
                return (try? PrototypeConfiguration.prepare(data)) == nil && !report.canUse
                    && !report.findings.map(\.detail).joined().contains("PRIVATE-VALUE")
            }
        }
        check("desktop-adaptation-does-not-hide-other-incompatibilities") {
            let sample = CompatibilitySamples.all.first { $0.id == "desktop-controller" }!
            let data = Data((sample.yaml + "\nexternal-controller-tls: '127.0.0.1:19443'\n").utf8)
            let report = ConfigurationCompatibility.inspect(data)
            return !report.canUse && (try? PrototypeConfiguration.prepare(data)) == nil
                && report.findings.contains { $0.level == .adapted && $0.detail.contains("external-controller") }
        }
        check("all-mixed-unsupported-locations-and-redaction") {
            let sample = CompatibilitySamples.all.first { $0.id == "unsupported-mixed" }!
            let report = ConfigurationCompatibility.inspect(Data(sample.yaml.utf8))
            let locations = Set(report.findings.filter { $0.level == .blocked }.map(\.location))
            let text = report.findings.map { $0.detail + $0.location }.joined()
            return ["顶层 · sniffer", "节点 1", "节点 2", "依赖", "规则 2"].allSatisfy { locations.contains($0) }
                && !text.contains("FICTIONAL-ONLY") && !text.contains("node.example.invalid") && !text.contains("EXAMPLE-SS")
        }
        check("multiple-errors-within-one-node-and-dns") {
            let yaml = CompatibilityFixture.yaml
                .replacingOccurrences(of: "up: 10", with: "up: INVALID")
                .replacingOccurrences(of: "down: 50", with: "down: INVALID")
                .replacingOccurrences(of: "enable: true", with: "enable: false")
                .replacingOccurrences(of: "https://1.1.1.1/dns-query", with: "quic://example.invalid")
                .replacingOccurrences(of: "enhanced-mode: fake-ip", with: "enhanced-mode: fake-ip\n  use-system-hosts: true\n  fake-ip-filter-mode: rule")
            let report = ConfigurationCompatibility.inspect(Data(yaml.utf8))
            let locations = Set(report.findings.filter { $0.level == .blocked }.map(\.location))
            return ["节点 1 · up", "节点 1 · down", "DNS · enable", "DNS · nameserver", "DNS · use-system-hosts", "DNS · fake-ip-filter-mode"].allSatisfy { locations.contains($0) }
        }
        check("diff-redacts-secrets-but-reports-field-change") {
            let next = Data(CompatibilityFixture.yaml.replacingOccurrences(of: "TEST-ONLY-PASSWORD", with: "CHANGED-FICTIONAL-PASSWORD").utf8)
            let result = try SubscriptionChangeSummary.compare(source, next).joined()
            return !result.contains("example.invalid") && !result.contains("TEST-HY2") && result.contains("字段变化 1") && !result.contains("CHANGED-FICTIONAL-PASSWORD")
        }
        check("old-record-without-optional-metadata-decodes") {
            let old: [String: Any] = ["format": "clash-vault-v2", "source": source.base64EncodedString(), "choices": [:]]
            let record = try JSONDecoder().decode(StoredConfiguration.self, from: JSONSerialization.data(withJSONObject: old))
            return record.source == source && record.sourceURL == nil && record.history == nil && record.startupConfirmed == nil
        }
        check("url-provenance-prevents-accidental-dedup") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let a = try add(repo), b = try add(repo, url: "https://example.invalid/other"), c = try add(repo, url: nil)
            let same = try add(repo)
            return try a != b && b != c && a == same && repo.library().entries.count == 3
        }
        check("url-secret-not-in-library-index") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            let text = String(decoding: storage.items[SubscriptionRepository.indexKey]!, as: UTF8.self)
            return try !text.contains("FICTIONAL") && !text.contains("example.invalid") && repo.record(id).sourceURL != nil
        }
        check("transaction-index-failure-keeps-current-and-history") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo), old = try repo.record(id), before = storage.items
            storage.failingWriteKey = SubscriptionRepository.indexKey
            do { try replace(repo, id: id, expected: old, number: 2); return false } catch { }
            return try before == storage.items && repo.activeRecord()?.source == old.source
        }
        check("stale-preview-cannot-overwrite-new-revision") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo), old = try repo.record(id)
            try replace(repo, id: id, expected: old, number: 2)
            let before = storage.items
            do { try replace(repo, id: id, expected: old, number: 3); return false } catch SubscriptionError.staleRevision { }
            return storage.items == before
        }
        check("history-bounded-and-last-usable-pinned") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            try repo.markUsable(id, source: source, choices: [:])
            for revision in 2...9 { try replace(repo, id: id, expected: repo.record(id), number: revision) }
            let latest = try repo.record(id)
            return try latest.history?.count == 5 && latest.lastUsable?.source == source && latest.lastUsable?.verifiedAt != nil && latest.revisionNumber == 9 && (repo.index()?.format) == "clash-subscriptions-v2" && latest.verifiedAt == nil && latest.startupConfirmed == false && storage.items.count == 2
        }
        check("manual-rollback-is-new-revision-and-keeps-failed-candidate") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo), old = try repo.record(id)
            try replace(repo, id: id, expected: old, number: 2)
            let candidate = try repo.record(id)
            try repo.replace(id, expected: candidate, source: old.source, choices: old.choices, sourceURL: old.sourceURL, nodeCount: 2, groupCount: 1, ruleCount: 5)
            let restored = try repo.record(id)
            return restored.source == old.source && restored.revisionNumber == 3 && restored.history?.first?.source == candidate.source
        }
        check("startup-proof-does-not-mark-node-usable") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            try repo.markStartupConfirmed(id, source: source, choices: [:])
            let value = try repo.record(id)
            return value.startupConfirmed == true && value.verifiedAt == nil
        }
        check("stale-ping-cannot-mark-new-revision-usable") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            try replace(repo, id: id, expected: repo.record(id), number: 2)
            try repo.markUsable(id, source: source, choices: [:])
            return try repo.record(id).verifiedAt == nil
        }
        check("metadata-only-revision-retains-startup-proof") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            try repo.markStartupConfirmed(id, source: source, choices: [:])
            let old = try repo.record(id)
            try repo.replace(id, expected: old, source: source, choices: [:], sourceURL: "https://example.invalid/new", nodeCount: 2, groupCount: 1, ruleCount: 5)
            return try repo.record(id).startupConfirmed == true
        }
        check("cleanup-failure-after-commit-new-record-remains-readable") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            storage.failingRemovals = [SubscriptionRepository.recordKey(id)]
            try replace(repo, id: id, expected: repo.record(id), number: 2)
            guard try repo.activeRecord()?.revisionNumber == 2, try repo.library().cleanupCount == 1 else { return false }
            storage.failingRemovals = []
            return try repo.cleanup().cleanupCount == 0 && repo.activeRecord()?.revisionNumber == 2
        }
        check("delete-revision-record-erases-all-history-and-url") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo)
            try replace(repo, id: id, expected: repo.record(id), number: 2)
            _ = try repo.delete([id])
            return storage.items.count == 1 && storage.items[SubscriptionRepository.indexKey] != nil
        }
        return .init(passed: total - failures.count, total: total, failures: failures)
    }
}
