import Foundation
import Hako

nonisolated enum ConfigurationDNS {
    struct Result {
        let value: [String: Any]
        let needsSystem: Bool
        let notes: [String]
    }
    static func prepare(_ input: Any?, ipv6: Bool, bootstrap: [String], context: [String: Any] = [:]) throws -> Result {
        guard let input else {
            return Result(value: [
                "enable": true, "ipv6": ipv6, "enhanced-mode": "redir-host", "respect-rules": true,
                "use-hosts": context["hosts"] != nil, "use-system-hosts": false, "nameserver": ["https://1.1.1.1/dns-query"],
                "default-nameserver": bootstrap, "proxy-server-nameserver": bootstrap,
                "fallback": [], "fake-ip-range": "198.18.0.1/16"
            ], needsSystem: true, notes: ["文件未定义 DNS：添加 redir-host 和经规则访问 Cloudflare DoH；节点引导解析使用连接前的系统 DNS，切网后需手动重连。"])
        }
        guard var dns = input as? [String: Any] else { throw ConfigurationValidation.issue("dns 必须是映射。") }
        try ConfigurationValidation.keys(dns, ConfigurationPolicy.dnsFields, at: "DNS")
        try ConfigurationValidation.optionalBooleans(dns, ["enable", "ipv6", "respect-rules",
            "use-hosts", "use-system-hosts", "direct-nameserver-follow-policy", "prefer-h3"], at: "DNS")
        let nodeNames = ConfigurationResources.nodes(context).compactMap { $0["name"] as? String }
        let groupDefinitions = context["proxy-groups"] as? [[String: Any]] ?? []
        let groupNames = groupDefinitions.compactMap { $0["name"] as? String }
        let proxyNames = Set(nodeNames + groupNames).union(["DIRECT"])
        let providers = context["rule-providers"] as? [String: [String: Any]] ?? [:]
        func validatePolicy(_ pattern: String) throws {
            guard validPolicyPattern(pattern) else { throw ConfigurationValidation.issue("DNS 策略模式无效。") }
            if pattern.hasPrefix("rule-set:") {
                for name in pattern.dropFirst(9).split(separator: ",").map(String.init) {
                    guard let provider = providers[name], provider["behavior"] as? String == "domain" else { throw ConfigurationValidation.issue("DNS rule-set 必须引用已定义的 domain 规则集。") }
                }
            }
        }
        func normalizeServers(_ servers: [String], field: String) throws -> [String] {
            try servers.flatMap { server -> [String] in
                if server == "system" || server == "system://" { return bootstrap }
                if let fragment = server.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first {
                    let name = String(fragment).removingPercentEncoding ?? String(fragment)
                    guard proxyNames.contains(name), !["default-nameserver", "proxy-server-nameserver", "proxy-server-nameserver-policy"].contains(field) || name == "DIRECT" else { throw ConfigurationValidation.issue("DNS 上游引用不存在的代理，或节点引导 DNS 使用代理造成递归风险。") }
                }
                return [server]
            }
        }
        var usesSystem = false
        var notes = ["保留文件的 DNS 模式、上游、节点引导解析器和 DNS IPv6 设置，不改成原型默认 DNS。"]
        if let listen = dns["listen"] {
            guard let address = listen as? String, validListener(address) else {
                throw ConfigurationValidation.issue("dns.listen 需要 IP:端口、:端口（IPv6 使用方括号）或空字符串。")
            }
            dns.removeValue(forKey: "listen")
            notes.append("dns.listen 为桌面监听设置：iOS 使用 Packet Tunnel 的 DNS 接入，不开放该监听端口；原始设置保留在订阅中。")
        }
        if ConfigurationValidation.boolean(dns["prefer-h3"]) == true {
            throw ConfigurationValidation.issue("dns.prefer-h3: true 尚未完成 iOS HTTP/3 验证；支持 false，不会静默关闭 HTTP/3 偏好。", .unsupportedFields)
        }
        guard ConfigurationValidation.boolean(dns["enable"]) != false else {
            throw ConfigurationValidation.issue("iOS 隧道需要内核 DNS；dns.enable: false 尚不支持。", .unsupportedFields)
        }
        guard dns["enhanced-mode"] == nil || ["normal", "fake-ip", "redir-host"].contains(dns["enhanced-mode"] as? String ?? "?") else {
            throw ConfigurationValidation.issue("DNS 模式未支持。")
        }
        guard let nameservers = dns["nameserver"] as? [String], !nameservers.isEmpty else {
            throw ConfigurationValidation.issue("自定义 DNS 需要非空 nameserver；不会静默替换为默认上游。")
        }
        for key in ["nameserver", "default-nameserver", "proxy-server-nameserver", "direct-nameserver", "fallback"] where dns[key] != nil {
            guard let servers = dns[key] as? [String], servers.count <= 16,
                  (["fallback", "direct-nameserver"].contains(key) || !servers.isEmpty),
                  servers.allSatisfy({ validServer($0, bootstrap: key == "default-nameserver") }) else {
                throw ConfigurationValidation.issue("DNS \(key)：上游地址列表格式未支持。")
            }
            usesSystem = usesSystem || servers.contains { $0 == "system" || $0 == "system://" }
            dns[key] = try normalizeServers(servers, field:key)
        }
        for key in ["nameserver-policy", "proxy-server-nameserver-policy"] where dns[key] != nil {
            guard var policy = dns[key] as? [String: Any], policy.count <= 128 else { throw ConfigurationValidation.issue("DNS 策略格式错误。") }
            for (pattern, value) in policy {
                try validatePolicy(pattern)
                let servers = (value as? [String]) ?? (value as? String).map { [$0] } ?? []
                guard !servers.isEmpty, servers.count <= 16, servers.allSatisfy({ validServer($0) }) else {
                    throw ConfigurationValidation.issue("DNS 策略中的上游格式未支持。")
                }
                usesSystem = usesSystem || servers.contains { $0 == "system" || $0 == "system://" }
                policy[pattern] = try normalizeServers(servers, field:key)
            }
            dns[key] = policy
        }
        if let range = dns["fake-ip-range"] {
            guard let range = range as? String, ConfigurationValidation.cidr(range, ipv6: false) else { throw ConfigurationValidation.issue("fake-ip-range 必须是 IPv4 CIDR。") }
        }
        if let filters = dns["fake-ip-filter"] {
            guard let filters = filters as? [String], filters.count <= 1024, filters.allSatisfy({ validPattern($0) }) else { throw ConfigurationValidation.issue("fake-ip-filter 当前只支持普通域名模式。") }
        }
        if let mode = dns["fake-ip-filter-mode"] {
            guard let mode = mode as? String, ["blacklist", "whitelist"].contains(mode) else { throw ConfigurationValidation.issue("fake-ip-filter-mode 暂不支持规则模式。") }
        }
        if let filter = dns["fallback-filter"] {
            guard var filter = filter as? [String: Any] else { throw ConfigurationValidation.issue("fallback-filter 格式错误。") }
            try ConfigurationValidation.keys(filter, ["geoip", "geoip-code", "geosite", "ipcidr", "domain"], at: "DNS fallback-filter")
            try ConfigurationValidation.optionalBooleans(filter, ["geoip"], at: "DNS fallback-filter")
            if let code = filter["geoip-code"] {
                guard let code = code as? String, code.range(of: "^[A-Za-z]{2}$", options: .regularExpression) != nil else {
                    throw ConfigurationValidation.issue("fallback-filter.geoip-code 需要两位国家代码。")
                }
                filter["geoip-code"] = code.uppercased()
            }
            if filter["geoip"] == nil { filter["geoip"] = true }
            if ConfigurationValidation.boolean(filter["geoip"]) == true,
               let fallback = dns["fallback"] as? [String], !fallback.isEmpty {
                if filter["geoip-code"] == nil { filter["geoip-code"] = "CN" }
            } else if filter.removeValue(forKey: "geoip-code") != nil {
                notes.append("未启用 fallback GeoIP 筛选：不加载其国家分类，原始 geoip-code 保留在订阅中。")
            }
            if let sites = filter["geosite"] {
                guard let sites = sites as? [String], sites.count <= 128, sites.allSatisfy({ validGeoCode($0) }) else { throw ConfigurationValidation.issue("fallback-filter geosite 分类无效。") }
            }
            dns["fallback-filter"] = filter
            if let cidrs = filter["ipcidr"] {
                guard let cidrs = cidrs as? [String], cidrs.count <= 128,
                      cidrs.allSatisfy({ ConfigurationValidation.cidr($0, ipv6: $0.contains(":")) }) else { throw ConfigurationValidation.issue("fallback-filter ipcidr 格式错误。") }
            }
            if let domains = filter["domain"] {
                guard let domains = domains as? [String], domains.count <= 128, domains.allSatisfy({ validPattern($0) }) else { throw ConfigurationValidation.issue("fallback-filter domain 格式错误。") }
            }
        } else if let fallback = dns["fallback"] as? [String], !fallback.isEmpty {
            dns["fallback-filter"] = ["geoip": true, "geoip-code": "CN"]
        }
        if let code = fallbackGeoIPCode(dns) {
            notes.append("DNS fallback 保留 GeoIP 国家筛选（\(code)）：主 DNS 返回非目标国家 IP 时使用 fallback；数据随订阅快照校验和保存。省略 geoip / geoip-code 时沿用内核默认 true / CN。")
        }
        let needsSystem = dns["default-nameserver"] == nil || usesSystem
        if dns["default-nameserver"] == nil {
            dns["default-nameserver"] = bootstrap
            notes.append("缺少 default-nameserver：使用连接前的系统 DNS 引导上游域名，切网后需重连。")
        }
        if dns["proxy-server-nameserver"] == nil {
            dns["proxy-server-nameserver"] = dns["default-nameserver"]
            notes.append("缺少 proxy-server-nameserver：使用上述引导 DNS 解析节点域名。")
        }
        if usesSystem { notes.append("system DNS 标记替换为连接前获取的系统 DNS 地址，避免隧道内循环解析；切网后重连获取新地址。") }
        dns["enable"] = true
        if dns["ipv6"] == nil { dns["ipv6"] = false; notes.append("未设置 dns.ipv6：沿用 Clash 默认值 false。") }
        if dns["use-system-hosts"] != nil && ConfigurationValidation.boolean(dns["use-system-hosts"]) != false {
            throw ConfigurationValidation.issue("iOS 不读取桌面系统 hosts；use-system-hosts: true 尚不支持。", .unsupportedFields)
        }
        dns["use-system-hosts"] = false
        notes.append("不读取系统 hosts；fake-ip 映射仅在本次隧道会话中保存，重连后重建。")
        return Result(value: dns, needsSystem: needsSystem, notes: notes)
    }
    /// Match the pinned core's defaults, including DNS-only Geo dependencies.
    static func fallbackGeoIPCode(_ input: Any?) -> String? {
        guard let dns = input as? [String: Any], let fallback = dns["fallback"] as? [String], !fallback.isEmpty else { return nil }
        let filter = dns["fallback-filter"] as? [String: Any] ?? [:]
        guard ConfigurationValidation.boolean(filter["geoip"]) != false else { return nil }
        return (filter["geoip-code"] as? String ?? "CN").uppercased()
    }
    static func preservePolicyOrder(source: Data, runtime: String, root: [String: Any]) throws -> String {
        guard let dns = root["dns"] as? [String: Any], dns["nameserver-policy"] != nil || dns["proxy-server-nameserver-policy"] != nil else { return runtime }
        // An app-added policy on nodes-only/URI input has no original ordering to restore.
        let originalDNS = try ConfigurationInput.read(source, resolveResources: false).root["dns"] as? [String: Any]
        guard originalDNS?["nameserver-policy"] != nil || originalDNS?["proxy-server-nameserver-policy"] != nil else { return runtime }
        var error: NSError?
        guard let result = HakoPreserveDNSPolicyOrderForIOS(String(decoding: source, as: UTF8.self), runtime, &error) else {
            throw ConfigurationValidation.issue("DNS 策略顺序无法保留；未启用候选配置。")
        }
        return result.value
    }
    static func validListener(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard value.utf8.count <= 128, let url = URLComponents(string: "udp://" + value),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty, let port = url.port, (1...65535).contains(port), let host = url.host else { return false }
        if host.isEmpty { return value == ":" + String(port) }
        let address = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return ConfigurationValidation.address(address, ipv6: address.contains(":"))
    }
    static func validPattern(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 253 && value.range(of: "^[A-Za-z0-9+*._-]+$", options: .regularExpression) != nil
    }
    static func validGeoCode(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.range(of: "^!?[A-Za-z0-9_-]+(?:@[A-Za-z0-9_-]+)?$", options: .regularExpression) != nil
    }
    static func validPolicyPattern(_ value: String) -> Bool {
        if value.hasPrefix("geosite:") { return value.dropFirst(8).split(separator:",", omittingEmptySubsequences:false).allSatisfy { validGeoCode(String($0)) } }
        if value.hasPrefix("rule-set:") { return value.dropFirst(9).split(separator:",", omittingEmptySubsequences:false).allSatisfy { ConfigurationValidation.validName(String($0)) } }
        return value.split(separator:",", omittingEmptySubsequences:false).allSatisfy { validPattern(String($0)) }
    }
    static func geoSiteCodes(_ input: Any?) -> [String] {
        guard let dns = input as? [String: Any] else { return [] }
        var codes = (dns["fallback-filter"] as? [String: Any])?["geosite"] as? [String] ?? []
        for key in ["nameserver-policy", "proxy-server-nameserver-policy"] {
            for pattern in (dns[key] as? [String: Any] ?? [:]).keys where pattern.hasPrefix("geosite:") {
                codes += pattern.dropFirst(8).split(separator:",").map(String.init)
            }
        }
        return Array(Set(codes)).sorted()
    }
    static func validateHosts(_ input: Any?) throws {
        guard let input else { return }
        guard let hosts = input as? [String: Any], hosts.count <= 1024 else { throw ConfigurationValidation.issue("hosts 需要最多 1024 项映射。") }
        for (domain, value) in hosts {
            let addresses = (value as? [String]) ?? (value as? String).map { [$0] } ?? []
            guard validPattern(domain), !addresses.isEmpty, addresses.count <= 16,
                  addresses.allSatisfy({ ConfigurationValidation.address($0, ipv6:$0.contains(":")) }) else { throw ConfigurationValidation.issue("hosts 当前支持域名模式到 IPv4/IPv6 地址或地址列表；不接受无效地址或域名别名。") }
        }
    }
    static func validServer(_ value: String, bootstrap: Bool = false) -> Bool {
        guard value.utf8.count <= 2048, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        if value == "system" || value == "system://" { return true }
        let parts = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let name = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            guard !name.isEmpty, !name.contains("&"), !name.contains("="), !name.contains("#"), !bootstrap || name == "DIRECT" else { return false }
        }
        let value = String(parts[0])
        if ConfigurationValidation.address(value, ipv6: value.contains(":")) { return true }
        let normalized = value.contains("://") ? value : "udp://" + value
        guard let url = URLComponents(string: normalized), let scheme = url.scheme,
              ["udp", "tcp", "tls", "https"].contains(scheme), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, let host = url.host, !host.isEmpty else { return false }
        if !value.contains("://"), !ConfigurationValidation.address(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), ipv6: host.contains(":")) { return false }
        if bootstrap && !ConfigurationValidation.address(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), ipv6: host.contains(":")) { return false }
        return url.port == nil || (1...65535).contains(url.port!)
    }
}
