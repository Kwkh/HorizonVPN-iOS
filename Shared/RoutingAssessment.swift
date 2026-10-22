import Foundation

/// Conservative structural checks, not a prediction of every destination's route.
/// No rule payloads, node names, URLs or credentials enter the report.
nonisolated struct RoutingAssessment: Sendable {
    let domesticRuleNumbers: [Int]
    let otherRuleNumbers: [Int]
    let indirectRuleNumbers: [Int]
    var domesticOverrides: Int { domesticRuleNumbers.count }
    var otherOverrides: Int { otherRuleNumbers.count }
    var indirectRules: Int { indirectRuleNumbers.count }
    let preservesDNS: Bool
    let fallbackMayBeDirect: Bool
    var needsReview: Bool { domesticOverrides + otherOverrides + indirectRules > 0 || preservesDNS || fallbackMayBeDirect }

    static func inspect(_ source: Data) throws -> Self {
        try inspect(root: ConfigurationInput.read(ConfigurationSnapshot.original(source), resolveResources: false).root)
    }
    static func inspect(root: [String: Any]) -> Self {
        let rules = root["rules"] as? [String] ?? []
        var domestic: [Int] = [], other: [Int] = [], indirect: [Int] = []
        for (index, rule) in rules.dropLast().enumerated() {
            var fields = rule.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if fields.last?.lowercased() == "no-resolve" { fields.removeLast() }
            guard fields.count >= 3, let target = fields.last, target != "DIRECT" else { continue }
            let kind = fields[0].uppercased(), value = fields[1].lowercased()
            if kind == "PROCESS-NAME" { continue } // Explicitly disabled by the iOS adapter.
            if ["RULE-SET", "AND", "OR", "NOT", "SUB-RULE"].contains(kind) { indirect.append(index + 1) }
            else if (kind == "GEOIP" && value == "cn") || (kind == "GEOSITE" && value == "cn") ||
                (["DOMAIN", "DOMAIN-SUFFIX"].contains(kind) && (value == "cn" || value.hasSuffix(".cn"))) { domestic.append(index + 1) }
            else { other.append(index + 1) }
        }
        let groups = root["proxy-groups"] as? [[String: Any]] ?? []
        func mayDirect(_ target: String, visited: Set<String>) -> Bool {
            if target == "DIRECT" { return true }
            guard !visited.contains(target), let group = groups.first(where: { $0["name"] as? String == target }) else { return false }
            return (group["proxies"] as? [String] ?? []).contains { mayDirect($0, visited: visited.union([target])) }
        }
        let fallback = rules.last?.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return .init(domesticRuleNumbers: domestic, otherRuleNumbers: other, indirectRuleNumbers: indirect,
                     preservesDNS: root["dns"] != nil, fallbackMayBeDirect: mayDirect(fallback, visited: []))
    }
    func explanations(english: Bool) -> [String] {
        var lines: [String] = []
        func positions(_ numbers: [Int]) -> String {
            let listed = numbers.prefix(12).map { "#\($0)" }.joined(separator: ", ")
            return (english ? " Source rules: " : " 原规则序号：") + listed + (numbers.count > 12 ? " …" : "")
        }
        if domesticOverrides > 0 { lines.append(english ? "\(domesticOverrides) existing mainland-category rules take priority and may proxy or block domestic traffic." : "\(domesticOverrides) 条国内分类规则优先执行，可能代理或拦截国内流量。") ; lines[lines.count - 1] += positions(domesticRuleNumbers) }
        if otherOverrides > 0 { lines.append(english ? "\(otherOverrides) other non-direct rules remain ahead of smart routing. Their destinations may include domestic services." : "\(otherOverrides) 条其他非直连规则仍优先执行，匹配范围可能包含国内服务。") ; lines[lines.count - 1] += positions(otherRuleNumbers) }
        if indirectRules > 0 { lines.append(english ? "\(indirectRules) rule-set or compound rules require live verification; a static check cannot determine every match." : "\(indirectRules) 条规则集或组合规则需结合实际命中确认，静态检查无法判定全部请求。") ; lines[lines.count - 1] += positions(indirectRuleNumbers) }
        if preservesDNS { lines.append(english ? "Existing DNS policies are preserved. A direct connection can still be affected by DNS answers or resolver reachability." : "保留订阅的 DNS 策略；直连请求仍可能受解析结果或上游可达性影响。") }
        if fallbackMayBeDirect { lines.append(english ? "The fallback group contains DIRECT, including nested groups. Selecting it can also send foreign traffic directly." : "默认策略组或其子组含 DIRECT；选中直连后，国外流量也可能直连。") }
        lines.append(english ? "This check preserves all rules and hides their contents. No warning does not guarantee every domestic service goes direct; verify with live traffic." : "检查不修改规则，也不展示规则原文。没有提示不代表所有国内服务必定直连，请结合实际连接验证。")
        return lines
    }
}
