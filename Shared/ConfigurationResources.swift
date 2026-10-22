import Foundation
import Hako

/// Resource plans contain credentials in memory. Diagnostics use only kind and ordinal position.
nonisolated enum ConfigurationResources {
    struct Request {
        let key: String
        let url: String
        let headers: [String: String]
        let maximumBytes: Int
    }
    static let providerFields: Set<String> = ["filter", "exclude-filter", "exclude-type", "override","type", "url", "path", "interval", "header", "payload", "health-check", "behavior", "format", "size-limit"]
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("PrivateCore", isDirectory: true) }
    static func plan(_ root: [String: Any]) throws -> [Request] {
        var requests: [Request] = []
        for kind in ["proxy", "rule"] {
            let key = kind + "-providers"
            guard let raw = root[key] else { continue }
            guard let providers = raw as? [String: Any], providers.count <= 32 else { throw ConfigurationValidation.issue(key + "：最多 32 项映射。") }
            for (index, entry) in providers.sorted(by: { $0.key < $1.key }).enumerated() {
                let location = key + " \(index + 1)"
                guard ConfigurationValidation.validName(entry.key), let provider = entry.value as? [String: Any] else { throw ConfigurationValidation.issue(location + "：名称或结构无效。") }
                try ConfigurationValidation.keys(provider, providerFields, at: location)
                guard let type = provider["type"] as? String, ["http", "inline"].contains(type) else { throw ConfigurationValidation.issue(location + "：支持 HTTPS http 或 inline；不读取订阅指定的本地文件路径。") }
                if provider["interval"] != nil && !ConfigurationNodeOptions.integer(provider["interval"], range: 0...604800) { throw ConfigurationValidation.issue(location + "：interval 无效。") }
                if let path = provider["path"], !(path is String) { throw ConfigurationValidation.issue(location + "：path 类型无效。") }
                if kind == "proxy" { try ConfigurationSelectionPolicy.validateProvider(provider, at: location) }
                if kind == "rule" {
                    guard ConfigurationSelectionPolicy.filterFields.union(["override"]).allSatisfy({ provider[$0] == nil }) else { throw ConfigurationValidation.issue(location + "：节点筛选与 override 不适用于规则 provider。") }

                    guard let behavior = provider["behavior"] as? String, ["domain", "ipcidr", "classical"].contains(behavior),
                          ["yaml", "text", "mrs"].contains(provider["format"] as? String ?? "yaml"),
                          !(behavior == "classical" && provider["format"] as? String == "mrs"), provider["health-check"] == nil else { throw ConfigurationValidation.issue(location + "：behavior / format 或健康检查组合未支持。") }
                } else if provider["behavior"] != nil || provider["format"] != nil { throw ConfigurationValidation.issue(location + "：节点 provider 需要 Clash 节点 YAML。") }
                if let health = provider["health-check"] {
                    guard kind == "proxy", let health = health as? [String: Any] else { throw ConfigurationValidation.issue(location + "：health-check 格式错误。") }
                    try ConfigurationValidation.keys(health, ["enable", "url", "interval", "timeout", "lazy", "expected-status"], at: location + " health-check")
                    try ConfigurationValidation.optionalBooleans(health, ["enable", "lazy"], at: location)
                    var group = health; group.removeValue(forKey: "enable"); group["type"] = "url-test"; group["name"] = "CHECK"
                    try ConfigurationGroups.validate(group, at: index)
                }
                if type == "inline" {
                    guard provider["url"] == nil, provider["header"] == nil, provider["payload"] != nil,
                          provider["format"] as? String != "mrs" else { throw ConfigurationValidation.issue(location + "：inline 只接受 payload，不能混用远程来源或 MRS。") }
                    continue
                }
                guard provider["payload"] == nil, let url = provider["url"] as? String, validURL(url) else { throw ConfigurationValidation.issue(location + "：需要 HTTPS 来源；远程 payload 回退尚不支持。") }
                var headers: [String: String] = [:]
                if let raw = provider["header"] {
                    guard let values = raw as? [String: [String]], values.count <= 16 else { throw ConfigurationValidation.issue(location + "：header 需要字符串数组映射。") }
                    for (name, list) in values {
                        guard name.range(of: "^[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
                              !["host", "connection", "content-length", "cookie", "proxy-authorization"].contains(name.lowercased()),
                              list.count == 1, let value = list.first, value.utf8.count <= 8192,
                              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ConfigurationValidation.issue(location + "：请求头格式未支持（内容已隐藏）。") }
                        headers[name] = value
                    }
                }
                var limit = kind == "proxy" ? 2 * 1024 * 1024 : 8 * 1024 * 1024
                if let size = provider["size-limit"] {
                    guard ConfigurationNodeOptions.integer(size, range: 0...ConfigurationResourceStore.maximumResourceBytes) else { throw ConfigurationValidation.issue(location + "：size-limit 无效。") }
                    if let n = size as? NSNumber, n.intValue > 0 { limit = min(limit, n.intValue) }
                }
                requests.append(Request(key: kind + ":" + entry.key, url: url, headers: headers, maximumBytes: limit))
            }
        }
        if root["geox-url"] != nil {
            guard let urls = root["geox-url"] as? [String: Any] else { throw ConfigurationValidation.issue("geox-url 需要映射。") }
            try ConfigurationValidation.keys(urls, ["geoip", "geosite", "mmdb", "asn"], at: "geox-url")
            guard urls.values.allSatisfy({ ($0 as? String).map(validURL) == true }) else { throw ConfigurationValidation.issue("geox-url：数据来源需要 HTTPS。") }
        }
        // The pinned core supplies its exact default Geo URLs and discovers direct rule dependencies.
        let json = String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]), as: UTF8.self)
        var error: NSError?
        guard let plan = HakoPlanResourcesForIOS(json, &error),
              let value = try? JSONSerialization.jsonObject(with: Data(plan.value.utf8)) as? [String: Any],
              let geodata = value["geodata"] as? [[String: Any]] else { throw ConfigurationValidation.issue("内核无法规划依赖，请检查配置结构。") }
        if let errors = value["errors"] as? [[String: Any]], errors.contains(where: { ($0["field"] as? String ?? "").hasPrefix("geox-url") }) {
            throw ConfigurationValidation.issue("Geo 规则需要有效的 HTTPS 数据来源；geox-url 配置缺失或无效。")
        }
        for geo in geodata {
            guard let kind = geo["kind"] as? String, let format = geo["format"] as? String,
                  ["geoip:dat", "geoip:mmdb", "geosite:dat"].contains(kind + ":" + format),
                  let url = geo["url"] as? String, validURL(url) else { throw ConfigurationValidation.issue("Geo 数据来源或格式未支持。") }
            requests.append(Request(key: "geo:" + kind + ":" + format, url: url, headers: [:], maximumBytes: ConfigurationResourceStore.maximumResourceBytes))
        }
        guard requests.count <= 35 else { throw ConfigurationValidation.issue("远程依赖总数超过 35 项。") }
        return requests
    }
    nonisolated static func validURL(_ value: String) -> Bool {
        guard value.utf8.count <= 8192, let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil else { return false }
        return url.port == nil || (1...65535).contains(url.port!)
    }
    static func expand(_ root: [String: Any], snapshot: ConfigurationSnapshot?) throws -> (root: [String: Any], notes: [String]) {
        guard root["proxy-providers"] != nil || root["rule-providers"] != nil || root["geox-url"] != nil || hasGeoRules(root) || ConfigurationDNS.fallbackGeoIPCode(root["dns"]) != nil || !ConfigurationDNS.geoSiteCodes(root["dns"]).isEmpty else { return (root, []) }
        let requests = try plan(root)
        let resources = snapshot?.resources ?? []
        guard Set(requests.map(\.key)) == Set(resources.map(\.key)) else { throw ConfigurationValidation.issue("远程依赖尚未完整下载并校验；请通过导入或手动刷新建立完整快照。") }
        var result = root, providerNodes: [String: [[String: Any]]] = [:]
        for kind in ["proxy", "rule"] {
            guard let providers = root[kind + "-providers"] as? [String: [String: Any]] else { continue }
            var runtime: [String: [String: Any]] = [:]
            for (index, entry) in providers.sorted(by: { $0.key < $1.key }).enumerated() {
                var provider = entry.value
                let location = kind + "-providers \(index + 1)"
                let format = provider["format"] as? String ?? "yaml", behavior = provider["behavior"] as? String ?? ""
                var body: Data
                if provider["type"] as? String == "inline" {
                    body = try JSONSerialization.data(withJSONObject: [kind == "proxy" ? "proxies" : "payload": provider["payload"]!], options: [.withoutEscapingSlashes])
                } else {
                    guard let resource = resources.first(where: { $0.key == kind + ":" + entry.key }) else { throw ConfigurationValidation.issue(location + "：缺少快照。") }
                    body = try ConfigurationResourceStore.load(resource)
                }
                if kind == "rule", format == "yaml" { body = try canonicalRuleYAML(body) }
                if kind == "rule", format != "mrs", behavior != "classical" {
                    let lines = try ruleLines(body, format: format)
                    guard !lines.isEmpty, lines.count <= 20_000 else { throw ConfigurationValidation.issue(location + "：规则数量需为 1–20000。") }
                    for line in lines {
                        let valid = behavior == "ipcidr" ? ConfigurationValidation.cidr(line, ipv6: line.contains(":")) :
                            line.utf8.count <= 253 && line.range(of: "^(?:\\+\\.|\\*\\.|\\.)?[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+)*$", options: .regularExpression) != nil
                        guard valid else { throw ConfigurationValidation.issue(location + "：包含无效域名或 CIDR，禁止静默丢弃规则。") }
                    }
                }
                // Classical rule sets must satisfy the same rule contract as inline rules.
                if kind == "rule", behavior == "classical" {
                    let lines: [String]
                    if format == "text" {
                        guard let text = String(data: body, encoding: .utf8) else { throw ConfigurationValidation.issue(location + "：文本编码无效。") }
                        lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
                    } else {
                        let payload = try PrototypeConfiguration.decodeYAML(body, configurationShape: false, maximumBytes: 8 * 1024 * 1024)
                        try ConfigurationValidation.keys(payload, ["payload"], at: location)
                        guard let rules = payload["payload"] as? [String] else { throw ConfigurationValidation.issue(location + "：需要 payload 规则列表。") }
                        lines = rules
                    }
                    guard lines.count <= 4096 else { throw ConfigurationValidation.issue(location + "：classical 最多 4096 条。") }
                    for (i, line) in lines.enumerated() {
                        let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        guard parts.first != "PROCESS-NAME", line.unicodeScalars.allSatisfy(\.isASCII) else {
                            throw ConfigurationValidation.issue(location + "：进程规则停用与国际化域名适配目前仅支持主配置 rules；此 classical 条目未启用。")
                        }
                        guard parts.count == 2, !["RULE-SET", "GEOIP", "GEOSITE", "MATCH"].contains(parts[0]) else { throw ConfigurationValidation.issue(location + "：规则 \(i + 1) 需要独立匹配条件；嵌套规则集与 Geo 请放在主配置。") }
                        _ = try ConfigurationRules.validate([line + ",DIRECT", "MATCH,DIRECT"], targets: ["DIRECT"])
                    }
                }
                var error: NSError?, count = 0
                guard kind == "proxy" || (HakoInspectProviderForIOS(kind, behavior, format, body, &count, &error) && count > 0 && count <= 20_000) else { throw ConfigurationValidation.issue(location + "：内容、条目数量或格式无效。") }
                if kind == "proxy" {
                    let parsed = try PrototypeConfiguration.decodeYAML(body, configurationShape: false, maximumBytes: 2 * 1024 * 1024)
                    try ConfigurationValidation.keys(parsed, ["proxies"], at: location)
                    guard let rawNodes = parsed["proxies"] as? [[String: Any]], !rawNodes.isEmpty else { throw ConfigurationValidation.issue(location + "：需要 proxies 节点列表。") }
                    let nodes = try ConfigurationSelectionPolicy.provider(rawNodes, options: provider, at: location)
                    for field in ConfigurationSelectionPolicy.filterFields.union(["override"]) { provider.removeValue(forKey: field) }
                    for (i, node) in nodes.enumerated() { _ = try ConfigurationValidation.validateNode(node, index: i) }
                    providerNodes[entry.key] = nodes
                    provider["type"] = "inline"; provider["payload"] = nodes
                    if var health = provider["health-check"] as? [String: Any], ConfigurationValidation.boolean(health["enable"]) == true {
                        health["interval"] = max(60, (health["interval"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? 300)
                        health["url"] = health["url"] ?? "https://cp.cloudflare.com/generate_204"
                        health["lazy"] = health["lazy"] ?? true
                        provider["health-check"] = health
                    }
                } else if provider["type"] as? String != "inline" {
                    guard let resource = resources.first(where: { $0.key == "rule:" + entry.key }) else { throw ConfigurationValidation.issue(location + "：缺少规则快照。") }
                    provider["type"] = "file"
                    provider["path"] = directory.appendingPathComponent(resource.digest + ".rules").path
                }
                if kind == "proxy", var health = provider["health-check"] as? [String: Any],
                   let status = health["expected-status"], let text = ConfigurationGroups.statusText(status) {
                    health["expected-status"] = text; provider["health-check"] = health
                }
                for key in ["url", "header", "interval", "size-limit"] { provider.removeValue(forKey: key) }
                if kind == "proxy" || provider["type"] as? String == "inline" { provider.removeValue(forKey: "path") }
                runtime[entry.key] = provider
            }
            result[kind + "-providers"] = runtime
        }
        // Catalog construction uses effective provider membership, while runtime preserves `use`.
        result["proxies"] = (root["proxies"] as? [[String: Any]] ?? [])
        let groups = root["proxy-groups"] as? [[String: Any]] ?? []
        for index in groups.indices {
            if let use = groups[index]["use"] {
                guard let names = use as? [String], !names.isEmpty, Set(names).count == names.count else { throw ConfigurationValidation.issue("策略组 \(index + 1)：use 需要不重复的 provider 名称列表。") }
                for name in names where providerNodes[name] == nil { throw ConfigurationValidation.issue("策略组 \(index + 1)：use 引用了不存在的节点 provider。") }
            }
        }
        result["proxy-groups"] = groups
        let bundled = resources.filter { $0.bundledVersion != nil }.count
        let localNotes = bundled > 0 ? ["本版本含 \(bundled) 项内置 Geo 数据，首次导入无需联网下载；可在订阅维护中手动更新。原始规则保留，数据版本随订阅一起回滚。"] : []
        let policyNotes = (root["proxy-providers"] as? [String: [String: Any]] ?? [:]).values.contains { p in ConfigurationSelectionPolicy.filterFields.union(["override"]).contains { p[$0] != nil } }
            ? ["provider 按原节点名称和类型筛选，再应用 override；改名、UDP、证书与带宽覆盖后重新校验有效节点。有效快照保留健康检查；刷新和回滚从各版本原文重新计算，改名重名或空结果拒绝采用。"] : []
        return (result, policyNotes + localNotes + ["providers 与 Geo 资源在 App 中受控准备并校验；默认 Geo 优先使用完整本地快照或内置 MetaCubeX 数据，自定义来源不替换；手动更新访问对应来源，仅这些固定无凭据地址允许跳转至 GitHub release CDN。依赖和主订阅共同保存、刷新与回滚；扩展只读取快照，不按 interval 独立更新。桌面 path 被替换，不读取任意本地路径；规则集 YAML 规范化为块列表供内核读取，快照保留原文。", "provider 健康检查保留，启用时默认 300 秒、lazy=true，正数间隔最低 60 秒；会产生请求与耗电。"])
    }
    static func canonicalRuleYAML(_ body: Data) throws -> Data {
        let root = try PrototypeConfiguration.decodeYAML(body, configurationShape: false, maximumBytes: 8 * 1024 * 1024)
        try ConfigurationValidation.keys(root, ["payload"], at: "规则集")
        guard root["payload"] is [String] else { throw ConfigurationValidation.issue("规则集需要字符串 payload 列表。") }
        var error: NSError?
        let json = String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]), as: UTF8.self)
        guard let yaml = HakoJSONToYaml(json, &error) else { throw ConfigurationValidation.issue("规则集 YAML 规范化失败。") }
        return Data(yaml.value.utf8)
    }
    static func ruleLines(_ body: Data, format: String) throws -> [String] {
        if format == "yaml" {
            let root = try PrototypeConfiguration.decodeYAML(body, configurationShape: false, maximumBytes: 8 * 1024 * 1024)
            guard let lines = root["payload"] as? [String] else { throw ConfigurationValidation.issue("规则集 payload 无效。") }
            return lines
        }
        guard let text = String(data: body, encoding: .utf8) else { throw ConfigurationValidation.issue("规则集需要 UTF-8 文本。") }
        return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
    static func hasGeoRules(_ root: [String: Any]) -> Bool {
        (root["rules"] as? [String] ?? []).contains { ["GEOIP", "GEOSITE"].contains($0.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "") }
    }
    static func nodes(_ root: [String: Any]) -> [[String: Any]] {
        let providers = root["proxy-providers"] as? [String: [String: Any]] ?? [:]
        return (root["proxies"] as? [[String: Any]] ?? []) + providers.keys.sorted().flatMap { providers[$0]?["payload"] as? [[String: Any]] ?? [] }
    }
    static func members(_ group: [String: Any], root: [String: Any]) throws -> [String]? {
        try ConfigurationSelectionPolicy.members(group, root: root)
    }
    /// Called only before preflight/start. Paths are app-generated; no subscription path is trusted.
    static func install(_ source: Data, in directory: URL, validateGeo: Bool = true) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["GeoIP.dat", "GeoSite.dat", "geoip.metadb"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
        guard let snapshot = try ConfigurationSnapshot.read(source) else { return }
        let raw = try ConfigurationInput.read(source, resolveResources: false).root
        for resource in snapshot.resources {
            let name: String
            if resource.key.hasPrefix("rule:") { name = resource.digest + ".rules" }
            else if resource.key == "geo:geoip:dat" { name = "GeoIP.dat" }
            else if resource.key == "geo:geoip:mmdb" { name = "geoip.metadb" }
            else if resource.key == "geo:geosite:dat" { name = "GeoSite.dat" }
            else { continue }
            let url = directory.appendingPathComponent(name)
            if resource.key.hasPrefix("rule:"),
               let definition = (raw["rule-providers"] as? [String: [String: Any]])?[String(resource.key.dropFirst(5))],
               definition["format"] as? String ?? "yaml" == "yaml" {
                try canonicalRuleYAML(ConfigurationResourceStore.load(resource)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else { try ConfigurationResourceStore.write(resource, to: url) }
            if validateGeo && resource.key.hasPrefix("geo:") {
                let parts = resource.key.split(separator: ":").map(String.init)
                var codes = (raw["rules"] as? [String] ?? []).compactMap { rule -> String? in
                    let p = rule.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    return p.count >= 2 && p[0].lowercased() == parts[1] ? p[1] : nil
                }
                if parts[1] == "geoip", let code = ConfigurationDNS.fallbackGeoIPCode(raw["dns"]) { codes.append(code) }
                if parts[1] == "geosite" { codes += ConfigurationDNS.geoSiteCodes(raw["dns"]) }
                var error: NSError?
                guard HakoValidateGeodataCodesForIOS(parts[1], parts[2], url.path, codes.joined(separator: ","), &error) else { throw ConfigurationValidation.issue("Geo 数据无效或缺少所引用分类；未启用候选配置。") }
            }
        }
    }
}
