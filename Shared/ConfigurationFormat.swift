import Foundation

/// Conservative content signatures, never file extensions or user-provided labels.
/// Messages contain only fixed text; credentials and arbitrary keys stay private.
nonisolated enum ConfigurationFormat: CaseIterable {
    case singBox, xray, outboundJSON, shadowsocks, wireGuard, proxyINI, quantumult
    case openVPN, html, appleProfile, ruleProvider, unrecognized

    var label: String {
        switch self {
        case .singBox: "sing-box"
        case .xray: "Xray / V2Ray"
        case .outboundJSON: "sing-box / Xray / V2Ray"
        case .shadowsocks: "Shadowsocks JSON / SIP008"
        case .wireGuard: "WireGuard INI"
        case .proxyINI: "Surge / Shadowrocket / Surfboard INI"
        case .quantumult: "Quantumult X INI"
        case .openVPN: "OpenVPN"
        case .html: "HTML"
        case .appleProfile: "Apple configuration profile"
        case .ruleProvider: "Clash rule-provider"
        case .unrecognized: ""
        }
    }

    var message: String {
        switch self {
        case .html: "收到的是 HTML 网页，不是订阅配置。请使用供应商提供的 Clash / Mihomo 订阅地址，而非登录页或分享网页。"
        case .ruleProvider: "这是 Clash 规则集片段，不是完整订阅。请导入包含节点或 proxy-providers 的主配置。"
        case .unrecognized: "无法识别配置格式。请提供 Clash / Mihomo YAML、Clash JSON 或已支持的节点链接；修改文件后缀不能转换格式。"
        default: "已识别 \(label) 格式，不是 Clash / Mihomo 配置。请在供应商处选择 Clash / Mihomo 格式后重新导入；当前不自动转换此格式。"
        }
    }

    var englishMessage: String {
        switch self {
        case .html: "Received an HTML page, not a subscription. Use the provider’s Clash / Mihomo subscription URL instead of a login or sharing page."
        case .ruleProvider: "This is a Clash rule-provider fragment, not a complete subscription. Import the main configuration containing nodes or proxy-providers."
        case .unrecognized: "Configuration format not recognized. Provide Clash / Mihomo YAML, Clash JSON or supported node URIs. Renaming the file extension does not convert its format."
        default: "Detected \(label), not a Clash / Mihomo configuration. Select Clash / Mihomo format at your provider and import again. This format is not automatically converted."
        }
    }

    static func english(_ message: String) -> String? {
        for format in allCases {
            if message == format.message { return format.englishMessage }
            if message == format.message + "（2020）" { return format.englishMessage + " (2020)" }
        }
        return nil
    }

    static func detectText(_ text: String) -> Self? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") && !$0.hasPrefix("//") }
        guard let first = lines.first?.lowercased() else { return .unrecognized }
        if first.hasPrefix("{") || first.hasPrefix("/*") {
            let json = removingJSONComments(text)
            if let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
               let format = detectRoot(root) { return format }
        }
        if first.hasPrefix("["), lines.contains(where: {
            $0.lowercased().range(of: #"^\[(server_local|server_remote|filter_local|filter_remote|rewrite_local|rewrite_remote)\]\s*(?:[#;].*)?$"#, options: .regularExpression) != nil
        }) { return .quantumult }
        // Anchor sections/directives: matching strings inside YAML values must not reject Clash.
        if first.range(of: #"^\[(interface|peer)\]\s*(?:[#;].*)?$"#, options: .regularExpression) != nil { return .wireGuard }
        if first.range(of: #"^\[(general|proxy|proxy group|rule|host|mitm|script|rewrite)\]\s*(?:[#;].*)?$"#, options: .regularExpression) != nil { return .proxyINI }
        if first.range(of: #"^\[(general|server_local|server_remote|filter_local|filter_remote|policy|dns|rewrite_local|rewrite_remote)\]$"#, options: .regularExpression) != nil {
            return .quantumult
        }
        let directives = lines.map { $0.lowercased().split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? "" }
        let openVPN: Set<String> = ["client", "dev", "proto", "remote", "nobind", "resolv-retry", "persist-key", "persist-tun", "auth-user-pass", "<ca>", "<cert>", "<key>"]
        if openVPN.contains(directives[0]), Set(directives).intersection(openVPN).count >= 2 { return .openVPN }
        // Permit leading HTML comments; do not search arbitrary YAML scalar content.
        let markup = text.replacingOccurrences(of: #"(?s)^\s*(?:<!--.*?-->\s*)*"#, with: "", options: .regularExpression).lowercased()
        if markup.range(of: #"^<(?:!doctype\s+html\b|html\b|head\b|body\b)"#, options: .regularExpression) != nil { return .html }
        if markup.hasPrefix("<?xml") || markup.hasPrefix("<plist") {
            if markup.contains("<key>payloadtype</key>") && markup.contains("<plist") { return .appleProfile }
        }
        return nil
    }

    /// Diagnostic recognition only, not a new accepted input dialect. Preserve quoted
    /// URLs and escaped quotes; never strip // or /* inside a credential/string.
    private static func removingJSONComments(_ text: String) -> String {
        let chars = Array(text)
        var output = "", index = 0, quoted = false, escaped = false
        while index < chars.count {
            let c = chars[index]
            if quoted {
                output.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
                index += 1; continue
            }
            if c == "\"" { quoted = true }
            if c == "/", index + 1 < chars.count {
                if chars[index + 1] == "/" {
                    index += 2
                    while index < chars.count && chars[index] != "\n" && chars[index] != "\r\n" && chars[index] != "\r" { index += 1 }
                    output.append(" "); continue
                }
                if chars[index + 1] == "*" {
                    index += 2
                    while index + 1 < chars.count && !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                    guard index + 1 < chars.count else { return text }
                    index += 2; output.append(" "); continue
                }
            }
            output.append(c); index += 1
        }
        return output
    }

    static func detectRoot(_ root: [String: Any]) -> Self? {
        // A recognizable Clash document with extra fields goes to compatibility diagnostics.
        let clashMarkers: Set<String> = ["proxies", "proxy-groups", "proxy-providers", "rules", "rule-providers"]
        if !Set(root.keys).isDisjoint(with: clashMarkers) { return nil }
        let outbound = root["outbounds"] as? [[String: Any]]
        let inbound = root["inbounds"] as? [[String: Any]]
        if outbound != nil || inbound != nil {
            let entries = (outbound ?? []) + (inbound ?? [])
            let types = entries.contains { $0["type"] is String }
            let protocols = entries.contains { $0["protocol"] is String }
            if types && !protocols { return .singBox }
            if protocols && !types { return .xray }
            return .outboundJSON
        }
        if root["servers"] is [[String: Any]] || (root["server"] is String && root["method"] is String) { return .shadowsocks }
        if root["payload"] is [Any], Set(root.keys) == ["payload"] { return .ruleProvider }
        return nil
    }
}
