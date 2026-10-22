import Foundation
import CoreFoundation
import Darwin

nonisolated enum ConfigurationValidation {
    nonisolated static func issue(_ detail: String, _ code: PrototypeError = .unsupportedShape) -> ConfigurationIssue {
        ConfigurationIssue(code: code, detail: detail)
    }
    static func keys(_ object: [String: Any], _ allowed: Set<String>, at location: String) throws {
        let extra = Set(object.keys).subtracting(allowed)
        guard !extra.isEmpty else { return }
        // Unknown keys could themselves contain credentials. Only known field names are shown.
        let known = ConfigurationPolicy.knownFields
        let labels = extra.intersection(known).sorted()
        let hidden = extra.subtracting(known).count
        let suffix = (labels.isEmpty ? "" : "尚未支持 " + labels.joined(separator: "、")) + (hidden == 0 ? "" : "；另有 \(hidden) 个未识别字段（名称已隐藏）")
        throw issue(location + "：" + suffix + "。", .unsupportedFields)
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    static func optionalBooleans(_ object: [String: Any], _ keys: [String], at location: String) throws {
        for key in keys where object[key] != nil {
            guard boolean(object[key]) != nil else { throw issue(location + "：布尔字段类型错误。") }
        }
    }
    static func validName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && !value.contains(",") &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
        !["DIRECT", "REJECT", "REJECT-DROP", "PASS", "GLOBAL", "COMPATIBLE"].contains(value)
    }
    static func host(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return !value.isEmpty && value.utf8.count <= 253 &&
            value.range(of: "^[A-Za-z0-9.:-]+$", options: .regularExpression) != nil
    }
    static func secret(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return !value.isEmpty && value.utf8.count <= 4096 && !value.contains("\u{0}")
    }
    static func port(_ value: Any?, allowZero: Bool = false) -> Bool {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue.rounded() == number.doubleValue &&
                (Double(allowZero ? 0 : 1)...65535).contains(number.doubleValue)
        }
        guard let text = value as? String, (1...5).contains(text.utf8.count),
              let first = text.utf8.first, (49...57).contains(first),
              text.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(text), (1...65535).contains(port) else { return false }
        return true
    }
    static func bandwidth(_ value: Any?) -> Bool {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue.isFinite && (0...100_000).contains(number.doubleValue)
        }
        guard let text = value as? String, text.count <= 32 else { return false }
        return text.range(of: "^[0-9]+(?:\\.[0-9]+)?(?: ?[kKmMgG]?[bB](?:ps)?)?$", options: .regularExpression) != nil
    }
    static func cidr(_ value: String, ipv6: Bool) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let prefix = Int(parts[1]), (0...(ipv6 ? 128 : 32)).contains(prefix) else { return false }
        return address(String(parts[0]), ipv6: ipv6)
    }
    static func address(_ value: String, ipv6: Bool) -> Bool {
        var storage = in6_addr()
        return value.withCString { inet_pton(ipv6 ? AF_INET6 : AF_INET, $0, &storage) } == 1
    }
    static func validateNode(_ node: [String: Any], index: Int) throws -> ConfigurationCatalog.Node {
        let location = "节点 \(index + 1)"
        guard let kind = node["type"] as? String, ConfigurationNodeOptions.kinds.contains(kind) else {
            throw issue(location + "：此协议尚未接入。")
        }
        try keys(node, ConfigurationNodeOptions.fields(kind), at: location)
        try ConfigurationNodeOptions.validateInactive(node, at: location)
        guard let name = node["name"] as? String, validName(name), host(node["server"]) else {
            throw issue(location + "：名称或服务器字段格式错误。")
        }
        guard port(node["port"]) else { throw PrototypeError.invalidPort }
        try optionalBooleans(node, ["skip-cert-verify", "tls", "udp"], at: location)
        if let fingerprint = node["fingerprint"] {
            guard let text = fingerprint as? String,
                  text.replacingOccurrences(of: ":", with: "").range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw issue(location + "：fingerprint 必须是 SHA-256 证书指纹，不是浏览器名称。")
            }
        }
        if let value = node["alpn"] {
            guard let values = value as? [String], !values.isEmpty, values.count <= 8,
                  values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && !$0.contains("\u{0}") }) else {
                throw issue(location + "：alpn 必须是非空字符串列表。")
            }
        }
        if ["vless", "vmess", "trojan"].contains(kind) {
            try ConfigurationNodeOptions.validateTransport(node, kind: kind, at: location)
        }
        if kind == "ss" {
            try ConfigurationNodeOptions.validateSS(node, at: location)
        } else if kind == "tuic" {
            guard let uuid = node["uuid"] as? String, UUID(uuidString: uuid) != nil,
                  secret(node["password"]), node["sni"] == nil || host(node["sni"]) else {
                throw issue(location + "：TUIC v5 需要有效 UUID、密码及 SNI；暂不支持 v4 token。")
            }
            try optionalBooleans(node, ["disable-sni", "reduce-rtt", "fast-open"], at: location)
            for (key, allowed) in [("udp-relay-mode", ["native", "quic"]), ("congestion-controller", ["bbr", "cubic", "new_reno"])] {
                if let value = node[key], !(value is String && allowed.contains(value as! String)) { throw issue(location + "：TUIC " + key + " 不支持。") }
            }
            for (key, range) in [("heartbeat-interval", 1...600000), ("request-timeout", 1...600000), ("max-open-streams", 1...1024), ("max-udp-relay-packet-size", 576...65535)] {
                if let value = node[key], !ConfigurationNodeOptions.integer(value, range: range) { throw issue(location + "：TUIC " + key + " 超出支持范围。") }
            }
        } else if kind == "trojan" {
            guard secret(node["password"]), node["sni"] == nil || host(node["sni"]) else { throw issue(location + "：Trojan 凭据或 SNI 无效。") }
        } else if kind == "vmess" {
            guard let uuid = node["uuid"] as? String, UUID(uuidString: uuid) != nil,
                  let cipher = node["cipher"] as? String, ["auto", "aes-128-gcm", "chacha20-poly1305", "none", "zero"].contains(cipher),
                  ConfigurationNodeOptions.integer(node["alterId"], range: 0...65535),
                  node["servername"] == nil || host(node["servername"]) else { throw issue(location + "：VMess UUID、cipher、alterId 或 TLS 名称无效。") }
        } else if kind == "vless" {
            guard let uuid = node["uuid"] as? String, UUID(uuidString: uuid) != nil,
                  node["servername"] == nil || host(node["servername"]),
                  node["flow"] == nil || ["", "xtls-rprx-vision"].contains(node["flow"] as? String ?? "?") else {
                throw issue(location + "：VLESS 要求有效 UUID；flow 可为 Vision。")
            }
            if let value = node["client-fingerprint"] {
                guard let value = value as? String,
                      ["chrome", "firefox", "safari", "ios", "android", "edge", "360", "qq", "random", "randomized"].contains(value) else {
                    throw issue(location + "：不支持此 client-fingerprint。")
                }
            }
            if node["flow"] as? String == "xtls-rprx-vision" {
                guard boolean(node["tls"]) == true, ConfigurationNodeOptions.transportName(node) == "tcp" else {
                    throw issue(location + "：Vision flow 需要 TCP + TLS，不能与 gRPC 组合。")
                }
            }
            if let reality = node["reality-opts"] {
                guard boolean(node["tls"]) == true, ["tcp", "grpc"].contains(ConfigurationNodeOptions.transportName(node)) else {
                    throw issue(location + "：Reality 当前支持 TCP 或 gRPC，且需要 TLS。")
                }
                guard let reality = reality as? [String: Any] else { throw issue(location + "：Reality 格式错误。") }
                try keys(reality, ["public-key", "short-id"], at: location + " Reality")
                guard let key = reality["public-key"] as? String, key.utf8.count == 43,
                      let decoded = Data(base64Encoded: key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
                      decoded.count == 32 else { throw issue(location + "：Reality public-key 格式错误。") }
                if let id = reality["short-id"] {
                    guard let text = id as? String, text.count <= 16, text.count % 2 == 0,
                          text.isEmpty || text.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else {
                        throw issue(location + "：Reality short-id 格式错误。")
                    }
                }
                guard node["client-fingerprint"] != nil else { throw issue(location + "：Reality 需要 client-fingerprint。") }
            }
        } else {
            guard secret(node["password"]), node["sni"] == nil || host(node["sni"]) else {
                throw issue(location + "：Hysteria2 凭据或 SNI 格式错误。")
            }
            if node["obfs"] != nil || node["obfs-password"] != nil {
                guard node["obfs"] as? String == "salamander", secret(node["obfs-password"]) else {
                    throw issue(location + "：当前仅支持 Salamander 混淆，且必须提供混淆密码。")
                }
            }
            for key in ["up", "down"] where node[key] != nil {
                guard bandwidth(node[key]) else { throw issue(location + "：带宽字段格式错误。") }
            }
        }
        let label = "节点 \(index + 1) · " + (["hy2", "hysteria2"].contains(kind) ? "Hysteria2" : kind.uppercased())
        return .init(name: name, kind: kind, isFixture: (node["server"] as? String)?.hasSuffix(".invalid") == true, label: label)
    }
}
