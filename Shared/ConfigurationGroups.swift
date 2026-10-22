import Foundation

nonisolated enum ConfigurationGroups {
    static let kinds = ["select", "url-test", "fallback", "load-balance"]
    static func validate(_ group: [String: Any], at index: Int) throws {
        let location = "策略组 \(index + 1)"
        try ConfigurationSelectionPolicy.validate(group, at: location)
        try ConfigurationValidation.keys(group, ConfigurationPolicy.groupFields, at: location)
        guard let kind = group["type"] as? String, kinds.contains(kind),
              let name = group["name"] as? String, ConfigurationValidation.validName(name) else {
            throw ConfigurationValidation.issue(location + "：支持 select、url-test、fallback、load-balance，且需要有效名称。")
        }
        try ConfigurationValidation.optionalBooleans(group, ["lazy", "disable-udp", "hidden", "include-all", "include-all-proxies", "include-all-providers"], at: location)
        for (field, range) in [("interval", 0...86400), ("timeout", 1...30000), ("tolerance", 0...10000), ("max-failed-times", 1...100)] where group[field] != nil {
            guard ConfigurationNodeOptions.integer(group[field], range: range) else { throw ConfigurationValidation.issue(location + "：" + field + " 超出支持范围。") }
        }
        if group["tolerance"] != nil && kind != "url-test" { throw ConfigurationValidation.issue(location + "：tolerance 仅适用于 url-test。") }
        if let strategy = group["strategy"] {
            guard kind == "load-balance", let strategy = strategy as? String, ["consistent-hashing", "round-robin", "sticky-sessions"].contains(strategy) else { throw ConfigurationValidation.issue(location + "：strategy 仅适用于 load-balance，且必须为受支持策略。") }
        }
        if let value = group["url"] {
            guard let value = value as? String, validTestURL(value) else { throw ConfigurationValidation.issue(location + "：测速地址需要 HTTP(S)，不能携带用户信息或片段。") }
        }
        if let status = group["expected-status"] {
            guard statusText(status) != nil else { throw ConfigurationValidation.issue(location + "：expected-status 需要 HTTP 状态码或范围。") }
        }
        if let icon = group["icon"] {
            guard let icon = icon as? String, icon.utf8.count <= 8192, !icon.contains("\u{0}") else { throw ConfigurationValidation.issue(location + "：icon 格式错误。") }
        }
    }
    static func validTestURL(_ text: String) -> Bool {
        guard text.utf8.count <= 2048, let url = URLComponents(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil else { return false }
        return url.port == nil || (1...65535).contains(url.port!)
    }
    /// Normalize YAML integer HTTP status without accepting booleans, fractional values or arbitrary strings.
    static func statusText(_ input: Any) -> String? {
        if let text = input as? String { return validStatus(text) ? text : nil }
        if ConfigurationNodeOptions.integer(input, range: 100...599), let number = input as? NSNumber {
            return String(number.intValue)
        }
        return nil
    }
    static func validStatus(_ text: String) -> Bool {
        if text == "*" || text.isEmpty { return true }
        guard text.count <= 128 else { return false }
        return text.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { range in
            let values = range.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
            return values.count == range.split(separator: "-", omittingEmptySubsequences: false).count &&
                (1...2).contains(values.count) && values.allSatisfy { (100...599).contains($0) } && values.first! <= values.last!
        }
    }
    static func runtime(_ group: [String: Any]) -> [String: Any] {
        var result = group
        if let status = result["expected-status"], let text = statusText(status) { result["expected-status"] = text }
        result.removeValue(forKey: "icon"); result.removeValue(forKey: "hidden")
        if group["type"] as? String != "select" {
            result["url"] = group["url"] ?? "https://cp.cloudflare.com/generate_204"
            let interval = (group["interval"] as? NSNumber)?.intValue ?? 300
            result["interval"] = interval == 0 ? 300 : max(60, interval)
            result["lazy"] = group["lazy"] ?? true
            result["timeout"] = group["timeout"] ?? 5000
        }
        if let interval = (result["interval"] as? NSNumber)?.intValue, interval > 0 {
            result["interval"] = max(60, interval)
        }
        return result
    }
    static let includeFields = ["include-all", "include-all-proxies", "include-all-providers"]
    static func resolveIncludes(_ root: [String: Any]) throws -> (root: [String: Any], notes: [String]) {
        guard var groups = root["proxy-groups"] as? [[String: Any]] else { return (root, []) }
        var changed = false
        // Go slices.Sort compares UTF-8 bytes; locale/canonical Unicode sorting can differ.
        func ordered(_ names: [String]) -> [String] { names.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } }
        let allNodes = ordered((root["proxies"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        let allProviders = ordered(Array((root["proxy-providers"] as? [String: Any] ?? [:]).keys))
        for i in groups.indices where includeFields.contains(where: { groups[i][$0] != nil }) {
            var group = groups[i]
            try ConfigurationValidation.optionalBooleans(group, includeFields, at: "策略组 \(i + 1)")
            for key in ["proxies", "use"] where group[key] != nil {
                guard group[key] is [String] else { throw ConfigurationValidation.issue("策略组 \(i + 1)：成员需要字符串列表。") }
            }
            let all = ConfigurationValidation.boolean(group["include-all"]) == true
            if all || ConfigurationValidation.boolean(group["include-all-proxies"]) == true {
                var members = group["proxies"] as? [String] ?? []
                // Preserve explicit duplicates for the validator; only avoid re-adding collected names.
                var seen = Set(members)
                for name in try ConfigurationSelectionPolicy.included(allNodes, options: group) where seen.insert(name).inserted { members.append(name) }
                if !members.isEmpty { group["proxies"] = members }
            }
            if all || ConfigurationValidation.boolean(group["include-all-providers"]) == true {
                // As in the core, this flag replaces `use`, rather than appending to it.
                group.removeValue(forKey: "use")
                if !allProviders.isEmpty { group["use"] = allProviders }
            }
            for key in includeFields { group.removeValue(forKey: key) }
            groups[i] = group; changed = true
        }
        guard changed else { return (root, []) }
        var result = root; result["proxy-groups"] = groups
        return (result, ["include-all 按内核顺序展开：显式成员优先，自动节点与 providers 按名称排序；自动收集不重复加入已有节点，不收集策略组。include-all-providers 替代 use。每次刷新重新计算，原始字段保留；空组仍明确拒绝，避免自动直连。"])
    }
    static func notes(_ groups: [[String: Any]]) -> [String] {
        var notes: [String] = []
        if groups.contains(where: { $0["type"] as? String != "select" }) {
            notes.append("url-test / fallback / load-balance 由内核执行自动选择或连接分配；未指定测速地址时使用 Cloudflare HTTPS 204，默认 300 秒、lazy=true；正数间隔最低适配为 60 秒，0 采用内核默认 300 秒。测速会产生网络请求和耗电，断开隧道后停止。")
        }
        if groups.contains(where: { $0["type"] as? String == "select" && (($0["interval"] as? NSNumber)?.intValue ?? 0) > 0 && (($0["interval"] as? NSNumber)?.intValue ?? 60) < 60 }) {
            notes.append("select 组指定的正数健康检查间隔最低适配为 60 秒。")
        }
        if groups.contains(where: { $0["icon"] != nil || $0["hidden"] != nil }) {
            notes.append("策略组 icon / hidden 属于客户端展示提示：iOS 使用现有图标并显示全部组，不下载远程图标；组选择语义保留。")
        }
        if groups.contains(where: { group in ConfigurationSelectionPolicy.filterFields.contains(where: { group[$0] != nil }) }) {
            notes.append("策略组筛选沿用固定内核：filter 筛选自动收集与 provider 成员，不排除显式 proxies；exclude-filter 与 exclude-type 对全部成员生效。空组拒绝导入，不自动直连。")
        }
        return notes
    }
}
