import Foundation

nonisolated enum ConfigurationInput {
    struct Document { let root: [String: Any]; let notes: [String] }
    static func read(_ input: Data, resolveResources: Bool = true) throws -> Document {
        let snapshot = try ConfigurationSnapshot.read(input)
        let data = snapshot?.original ?? input
        guard !data.isEmpty, data.count <= PrototypeConfiguration.maximumBytes,
              let raw = String(data: data, encoding: .utf8) else { throw PrototypeError.invalidFile }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        func contentLines(_ text: String) -> [String] {
            text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        var links: String?
        if let first = contentLines(text).first, first.contains("://"),
           NodeURI.schemes.contains(String(first.prefix(while: { $0 != ":" })).lowercased()) { links = text }
        else {
            let compact = text.filter { !$0.isWhitespace }
            if let decoded = NodeURI.base64(compact), let value = String(data: decoded, encoding: .utf8),
               let first = contentLines(value).first,
               first.contains("://") { links = value }
        }
        func finish(_ input: Document) throws -> Document {
            let adapted = try (snapshot?.routing ?? .subscription).apply(input)
            guard resolveResources else { return adapted }
            let included = try ConfigurationGroups.resolveIncludes(adapted.root)
            let expanded = try ConfigurationResources.expand(included.root, snapshot: snapshot)
            return Document(root: expanded.root, notes: adapted.notes + included.notes + expanded.notes)
        }
        if let links {
            let lines = contentLines(links)
            guard (1...PrototypeConfiguration.maximumNodes).contains(lines.count) else { throw ConfigurationValidation.issue("节点链接数量需为 1–512。") }
            var nodes: [[String: Any]] = [], failures: [String] = []
            for (i, line) in lines.enumerated() {
                do { nodes.append(try NodeURI.parse(line, index: i)) }
                catch let e as ConfigurationIssue { failures.append("链接 \(i + 1)：" + e.detail) }
                catch { failures.append("链接 \(i + 1)：格式无效。") }
            }
            guard failures.isEmpty else { throw ConfigurationValidation.issue(failures.joined(separator: "\n")) }
            // Links have no references. Resolve duplicate display names deterministically without dropping nodes.
            var used = Set<String>(), renamed = false
            for i in nodes.indices {
                let base = nodes[i]["name"] as! String
                var name = base, suffix = 2
                while used.contains(name) { name = String(base.prefix(32)) + " (\(suffix))"; suffix += 1; renamed = true }
                used.insert(name); nodes[i]["name"] = name
            }
            var notes = ["节点链接已在本机转换；未使用公共转换服务。链接节点的 UDP 开关设为 true；保留原始输入供刷新与回滚。"]
            if renamed { notes.append("节点链接中存在重名，已添加序号以保留全部节点。") }
            return try finish(template(["proxies": nodes], notes: notes))
        }
        if let format = ConfigurationFormat.detectText(text) {
            throw ConfigurationValidation.issue(format.message, .incompatibleFormat)
        }
        let bytes = Data(text.utf8)
        let root: [String: Any]
        do { root = try PrototypeConfiguration.decodeYAML(bytes) }
        catch {
            // Only failed shape checks need a second parse. Never bypass the strict
            // parser for accepted Clash input (duplicates/multiple documents included).
            if let mapping = try? PrototypeConfiguration.decodeYAML(bytes, configurationShape: false) {
                try rejectForeignFormat(mapping)
            }
            throw error
        }
        try rejectForeignFormat(root)
        // Node bundles may carry metadata or DNS. Do not overwrite a partial routing configuration.
        let nodeBundleFields = Set(["proxies", "mode", "ipv6", "dns", "hosts", "log-level", "unified-delay",
            "profile", "allow-lan", "bind-address", "tcp-concurrent", "global-client-fingerprint",
            "keep-alive-interval", "keep-alive-idle", "disable-keep-alive"])
            .union(ConfigurationPolicy.desktopPorts).union(ConfigurationPolicy.desktopStrings).union(ConfigurationPolicy.inactiveFields)
        let input: Document
        if root["proxies"] != nil && Set(root.keys).isSubset(of: nodeBundleFields) {
            input = try template(root, notes: [])
        } else { input = Document(root: root, notes: []) }
        // Diagnostics need the unexpanded fields to report independent failures together.
        // Resource planning uses the core's native include semantics; materialize only for runtime/catalog.
        return try finish(input)
    }
    private static func rejectForeignFormat(_ root: [String: Any]) throws {
        if let format = ConfigurationFormat.detectRoot(root) {
            throw ConfigurationValidation.issue(format.message, .incompatibleFormat)
        }
        let indicators = ConfigurationPolicy.rootFields.union(["tun", "hosts", "sniffer", "authentication", "listeners", "sub-rules"])
        if Set(root.keys).isDisjoint(with: indicators) {
            throw ConfigurationValidation.issue(ConfigurationFormat.unrecognized.message, .incompatibleFormat)
        }
    }
    private static func template(_ root: [String: Any], notes: [String]) throws -> Document {
        guard let nodes = root["proxies"] as? [[String: Any]], (1...PrototypeConfiguration.maximumNodes).contains(nodes.count),
              nodes.allSatisfy({ $0["name"] is String }) else { throw ConfigurationValidation.issue("节点列表需要 1–512 个具名节点。") }
        let names = nodes.compactMap { $0["name"] as? String }
        var group = "Imported", suffix = 2
        while names.contains(group) { group = "Imported-\(suffix)"; suffix += 1 }
        var result = root
        if result["mode"] == nil { result["mode"] = "rule" }
        result["proxy-groups"] = [["name": group, "type": "select", "proxies": names]]
        result["rules"] = ["MATCH," + group]
        let dnsNote = root["dns"] == nil ? "DNS 使用系统引导 + Cloudflare DoH。" : "保留输入中的 DNS，按同一兼容性流程校验。"
        return Document(root: result, notes: notes + ["此输入没有策略组和分流规则：已补充一个手动 select 组（默认首节点）与 MATCH 规则，普通流量统一交给所选节点；" + dnsNote + "原有元数据保留并校验，保存不会自动连接。"])
    }
}
