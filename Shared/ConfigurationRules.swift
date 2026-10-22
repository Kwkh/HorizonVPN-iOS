import Foundation

nonisolated enum ConfigurationRules {
    static func adaptations(_ rules: [String]) -> [String] {
        let count = rules.filter { $0.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) == "PROCESS-NAME" }.count
        var notes: [String] = []
        if count > 0 { notes.append("iOS 无法使用桌面进程名：运行配置停用 \(count) 条 PROCESS-NAME 规则，流量继续匹配后续规则；原始规则保留用于刷新及回滚。") }
        if rules.contains(where: { rule in
            let parts = rule.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count >= 3 && ["DOMAIN", "DOMAIN-SUFFIX"].contains(parts[0]) && !parts[1].unicodeScalars.allSatisfy(\.isASCII)
        }) { notes.append("国际化域名规则在运行配置中转换为 ASCII/Punycode，以匹配 DNS 域名；原文保留。") }
        return notes
    }
    static func runtime(_ rules: [String]) throws -> [String] {
        try rules.compactMap { rule in
            var parts = rule.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first == "PROCESS-NAME" { return nil }
            if parts.count >= 3 && ["DOMAIN", "DOMAIN-SUFFIX"].contains(parts[0]) { parts[1] = try asciiDomain(parts[1]) }
            return parts.joined(separator: ",")
        }
    }
    static func asciiDomain(_ value: String) throws -> String {
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.union(.whitespacesAndNewlines).contains($0) }),
              !value.contains(where: { "/:@?#%\\,".contains($0) }) else { throw ConfigurationValidation.issue("域名规则格式错误。") }
        if value.unicodeScalars.allSatisfy(\.isASCII) {
            guard value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw ConfigurationValidation.issue("域名规则格式错误。") }
            return value
        }
        guard let host = URL(string: "https://" + value)?.host, host.unicodeScalars.allSatisfy(\.isASCII),
              host.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw ConfigurationValidation.issue("国际化域名规则无法转换。") }
        return host
    }
    static func validate(_ rules: [String], targets: Set<String>, providers: Set<String> = []) throws -> String {
        var match: String?
        for (index, rule) in rules.enumerated() {
            let parts = rule.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let location = "规则 \(index + 1)"
            guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else { throw ConfigurationValidation.issue(location + "：格式错误。") }
            if parts[0] == "MATCH" {
                guard parts.count == 2, index == rules.count - 1, targets.contains(parts[1]) else { throw ConfigurationValidation.issue("MATCH 必须是最后一条，且指向有效目标。") }
                match = parts[1]; continue
            }
            if parts[0] == "PROCESS-NAME" {
                guard parts.count == 3, targets.contains(parts[2]), !parts[1].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ConfigurationValidation.issue(location + "：进程规则格式或引用错误。") }
                continue // Explicitly disclosed iOS adaptation, removed only from runtime.
            }
            let domains = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD"], cidrs = ["IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR"]
            let extended = ["DST-PORT", "SRC-PORT", "NETWORK", "RULE-SET", "GEOIP", "GEOSITE"]
            guard domains.contains(parts[0]) || cidrs.contains(parts[0]) || extended.contains(parts[0]) else {
                throw ConfigurationValidation.issue(location + "：支持域名、IP-CIDR、SRC-IP-CIDR、DST/SRC-PORT、NETWORK、RULE-SET、GEOIP、GEOSITE、MATCH；其他规则未接入。")
            }
            let noResolve = cidrs.contains(parts[0]) || ["GEOIP", "RULE-SET"].contains(parts[0])
            guard (parts.count == 3 || (parts.count == 4 && noResolve && parts[3] == "no-resolve")), targets.contains(parts[2]) else { throw ConfigurationValidation.issue(location + "：目标引用或选项错误。") }
            if cidrs.contains(parts[0]) {
                guard ConfigurationValidation.cidr(parts[1], ipv6: parts[1].contains(":")) else { throw ConfigurationValidation.issue(location + "：CIDR 格式错误。") }
            } else if ["DST-PORT", "SRC-PORT"].contains(parts[0]) {
                guard validPorts(parts[1]) else { throw ConfigurationValidation.issue(location + "：端口范围无效。") }
            } else if parts[0] == "NETWORK" {
                guard ["TCP", "UDP"].contains(parts[1]) else { throw ConfigurationValidation.issue(location + "：NETWORK 支持 TCP 或 UDP。") }
            } else if parts[0] == "RULE-SET" {
                guard providers.contains(parts[1]) else { throw ConfigurationValidation.issue(location + "：规则 provider 引用不存在。") }
            } else if ["GEOIP", "GEOSITE"].contains(parts[0]) {
                guard parts[1].range(of: "^!?[A-Za-z0-9_-]+(?:@[A-Za-z0-9_-]+)?$", options: .regularExpression) != nil else { throw ConfigurationValidation.issue(location + "：Geo 分类格式无效。") }
            } else if domains.contains(parts[0]) {
                if parts[0] == "DOMAIN-KEYWORD" {
                    guard parts[1].unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.controlCharacters.contains($0) }) else { throw ConfigurationValidation.issue(location + "：域名关键词需要 ASCII 文本。") }
                } else { _ = try asciiDomain(parts[1]) }
            }
        }
        guard let match else { throw ConfigurationValidation.issue("需要末尾 MATCH 规则，明确默认流量目标。") }
        return match
    }
    static func validPorts(_ value: String) -> Bool {
        value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { item in
            let parts = item.split(separator: "-", omittingEmptySubsequences: false)
            let values = parts.compactMap { Int($0) }
            return values.count == parts.count && (1...2).contains(values.count) && values.allSatisfy { (1...65535).contains($0) } && values.first! <= values.last!
        }
    }
}
