import Foundation
import Hako

/// Immutable snapshot projection. The pinned core supplies regex, override and
/// group membership semantics; no provider is started and no network is used.
nonisolated enum ConfigurationSelectionPolicy {
    static let filterFields: Set<String> = ["filter", "exclude-filter", "exclude-type"]
    static let overrideFields: Set<String> = ["udp", "skip-cert-verify", "tfo", "ip-version", "up", "down", "additional-prefix", "additional-suffix", "proxy-name"]
    static func validate(_ options: [String: Any], at location: String) throws {
        for field in filterFields where options[field] != nil {
            guard ConfigurationNodeOptions.text(options[field], limit: 2048, empty: true),
                  (options[field] as? String)?.components(separatedBy: "`").count ?? 0 <= 16 else {
                throw ConfigurationValidation.issue(location + "：筛选字段需要有限长度的字符串；最多 16 段表达式。")
            }
        }
    }
    static func validateProvider(_ options: [String: Any], at location: String) throws {
        try validate(options, at: location)
        guard let raw = options["override"] else { return }
        guard let value = raw as? [String: Any] else { throw ConfigurationValidation.issue(location + "：override 需要映射。") }
        try ConfigurationValidation.keys(value, overrideFields, at: location + " override")
        try ConfigurationValidation.optionalBooleans(value, ["udp", "skip-cert-verify", "tfo"], at: location + " override")
        if let version = value["ip-version"], !(version is String && ["dual", "ipv4", "ipv6", "ipv4-prefer", "ipv6-prefer"].contains(version as! String)) {
            throw ConfigurationValidation.issue(location + "：override ip-version 无效。")
        }
        for field in ["up", "down"] where value[field] != nil {
            guard ConfigurationValidation.bandwidth(value[field]) else { throw ConfigurationValidation.issue(location + "：override 带宽格式无效。") }
        }
        for field in ["additional-prefix", "additional-suffix"] where value[field] != nil {
            guard ConfigurationNodeOptions.text(value[field], limit: 256, empty: field.hasPrefix("additional-")) else {
                throw ConfigurationValidation.issue(location + "：override 字符串格式无效。")
            }
        }
        if let raw = value["proxy-name"] {
            guard let entries = raw as? [[String: Any]], entries.count <= 16 else { throw ConfigurationValidation.issue(location + "：proxy-name 需要最多 16 项替换列表。") }
            for entry in entries {
                try ConfigurationValidation.keys(entry, ["pattern", "target"], at: location + " proxy-name")
                guard ConfigurationNodeOptions.text(entry["pattern"], limit: 2048, empty: true),
                      ConfigurationNodeOptions.text(entry["target"], limit: 256, empty: true) else { throw ConfigurationValidation.issue(location + "：proxy-name 需要 pattern 与 target 字符串。") }
            }
        }
    }
    private static func resolve(_ input: [String: Any], at location: String) throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: input, options: [.withoutEscapingSlashes])
        var error: NSError?
        guard let result = HakoResolvePolicyForIOS(String(decoding: data, as: UTF8.self), &error),
              let value = try? JSONSerialization.jsonObject(with: Data(result.value.utf8)) else {
            throw ConfigurationValidation.issue(location + "：筛选／改名表达式无效、超过计算限额，或筛选后没有可用成员；未启用候选配置。")
        }
        return value
    }
    static func included(_ names: [String], options: [String: Any]) throws -> [String] {
        try validate(options, at: "策略组自动收集")
        guard let pattern = options["filter"] as? String, !pattern.isEmpty else { return names }
        guard let rows = try resolve(["operation": "matches", "pattern": pattern, "names": names], at: "策略组自动收集") as? [[Bool]],
              rows.allSatisfy({ $0.count == names.count }) else { throw PrototypeError.unsupportedShape }
        // Native include-all-proxies loops sorted names first, then expressions.
        // Provider filtering instead loops expressions first; do not conflate them.
        return names.indices.filter { i in rows.contains { $0[i] } }.map { names[$0] }
    }
    static func provider(_ nodes: [[String: Any]], options: [String: Any], at location: String) throws -> [[String: Any]] {
        try validateProvider(options, at: location)
        guard (1...PrototypeConfiguration.maximumNodes).contains(nodes.count) else { throw ConfigurationValidation.issue(location + "：原始节点数量需为 1–512。") }
        var seen = Set<String>()
        for node in nodes {
            guard let name = node["name"] as? String, ConfigurationValidation.validName(name), seen.insert(name).inserted,
                  node["type"] is String else { throw ConfigurationValidation.issue(location + "：原始节点名称或类型无效／重名。") }
        }
        guard filterFields.union(["override"]).contains(where: { options[$0] != nil }) else { return nodes }
        var policy = options.filter { filterFields.union(["override"]).contains($0.key) }
        if var overrides = policy["override"] as? [String: Any] {
            // The native provider decoder accepts numeric bandwidth as a string.
            for field in ["up", "down"] {
                if let number = overrides[field] as? NSNumber { overrides[field] = number.stringValue }
            }
            policy["override"] = overrides
        }
        guard let result = try resolve(["operation": "provider", "options": policy, "nodes": nodes], at: location) as? [[String: Any]] else { throw PrototypeError.unsupportedShape }
        return result
    }
    static func members(_ group: [String: Any], root: [String: Any]) throws -> [String]? {
        guard group["proxies"] == nil || group["proxies"] is [String], group["use"] == nil || group["use"] is [String] else { return nil }
        let definitions = root["proxy-providers"] as? [String: [String: Any]] ?? [:]
        let explicit = group["proxies"] as? [String] ?? [], use = group["use"] as? [String] ?? []
        // Preserve duplicate detection even if a filter could hide the error.
        guard Set(explicit).count == explicit.count, Set(use).count == use.count else { return nil }
        let plain = explicit + use.flatMap { (definitions[$0]?["payload"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } }
        guard filterFields.contains(where: { group[$0] != nil }) else { return plain }
        try validate(group, at: "策略组")
        var types: [String: String] = ["DIRECT": "DIRECT", "REJECT": "REJECT", "REJECT-DROP": "REJECT-DROP"]
        for node in ConfigurationResources.nodes(root) + (root["proxy-groups"] as? [[String: Any]] ?? []) {
            if let name = node["name"] as? String, let type = node["type"] as? String { types[name] = type }
        }
        func descriptors(_ names: [String]) throws -> [[String: String]] {
            try names.map { name in
                guard let type = types[name] else { throw ConfigurationValidation.issue("策略组引用了不存在的目标。") }
                return ["name": name, "type": type]
            }
        }
        var providers: [[String: Any]] = []
        if !explicit.isEmpty { providers.append(["compatible": true, "nodes": try descriptors(explicit)]) }
        for name in use {
            guard let nodes = definitions[name]?["payload"] as? [[String: Any]] else { throw ConfigurationValidation.issue("策略组引用了不存在的节点 provider。") }
            providers.append(["compatible": false, "nodes": try descriptors(nodes.compactMap { $0["name"] as? String })])
        }
        guard let result = try resolve(["operation": "group", "options": group.filter { filterFields.contains($0.key) }, "providers": providers], at: "策略组") as? [String] else { throw PrototypeError.unsupportedShape }
        return result
    }
}
