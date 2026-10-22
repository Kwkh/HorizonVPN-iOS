import Foundation

/// Only fixed labels and ordinal positions leave the parser. Never expose source keys/values.
nonisolated struct ConfigurationCompatibility: Identifiable, Sendable {
    enum Level: String, CaseIterable, Sendable { case supported, adapted, blocked }
    struct Finding: Identifiable, Sendable {
        let id = UUID()
        let level: Level
        let location: String
        let detail: String
    }
    let id = UUID()
    var findings: [Finding] = []
    var canUse: Bool { !findings.contains { $0.level == .blocked } }

    static func inspect(_ data: Data, prepared: PrototypeConfiguration.Prepared? = nil) -> Self {
        var report = Self()
        func add(_ level: Level, _ location: String, _ detail: String) {
            guard !report.findings.contains(where: { $0.level == level && $0.location == location && $0.detail == detail }) else { return }
            report.findings.append(.init(level: level, location: location, detail: detail))
        }
        func check(_ location: String, _ action: () throws -> Void) {
            do { try action() }
            catch let error as ConfigurationIssue { add(.blocked, location, error.detail) }
            catch let error as PrototypeError { add(.blocked, location, error.summary) }
            catch { add(.blocked, location, "结构或字段无效。") }
        }
        let root: [String: Any]
        do {
            do { root = try PrototypeConfiguration.decode(data) }
            catch {
                // A missing or invalid resource must not hide unrelated node, group, DNS or root findings.
                root = try ConfigurationInput.read(data, resolveResources: false).root
                if let error = error as? ConfigurationIssue { add(.blocked, "依赖", error.detail) }
                else { add(.blocked, "依赖", "依赖校验未通过。") }
            }
        }
        catch let e as ConfigurationIssue { add(.blocked, "导入内容", e.detail); return report }
        catch { add(.blocked, "YAML", "需要不超过 1 MiB 的 UTF-8 单文档 YAML 映射；请先修复语法，再检查全部字段。"); return report }
        let known = ConfigurationPolicy.knownFields
        func keys(_ value: [String: Any], _ allowed: Set<String>, _ location: String) {
            let extras = Set(value.keys).subtracting(allowed).sorted()
            for (i, key) in extras.enumerated() {
                add(.blocked, location, known.contains(key) ? "尚未支持字段：\(key)。" : "未支持字段 \(i + 1)（名称已隐藏）。")
            }
        }
        keys(root, PrototypeConfiguration.supportedRootFields, "顶层")
        for field in ConfigurationPolicy.inactiveFields.sorted() where root[field] != nil {
            check("顶层 · " + field) {
                for note in try ConfigurationPolicy.adaptations([field: root[field]!]) { add(.adapted, "iOS", note) }
            }
        }
        // Report desktop adaptations even when an unrelated node/rule blocks import.
        for field in PrototypeConfiguration.desktopControllerFields where root[field] != nil {
            check("顶层 · " + field) {
                for note in try PrototypeConfiguration.desktopControllerAdaptations([field: root[field]!]) {
                    add(.adapted, "iOS", note)
                }
            }
        }
        for field in ["profile", "find-process-mode", "tcp-concurrent", "global-client-fingerprint", "keep-alive-interval", "keep-alive-idle", "disable-keep-alive", "external-ui", "external-ui-url", "external-ui-name"] where root[field] != nil {
            check("顶层 · " + field) { for note in try ConfigurationPolicy.adaptations([field: root[field]!]) { add(.adapted, "iOS", note) } }
        }
        for kind in ["proxy", "rule"] {
            if let providers = root[kind + "-providers"] as? [String: Any] {
                for (i, entry) in providers.sorted(by: { $0.key < $1.key }).enumerated() {
                    let location = kind + "-providers \(i + 1)"
                    if let definition = entry.value as? [String: Any] { keys(definition, ConfigurationResources.providerFields, location) }
                    // Inspect raw definitions; normalized file paths are internal, not user file-provider support.
                    if let original = try? ConfigurationInput.read(data, resolveResources: false).root[kind + "-providers"] as? [String: Any], let definition = original[entry.key] {
                        var isolated = root; isolated["proxy-providers"] = [:]; isolated["rule-providers"] = [:]
                        isolated[kind + "-providers"] = [entry.key: definition]
                        if kind == "proxy", let definition = definition as? [String: Any], let overrides = definition["override"] as? [String: Any] {
                            keys(overrides, ConfigurationSelectionPolicy.overrideFields, location + " override")
                        }
                        check(location) { _ = try ConfigurationResources.plan(isolated) }
                    }
                }
            }
        }
        if root["mode"] != nil && root["mode"] as? String != "rule" { add(.blocked, "mode", "只支持 rule 模式。") }
        let nodes = ConfigurationResources.nodes(root)
        for (i, node) in nodes.enumerated() {
            let location = "节点 \(i + 1)", kind = node["type"] as? String
            // Valid nodes need one contract check. Only invalid nodes need field-by-field
            // isolation to collect independent errors; this matters for large providers.
            let validNode = (try? ConfigurationValidation.validateNode(node, index: i)) != nil
            if !validNode, let kind, ConfigurationNodeOptions.kinds.contains(kind) {
                let fields = ConfigurationNodeOptions.fields(kind)
                keys(node, fields, location)
                var baseline: [String: Any] = ["name": "EXAMPLE", "type": kind, "server": "node.example.invalid", "port": 443, "password": "FICTIONAL-ONLY"]
                if kind == "tuic" { baseline["uuid"] = "11111111-1111-4111-8111-111111111111" }
                if kind == "vless" || kind == "vmess" {
                    baseline.removeValue(forKey: "password")
                    baseline["uuid"] = "11111111-1111-4111-8111-111111111111"
                    baseline["tls"] = true
                    if kind == "vmess" { baseline["cipher"] = "auto"; baseline["alterId"] = 0 }
                } else if kind == "ss" { baseline["cipher"] = "aes-128-gcm" }
                let coupled: Set<String> = ["network", "tls", "ws-opts", "grpc-opts", "flow", "reality-opts", "client-fingerprint", "servername", "alpn", "fingerprint"]
                for field in fields.sorted() where node[field] != nil {
                    var isolated = baseline
                    if coupled.contains(field) {
                        for key in coupled { isolated[key] = node[key] }
                    } else { isolated[field] = node[field] }
                    if field == "obfs" || field == "obfs-password" {
                        isolated["obfs"] = node["obfs"]; isolated["obfs-password"] = node["obfs-password"]
                    }
                    if kind == "ss" && ["cipher", "password", "plugin", "plugin-opts", "client-fingerprint"].contains(field) {
                        for key in ["plugin", "plugin-opts", "client-fingerprint"] { isolated[key] = node[key] }
                        isolated["cipher"] = node["cipher"]; isolated["password"] = node["password"]
                    }
                    check(location + " · " + field) { _ = try ConfigurationValidation.validateNode(isolated, index: i) }
                }
                if let ws = node["ws-opts"] as? [String: Any] { keys(ws, ["path", "headers", "max-early-data", "early-data-header-name"], location + " WS") }
                if let grpc = node["grpc-opts"] as? [String: Any] { keys(grpc, ["grpc-service-name", "grpc-user-agent"], location + " gRPC") }
                if let reality = node["reality-opts"] as? [String: Any] { keys(reality, ["public-key", "short-id"], location + " Reality") }
            }
            if !validNode { check(location) { _ = try ConfigurationValidation.validateNode(node, index: i) } }
            if ConfigurationNodeOptions.skipsCertificateVerification(node) { add(.adapted, location, "此节点跳过证书校验；首次使用此配置版本前必须明确授权，导入不会自动启用。") }
            if !report.findings.contains(where: { $0.location.hasPrefix(location) && $0.level == .blocked }) { add(.supported, location, "协议与节点字段通过当前支持范围校验。") }
        }
        let groups = root["proxy-groups"] as? [[String: Any]] ?? []
        let targets = Set(nodes.compactMap { $0["name"] as? String } + groups.compactMap { $0["name"] as? String }).union(["DIRECT", "REJECT", "REJECT-DROP"])
        for (i, group) in groups.enumerated() {
            let location = "策略组 \(i + 1)"
            check(location) { try ConfigurationGroups.validate(group, at: i) }
            if let members = try? ConfigurationResources.members(group, root: root) {
                for (j, member) in members.enumerated() where !targets.contains(member) { add(.blocked, location, "成员 \(j + 1) 引用了不存在的目标。") }
            } else { add(.blocked, location, "需要内联 proxies 成员列表。") }
        }
        if let rules = root["rules"] as? [String] {
            for note in ConfigurationRules.adaptations(rules) { add(.adapted, "iOS 规则", note) }
            for (i, rule) in rules.enumerated() {
                // Check every rule independently, with a synthetic valid terminal MATCH.
                let isMatch = rule.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) == "MATCH"
                check("规则 \(i + 1)") { _ = try ConfigurationRules.validate(isMatch ? [rule] : [rule, "MATCH,DIRECT"], targets: targets, providers: Set((root["rule-providers"] as? [String: Any] ?? [:]).keys)) }
                if isMatch && i != rules.count - 1 { add(.blocked, "规则 \(i + 1)", "MATCH 必须位于末尾。") }
            }
        }
        if let dns = root["dns"] as? [String: Any] {
            keys(dns, ConfigurationPolicy.dnsFields, "DNS")
            let baseline: [String: Any] = ["enable": true, "nameserver": ["https://1.1.1.1/dns-query"], "fallback-filter": ["geoip": false]]
            let supported = ConfigurationPolicy.dnsFields
            for field in supported.sorted() where dns[field] != nil {
                var isolated = baseline
                isolated[field] = dns[field]
                check("DNS · " + field) { _ = try ConfigurationDNS.prepare(isolated, ipv6: true, bootstrap: ["1.1.1.1"], context:root) }
            }
            for key in ["nameserver", "default-nameserver", "proxy-server-nameserver", "direct-nameserver", "fallback"] {
                if let servers = dns[key] as? [String] {
                    for (i, server) in servers.enumerated() where !ConfigurationDNS.validServer(server, bootstrap: key == "default-nameserver") { add(.blocked, "DNS " + key, "上游 \(i + 1) 的格式或协议尚未支持。") }
                }
            }
            for key in ["nameserver-policy", "proxy-server-nameserver-policy"] {
                if let policies = dns[key] as? [String: Any] {
                    for (i, entry) in policies.sorted(by: { $0.key < $1.key }).enumerated() {
                        if !ConfigurationDNS.validPolicyPattern(entry.key) { add(.blocked, "DNS " + key, "策略 \(i + 1) 不是受支持的普通域名模式。") }
                        let servers = (entry.value as? [String]) ?? (entry.value as? String).map { [$0] } ?? []
                        if servers.isEmpty || !servers.allSatisfy({ ConfigurationDNS.validServer($0) }) { add(.blocked, "DNS " + key, "策略 \(i + 1) 的上游格式未支持。") }
                    }
                }
            }
            if let fallback = dns["fallback-filter"] as? [String: Any] { keys(fallback, ["geoip", "geoip-code", "geosite", "ipcidr", "domain"], "DNS fallback-filter") }
        }
        check("DNS") {
            let dns = try ConfigurationDNS.prepare(root["dns"], ipv6: true, bootstrap: ["1.1.1.1"], context:root)
            for note in dns.notes { add(.adapted, "iOS", note) }
        }
        // Keep the existing fail-closed validator authoritative (references, cycles and bridge deviations).
        do {
            let prepared = try (prepared?.source == data ? prepared : nil) ?? PrototypeConfiguration.prepare(data)
            for note in prepared.adaptations { add(.adapted, "iOS", note) }
            add(.supported, "配置结构", prepared.summary)
        } catch let error as ConfigurationIssue { add(.blocked, "完整校验", error.detail) }
        catch let error as PrototypeError { add(.blocked, "完整校验", error.summary) }
        catch { add(.blocked, "完整校验", "校验未通过。") }
        return report
    }
}
