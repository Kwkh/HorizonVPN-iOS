import Foundation

/// Strict, local conversion. Unknown parameters are rejected, never discarded.
nonisolated enum NodeURI {
    static let schemes = ["ss", "vmess", "vless", "trojan", "hy2", "hysteria2", "tuic"]
    static func failure(_ index: Int, _ detail: String) -> ConfigurationIssue {
        ConfigurationValidation.issue("节点链接 \(index + 1)：" + detail)
    }
    static func base64(_ value: String) -> Data? {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !s.isEmpty, s.utf8.count <= PrototypeConfiguration.maximumBytes,
              s.range(of: "^[A-Za-z0-9+/]*={0,2}$", options: .regularExpression) != nil, s.count % 4 != 1 else { return nil }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
    static func parse(_ value: String, index: Int) throws -> [String: Any] {
        guard value.utf8.count <= 16384, let schemeEnd = value.range(of: "://") else { throw failure(index, "格式无效。") }
        let scheme = String(value[..<schemeEnd.lowerBound]).lowercased()
        guard schemes.contains(scheme) else { throw failure(index, "协议尚未支持。") }
        if scheme == "vmess" { return try vmess(String(value[schemeEnd.upperBound...]), index: index) }
        var input = value
        if scheme == "ss" {
            let body = String(value[schemeEnd.upperBound...])
            let pieces = body.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            if !pieces[0].contains("@") {
                guard let data = base64(String(pieces[0])), let decoded = String(data: data, encoding: .utf8),
                      let at = decoded.lastIndex(of: "@") else { throw failure(index, "SS Base64 格式无效。") }
                let credentials = String(decoded[..<at]).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                input = "ss://" + credentials + "@" + decoded[decoded.index(after: at)...] + (pieces.count == 2 ? "#" + pieces[1] : "")
            }
        }
        guard let c = URLComponents(string: input), let server = c.host, let port = c.port ?? (["hy2", "hysteria2"].contains(scheme) ? 443 : nil),
              !server.isEmpty, (1...65535).contains(port), c.path.isEmpty || c.path == "/",
              let user = c.user, !user.isEmpty else { throw failure(index, "需要服务器、端口和凭据。") }
        var q: [String: String] = [:]
        for item in c.queryItems ?? [] {
            guard q[item.name] == nil, let value = item.value else { throw failure(index, "参数重复或缺少值。") }
            q[item.name] = value
        }
        let kind = scheme == "hy2" ? "hysteria2" : scheme
        var n: [String: Any] = ["type": kind, "name": c.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? "Node-\(index + 1)",
                                "server": server.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), "port": port]
        func allow(_ keys: Set<String>) throws {
            guard Set(q.keys).isSubset(of: keys) else { throw failure(index, "包含未支持参数（名称与值已隐藏）。") }
        }
        func alias(_ a: String, _ b: String) throws -> String? {
            guard q[a] == nil || q[b] == nil else { throw failure(index, "同一字段存在多个别名。") }
            return q[a] ?? q[b]
        }
        if kind == "tuic" {
            try allow(["sni", "alpn", "congestion_control", "udp_relay_mode", "insecure", "allowInsecure", "disable_sni", "reduce_rtt"])
            guard let password = c.password, !password.isEmpty else { throw failure(index, "TUIC v5 需要 UUID 与密码。") }
            n["uuid"] = user; n["password"] = password; n["sni"] = q["sni"]
            n["congestion-controller"] = q["congestion_control"]
            n["udp-relay-mode"] = q["udp_relay_mode"]
            if let alpn = q["alpn"] { n["alpn"] = alpn.components(separatedBy: ",") }
            for (input, output) in [("disable_sni", "disable-sni"), ("reduce_rtt", "reduce-rtt")] {
                if let value = q[input] {
                    guard ["0", "1", "false", "true"].contains(value) else { throw failure(index, "TUIC 布尔参数无效。") }
                    n[output] = ["1", "true"].contains(value)
                }
            }
            if let value = try alias("insecure", "allowInsecure") {
                guard ["0", "1", "false", "true"].contains(value) else { throw failure(index, "证书校验开关无效。") }
                n["skip-cert-verify"] = ["1", "true"].contains(value)
            }
        } else if kind == "ss" {
            try allow(["plugin"])
            var auth: String
            if let password = c.password { auth = user + ":" + password }
            else if user.contains(":") { auth = user }
            else if let data = base64(user), let decoded = String(data: data, encoding: .utf8) { auth = decoded }
            else { throw failure(index, "SS 凭据编码无效。") }
            let parts = auth.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw failure(index, "SS 缺少 cipher 或密码。") }
            n["cipher"] = String(parts[0]); n["password"] = String(parts[1])
            if let plugin = q["plugin"] {
                let parsed = try ssPlugin(plugin, index: index)
                n["plugin"] = parsed.name; n["plugin-opts"] = parsed.options
            }
        } else {
            guard c.password == nil || kind == "hysteria2" else { throw failure(index, "凭据中的特殊字符需要百分号编码。") }
            if kind == "hysteria2" {
                try allow(["sni", "peer", "insecure", "obfs", "obfs-password", "up", "down", "alpn", "pinSHA256"])
                n["password"] = user + (c.password.map { ":" + $0 } ?? "")
                n["sni"] = try alias("sni", "peer")
                n["fingerprint"] = q["pinSHA256"]
                for key in ["obfs", "obfs-password", "up", "down"] { n[key] = q[key] }
            } else {
                try allow(["type", "security", "sni", "peer", "fp", "alpn", "flow", "pbk", "sid", "path", "host", "serviceName", "mode", "encryption", "allowInsecure", "insecure", "packetEncoding", "ed", "eh"])
                n[kind == "vless" ? "uuid" : "password"] = user
                let security = q["security"] ?? (kind == "trojan" ? "tls" : "none")
                guard ["tls", "reality", "none"].contains(security), kind != "trojan" || security == "tls" else { throw failure(index, "不支持此安全层组合。") }
                if kind == "vless" { n["tls"] = security != "none" }
                n[kind == "trojan" ? "sni" : "servername"] = try alias("sni", "peer")
                n["client-fingerprint"] = q["fp"]
                if let flow = q["flow"] { guard kind == "vless" else { throw failure(index, "flow 不适用于此协议。") }; n["flow"] = flow }
                if let encryption = q["encryption"], kind != "vless" || encryption != "none" { throw failure(index, "不支持此 encryption。") }
                if let packet = q["packetEncoding"] { guard kind == "vless" else { throw failure(index, "packetEncoding 不适用于此协议。") }; n["packet-encoding"] = packet }
                if security == "reality" {
                    guard kind == "vless", let key = q["pbk"] else { throw failure(index, "Reality 缺少参数。") }
                    var reality = ["public-key": key]
                    if let sid = q["sid"] { reality["short-id"] = sid }
                    n["reality-opts"] = reality
                } else if q["pbk"] != nil || q["sid"] != nil { throw failure(index, "Reality 参数与安全层不匹配。") }
                let network = q["type"] ?? "tcp"
                n["network"] = network
                if network == "ws" {
                    guard q["serviceName"] == nil, q["mode"] == nil else { throw failure(index, "gRPC 参数与 WS 不匹配。") }
                    var ws: [String: Any] = [:]
                    ws["path"] = q["path"]
                    if let host = q["host"] { ws["headers"] = ["Host": host] }
                    if let early = q["ed"] { guard let count = Int(early) else { throw failure(index, "early data 无效。") }; ws["max-early-data"] = count }
                    ws["early-data-header-name"] = q["eh"]
                    if !ws.isEmpty { n["ws-opts"] = ws }
                } else if network == "grpc" {
                    guard q["path"] == nil, q["host"] == nil, q["ed"] == nil, q["eh"] == nil,
                          q["mode"] == nil || q["mode"] == "gun" else { throw failure(index, "gRPC 参数组合尚未支持。") }
                    n["grpc-opts"] = ["grpc-service-name": q["serviceName"] ?? ""]
                } else if ["path", "host", "serviceName", "mode", "ed", "eh"].contains(where: { q[$0] != nil }) { throw failure(index, "传输参数与 TCP 不匹配。") }
            }
            if let alpn = q["alpn"] { n["alpn"] = alpn.components(separatedBy: ",") }
            if let insecure = try alias("insecure", "allowInsecure") {
                guard ["0", "1", "false", "true"].contains(insecure) else { throw failure(index, "证书校验开关无效。") }
                n["skip-cert-verify"] = ["1", "true"].contains(insecure)
            }
        }
        // Explicit convention for node links, which normally omit the YAML UDP switch.
        if ["ss", "trojan", "vmess", "vless"].contains(kind) { n["udp"] = true }
        _ = try ConfigurationValidation.validateNode(n, index: index)
        return n
    }
    /// SIP002 plugin options are already URL-decoded by URLComponents. Escapes
    /// apply to separators here; do not percent-decode a second time.
    private static func ssPlugin(_ input: String, index: Int) throws -> (name: String, options: [String: Any]) {
        var tokens = [String](), token = "", escaped = false
        for character in input {
            if escaped { token.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == ";" { tokens.append(token); token = "" }
            else { token.append(character) }
        }
        guard !escaped else { throw failure(index, "插件转义格式无效。") }
        tokens.append(token)
        let identifier = tokens.removeFirst()
        let name = ["obfs-local", "simple-obfs", "obfs"].contains(identifier) ? "obfs" : identifier
        guard ["obfs", "v2ray-plugin"].contains(name) else { throw failure(index, "SS 插件尚未支持。") }
        var options: [String: Any] = [:]
        for token in tokens {
            let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = pair.first, !first.isEmpty else { throw failure(index, "插件参数为空。") }
            let key = String(first), value = pair.count == 2 ? String(pair[1]) : nil
            let target = name == "obfs" ? ["obfs": "mode", "obfs-host": "host"][key] : ["mode": "mode", "host": "host", "path": "path", "tls": "tls", "mux": "mux", "skip-cert-verify": "skip-cert-verify"][key]
            guard let target, options[target] == nil else { throw failure(index, "插件参数未支持或重复。") }
            if ["tls", "mux", "skip-cert-verify"].contains(target) {
                guard value == nil || ["true", "false", "1", "0"].contains(value!) else { throw failure(index, "插件布尔参数无效。") }
                options[target] = value == nil || value == "true" || value == "1"
            } else {
                guard let value, !value.isEmpty else { throw failure(index, "插件参数缺少值。") }
                options[target] = value
            }
        }
        if name == "v2ray-plugin", options["mode"] == nil { options["mode"] = "websocket" }
        return (name, options)
    }
    private static func vmess(_ body: String, index: Int) throws -> [String: Any] {
        guard let data = base64(body), let json = String(data: data, encoding: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw failure(index, "VMess 需要 Base64 JSON。") }
        // Reuse the duplicate-key rejecting YAML/JSON parser, not JSONSerialization's last-key-wins behavior.
        let v = try PrototypeConfiguration.decodeYAML(Data(json.utf8), configurationShape: false)
        let allowed: Set<String> = ["v", "ps", "add", "port", "id", "aid", "scy", "net", "type", "host", "path", "tls", "sni", "alpn", "fp"]
        guard Set(v.keys).isSubset(of: allowed), v["type"] == nil || v["type"] as? String == "none",
              v["v"] == nil || v["v"] as? String == "2", let host = v["add"] as? String, let uuid = v["id"] as? String else { throw failure(index, "VMess 分享字段或版本尚未支持。") }
        func str(_ key: String, _ fallback: String = "") throws -> String {
            guard let value = v[key] else { return fallback }
            guard let s = value as? String else { throw failure(index, "VMess 字段类型无效。") }
            return s
        }
        let network = try str("net", "tcp"), tls = try str("tls")
        guard ["", "none", "tls"].contains(tls) else { throw failure(index, "VMess TLS 类型无效。") }
        let aid: Int
        if let value = v["aid"] as? String, let n = Int(value) { aid = n }
        else if v["aid"] == nil { aid = 0 }
        else if ConfigurationNodeOptions.integer(v["aid"], range: 0...65535) { aid = (v["aid"] as! NSNumber).intValue }
        else { throw failure(index, "VMess alterId 无效。") }
        let title = try str("ps", "Node-\(index + 1)")
        var n: [String: Any] = ["type": "vmess", "name": title.isEmpty ? "Node-\(index + 1)" : title, "server": host,
                                "uuid": uuid, "alterId": aid, "cipher": try str("scy", "auto"), "network": network, "tls": tls == "tls", "udp": true]
        n["port"] = v["port"]
        for (key, target) in [("sni", "servername"), ("fp", "client-fingerprint")] { let value = try str(key); if !value.isEmpty { n[target] = value } }
        let alpn = try str("alpn"); if !alpn.isEmpty { n["alpn"] = alpn.components(separatedBy: ",") }
        let path = try str("path"), transportHost = try str("host")
        if network == "ws" {
            var ws: [String: Any] = [:]
            if !path.isEmpty { ws["path"] = path }
            if !transportHost.isEmpty { ws["headers"] = ["Host": transportHost] }
            if !ws.isEmpty { n["ws-opts"] = ws }
        } else if network == "grpc" {
            guard transportHost.isEmpty else { throw failure(index, "gRPC host 尚未支持。") }
            n["grpc-opts"] = ["grpc-service-name": path]
        } else if !path.isEmpty || !transportHost.isEmpty { throw failure(index, "TCP 伪装参数尚未支持。") }
        _ = try ConfigurationValidation.validateNode(n, index: index)
        return n
    }
}
