import Foundation

/// Structural differences only. Node names, endpoints, tokens and YAML values never enter the report.
nonisolated enum SubscriptionChangeSummary {
    static func compare(_ old: Data, _ new: Data) throws -> [String] {
        let a = try PrototypeConfiguration.decode(old), b = try PrototypeConfiguration.decode(new)
        func encoded(_ value: Any?) -> Data? {
            guard let value else { return nil }
            return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
        func nodes(_ root: [String: Any]) -> [String: [String: Any]] {
            var result: [String: [String: Any]] = [:]
            for node in ConfigurationResources.nodes(root) {
                if let name = node["name"] as? String { result[name] = node }
            }
            return result
        }
        let an = nodes(a), bn = nodes(b), before = Set(an.keys), after = Set(bn.keys)
        let changed = before.intersection(after).filter { encoded(an[$0]) != encoded(bn[$0]) }.count
        var result = ["节点新增 \(after.subtracting(before).count) · 删除 \(before.subtracting(after).count) · 字段变化 \(changed)"]
        func membership(_ root: [String: Any]) throws -> [[String: Any]] {
            try (root["proxy-groups"] as? [[String: Any]] ?? []).map { group in
                ["name": group["name"] ?? "", "members": try ConfigurationResources.members(group, root: root) ?? []]
            }
        }
        let sameMembership = try encoded(membership(a)) == encoded(membership(b))
        for (key, label) in [("proxy-groups", "策略组"), ("rules", "规则"), ("dns", "DNS")] {
            let same = encoded(a[key]) == encoded(b[key]) && (key != "proxy-groups" || sameMembership)
            result.append(label + (same ? "：未改变" : "：已改变"))
        }
        var ar = a, br = b
        for key in ["proxies", "proxy-groups", "rules", "dns"] { ar.removeValue(forKey: key); br.removeValue(forKey: key) }
        result.append(encoded(ar) == encoded(br) ? "其他配置：未改变" : "其他配置：已改变")
        let oldResources = try ConfigurationSnapshot.read(old)?.resources ?? []
        let newResources = try ConfigurationSnapshot.read(new)?.resources ?? []
        if !oldResources.isEmpty || !newResources.isEmpty {
            let before = Dictionary(uniqueKeysWithValues: oldResources.map { ($0.key, $0.digest) })
            let after = Dictionary(uniqueKeysWithValues: newResources.map { ($0.key, $0.digest) })
            let keys = Set(before.keys).union(after.keys)
            result.append("依赖资源变化：\(keys.filter { before[$0] != after[$0] }.count) 项；回滚将一并恢复。")
        }
        if old != new && oldResources == newResources && encoded(a) == encoded(b) { result.append("仅原文排版或注释不同。") }
        let oldMode = try ConfigurationRouting.mode(in: old), newMode = try ConfigurationRouting.mode(in: new)
        if oldMode != newMode {
            result.append(newMode == .smart ? "分流：智能分流（原有规则优先，国内直连，剩余流量使用原代理目标）。" : "分流：恢复遵循订阅，移除智能分流附加规则与 DNS。")
        }
        return result
    }
}
