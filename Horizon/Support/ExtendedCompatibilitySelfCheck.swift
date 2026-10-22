import Foundation

/// Fictional protocol/transport matrix; never dials a server.
enum ExtendedCompatibilitySelfCheck {
    static let uuid = "11111111-1111-4111-8111-111111111111"
    static var nodes: [[String: Any]] {
        var values: [[String: Any]] = []
        for cipher in ConfigurationNodeOptions.ssCiphers {
            let password = cipher.hasPrefix("2022-") ? Data(repeating: 1, count: cipher.contains("aes-128") ? 16 : 32).base64EncodedString() : "FICTIONAL-ONLY"
            values.append(["name": "SS-\(values.count)", "type": "ss", "server": "node.example.invalid", "port": 443, "cipher": cipher, "password": password, "udp": true])
        }
        for kind in ["vless", "vmess", "trojan"] {
            for network in ["tcp", "ws", "grpc"] {
                var n: [String: Any] = ["name": "\(kind)-\(network)", "type": kind, "server": "node.example.invalid", "port": 443, "network": network, "udp": true]
                if kind == "trojan" { n["password"] = "FICTIONAL-ONLY"; n["sni"] = "tls.example.invalid" }
                else { n["uuid"] = uuid; n["tls"] = true; n["servername"] = "tls.example.invalid" }
                if kind == "vmess" { n["cipher"] = "auto"; n["alterId"] = 0 }
                if network == "ws" { n["ws-opts"] = ["path": "/fixture?one=two", "headers": ["Host": "ws.example.invalid"], "max-early-data": 2048, "early-data-header-name": "Sec-WebSocket-Protocol"] }
                if network == "grpc" { n["grpc-opts"] = ["grpc-service-name": "fixture", "grpc-user-agent": "fixture"] }
                values.append(n)
            }
        }
        return values
    }
    static var document: Data { try! JSONSerialization.data(withJSONObject: ["proxies": nodes], options: [.sortedKeys, .prettyPrinted]) }
    static func run() -> PrototypeSelfCheck.Result {
        var total = 0, failures: [String] = []
        func check(_ name: String, _ body: () throws -> Bool) {
            total += 1
            do { if try !body() { failures.append(name) } } catch { failures.append(name + ":" + ((error as? ConfigurationIssue)?.detail ?? (error as? PrototypeError)?.summary ?? "failed")) }
        }
        func rejects(_ n: [String: Any]) -> Bool { (try? ConfigurationValidation.validateNode(n, index: 0)) == nil }
        func input(_ s: String) throws -> PrototypeConfiguration.Prepared { try PrototypeConfiguration.prepare(Data(s.utf8)) }
        check("new-protocol-matrix-preserved") {
            let p = try PrototypeConfiguration.prepare(document)
            let runtime = try JSONSerialization.jsonObject(with: Data(p.runtimeJSON.utf8)) as! [String: Any]
            let a = try JSONSerialization.data(withJSONObject: nodes, options: .sortedKeys)
            let b = try JSONSerialization.data(withJSONObject: runtime["proxies"]!, options: .sortedKeys)
            return a == b && p.source == document && p.catalog.nodes.count == nodes.count && p.ruleCount == 1
        }
        check("new-diagnostics-match-validator") { ConfigurationCompatibility.inspect(document).canUse }
        check("partial-full-config-is-not-filled") {
            (try? input("proxies: []\nrules: ['MATCH,DIRECT']")) == nil
        }
        check("generated-group-collision") {
            var n = nodes[0]; n["name"] = "Imported"
            let data = try JSONSerialization.data(withJSONObject: ["proxies": [n]])
            return try PrototypeConfiguration.prepare(data).catalog.groups[0].name == "Imported-2"
        }
        for kind in ["vless", "vmess"] {
            check(kind + "-ws-without-tls") {
                var n = nodes.first { $0["name"] as? String == kind + "-ws" }!
                n["tls"] = false; n.removeValue(forKey: "servername")
                return !rejects(n)
            }
        }
        for (key, value) in [("plugin", "v2ray-plugin"), ("cipher", "rc4-md5"), ("udp", "true")] {
            check("ss-refuses-" + key) { var n = nodes[0]; n[key] = value; return rejects(n) }
        }
        check("ss2022-invalid-key") { var n = nodes[5]; n["password"] = "bad"; return rejects(n) }
        check("ss2022-identity-chain") {
            var n = nodes[5]; n["password"] = Array(repeating: n["password"] as! String, count: 2).joined(separator: ":"); return !rejects(n)
        }
        for (key, value) in [("flow", "xtls-rprx-vision"), ("network", "xhttp")] {
            check("vless-refuses-" + key) { var n = nodes.first { $0["name"] as? String == "vless-ws" }!; n[key] = value; return rejects(n) }
        }
        check("unknown-ws-field-blocked") {
            var n = nodes.first { $0["name"] as? String == "vless-ws" }!; n["ws-opts"] = ["secret-option": "PRIVATE"]; return rejects(n)
        }
        check("header-newline-blocked") {
            var n = nodes.first { $0["name"] as? String == "trojan-ws" }!; n["ws-opts"] = ["headers": ["Host": "test\r\nX-Fake: bad"]]; return rejects(n)
        }
        let ss = "ss://" + Data("aes-128-gcm:FICTIONAL-ONLY".utf8).base64EncodedString() + "@node.example.invalid:443#EXAMPLE"
        let oldSS = "ss://" + Data("aes-128-gcm:FICTIONAL-ONLY@node.example.invalid:443".utf8).base64EncodedString() + "#EXAMPLE"
        let vless = "vless://\(uuid)@node.example.invalid:443?encryption=none&security=tls&type=ws&sni=tls.example.invalid&path=%2Fweb%3Fx%3D1&host=ws.example.invalid#EXAMPLE"
        let trojan = "trojan://FAKE%3A%2B%40%26%25@node.example.invalid:443?type=grpc&serviceName=fixture&sni=tls.example.invalid#TROJAN"
        let hy2 = "hysteria2://FICTIONAL@node.example.invalid:443?sni=tls.example.invalid&obfs=salamander&obfs-password=FAKE#HY2"
        let vmessObject: [String: Any] = ["v": "2", "ps": "VMESS", "add": "node.example.invalid", "port": "443", "id": uuid, "aid": "0", "scy": "auto", "net": "ws", "type": "none", "host": "ws.example.invalid", "path": "/ws", "tls": "tls", "sni": "tls.example.invalid"]
        let vmess = "vmess://" + (try! JSONSerialization.data(withJSONObject: vmessObject)).base64EncodedString()
        for (i, link) in [ss, oldSS, vless, trojan, hy2, vmess].enumerated() {
            check("uri-\(i)-source-and-contract") { let p = try input(link); return p.catalog.nodes.count == 1 && p.source == Data(link.utf8) && ConfigurationCompatibility.inspect(p.source).canUse }
        }
        check("uri-percent-credential-exact") {
            let root = try PrototypeConfiguration.decode(Data(trojan.utf8))
            return (root["proxies"] as? [[String: Any]])?[0]["password"] as? String == "FAKE:+@&%"
        }
        check("uri-ws-query-path-exact") {
            let root = try PrototypeConfiguration.decode(Data(vless.utf8))
            let n = (root["proxies"] as! [[String: Any]])[0]
            return (n["ws-opts"] as? [String: Any])?["path"] as? String == "/web?x=1"
        }
        let list = [ss, vless, trojan, vmess, hy2].joined(separator: "\r\n")
        check("list-duplicate-names-keeps-every-node") {
            let p = try input(list); return p.catalog.nodes.count == 5 && Set(p.catalog.nodes.map(\.name)).count == 5
        }
        check("base64-standard-and-url-safe") {
            let base = Data(list.utf8).base64EncodedString()
            let safe = base.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return try input(base).catalog.nodes.count == 5 && input(safe).catalog.nodes.count == 5
        }
        check("template-choice-roundtrip") {
            let p = try input(list), group = p.catalog.groups[0]
            let stored = StoredConfiguration(source: p.source, choices: [group.name: p.catalog.nodes[2].name])
            let copy = try JSONDecoder().decode(StoredConfiguration.self, from: JSONEncoder().encode(stored))
            return try PrototypeConfiguration.prepare(copy.source, choices: copy.choices).nodeName == p.catalog.nodes[2].name
        }
        check("base64-diff-no-secret") {
            let a = Data(Data(list.utf8).base64EncodedString().utf8), b = Data(Data(list.replacingOccurrences(of: "FICTIONAL-ONLY", with: "CHANGED").utf8).base64EncodedString().utf8)
            let result = try SubscriptionChangeSummary.compare(a, b).joined()
            return !result.contains("FICTIONAL") && !result.contains("example.invalid")
        }
        for (i, bad) in [vless.replacingOccurrences(of: "#EXAMPLE", with: "&unknown=PRIVATE#EXAMPLE"), vless.replacingOccurrences(of: "security=tls", with: "security=tls&security=none"), trojan.replacingOccurrences(of: "type=grpc", with: "type=grpc&allowInsecure=invalid"), ss.replacingOccurrences(of: "#EXAMPLE", with: "?plugin=obfs#EXAMPLE"), "vmess://invalid", list + "\nunsupported://PRIVATE", vless.replacingOccurrences(of: "type=ws", with: "type=xhttp")].enumerated() {
            check("bad-uri-\(i)-rejected") { (try? input(bad)) == nil }
        }
        check("vmess-duplicate-json-key-rejected") {
            let raw = "{\"v\":\"2\",\"v\":\"2\"}"
            return (try? input("vmess://" + Data(raw.utf8).base64EncodedString())) == nil
        }
        check("vmess-trailing-document-rejected") {
            let raw = "{}\n---\nv: 2"
            return (try? input("vmess://" + Data(raw.utf8).base64EncodedString())) == nil
        }
        check("list-limit-enforced") { (try? input(Array(repeating: ss, count: PrototypeConfiguration.maximumNodes + 1).joined(separator: "\n"))) == nil }
        check("source-history-rolls-back-base64-and-choices") {
            let repo = SubscriptionRepository(storage: MemorySubscriptionStorage())
            let raw = Data(Data(list.utf8).base64EncodedString().utf8)
            let p = try PrototypeConfiguration.prepare(raw), group = p.catalog.groups[0]
            let choices = [group.name: p.catalog.nodes[2].name]
            var first = StoredConfiguration(source: raw, choices: choices)
            first.sourceURL = "https://example.invalid/sub?token=FICTIONAL"
            let id = try repo.add(first, fileName: "nodes.txt", nodeCount: 5, groupCount: 1, ruleCount: 1, makeCurrent: true)
            try repo.replace(id, expected: first, source: Data(ss.utf8), choices: [:], sourceURL: first.sourceURL, nodeCount: 1, groupCount: 1, ruleCount: 1)
            let current = try repo.record(id), old = current.history![0]
            try repo.replace(id, expected: current, source: old.source, choices: old.choices, sourceURL: current.sourceURL, nodeCount: 5, groupCount: 1, ruleCount: 1)
            let restored = try repo.record(id)
            return try restored.source == raw && restored.sourceURL == first.sourceURL && restored.choices == choices &&
                PrototypeConfiguration.prepare(restored.source, choices: restored.choices).nodeName == p.catalog.nodes[2].name
        }
        check("all-uri-errors-redacted") {
            let text = "trojan://SECRET@node.example.invalid:443?unknown=TOKEN\nvless://bad@node.example.invalid:443"
            let r = ConfigurationCompatibility.inspect(Data(text.utf8)); let message = r.findings.map(\.detail).joined()
            return !r.canUse && message.contains("链接 1") && message.contains("链接 2") && !message.contains("SECRET") && !message.contains("TOKEN") && !message.contains("node.example.invalid")
        }
        return .init(passed: total - failures.count, total: total, failures: failures)
    }
}
