import Foundation

@main struct InactiveCompatibilityCheck {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try value() else { fatalError("Inactive option regression: " + label) }
            count += 1
        }
        func json(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) }
        let base = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        func rejected(_ root: [String: Any]) throws {
            let raw = try json(root)
            try check((try? PrototypeConfiguration.prepare(raw)) == nil, "invalid input rejected")
            try check(!ConfigurationCompatibility.inspect(raw).canUse, "diagnostics agree")
            try check((try? PrototypeConfiguration.runtimeDocument(root)) == nil, "direct runtime call cannot strip active options")
        }
        for field in ["tun", "sniffer"] {
            for value: Any in [true, "false", 0, NSNull()] {
                var root = base; root[field] = ["enable": value]; try rejected(root)
            }
            for value: Any in [[:], [], false, NSNull()] {
                var root = base; root[field] = value; try rejected(root)
            }
            var root = base
            root[field] = ["enable": false, "UNTRUSTED-KEY": "FICTIONAL-SECRET"]
            let raw = try json(root), prepared = try PrototypeConfiguration.prepare(raw)
            try check(prepared.source == raw, "inactive payload original preserved")
            try check(!prepared.runtimeJSON.contains("FICTIONAL-SECRET"), "inactive payload removed")
            let report = ConfigurationCompatibility.inspect(raw)
            try check(report.canUse && report.findings.contains { $0.level == .adapted }, "inactive payload disclosed")
            try check(!report.findings.contains { $0.detail.contains("FICTIONAL-SECRET") || $0.detail.contains("UNTRUSTED-KEY") }, "diagnostics private")
        }
        for (field, empty) in [("hosts", [:] as Any), ("listeners", [] as Any), ("authentication", [] as Any)] {
            var root = base; root[field] = empty
            try check(try PrototypeConfiguration.prepare(json(root)).source == json(root), "empty container accepted")
            for value: Any in [false, "", NSNull(), ["FICTIONAL"], ["FICTIONAL": "VALUE"]] {
                root[field] = value; try rejected(root)
            }
        }
        for original in ExtendedCompatibilitySelfCheck.nodes {
            var node = original
            for field in ["tfo", "mptcp", "smux"] {
                node = original
                if field == "smux" { node[field] = ["enabled": false, "protocol": "smux"] as [String: Any] }
                else { node[field] = false }
                let raw = try json(["proxies": [node]])
                let prepared = try PrototypeConfiguration.prepare(raw)
                try check(prepared.source == raw && !prepared.runtimeJSON.contains("\"" + field + "\""), "node inactive option projected")
                for invalid: Any in (field == "mptcp" ? [true, "false", 0, NSNull()] : ["false", 0, NSNull()]) {
                    node[field] = field == "smux" ? ["enabled": invalid] : invalid
                    try check((try? PrototypeConfiguration.prepare(json(["proxies": [node]]))) == nil, "node enabled/wrong type rejected")
                }
            }
        }
        for kind in ["vmess", "vless", "trojan"] {
            var node = ExtendedCompatibilitySelfCheck.nodes.first { $0["name"] as? String == kind + "-tcp" }!
            node["network"] = ""
            if kind != "trojan" { node["packet-encoding"] = "" }
            let normalized = try PrototypeConfiguration.prepare(json(["proxies": [node]]))
            var explicit = node; explicit["network"] = "tcp"; explicit.removeValue(forKey: "packet-encoding")
            let equivalent = try PrototypeConfiguration.prepare(json(["proxies": [explicit]]))
            try check(normalized.runtimeJSON == equivalent.runtimeJSON, "empty defaults match explicit defaults")
            node["ws-opts"] = ["path": "/"]
            try check((try? PrototypeConfiguration.prepare(json(["proxies": [node]]))) == nil, "empty TCP cannot silently use WS options")
        }
        var vmess = ExtendedCompatibilitySelfCheck.nodes.first { $0["name"] as? String == "vmess-tcp" }!
        for field in ["global-padding", "authenticated-length"] {
            vmess[field] = false
            try check((try? PrototypeConfiguration.prepare(json(["proxies": [vmess]]))) != nil, "VMess false option accepted")
            for value: Any in ["false", 0, NSNull()] {
                vmess[field] = value
                try check((try? PrototypeConfiguration.prepare(json(["proxies": [vmess]]))) == nil, "VMess active/type rejected")
            }
            vmess.removeValue(forKey: field)
        }
        vmess.removeValue(forKey: "alterId")
        try check((try? PrototypeConfiguration.prepare(json(["proxies": [vmess]]))) == nil, "required alterId never fabricated")
        vmess["alterId"] = 0
        vmess.removeValue(forKey: "cipher")
        try check((try? PrototypeConfiguration.prepare(json(["proxies": [vmess]]))) == nil, "required cipher never fabricated")
        var multiple = base; multiple["tun"] = ["enable": true]; multiple["sniffer"] = ["enable": true]
        let report = ConfigurationCompatibility.inspect(try json(multiple))
        for field in ["tun", "sniffer"] {
            try check(report.findings.contains { $0.location == "顶层 · " + field && $0.level == .blocked }, "independent errors reported")
        }
        print("Inactive/default compatibility: \(count) checks passed; fictional inputs, no network or Keychain.")
    }
}
