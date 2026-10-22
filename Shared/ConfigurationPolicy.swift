import Foundation

/// Standard field names only. The same registry drives validation and safe diagnostics.
nonisolated enum ConfigurationPolicy {
    static let desktopStrings: Set<String> = ["external-controller", "secret", "external-ui", "external-ui-url", "external-ui-name"]
    static let desktopPorts: Set<String> = ["mixed-port", "port", "socks-port", "redir-port", "tproxy-port"]
    static let inactiveFields: Set<String> = ["tun", "sniffer", "listeners", "authentication"]
    static let rootFields: Set<String> = Set(["hosts", "mode", "proxies", "proxy-groups", "rules", "dns", "ipv6", "allow-lan", "bind-address", "log-level", "unified-delay", "profile", "find-process-mode", "tcp-concurrent", "global-client-fingerprint", "keep-alive-interval", "keep-alive-idle", "disable-keep-alive", "proxy-providers", "rule-providers", "geodata-mode", "geox-url", "geo-auto-update", "geo-update-interval", "geodata-loader"])
        .union(desktopStrings).union(desktopPorts).union(inactiveFields)
    static let groupFields: Set<String> = ["strategy", "filter", "exclude-filter", "exclude-type","include-all", "include-all-proxies", "include-all-providers", "name", "type", "proxies", "use", "url", "interval", "timeout", "lazy", "tolerance", "expected-status", "max-failed-times", "disable-udp", "icon", "hidden"]
    static let dnsFields: Set<String> = ["listen", "prefer-h3", "enable", "ipv6", "enhanced-mode", "nameserver", "default-nameserver", "proxy-server-nameserver", "respect-rules", "fake-ip-range", "fake-ip-filter", "fake-ip-filter-mode", "use-hosts", "use-system-hosts", "nameserver-policy", "proxy-server-nameserver-policy", "direct-nameserver", "direct-nameserver-follow-policy", "fallback", "fallback-filter"]
    static let knownFields: Set<String> = rootFields.union(ConfigurationSelectionPolicy.overrideFields).union(groupFields).union(dnsFields).union([
        "tun", "sniffer", "hosts", "listeners", "external-controller-tls", "external-controller-unix", "authentication", "skip-cert-verify", "ws-opts", "grpc-opts", "xhttp-opts", "dialer-proxy", "filter", "exclude-filter", "exclude-type", "override", "health-check", "include-all", "include-all-proxies", "include-all-providers", "strategy", "geoip", "geosite", "geoip-code", "prefer-h3", "path", "header", "payload", "behavior", "format", "size-limit", "proxy", "type", "store-selected", "store-fake-ip"])

    static func adaptations(_ root: [String: Any]) throws -> [String] {
        try ConfigurationDNS.validateHosts(root["hosts"])
        var notes = try PrototypeConfiguration.desktopControllerAdaptations(root)
        for field in inactiveFields.sorted() where root[field] != nil {
            if field == "tun" || field == "sniffer" {
                try requireDisabled(root[field], flag: "enable", at: field)
                notes.append(field == "tun"
                    ? "tun.enable: false：订阅的桌面 TUN 块已关闭，其余子字段不应用也不作功能校验；原文保留。连接时仍使用 App 管理的 iOS Packet Tunnel。"
                    : "sniffer.enable: false：保留关闭语义，其余子字段不应用也不作功能校验；原文保留，不启用域名嗅探。")
            } else {
                let empty = (root[field] as? [Any])?.isEmpty == true
                guard empty else { throw ConfigurationValidation.issue(field + "：当前仅接受空列表 []。", .unsupportedFields) }
                notes.append(field + "：空配置不产生运行行为，运行配置省略此项；原文保留。非空内容仍需单独支持。")
            }
        }
        for key in desktopStrings.subtracting(PrototypeConfiguration.desktopControllerFields).sorted() where root[key] != nil {
            guard let value = root[key] as? String, value.utf8.count <= 8192, !value.contains("\u{0}") else {
                throw ConfigurationValidation.issue("顶层 " + key + "：字符串格式错误（值已隐藏）。")
            }
            notes.append(key + "：桌面管理界面资源在 iOS 不加载；不下载或开放外部管理服务。")
        }
        if let profile = root["profile"] {
            guard let profile = profile as? [String: Any] else { throw ConfigurationValidation.issue("profile 必须是映射。") }
            try ConfigurationValidation.keys(profile, ["store-selected", "store-fake-ip"], at: "profile")
            try ConfigurationValidation.optionalBooleans(profile, ["store-selected", "store-fake-ip"], at: "profile")
            notes.append("profile：节点选择由 App 钥匙串管理；内核选择和 fake-IP 磁盘缓存关闭。")
        }
        if let mode = root["find-process-mode"] {
            guard mode as? String == "off" else { throw ConfigurationValidation.issue("find-process-mode：iOS 不支持进程探测；只接受 off。") }
        }
        try ConfigurationValidation.optionalBooleans(root, ["tcp-concurrent", "disable-keep-alive", "geo-auto-update", "geodata-mode"], at: "顶层")
        for key in ["keep-alive-interval", "keep-alive-idle"] where root[key] != nil {
            guard ConfigurationNodeOptions.integer(root[key], range: 0...86400) else { throw ConfigurationValidation.issue(key + "：需要 0–86400 秒的整数。") }
        }
        if let fp = root["global-client-fingerprint"] {
            guard let fp = fp as? String, ["chrome", "firefox", "safari", "ios", "android", "edge", "360", "qq", "random", "randomized"].contains(fp) else { throw ConfigurationValidation.issue("global-client-fingerprint 尚未支持此值。") }
        }
        if root["geo-auto-update"] != nil || root["geo-update-interval"] != nil {
            if root["geo-update-interval"] != nil && !ConfigurationNodeOptions.integer(root["geo-update-interval"], range: 1...8760) { throw ConfigurationValidation.issue("geo-update-interval 格式错误。") }
            notes.append("Geo 自动更新由完整订阅的手动刷新取代；运行期间不单独替换依赖，保证可回滚。")
        }
        if let loader = root["geodata-loader"] {
            guard let loader = loader as? String, ["standard", "memconservative"].contains(loader) else { throw ConfigurationValidation.issue("geodata-loader 格式错误。") }
            notes.append("geodata-loader：iOS 固定使用 memconservative。")
        }
        return notes
    }

    /// Only an explicit Boolean false authorizes treating a block as inactive.
    /// Its payload is opaque and never reaches the core; no values enter diagnostics.
    static func requireDisabled(_ value: Any?, flag: String, at location: String) throws {
        guard let block = value as? [String: Any],
              ConfigurationValidation.boolean(block[flag]) == false else {
            throw ConfigurationValidation.issue(location + "：当前仅接受显式布尔 " + flag + ": false；启用、缺少开关或错误类型均不支持。", .unsupportedFields)
        }
    }
}
