import Foundation

/// An opt-in layer over the original subscription, versioned with its dependency snapshot.
/// Existing rules and explicit DNS choices retain precedence. No source YAML is rewritten.
nonisolated enum ConfigurationRouting: String, Codable, Sendable {
    case subscription
    case smart = "smart-fallback-v1"

    static func mode(in source: Data) throws -> Self {
        try ConfigurationSnapshot.read(source)?.routing ?? .subscription
    }

    func apply(_ input: ConfigurationInput.Document) throws -> ConfigurationInput.Document {
        guard self == .smart else { return input }
        var root = input.root
        guard var rules = root["rules"] as? [String], let last = rules.last else {
            throw ConfigurationValidation.issue("智能分流需要有效的末尾 MATCH 规则。")
        }
        let fields = last.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2, fields[0] == "MATCH",
              !["DIRECT", "REJECT", "REJECT-DROP"].contains(fields[1]) else {
            throw ConfigurationValidation.issue("智能分流需要末尾 MATCH 指向代理节点或策略组；原配置保持不变。")
        }
        // Run the original rules first, including reject/provider/user exceptions.
        // GEOIP resolves if necessary; no-resolve here would miss some domestic destinations.
        let additions = ["GEOSITE,cn,DIRECT", "GEOIP,CN,DIRECT"]
        guard rules.count + additions.count <= PrototypeConfiguration.maximumRules else {
            throw ConfigurationValidation.issue("规则数量已达上限，无法添加智能分流。")
        }
        rules.insert(contentsOf: additions, at: rules.count - 1)
        root["rules"] = rules
        let domestic = ["https://dns.alidns.com/dns-query#DIRECT", "https://doh.pub/dns-query#DIRECT"]
        var notes = input.notes + ["智能分流：原有规则优先，在末尾 MATCH 前增加国内域名与中国大陆 IP 直连；其他流量保留原代理目标。国内分类基于规则数据，不能保证覆盖所有服务。"]
        if root["dns"] == nil {
            // Resolve direct destinations locally, and the proxy fallback through its selected exit.
            // Resolver hostnames use the separately captured bootstrap DNS, never the proxy DNS.
            let target = fields[1].addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? fields[1]
            root["dns"] = ["enable": true, "ipv6": ConfigurationValidation.boolean(root["ipv6"]) ?? true,
                "enhanced-mode": "redir-host", "respect-rules": true,
                "nameserver": ["https://1.1.1.1/dns-query#" + target],
                "default-nameserver": ["system"], "proxy-server-nameserver": ["system"],
                "direct-nameserver": domestic, "direct-nameserver-follow-policy": false,
                "nameserver-policy": ["geosite:cn": domestic],
                "use-hosts": root["hosts"] != nil, "use-system-hosts": false] as [String: Any]
            notes.append("智能 DNS：直连出口使用国内加密 DNS，经 DIRECT 发出；默认业务 DNS 经末尾代理目标发出，节点域名用连接前系统 DNS 引导。")
        } else {
            guard var dns = root["dns"] as? [String: Any] else { throw ConfigurationValidation.issue("dns 必须是映射。") }
            if dns["direct-nameserver"] == nil {
                dns["direct-nameserver"] = domestic
                // Respect explicit subscription domain policies on the direct path too.
                if dns["direct-nameserver-follow-policy"] == nil { dns["direct-nameserver-follow-policy"] = true }
                root["dns"] = dns
                notes.append("智能 DNS：补充国内直连解析器，保留原 DNS 域名策略、默认上游、IPv6 和节点引导配置。")
            } else {
                notes.append("智能 DNS：订阅已指定直连解析器，完整保留；实际分流与解析需通过诊断确认。")
            }
        }
        return .init(root: root, notes: notes)
    }
}
