import Foundation

/// Offline, synthetic checks. Never loads the vault, starts a tunnel or opens sockets.
enum PrototypeSelfCheck {
    static let fixture = """
    mode: rule
    proxies:
      - name: TEST-HY2
        type: hysteria2
        server: node.example.invalid
        port: 443
        password: TEST-ONLY-PASSWORD
        sni: tls.example.invalid
        obfs: salamander
        obfs-password: TEST-ONLY-OBFS
        up: 10
        down: 50
    proxy-groups:
      - name: TEST-SELECT
        type: select
        proxies: [TEST-HY2]
    rules: ["MATCH,TEST-SELECT"]
    """
    struct Result: Codable {
        let passed: Int
        let total: Int
        let failures: [String]
        var summary: String { "离线自检 \(passed)/\(total)；未访问网络或钥匙串。" }
    }
    static func run() -> Result {
        var failures: [String] = []
        var total = 0
        func check(_ name: String, _ body: () throws -> Bool) {
            total += 1
            do { if try !body() { failures.append(name) } }
            catch { failures.append(name + ":" + String((error as? PrototypeError)?.rawValue ?? 0)) }
        }
        func refused(_ value: String, _ expected: PrototypeError) -> Bool {
            do { _ = try PrototypeConfiguration.prepare(Data(value.utf8)); return false }
            catch { return ((error as? PrototypeError) ?? (error as? ConfigurationIssue)?.code) == expected }
        }
        check("fixture") {
            let result = try PrototypeConfiguration.prepare(Data(fixture.utf8))
            let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
            let dns = root["dns"] as! [String: Any]
            let tun = root["tun"] as! [String: Any]
            return !result.runtimeJSON.contains("\\/") && result.isFixture && root["ipv6"] as? Bool == true && dns["respect-rules"] as? Bool == true && tun["stack"] as? String == "gvisor"
        }
        check("bootstrap-override-keeps-source-and-doh") {
            let source = Data(fixture.utf8)
            let result = try PrototypeConfiguration.prepare(source, bootstrapServers: ["192.0.2.53"])
            let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
            let dns = root["dns"] as! [String: Any]
            return result.source == source && dns["proxy-server-nameserver"] as? [String] == ["192.0.2.53"] &&
                dns["default-nameserver"] as? [String] == ["192.0.2.53"] &&
                dns["nameserver"] as? [String] == ["https://1.1.1.1/dns-query"] && dns["respect-rules"] as? Bool == true
        }
        check("unknown-field") { refused(fixture + "\nunknown-token: TEST-SECRET", .unsupportedFields) }
        check("verge-unified-delay-default") {
            let result = try PrototypeConfiguration.prepare(Data(fixture.utf8))
            let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
            return result.unifiedDelay && root["unified-delay"] as? Bool == true && result.source == Data(fixture.utf8)
        }
        check("explicit-unified-delay-preserved") {
            let source = Data((fixture + "\nunified-delay: false").utf8)
            let result = try PrototypeConfiguration.prepare(source)
            let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
            return !result.unifiedDelay && root["unified-delay"] as? Bool == false && result.source == source
        }
        check("invalid-unified-delay-type") { refused(fixture + "\nunified-delay: 'true'", .invalidFile) }
        check("dns-override") { refused(fixture + "\ndns: {enable: false}", .unsupportedFields) }
        check("bad-reference") { refused(fixture.replacingOccurrences(of: "proxies: [TEST-HY2]", with: "proxies: [MISSING]"), .unsupportedShape) }
        check("tls-downgrade-requires-consent") {
            let source = Data(fixture.replacingOccurrences(of: "    up: 10", with: "    skip-cert-verify: true\n    up: 10").utf8)
            let prepared = try PrototypeConfiguration.prepare(source)
            do { try StoredConfiguration(source: source).requireCertificateConsent(for: prepared); return false }
            catch { return error as? PrototypeError == .certificateConsent && prepared.insecureNodeCount == 1 }
        }
        for (label, scalar, expected) in [
            ("double-quoted-port", "\"443\"", "443"),
            ("single-quoted-port", "'443'", "443"),
            ("minimum-quoted-port", "\"1\"", "1"),
            ("maximum-quoted-port", "\"65535\"", "65535")
        ] {
            check(label) {
                let yaml = fixture.replacingOccurrences(of: "port: 443", with: "port: " + scalar)
                let result = try PrototypeConfiguration.prepare(Data(yaml.utf8))
                let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
                let nodes = root["proxies"] as! [[String: Any]]
                return result.source == Data(yaml.utf8) && nodes[0]["port"] as? String == expected
            }
        }
        for (label, scalar) in [
            ("boolean-port", "true"), ("zero-port", "0"),
            ("negative-port", "-1"), ("fractional-port", "443.5"),
            ("out-of-range-port", "65536"), ("zero-quoted-port", "\"0\""),
            ("out-of-range-quoted-port", "\"65536\""), ("overflow-quoted-port", "\"99999999999999999999\""),
            ("empty-quoted-port", "\"\""), ("padded-quoted-port", "\" 443 \""),
            ("leading-zero-port", "\"0443\""), ("hex-quoted-port", "\"0x1bb\""),
            ("signed-quoted-port", "\"+443\""), ("non-ascii-port", "\"４４３\"")
        ] {
            check(label) {
                refused(fixture.replacingOccurrences(of: "port: 443", with: "port: " + scalar), .invalidPort)
            }
        }
        check("second-document") { refused(fixture + "\n---\nsecret: TEST-SECRET", .invalidFile) }
        check("leading-document-marker") { try PrototypeConfiguration.prepare(Data(("---\n" + fixture).utf8)).isFixture }
        check("document-end-marker") { try PrototypeConfiguration.prepare(Data(("---\n" + fixture + "\n...\n# end").utf8)).isFixture }
        check("trailing-document-after-end") { refused(fixture + "\n...\n---\nmode: direct", .invalidFile) }
        check("dual-protocol-preserves-semantics") {
            let result = try PrototypeConfiguration.prepare(Data(CompatibilityFixture.yaml.utf8))
            let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
            let dns = root["dns"] as! [String: Any], nodes = root["proxies"] as! [[String: Any]]
            let rules = root["rules"] as! [String]
            return result.catalog.nodes.count == 2 && result.ruleCount == 5 && result.nodeName == "TEST-HY2" &&
                nodes[0]["fingerprint"] as? String == String(repeating: "01", count: 32) &&
                nodes[0]["alpn"] as? [String] == ["h3"] && nodes[1]["flow"] as? String == "xtls-rprx-vision" &&
                dns["enhanced-mode"] as? String == "fake-ip" && dns["ipv6"] as? Bool == false &&
                dns["nameserver"] as? [String] == ["https://1.1.1.1/dns-query"] &&
                dns["default-nameserver"] as? [String] == ["192.0.2.53", "192.0.2.54"] &&
                root["ipv6"] as? Bool == false && root["mixed-port"] == nil && root["allow-lan"] == nil &&
                rules.count == 6 && rules.first == "IP-CIDR6,::/0,REJECT,no-resolve" &&
                rules.last == "MATCH,TEST-SELECT" && !result.needsSystemBootstrap
        }
        check("persisted-selection-used-for-start-and-ping") {
            let original = Data(CompatibilityFixture.yaml.utf8)
            let stored = StoredConfiguration(source: original, choices: ["TEST-SELECT": "TEST-VLESS"])
            let decoded = try JSONDecoder().decode(StoredConfiguration.self, from: JSONEncoder().encode(stored))
            let result = try PrototypeConfiguration.prepare(decoded.source, choices: decoded.choices)
            let root = try JSONSerialization.jsonObject(with: Data(result.runtimeJSON.utf8)) as! [String: Any]
            let groups = root["proxy-groups"] as! [[String: Any]]
            return decoded.source == original && result.nodeName == "TEST-VLESS" &&
                (groups[0]["proxies"] as? [String])?.first == "TEST-VLESS"
        }
        check("duplicate-node-names") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: "TEST-VLESS", with: "TEST-HY2"), .unsupportedShape) }
        check("invalid-reality-public-key") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: CompatibilityFixture.publicKey, with: "TEST-BAD"), .unsupportedShape) }
        check("invalid-certificate-pin") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: String(repeating: "01", count: 32), with: "chrome"), .unsupportedShape) }
        check("group-cycle") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: "[TEST-HY2, TEST-VLESS]", with: "[TEST-SELECT, TEST-VLESS]"), .unsupportedShape) }
        check("missing-rule-target") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: "MATCH,TEST-SELECT", with: "MATCH,MISSING"), .unsupportedShape) }
        check("invalid-cidr") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: "10.0.0.0/8", with: "10.0.0.0/33"), .unsupportedShape) }
        check("empty-providers-are-valid") { (try? PrototypeConfiguration.prepare(Data((fixture + "\nproxy-providers: {}").utf8))) != nil }
        check("system-dns-snapshot") { (try? PrototypeConfiguration.prepare(Data(CompatibilityFixture.yaml.replacingOccurrences(of: "https://1.1.1.1/dns-query", with: "system").utf8)))?.needsSystemBootstrap == true }
        check("dns-enable-stays-required") { refused(CompatibilityFixture.yaml.replacingOccurrences(of: "enable: true", with: "enable: false"), .unsupportedFields) }
        check("oversize") { refused(String(repeating: "x", count: PrototypeConfiguration.maximumBytes + 1), .invalidFile) }
        check("error-redaction") {
            let foreign = NSError(domain: "TEST-SECRET", code: 9, userInfo: [NSLocalizedDescriptionKey: "TEST-PASSWORD"])
            let text = TunnelDiagnostics.safeErrorSummary(foreign)
            return !text.contains("TEST-")
        }
        let expanded = ExtendedCompatibilitySelfCheck.run()
        total += expanded.total
        failures += expanded.failures.map { "expanded." + $0 }
        let maintenance = SubscriptionMaintenanceSelfCheck.run()
        total += maintenance.total
        failures += maintenance.failures.map { "maintenance." + $0 }
        let library = SubscriptionSelfCheck.run()
        total += library.total
        failures += library.failures.map { "subscriptions." + $0 }
        return Result(passed: total - failures.count, total: total, failures: failures)
    }
}
