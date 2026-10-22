import Foundation
import Hako

nonisolated enum PrototypeConfiguration {
    nonisolated static let maximumBytes = 1024 * 1024
    static let maximumNodes = 512
    static let maximumGroups = 64
    static let maximumRules = 8192
    static let maximumMembers = 576
    // Stable Keychain/profile identity; existing installations retain their configuration.
    static let policyVersion = "hy2-salamander-v1"
    static let desktopControllerFields = ["external-controller", "secret"]
    static let supportedRootFields = ConfigurationPolicy.rootFields
    static let policySummary = "支持 Hysteria2、TUIC v5、SS/SS2022、Trojan、VMess、VLESS 与约定 TCP/WS/gRPC 组合、select／url-test／fallback／load-balance 组与 include-all 自动收集、HTTPS／inline providers、域名/IP/端口/网络/规则集与 Geo 规则；保留支持范围内的 DNS 设置。iOS 使用 Packet Tunnel，不启用桌面端口或局域网监听。桌面进程规则会明确提示并停用；跳过证书校验须使用前确认。详细适配在每次导入时列出，不会自动连接。"
    struct Prepared: Sendable {
        let source: Data
        let catalog: ConfigurationCatalog
        let runtimeJSON: String
        let adaptations: [String]
        let ruleCount: Int
        let deviationCount: Int
        let needsSystemBootstrap: Bool
        let unifiedDelay: Bool
        let insecureNodeCount: Int
        var nodeName: String? { catalog.resolvedTarget() }
        var isFixture: Bool { catalog.nodes.contains(where: \.isFixture) }
        var summary: String { "\(catalog.nodes.count) 个节点、\(catalog.groups.count) 个策略组、\(ruleCount) 条规则。" }
    }
    static func prepare(_ data: Data, bootstrapServers: [String] = ["1.1.1.1"],
                        choices: [String: String] = [:]) throws -> Prepared {
        let input = try ConfigurationInput.read(data)
        let root = input.root
        var error: NSError?
        try ConfigurationValidation.keys(root, supportedRootFields, at: "顶层")
        let controllerNotes = try ConfigurationPolicy.adaptations(root)
        guard root["mode"] == nil || root["mode"] as? String == "rule" else {
            throw ConfigurationValidation.issue("当前支持 rule 模式；global/direct 模式尚未接入。")
        }
        try ConfigurationValidation.optionalBooleans(root, ["ipv6", "allow-lan", "unified-delay"], at: "顶层")
        for key in ConfigurationPolicy.desktopPorts where root[key] != nil {
            guard ConfigurationValidation.port(root[key], allowZero: true) else { throw PrototypeError.invalidPort }
        }
        if let level = root["log-level"] {
            guard let level = level as? String, ["silent", "error", "warning", "info", "debug"].contains(level) else { throw ConfigurationValidation.issue("log-level 格式错误。") }
        }
        if let bind = root["bind-address"], !(bind is String) { throw ConfigurationValidation.issue("bind-address 格式错误。") }
        let rawNodes = ConfigurationResources.nodes(root)
        guard (1...maximumNodes).contains(rawNodes.count),
              let rawGroups = (root["proxy-groups"] ?? [[String: Any]]()) as? [[String: Any]], rawGroups.count <= maximumGroups,
              let rules = root["rules"] as? [String], (1...maximumRules).contains(rules.count) else {
            throw ConfigurationValidation.issue("需要 1–512 个节点、最多 64 个策略组及 1–8192 条规则。")
        }
        let nodes = try rawNodes.enumerated().map { try ConfigurationValidation.validateNode($0.element, index: $0.offset) }
        var names = Set(nodes.map(\.name))
        guard names.count == nodes.count else { throw ConfigurationValidation.issue("节点名称重复。") }
        var groups: [ConfigurationCatalog.Group] = []
        for (index, group) in rawGroups.enumerated() {
            try ConfigurationGroups.validate(group, at: index)
            guard let name = group["name"] as? String, names.insert(name).inserted,
                  let members = try ConfigurationResources.members(group, root: root), !members.isEmpty, members.count <= maximumMembers,
                  Set(members).count == members.count else {
                throw ConfigurationValidation.issue("策略组 \(index + 1)：名称不能重复，成员列表不能为空或重复。")
            }
            groups.append(.init(id: index, name: name, members: members, kind: group["type"] as? String ?? "select"))
        }
        let targets = names.union(["DIRECT", "REJECT", "REJECT-DROP"])
        guard groups.allSatisfy({ $0.members.allSatisfy { targets.contains($0) } }) else { throw ConfigurationValidation.issue("策略组引用了不存在的目标。") }
        let groupMap = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.members) })
        var completed = Set<String>()
        func visit(_ name: String, path: Set<String>) throws {
            guard !completed.contains(name), let members = groupMap[name] else { return }
            guard !path.contains(name) else { throw ConfigurationValidation.issue("策略组存在循环引用。") }
            for member in members { try visit(member, path: path.union([name])) }
            completed.insert(name)
        }
        for group in groups { try visit(group.name, path: []) }
        var selected: [String: String] = [:]
        for group in groups where group.allowsSelection {
            if let choice = choices[group.name] {
                guard group.members.contains(choice) else { throw ConfigurationValidation.issue("保存的节点选择已失效；请重新导入。") }
                selected[group.name] = choice
            } else { selected[group.name] = group.members[0] }
        }
        let matchTarget = try ConfigurationRules.validate(rules, targets: targets, providers: Set((root["rule-providers"] as? [String: Any] ?? [:]).keys))
        let catalog = ConfigurationCatalog(nodes: nodes, groups: groups, choices: selected, matchTarget: matchTarget)
        let dns = try ConfigurationDNS.prepare(root["dns"], ipv6: ConfigurationValidation.boolean(root["ipv6"]) ?? true, bootstrap: bootstrapServers, context: root)
        var notes = input.notes + dns.notes + controllerNotes + ConfigurationGroups.notes(rawGroups)
        notes += ConfigurationNodeOptions.notes(rawNodes)
        let insecureNodeCount = rawNodes.filter { ConfigurationNodeOptions.skipsCertificateVerification($0) }.count
        if insecureNodeCount > 0 { notes.append("包含 \(insecureNodeCount) 个跳过证书校验的节点；保存不会启用它们，连接前必须明确授权此配置版本。更新后需重新确认。") }
        notes += ConfigurationRules.adaptations(rules)
        if rawNodes.contains(where: { ($0["type"] as? String == "vless" || ($0["type"] as? String == "vmess" && ["none", "zero"].contains($0["cipher"] as? String ?? ""))) && ConfigurationValidation.boolean($0["tls"]) != true }) {
            notes.append("包含未启用 TLS 且协议本身不加密的节点；按原输入保留，没有自动增加 TLS。")
        }
        let unifiedDelay = ConfigurationValidation.boolean(root["unified-delay"]) ?? true
        notes.append(root["unified-delay"] == nil
            ? "未设置 unified-delay：默认开启，与当前 Mac Verge 一致；手动测速使用 Cloudflare HTTP 204，超时 10 秒。"
            : "保留文件的 unified-delay 设置；手动测速使用 Cloudflare HTTP 204，超时 10 秒。")
        let desktop = (ConfigurationPolicy.desktopPorts.union(["allow-lan", "bind-address"])).sorted().filter { root[$0] != nil }
        if !desktop.isEmpty { notes.append("不启用桌面监听设置：" + desktop.joined(separator: "、") + "；手机流量由 Packet Tunnel 接入。") }
        notes.append("日志固定为 silent；关闭内核磁盘缓存。选择结果和原文件共同保存在本机钥匙串，不写入日志。")
        notes.append("TUN 使用 gvisor、MTU 1280，由 iOS 安装 IPv4/IPv6 默认路由；不提供 ICMP 或局域网代理，系统保留流量可能不受默认路由覆盖。")
        if ConfigurationValidation.boolean(root["ipv6"]) == false {
            notes.append("保留 ipv6: false。为避免手机原生 IPv6 绕过，仍接入 IPv6 默认路由，并在规则最前增加 IPv6 拒绝规则。")
        }
        let document = try runtimeDocument(root, bootstrapServers: bootstrapServers, choices: selected)
        let runtime = try ConfigurationDNS.preservePolicyOrder(source: ConfigurationSnapshot.original(data), runtime: document, root: root)
        guard HakoValidateConfigShape(runtime, &error) else { throw PrototypeError.runtimeShape }
        #if HORIZON_NATIVE_MAC
        let profile = "macosPacketTunnel"
        #else
        let profile = "iosPacketTunnel"
        #endif
        guard let deviations = HakoConfigDeviationsJSON(runtime, profile, &error),
              let report = try? JSONSerialization.jsonObject(with: Data(deviations.value.utf8)) as? [String: Any],
              report["schemaVersion"] as? Int == 1, let entries = report["deviations"] as? [[String: Any]] else { throw PrototypeError.deviationReport }
        let permitted: Set<String> = ["tun.enable", "tun.device", "tun.auto-route", "tun.auto-detect-interface",
            "tun.gso", "tun.gso-max-size", "tun.recvmsgx", "tun.sendmsgx", "tun.disable-icmp-forwarding",
            "tun.dns-hijack", "tun.mtu", "geo-auto-update", "find-process-mode", "geodata-loader"]
        guard entries.allSatisfy({ entry in
            guard let field = entry["field"] as? String else { return false }
            return permitted.contains(field) && entry["category"] as? String == "forced"
        }) else { throw PrototypeError.coreDeviation }
        return Prepared(source: data, catalog: catalog, runtimeJSON: runtime, adaptations: notes, ruleCount: rules.count,
                        deviationCount: entries.count, needsSystemBootstrap: dns.needsSystem, unifiedDelay: unifiedDelay, insecureNodeCount: insecureNodeCount)
    }
    static func decode(_ data: Data) throws -> [String: Any] { try ConfigurationInput.read(data).root }
    static func desktopControllerAdaptations(_ root: [String: Any]) throws -> [String] {
        var notes: [String] = []
        for field in desktopControllerFields where root[field] != nil {
            guard let value = root[field] as? String, value.utf8.count <= 8192, !value.contains("\u{0}") else {
                throw ConfigurationValidation.issue("顶层 " + field + "：需要不超过 8192 字节的字符串（值已隐藏）。")
            }
            notes.append(field == "external-controller"
                ? "external-controller：iOS 不启用订阅中的外部控制接口；App 使用隧道 IPC，不开放该管理端口。"
                : "顶层 secret：仅用于外部控制接口认证，iOS 运行配置不采用；节点密码保持原样。")
        }
        return notes
    }
    static func decodeYAML(_ data: Data, configurationShape: Bool = true, maximumBytes: Int = maximumBytes) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumBytes, var yaml = String(data: data, encoding: .utf8) else { throw PrototypeError.invalidFile }
        var error: NSError?
        // JSON is a YAML input too, but the pinned YAML parser rejects JSON's optional \/ escape.
        // The core JSON converter preserves values and rejects duplicate keys before conversion.
        if (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            guard let converted = HakoJSONToYaml(yaml, &error) else { throw PrototypeError.invalidFile }
            yaml = converted.value
        }
        // The bridge checks EOF after the first document, allowing a legal ---.
        guard (!configurationShape || HakoValidateConfigShape(yaml, &error)), let box = HakoYamlToJSON(yaml, &error),
              let root = try? JSONSerialization.jsonObject(with: Data(box.value.utf8)) as? [String: Any] else { throw PrototypeError.invalidFile }
        return root
    }
    static func runtimeDocument(_ source: [String: Any], bootstrapServers: [String] = ["1.1.1.1"],
                                choices: [String: String] = [:]) throws -> String {
        var root = source
        // Validate again here so direct callers cannot strip an enabled feature.
        _ = try ConfigurationPolicy.adaptations(source)
        for field in ConfigurationPolicy.inactiveFields { root.removeValue(forKey: field) }
        if (root["hosts"] as? [String: Any])?.isEmpty == true { root.removeValue(forKey: "hosts") }
        func runtimeNodes(_ nodes: [[String: Any]]) throws -> [[String: Any]] {
            try nodes.enumerated().map { index, node in
                _ = try ConfigurationValidation.validateNode(node, index: index)
                return ConfigurationNodeOptions.runtime(node)
            }
        }
        if let nodes = root["proxies"] as? [[String: Any]] { root["proxies"] = try runtimeNodes(nodes) }
        if var providers = root["proxy-providers"] as? [String: [String: Any]] {
            for name in Array(providers.keys) {
                if let nodes = providers[name]?["payload"] as? [[String: Any]] {
                    providers[name]?["payload"] = try runtimeNodes(nodes)
                }
            }
            root["proxy-providers"] = providers
        }
        if let rules = source["rules"] as? [String] { root["rules"] = try ConfigurationRules.runtime(rules) }
        for field in ConfigurationPolicy.desktopPorts.union(ConfigurationPolicy.desktopStrings).union(["allow-lan", "bind-address", "geo-update-interval"]) {
            root.removeValue(forKey: field)
        }
        root["mode"] = "rule"
        root["log-level"] = "silent"
        root["ipv6"] = ConfigurationValidation.boolean(source["ipv6"]) ?? true
        root["find-process-mode"] = "off"
        root["unified-delay"] = ConfigurationValidation.boolean(source["unified-delay"]) ?? true
        root["geo-auto-update"] = false
        root["geodata-loader"] = "memconservative"
        root["profile"] = ["store-selected": false, "store-fake-ip": false]
        root["dns"] = try ConfigurationDNS.prepare(source["dns"], ipv6: root["ipv6"] as? Bool ?? true, bootstrap: bootstrapServers, context: source).value
        // select initially uses its first member. Apply saved selection before startup.
        if var groups = root["proxy-groups"] as? [[String: Any]] {
            for index in groups.indices {
                groups[index] = ConfigurationGroups.runtime(groups[index])
                if groups[index]["type"] as? String == "select", let name = groups[index]["name"] as? String, let choice = choices[name],
                   let members = groups[index]["proxies"] as? [String], members.contains(choice) {
                    groups[index]["proxies"] = [choice] + members.filter { $0 != choice }
                }
            }
            root["proxy-groups"] = groups
        }
        if root["ipv6"] as? Bool == false, let rules = root["rules"] as? [String] {
            root["rules"] = ["IP-CIDR6,::/0,REJECT,no-resolve"] + rules
        }
        root["tun"] = ["enable": true, "stack": "gvisor", "mtu": 1280, "auto-route": false,
            "auto-detect-interface": false, "device": "hako-packet-flow",
            "dns-hijack": ["0.0.0.0:53"], "disable-icmp-forwarding": true] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
