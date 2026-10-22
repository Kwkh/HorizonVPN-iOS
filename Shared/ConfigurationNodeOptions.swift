import Foundation

/// A single field contract is shared by validation and compatibility diagnostics.
nonisolated enum ConfigurationNodeOptions {
    static let kinds = ["hysteria2", "hy2", "vless", "vmess", "trojan", "ss", "tuic"]
    static func fields(_ kind: String) -> Set<String> {
        let base: Set<String> = ["name", "type", "server", "port", "tfo", "mptcp", "smux", "ip-version"]
        let tls: Set<String> = ["alpn", "fingerprint", "skip-cert-verify"]
        let transport: Set<String> = ["network", "ws-opts", "grpc-opts", "udp", "client-fingerprint"]
        switch kind {
        case "tuic": return base.union(tls).union(["uuid", "password", "sni", "udp-relay-mode", "congestion-controller", "heartbeat-interval", "request-timeout", "disable-sni", "reduce-rtt", "fast-open", "max-open-streams", "max-udp-relay-packet-size"])
        case "ss": return base.union(["cipher", "password", "udp", "udp-over-tcp", "udp-over-tcp-version", "plugin", "plugin-opts", "client-fingerprint"])
        case "vmess": return base.union(tls).union(transport).union(["uuid", "alterId", "cipher", "tls", "servername", "packet-encoding", "global-padding", "authenticated-length"])
        case "vless": return base.union(tls).union(transport).union(["uuid", "flow", "tls", "servername", "reality-opts", "packet-encoding"])
        case "trojan": return base.union(tls).union(transport).union(["password", "sni"])
        default: return base.union(tls).union(["udp", "password", "sni", "obfs", "obfs-password", "up", "down"])
        }
    }
    static func transportName(_ node: [String: Any]) -> String {
        let value = node["network"] as? String ?? ""
        return value.isEmpty ? "tcp" : value
    }
    static func validateInactive(_ node: [String: Any], at location: String) throws {
        for field in ["mptcp"] where node[field] != nil {
            guard ConfigurationValidation.boolean(node[field]) == false else {
                throw ConfigurationValidation.issue(location + " · " + field + "：当前仅支持布尔 false；不将启用或错误类型静默改为关闭。", .unsupportedFields)
            }
        }
        try ConfigurationValidation.optionalBooleans(node, ["tfo", "global-padding", "authenticated-length", "udp-over-tcp"], at: location)
        if let version = node["ip-version"], !(version is String && ["dual", "ipv4", "ipv6", "ipv4-prefer", "ipv6-prefer"].contains(version as! String)) {
            throw ConfigurationValidation.issue(location + "：ip-version 无效。")
        }
        let kind = node["type"] as? String ?? ""
        if ["hysteria2", "hy2", "tuic"].contains(kind) && ConfigurationValidation.boolean(node["tfo"]) == true {
            throw ConfigurationValidation.issue(location + "：QUIC 节点不使用 TCP Fast Open。")
        }
        if ["hysteria2", "hy2"].contains(kind), let udp = node["udp"], ConfigurationValidation.boolean(udp) != true {
            throw ConfigurationValidation.issue(location + "：Hysteria2 原生支持 UDP，目前不能通过 udp:false 关闭。")
        }
        if let value = node["smux"] {
            guard let mux = value as? [String: Any], let enabled = ConfigurationValidation.boolean(mux["enabled"]) else { throw ConfigurationValidation.issue(location + "：smux 需要布尔 enabled。") }
            if enabled {
                guard ["ss", "vmess", "vless", "trojan"].contains(kind) else { throw ConfigurationValidation.issue(location + "：此协议未接入 smux。") }
                try ConfigurationValidation.keys(mux, ["enabled", "protocol", "max-connections", "min-streams", "max-streams", "padding", "statistic", "only-tcp"], at: location + " smux")
                try ConfigurationValidation.optionalBooleans(mux, ["enabled", "padding", "statistic", "only-tcp"], at: location + " smux")
                if let proto = mux["protocol"], !(proto is String && ["smux", "yamux", "h2mux"].contains(proto as! String)) { throw ConfigurationValidation.issue(location + "：smux protocol 无效。") }
                for key in ["max-connections", "min-streams", "max-streams"] where mux[key] != nil {
                    guard integer(mux[key], range: 0...1024) else { throw ConfigurationValidation.issue(location + "：smux 并发参数超出范围。") }
                }
            }
        }
    }
    static func runtime(_ node: [String: Any]) -> [String: Any] {
        var result = node
        // Validated false-only options are absent in the runtime, exactly as with omission.
        for field in ["tfo", "mptcp", "global-padding", "authenticated-length"] where ConfigurationValidation.boolean(node[field]) == false { result.removeValue(forKey: field) }
        if let mux = node["smux"] as? [String: Any], ConfigurationValidation.boolean(mux["enabled"]) == false { result.removeValue(forKey: "smux") }
        if ["hy2", "hysteria2"].contains(node["type"] as? String ?? "") { result.removeValue(forKey: "udp") }
        if result["network"] as? String == "" { result["network"] = "tcp" }
        if result["packet-encoding"] as? String == "" { result.removeValue(forKey: "packet-encoding") }
        return result
    }
    static func notes(_ nodes: [[String: Any]]) -> [String] {
        var notes: [String] = []
        if nodes.contains(where: { node in ["tfo", "mptcp", "smux", "global-padding", "authenticated-length"].contains { node[$0] != nil } }) {
            notes.append("保留已支持的节点连接选项；显式 false 与关闭的 smux 从运行配置省略。smux.enabled:false 的其余子字段不应用，原文保留；MPTCP 仍仅接受关闭。")
        }
        if nodes.contains(where: { $0["network"] as? String == "" || $0["packet-encoding"] as? String == "" }) {
            notes.append("空 network 按内核默认 TCP 处理；空 packet-encoding 使用原始 UDP 编码。原文保留，不修改显式非空选项。")
        }
        if nodes.contains(where: { ["hy2", "hysteria2"].contains($0["type"] as? String ?? "") && $0["udp"] != nil }) { notes.append("Hysteria2 的 udp:true 按协议原生 UDP 能力处理；此字段不传给不读取该开关的内核，原文保留。") }
        return notes
    }
    static func integer(_ value: Any?, range: ClosedRange<Int>) -> Bool {
        guard let n = value as? NSNumber, ConfigurationValidation.boolean(value) == nil else { return false }
        return n.doubleValue.isFinite && n.doubleValue.rounded() == n.doubleValue &&
            n.doubleValue >= Double(range.lowerBound) && n.doubleValue <= Double(range.upperBound)
    }
    static func text(_ value: Any?, limit: Int = 4096, empty: Bool = false) -> Bool {
        guard let s = value as? String else { return false }
        return (empty || !s.isEmpty) && s.utf8.count <= limit &&
            !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func validateTransport(_ node: [String: Any], kind: String, at location: String) throws {
        let fail = ConfigurationValidation.issue
        let network = transportName(node)
        guard ["tcp", "ws", "grpc"].contains(network), node["network"] == nil || node["network"] is String else {
            throw fail(location + "：传输仅支持 TCP、WebSocket、gRPC。", .unsupportedShape)
        }
        if node["ws-opts"] != nil {
            guard network == "ws", let ws = node["ws-opts"] as? [String: Any] else { throw fail(location + "：ws-opts 需要 WebSocket 传输。", .unsupportedShape) }
            try ConfigurationValidation.keys(ws, ["path", "headers", "max-early-data", "early-data-header-name"], at: location + " WS")
            if let path = ws["path"] { guard text(path), (path as? String)?.hasPrefix("/") == true else { throw fail(location + "：WS 路径无效。", .unsupportedShape) } }
            if let headers = ws["headers"] {
                guard let headers = headers as? [String: String], headers.count <= 32,
                      headers.allSatisfy({ key, value in
                          !key.isEmpty && key.utf8.count <= 128 && key.range(of: "^[A-Za-z0-9!#$%&'*+.^_`|~-]+$", options: .regularExpression) != nil && text(value)
                      }) else { throw fail(location + "：WS headers 格式无效。", .unsupportedShape) }
            }
            if let early = ws["max-early-data"], !integer(early, range: 0...65536) { throw fail(location + "：WS early data 超出范围。", .unsupportedShape) }
            if let header = ws["early-data-header-name"], !text(header, limit: 128) || (header as? String)?.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) == nil { throw fail(location + "：WS early data header 无效。", .unsupportedShape) }
        }
        if node["grpc-opts"] != nil {
            guard network == "grpc", let grpc = node["grpc-opts"] as? [String: Any] else { throw fail(location + "：grpc-opts 需要 gRPC 传输。", .unsupportedShape) }
            try ConfigurationValidation.keys(grpc, ["grpc-service-name", "grpc-user-agent"], at: location + " gRPC")
            for field in ["grpc-service-name", "grpc-user-agent"] where grpc[field] != nil {
                guard text(grpc[field], empty: true) else { throw fail(location + "：gRPC 字段格式无效。", .unsupportedShape) }
            }
        }
        if let fp = node["client-fingerprint"] {
            guard let fp = fp as? String, ["chrome", "firefox", "safari", "ios", "android", "edge", "360", "qq", "random", "randomized"].contains(fp) else { throw fail(location + "：不支持此 client-fingerprint。", .unsupportedShape) }
        }
        if let encoding = node["packet-encoding"] {
            guard let encoding = encoding as? String, ["", "packetaddr", "xudp"].contains(encoding) else { throw fail(location + "：不支持此 packet-encoding。", .unsupportedShape) }
        }
        let secure = kind == "trojan" || ConfigurationValidation.boolean(node["tls"]) == true
        if !secure && ["servername", "client-fingerprint", "alpn", "fingerprint", "reality-opts"].contains(where: { node[$0] != nil }) {
            throw fail(location + "：TLS 参数需要启用 TLS。", .unsupportedShape)
        }
    }
    static let ssCiphers = ["aes-128-gcm", "aes-192-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305"]
    static func validateSS(_ node: [String: Any], at location: String) throws {
        guard let cipher = node["cipher"] as? String, ssCiphers.contains(cipher), ConfigurationValidation.secret(node["password"]) else {
            throw ConfigurationValidation.issue(location + "：SS 需要受支持的 AEAD／SS2022 cipher 与密码；旧式加密尚未接入。")
        }
        try validateSSPlugin(node, at: location)
        if let version = node["udp-over-tcp-version"], !integer(version, range: 1...2) { throw ConfigurationValidation.issue(location + "：UDP over TCP 版本必须为 1 或 2。") }
        if cipher.hasPrefix("2022-") {
            let keys = (node["password"] as! String).split(separator: ":", omittingEmptySubsequences: false)
            let size = cipher == "2022-blake3-aes-128-gcm" ? 16 : 32
            guard keys.count <= 8, cipher != "2022-blake3-chacha20-poly1305" || keys.count == 1,
                  keys.allSatisfy({ Data(base64Encoded: String($0))?.count == size }) else {
                throw ConfigurationValidation.issue(location + "：SS2022 密钥编码或长度无效。")
            }
        }
    }
    static func skipsCertificateVerification(_ node: [String: Any]) -> Bool {
        ConfigurationValidation.boolean(node["skip-cert-verify"]) == true ||
        ConfigurationValidation.boolean((node["plugin-opts"] as? [String: Any])?["skip-cert-verify"]) == true
    }
    static func validateSSPlugin(_ node: [String: Any], at location: String) throws {
        if node["client-fingerprint"] != nil {
            guard node["plugin"] as? String == "v2ray-plugin",
                  ConfigurationValidation.boolean((node["plugin-opts"] as? [String: Any])?["tls"]) == true else {
                throw ConfigurationValidation.issue(location + "：SS 客户端指纹需要 v2ray-plugin TLS。")
            }
        }
        guard node["plugin"] != nil || node["plugin-opts"] != nil else { return }
        guard let plugin = node["plugin"] as? String, ["obfs", "v2ray-plugin"].contains(plugin), let options = node["plugin-opts"] as? [String: Any] else {
            throw ConfigurationValidation.issue(location + "：SS 插件仅接入 obfs 与 v2ray-plugin，且需 plugin-opts。")
        }
        let fields: Set<String> = plugin == "obfs" ? ["mode", "host"] : ["mode", "host", "path", "tls", "mux", "headers", "skip-cert-verify", "fingerprint"]
        try ConfigurationValidation.keys(options, fields, at: location + " plugin-opts")
        guard let mode = options["mode"] as? String, (plugin == "obfs" ? ["http", "tls"] : ["websocket"]).contains(mode) else { throw ConfigurationValidation.issue(location + "：SS 插件 mode 未支持。") }
        if let host = options["host"], !text(host, limit: 253) { throw ConfigurationValidation.issue(location + "：插件 host 无效。") }
        if plugin == "v2ray-plugin" {
            try ConfigurationValidation.optionalBooleans(options, ["tls", "mux", "skip-cert-verify"], at: location + " plugin-opts")
            if options["skip-cert-verify"] != nil || options["fingerprint"] != nil {
                guard ConfigurationValidation.boolean(options["tls"]) == true else { throw ConfigurationValidation.issue(location + "：插件证书选项需要 TLS。") }
            }
            if let fingerprint = options["fingerprint"] as? String {
                guard fingerprint.replacingOccurrences(of: ":", with: "").range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { throw ConfigurationValidation.issue(location + "：插件证书指纹无效。") }
            } else if options["fingerprint"] != nil { throw ConfigurationValidation.issue(location + "：插件证书指纹类型无效。") }
            var transport: [String: Any] = ["network": "ws"]
            transport["ws-opts"] = options.filter { ["path", "headers"].contains($0.key) }
            try validateTransport(transport, kind: "ss", at: location)
            if let fp = node["client-fingerprint"], !(fp is String && ["chrome", "firefox", "safari", "ios", "android", "edge", "360", "qq", "random", "randomized"].contains(fp as! String)) { throw ConfigurationValidation.issue(location + "：插件客户端指纹无效。") }
        }
    }

}
