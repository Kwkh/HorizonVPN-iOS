import Foundation

@main struct GeneralCompatibilityCheck {
    static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { fatalError("General compatibility regression: " + name) }; count += 1
        }
        func json(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) }
        let base = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        let example = (base["proxies"] as! [[String: Any]])[0]
        func node(_ name: String) -> [String: Any] { var node = example; node["name"] = name; return node }
        func document(_ group: [String: Any], providers: [String: Any] = [:]) -> [String: Any] {
            ["proxies": [node("Z"), node("A")], "proxy-providers": providers,
             "proxy-groups": [["name": "SELECT", "type": "select"].merging(group) { _, n in n }], "rules": ["MATCH,SELECT"]]
        }
        func rejects(_ root: [String: Any]) -> Bool { (try? PrototypeConfiguration.prepare(json(root))) == nil }
        let fixtureDirectory = URL(fileURLWithPath: ".build/research/general-compatibility")
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        var manifest: [[String: Any]] = []
        func export(_ name: String, _ prepared: PrototypeConfiguration.Prepared) throws {
            try Data(prepared.runtimeJSON.utf8).write(to: fixtureDirectory.appendingPathComponent(name + ".json"))
            var native = try JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as! [String: Any]
            let original = try PrototypeConfiguration.decodeYAML(ConfigurationSnapshot.original(prepared.source))
            if let groups = original["proxy-groups"] { native["proxy-groups"] = groups }
            try JSONSerialization.data(withJSONObject: native, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: fixtureDirectory.appendingPathComponent(name + "-native.json"))
            manifest.append(["name": name, "groups": prepared.catalog.groups.map { ["name": $0.name, "members": $0.members] as [String: Any] }])
        }
        for status: Any in [204, "204", "200-299/304", "*"] {
            let raw = try json(document(["proxies": ["A"], "expected-status": status]))
            let prepared = try PrototypeConfiguration.prepare(raw)
            let runtime = try JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as! [String: Any]
            try check((runtime["proxy-groups"] as! [[String: Any]])[0]["expected-status"] is String, "status normalized")
            try check(ConfigurationCompatibility.inspect(raw).canUse, "status info agrees")
            try export("status-\(count)", prepared)
        }
        for bad: Any in [true, 204.5, 99, 600, "200-100", "invalid"] {
            try check(rejects(document(["proxies": ["A"], "expected-status": bad])), "bad status rejected")
        }
        for listener in [":1053", "[::]:53", "0.0.0.0:53"] {
            var root = base; root["dns"] = ["listen": listener, "nameserver": ["1.1.1.1"]]
            try check(try PrototypeConfiguration.prepare(json(root)).runtimeJSON.contains("\"listen\"") == false, "listener adapted")
        }
        for bad in [":0", ":65536", ":53/path", "::53", ":53#extra"] {
            try check(!ConfigurationDNS.validListener(bad), "invalid listener")
        }
        for dns in [false, true] {
            var root: [String: Any] = ["proxies": [node("A")], "ipv6": false, "log-level": "debug", "unified-delay": false]
            if dns { root["dns"] = ["nameserver": ["9.9.9.9"], "default-nameserver": ["1.1.1.1"]] }
            let raw = try json(root), prepared = try PrototypeConfiguration.prepare(raw)
            try check(prepared.catalog.groups.count == 1 && prepared.source == raw, "node metadata source/template")
            try check(!prepared.unifiedDelay && prepared.runtimeJSON.contains("\"ipv6\":false"), "metadata retained")
            try check(prepared.runtimeJSON.contains(dns ? "9.9.9.9" : "https://1.1.1.1/dns-query"), "explicit/default DNS")
            try export("metadata-\(dns)", prepared)
        }
        try check(rejects(["proxies": [node("A")], "mode": "global"]), "node template cannot rewrite global")
        try check(rejects(["proxies": [node("A")], "proxy-groups": [["name": "SELECT", "type": "select", "proxies": ["A"]]]]), "missing rules not fabricated")
        try check(rejects(["proxies": [node("A")], "ipv6": "false"]), "invalid metadata not coerced")
        let direct = try PrototypeConfiguration.prepare(json(["proxies": [node("A")], "rules": ["MATCH,A"]]))
        try check(direct.catalog.groups.isEmpty && direct.nodeName == "A", "explicit rules need no groups")
        try export("no-groups", direct)
        let providers: [String: Any] = [
            "z": ["type": "inline", "payload": [node("PZ")]],
            "a": ["type": "inline", "payload": [node("PA")], "health-check": ["enable": false, "expected-status": 204]]]
        let cases: [(String, [String: Any], [String])] = [
            ("inline", ["include-all-proxies": true], ["A", "Z"]),
            ("provider", ["include-all-providers": true], ["PA", "PZ"]),
            ("all", ["include-all": true], ["A", "Z", "PA", "PZ"]),
            ("explicit-first", ["proxies": ["DIRECT", "Z"], "include-all-proxies": true], ["DIRECT", "Z", "A"]),
            ("override-use", ["use": ["not-referenced"], "include-all-providers": true], ["PA", "PZ"]),
            ("false", ["include-all": false, "proxies": ["Z"], "use": ["z"]], ["Z", "PZ"])]
        for (name, fields, members) in cases {
            let raw = try json(document(fields, providers: providers))
            let prepared = try PrototypeConfiguration.prepare(raw)
            try check(prepared.catalog.groups[0].members == members, "include order " + name)
            try check(prepared.source == raw && !prepared.runtimeJSON.contains("include-all"), "source/runtime " + name)
            try check(ConfigurationCompatibility.inspect(raw).canUse, "include diagnostic " + name)
            try export(name, prepared)
            let selected = try PrototypeConfiguration.prepare(raw, choices: ["SELECT": members.last!])
            try check(selected.catalog.choices["SELECT"] == members.last!, "choice retained " + name)
        }
        try check(rejects(document(["include-all": "true"])), "flag type")
        try check(rejects(document(["include-all-providers": true])), "empty group not direct")
        try check(try PrototypeConfiguration.prepare(json(document(["include-all": true, "filter": "A"]))).catalog.groups[0].members == ["A"], "filter applied to automatic members")
        try check(rejects(document(["include-all": true, "proxies": ["SELECT"]])), "cycles still blocked")
        try check(rejects(document(["include-all": true, "proxies": ["MISSING"]])), "missing explicit reference")
        try check(rejects(document(["include-all": true, "proxies": ["A", "A"]])), "explicit duplicates still blocked")
        var invalid = document(["include-all": "true"])
        invalid["dns"] = ["nameserver": ["1.1.1.1"], "prefer-h3": true]
        let report = ConfigurationCompatibility.inspect(try json(invalid))
        try check(report.findings.contains { $0.location == "策略组 1" && $0.level == .blocked }, "report invalid include flag")
        try check(report.findings.contains { $0.location == "DNS · prefer-h3" && $0.level == .blocked }, "report independent DNS failure too")
        let before = try json(document(["include-all": true], providers: providers))
        var refreshed = document(["include-all": true], providers: providers); refreshed["proxies"] = [node("Z"), node("B")]
        let after = try json(refreshed)
        let updated = try PrototypeConfiguration.prepare(after, choices: ["SELECT": "Z"])
        try check(updated.catalog.groups[0].members == ["B", "Z", "PA", "PZ"], "refresh recalculates")
        try check(updated.catalog.choices["SELECT"] == "Z", "surviving choice retained")
        try check(try PrototypeConfiguration.prepare(before).catalog.groups[0].members == ["A", "Z", "PA", "PZ"], "rollback restores membership")
        try check((try? PrototypeConfiguration.prepare(after, choices: ["SELECT": "A"])) == nil, "removed choice not silently retained")
        // HTTP provider path uses the same membership logic after controlled snapshot materialization.
        let remote: [String: Any] = ["remote": ["type": "http", "url": "https://example.invalid/nodes"]]
        let raw = try json(document(["include-all-providers": true], providers: remote))
        let snapshot = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: true, fetch: { _ in try json(["proxies": [node("REMOTE")]]) })
        let checked = try PrototypeConfiguration.prepare(snapshot)
        try check(checked.catalog.groups[0].members == ["REMOTE"], "downloaded provider membership")
        try export("remote", checked)
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: fixtureDirectory.appendingPathComponent("manifest.json"))
        print("General compatibility: \(count) checks passed; fictional fixtures, no network.")
    }
}
