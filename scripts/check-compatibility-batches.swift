import Foundation
import Hako

@main struct CompatibilityBatchesCheck {
    @MainActor static func main() async throws {
        var total = 0, failures: [String] = []
        func check(_ name: String, _ body: () throws -> Bool) {
            total += 1
            do { if try !body() { failures.append(name) } }
            catch let error as ConfigurationIssue { failures.append(name + " · " + error.detail) }
            catch { failures.append(name + " · code " + String((error as? PrototypeError)?.rawValue ?? 0)) }
        }
        func json(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) }
        let base = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        func document(_ changes: [String: Any]) throws -> Data { try json(base.merging(changes) { _, new in new }) }
        func refuses(_ changes: [String: Any]) -> Bool { (try? PrototypeConfiguration.prepare(document(changes))) == nil }
        check("hy2-default443-userpass") {
            let node = try NodeURI.parse("hy2://FICTIONAL:ONLY@node.example.invalid/?sni=tls.example.invalid", index: 0)
            return node["port"] as? Int == 443 && node["password"] as? String == "FICTIONAL:ONLY"
        }
        for encoded in [false, true] {
            check("comments-in-uri-list-\(encoded)") {
                let text = "# Example only\n\nhy2://FICTIONAL@node.example.invalid\n# End\n"
                let source = encoded ? Data(Data(text.utf8).base64EncodedString().utf8) : Data(text.utf8)
                return try PrototypeConfiguration.prepare(source).catalog.nodes.count == 1
            }
        }
        for (name, data) in [("sing-box", "{\"outbounds\": []}"), ("SIP008", "{\"servers\": []}"), ("WireGuard", "[Interface]\nPrivateKey=FICTIONAL"), ("HTML", "<!DOCTYPE html><html>Example</html>")] {
            check("format-" + name) { ConfigurationCompatibility.inspect(Data(data.utf8)).findings.contains { $0.detail.contains(name) } }
        }
        check("safe-metadata-runtime-and-dns-port") {
            let data = try document(["external-ui": "FICTIONAL", "redir-port": 7893, "profile": ["store-selected": true], "tcp-concurrent": true, "find-process-mode": "off", "dns": ["nameserver": ["1.1.1.1:5353"], "default-nameserver": ["[2606:4700:4700::1111]:53"]]])
            let prepared = try PrototypeConfiguration.prepare(data)
            let root = try JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as! [String: Any]
            return ConfigurationCompatibility.inspect(data).canUse && root["tcp-concurrent"] as? Bool == true && root["redir-port"] == nil && root["external-ui"] == nil && !prepared.runtimeJSON.contains("FICTIONAL")
        }
        let autoGroups: [[String: Any]] = [
            ["name": "TEST-SELECT", "type": "select", "proxies": ["Auto", "Backup", "TEST-HY2"], "icon": "https://example.invalid/icon"],
            ["name": "Auto", "type": "url-test", "proxies": ["TEST-HY2"], "interval": 5, "tolerance": 80],
            ["name": "Backup", "type": "fallback", "proxies": ["TEST-HY2", "DIRECT"], "interval": 900, "lazy": false, "url": "https://example.invalid/check", "expected-status": "200-299/304"]]
        let autoData = try document(["proxy-groups": autoGroups])
        let automatic = try PrototypeConfiguration.prepare(autoData)
        check("auto-group-contract-and-runtime") {
            let runtime = try JSONSerialization.jsonObject(with: Data(automatic.runtimeJSON.utf8)) as! [String: Any]
            let groups = runtime["proxy-groups"] as! [[String: Any]]
            return automatic.catalog.choices == ["TEST-SELECT": "Auto"] && automatic.catalog.resolvedTarget() == nil && automatic.catalog.groups[1].kind == "url-test" && groups[1]["interval"] as? Int == 60 && groups[2]["interval"] as? Int == 900 && groups[2]["lazy"] as? Bool == false && ConfigurationCompatibility.inspect(autoData).canUse
        }
        check("automatic-selection-sanitized-and-not-persisted") {
            let selections = RuntimeGroupChoices.sanitize("{\"proxies\":{\"Auto\":{\"now\":\"TEST-HY2\"},\"Backup\":{\"now\":\"PRIVATE-NAME\"}}}", catalog: automatic.catalog)!
            let names = RuntimeGroupChoices.names(selections, catalog: automatic.catalog)
            return selections == [1: 0] && automatic.catalog.resolvedTarget(runtimeChoices: names) == "TEST-HY2" && automatic.catalog.choices["Auto"] == nil
        }
        for type in ["relay", "unknown"] { check("refuse-group-" + type) { refuses(["proxy-groups": [["name": "TEST-SELECT", "type": type, "proxies": ["TEST-HY2"]]]]) } }
        for url in ["file:///tmp/a", "https://user:pw@example.invalid", "http://example.invalid/#secret"] { check("unsafe-health-url") { refuses(["proxy-groups": [["name": "TEST-SELECT", "type": "url-test", "proxies": ["TEST-HY2"], "url": url]]]) } }
        check("port-network-rules") {
            let prepared = try PrototypeConfiguration.prepare(document(["rules": ["DST-PORT,80/443/8000-9000,TEST-SELECT", "SRC-PORT,53,DIRECT", "NETWORK,UDP,TEST-SELECT", "SRC-IP-CIDR,192.0.2.0/24,DIRECT", "MATCH,TEST-SELECT"]]))
            return prepared.ruleCount == 5
        }
        check("invalid-port-rule") { refuses(["rules": ["DST-PORT,9000-8000,DIRECT", "MATCH,TEST-SELECT"]]) }
        let storage = MemorySubscriptionStorage()
        ConfigurationResourceStore.testStorage = storage
        let repo = SubscriptionRepository(storage: storage)
        let providerBody = Data("proxies:\n  - {name: PROVIDER-A, type: hysteria2, server: provider.example.invalid, port: 443, password: FICTIONAL-ONLY}\n".utf8)
        let ruleBody = Data("payload: ['+.example.invalid']\n".utf8)
        let providerRoot: [String: Any] = [
            "proxy-providers": ["remote": ["type": "http", "url": "https://example.invalid/nodes?token=FICTIONAL", "path": "../../never-read", "interval": 60, "header": ["Authorization": ["Bearer FICTIONAL"]], "health-check": ["enable": true, "interval": 10]]],
            "rule-providers": ["remote": ["type": "http", "behavior": "domain", "url": "https://example.invalid/rules", "format": "yaml", "interval": 60]],
            "proxy-groups": [["name": "TEST-SELECT", "type": "select", "use": ["remote"]]],
            "rules": ["RULE-SET,remote,DIRECT", "MATCH,TEST-SELECT"]]
        let providerSource = try document(providerRoot)
        let bundle = try await SubscriptionResourceLoader.prepare(providerSource, permitsNetwork: false) { request in
            if request.key == "proxy:remote" { precondition(request.headers["Authorization"] == "Bearer FICTIONAL"); return providerBody }
            return ruleBody
        }
        let prepared = try PrototypeConfiguration.prepare(bundle)
        let providerOnlySource = try json(providerRoot.merging(["mode": "rule"]) { _, new in new })
        let providerOnly = try await SubscriptionResourceLoader.prepare(providerOnlySource, permitsNetwork: false) { $0.key == "proxy:remote" ? providerBody : ruleBody }
        check("no-inline-proxies-required") { try PrototypeConfiguration.prepare(providerOnly).catalog.nodes.count == 1 }
        check("provider-only-members-and-safe-runtime") {
            return prepared.catalog.nodes.count == 2 && prepared.catalog.groups[0].members == ["PROVIDER-A"] && prepared.catalog.choices["TEST-SELECT"] == "PROVIDER-A" && !prepared.runtimeJSON.contains("Bearer") && !prepared.runtimeJSON.contains("never-read") && !prepared.runtimeJSON.contains("token=") && ConfigurationCompatibility.inspect(bundle).canUse
        }
        let id = try repo.add(StoredConfiguration(source: bundle, choices: prepared.catalog.choices), fileName: "provider.yaml", nodeCount: 2, groupCount: 1, ruleCount: 2, makeCurrent: true)
        ConfigurationResourceStore.discardPending()
        check("protected-snapshot-reopens-after-process-cache-clear") { try PrototypeConfiguration.prepare(repo.record(id).source).catalog.groups[0].members == ["PROVIDER-A"] }
        check("source-preserved-byte-exact") { try ConfigurationSnapshot.original(repo.record(id).source) == providerSource }
        let changedBody = Data(String(decoding: providerBody, as: UTF8.self).replacingOccurrences(of: "PROVIDER-A", with: "PROVIDER-B").utf8)
        let changed = try await SubscriptionResourceLoader.prepare(providerSource, permitsNetwork: false) { $0.key == "proxy:remote" ? changedBody : ruleBody }
        check("unchanged-main-file-detects-provider-update") { try changed != bundle && SubscriptionChangeSummary.compare(bundle, changed).contains { $0.contains("依赖资源变化：1") } }
        let expected = try repo.record(id)
        try repo.replace(id, expected: expected, source: changed, choices: [:], sourceURL: nil, nodeCount: 2, groupCount: 1, ruleCount: 2)
        check("history-retains-old-provider-bytes") {
            let previous = try repo.record(id).history!.first!
            return try PrototypeConfiguration.prepare(previous.source).catalog.groups[0].members == ["PROVIDER-A"]
        }
        var requests = 0
        do {
            _ = try await SubscriptionResourceLoader.prepare(providerSource, permitsNetwork: false) { request in
                requests += 1
                if requests == 2 { throw SubscriptionDownloader.Failure.transport }
                return providerBody
            }
            failures.append("partial-download-must-fail")
        } catch { total += 1; if try repo.record(id).source != changed { failures.append("partial-download-changed-active") } }
        let defaultGeo = try document(["rules": ["GEOIP,CN,DIRECT", "MATCH,TEST-SELECT"]])
        let networkFailures: [SubscriptionDownloader.Failure] = [.timedOut, .dns, .offline, .tls, .connectionLost, .unreachable, .redirect, .response, .tooLarge, .empty, .transport, .invalidURL]
        for failure in networkFailures {
            do {
                _ = try await SubscriptionResourceLoader.prepare(defaultGeo, permitsNetwork: false) { _ in throw failure }
                fatalError("failed dependency accepted")
            } catch let error as ConfigurationIssue {
                check("dependency-cause-\(failure)") {
                    let english = DiagnosticText.resourceDownloadEnglish(error.detail + "（2022）")
                    let unchanged = try repo.record(id).source == changed
                    return error.code == .resourceDownload && error.detail.contains("GeoIP 数据 / GitHub") && error.detail.contains(failure.safeReason)
                        && english?.contains("Dependency 1 (GeoIP data / GitHub)") == true
                        && !(english ?? "").contains("https://") && unchanged
                }
            }
        }
        do {
            _ = try await SubscriptionResourceLoader.prepare(providerSource, permitsNetwork: false) { _ in
                throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "FICTIONAL-SECRET-URL"])
            }
            fatalError("failure accepted")
        } catch let error as ConfigurationIssue {
            check("private-provider-failure-redacted") {
                error.detail.contains("节点列表") && !error.detail.contains("GitHub") && !error.detail.contains("FICTIONAL") && !error.detail.contains("remote")
            }
        }
        do {
            _ = try await SubscriptionResourceLoader.prepare(defaultGeo, permitsNetwork: false) { _ in throw CancellationError() }
            fatalError("cancellation accepted")
        } catch is CancellationError { check("dependency-cancel-not-reported-as-failure") { true } }
        check("rollback-restores-whole-bundle") {
            let current = try repo.record(id), old = current.history!.first!
            try repo.replace(id, expected: current, source: old.source, choices: old.choices, sourceURL: nil, nodeCount: 2, groupCount: 1, ruleCount: 2)
            ConfigurationResourceStore.discardPending()
            return try PrototypeConfiguration.prepare(repo.record(id).source).catalog.groups[0].members == ["PROVIDER-A"]
        }
        check("index-write-failure-keeps-complete-version") {
            let current = try repo.record(id)
            storage.failingWriteKey = SubscriptionRepository.indexKey
            defer { storage.failingWriteKey = nil }
            do { try repo.replace(id, expected: current, source: changed, choices: [:], sourceURL: nil, nodeCount: 2, groupCount: 1, ruleCount: 2); return false } catch { }
            return try repo.record(id).source == current.source
        }
        check("corrupt-resource-rejected") {
            let resource = try ConfigurationSnapshot.read(bundle)!.resources.first!
            let key = ConfigurationResourceStore.key(resource.digest, 0), original = storage.items[key]!
            storage.items[key] = Data("CORRUPTED".utf8)
            defer { storage.items[key] = original }
            return (try? PrototypeConfiguration.prepare(bundle)) == nil
        }
        // Materialize safe resources for the separate real-core preflight below.
        try ConfigurationResources.install(bundle, in: ConfigurationResources.directory)
        try Data(prepared.runtimeJSON.utf8).write(to: URL(fileURLWithPath: ".build/research/provider-fixture-runtime.json"))
        try Data(automatic.runtimeJSON.utf8).write(to: URL(fileURLWithPath: ".build/research/automatic-fixture-runtime.json"))
        for (behavior, format, payload) in [("domain", "text", "+.example.invalid\n"), ("ipcidr", "yaml", "payload: ['192.0.2.0/24']"), ("classical", "text", "DOMAIN,example.invalid\nDST-PORT,443\nNETWORK,UDP\n")] {
            let raw = try document(["rule-providers": ["set": ["type": "http", "url": "https://example.invalid/rules", "behavior": behavior, "format": format]], "rules": ["RULE-SET,set,DIRECT", "MATCH,TEST-SELECT"]])
            let candidate = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false) { _ in Data(payload.utf8) }
            check("rule-provider-" + behavior + "-" + format) { try PrototypeConfiguration.prepare(candidate).ruleCount == 2 }
        }
        let mrsURL = URL(fileURLWithPath: ".build/research/fixture-domain.mrs")
        if FileManager.default.fileExists(atPath: mrsURL.path) {
            let mrs = try Data(contentsOf: mrsURL)
            let raw = try document(["rule-providers": ["set": ["type": "http", "url": "https://example.invalid/rules", "behavior": "domain", "format": "mrs"]], "rules": ["RULE-SET,set,DIRECT", "MATCH,TEST-SELECT"]])
            let candidate = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false) { _ in mrs }
            check("mrs-rule-provider") { try PrototypeConfiguration.prepare(candidate).ruleCount == 2 }
            let corrupt = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false) { _ in Data("INVALID-MRS".utf8) }
            check("corrupt-mrs-rejected") { (try? PrototypeConfiguration.prepare(corrupt)) == nil }
        }
        check("file-provider-rejected") { refuses(["proxy-providers": ["p": ["type": "file", "path": "/private/secret.yaml"]]]) }
        check("provider-unsupported-option-reported") {
            var root = base; root["proxy-providers"] = ["p": ["type": "http", "url": "https://example.invalid/", "filter": "PRIVATE-FILTER", "override": ["dialer-proxy": "PRIVATE-CHAIN"]]]
            let report = ConfigurationCompatibility.inspect(try json(root)), text = report.findings.map(\.detail).joined()
            return !report.canUse && text.contains("dialer-proxy") && text.contains("override") && !text.contains("PRIVATE-FILTER") && !text.contains("PRIVATE-CHAIN")
        }
        check("chunked-resource-write-and-hash") {
            let payload = Data(repeating: 7, count: ConfigurationResourceStore.chunkBytes * 2 + 17)
            let source = try ConfigurationResourceStore.stage([("test:large", payload)], original: Data("{}".utf8))
            try ConfigurationResourceStore.persist(source, storage: storage)
            ConfigurationResourceStore.discardPending()
            let resource = try ConfigurationSnapshot.read(source)!.resources[0]
            let url = URL(fileURLWithPath: ".build/research/chunked-resource-test.bin")
            defer { try? FileManager.default.removeItem(at: url) }
            try ConfigurationResourceStore.write(resource, to: url, storage: storage)
            return try Data(contentsOf: url) == payload
        }
        // Minimal fictional protobuf data. No external geodata downloaded.
        func field(_ number: UInt8, _ bytes: Data) -> Data { precondition(bytes.count < 128); return Data([number << 3 | 2, UInt8(bytes.count)]) + bytes }
        let ip = field(1, field(1, Data("example".utf8)) + field(2, field(1, Data([192,0,2,0])) + Data([16,24])))
        let site = field(1, field(1, Data("example".utf8)) + field(2, Data([8,3]) + field(2, Data("example.invalid".utf8))))
        let geoSource = try document(["geodata-mode": true, "geox-url": ["geoip": "https://example.invalid/GeoIP.dat", "geosite": "https://example.invalid/GeoSite.dat"], "rules": ["GEOSITE,example,DIRECT", "GEOIP,example,DIRECT,no-resolve", "MATCH,TEST-SELECT"]])
        let geo = try await SubscriptionResourceLoader.prepare(geoSource, permitsNetwork: false) { $0.key == "geo:geoip:dat" ? ip : site }
        check("geo-categories-validated") {
            try ConfigurationResources.install(geo, in: ConfigurationResources.directory)
            let prepared = try PrototypeConfiguration.prepare(geo)
            try Data(prepared.runtimeJSON.utf8).write(to: URL(fileURLWithPath: ".build/research/geo-fixture-runtime.json"))
            return prepared.ruleCount == 3 && ConfigurationCompatibility.inspect(geo).canUse
        }
        let missing = try await SubscriptionResourceLoader.prepare(Data(String(decoding: geoSource, as: UTF8.self).replacingOccurrences(of: "GEOSITE,example,", with: "GEOSITE,missing,").utf8), permitsNetwork: false) { $0.key == "geo:geoip:dat" ? ip : site }
        check("missing-geo-category-fails-closed") { do { try ConfigurationResources.install(missing, in: ConfigurationResources.directory); return false } catch { return true } }
        try ConfigurationResources.install(geo, in: ConfigurationResources.directory)
        check("delete-collects-only-unreferenced-resources") {
            _ = try repo.delete([id]); return !storage.items.keys.contains { $0.hasPrefix("dependency-v1-") }
        }
        for failure in failures { print("FAIL: " + failure) }
        print("Batches checks: \(total - failures.count)/\(total); fictional fixtures, mock downloads and memory storage only")
        print("Fixture resource directory: " + ConfigurationResources.directory.path)
        if !failures.isEmpty { exit(1) }
    }
}
