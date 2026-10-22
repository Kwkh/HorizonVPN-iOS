import Foundation

@main struct SelectionPolicyCheck {
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try condition() else { fatalError("Selection policy: " + label) }; checks += 1
        }
        func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
        func node(_ name: String, _ kind: String = "trojan") -> [String: Any] {
            var n: [String: Any] = ["name": name, "type": kind, "server": "node.example.invalid", "port": 443, "password": "FICTIONAL-ONLY"]
            if kind == "ss" { n["cipher"] = "aes-128-gcm" }
            return n
        }
        func provider(_ names: [String], _ fields: [String: Any] = [:]) -> [String: Any] {
            ["type": "inline", "payload": names.map { node($0) }, "health-check": ["enable": true, "url": "https://example.invalid/check", "interval": 600, "lazy": true]].merging(fields) { _, n in n }
        }
        func root(_ fields: [String: Any], _ providers: [String: Any] = [:]) -> [String: Any] {
            ["proxies": [node("US-local"), node("JP-local"), node("SS-local", "ss")], "proxy-providers": providers,
             "proxy-groups": [["name": "SELECT", "type": "select"].merging(fields) { _, n in n }], "rules": ["MATCH,SELECT"]]
        }
        let directory = URL(fileURLWithPath: ".build/research/selection-policy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifest: [[String: Any]] = []
        func accepted(_ name: String, _ raw: [String: Any], _ members: [String]) throws -> PrototypeConfiguration.Prepared {
            let data = try json(raw), p = try PrototypeConfiguration.prepare(data)
            try check(p.catalog.groups[0].members == members, name + " catalog")
            try check(ConfigurationCompatibility.inspect(data).canUse, name + " diagnostics")
            try check(p.source == data, name + " original")
            try Data(p.runtimeJSON.utf8).write(to: directory.appendingPathComponent(name + ".json"))
            var native = try JSONSerialization.jsonObject(with: Data(p.runtimeJSON.utf8)) as! [String: Any]
            native["proxy-groups"] = raw["proxy-groups"]
            native["proxy-providers"] = raw["proxy-providers"]
            try json(native).write(to: directory.appendingPathComponent(name + "-native.json"))
            manifest.append(["name": name, "groups": p.catalog.groups.map { ["name": $0.name, "members": $0.members] as [String: Any] }])
            return p
        }
        func rejected(_ name: String, _ raw: [String: Any]) throws {
            try check((try? PrototypeConfiguration.prepare(json(raw))) == nil, name)
            try check(!ConfigurationCompatibility.inspect(json(raw)).canUse, name + " diagnostic")
        }
        let providers = ["a": provider(["JP-a", "US-a", "US-low"]), "b": provider(["US-b", "JP-b"])]
        _ = try accepted("explicit-bypass", root(["proxies": ["DIRECT", "JP-local"], "use": ["a"], "filter": "^US", "exclude-filter": "low$"], providers), ["DIRECT", "JP-local", "US-a"])
        _ = try accepted("include-filter", root(["include-all": true, "filter": "(?i)^us", "exclude-filter": "low$"], providers), ["US-local", "US-a", "US-b"])
        _ = try accepted("backtick-order", root(["proxies": ["DIRECT"], "use": ["a", "b"], "filter": "^US`^JP", "exclude-filter": "low$"], providers), ["US-a", "US-b", "JP-a", "JP-b", "DIRECT"])
        _ = try accepted("lookaround", root(["include-all": true, "filter": "^(?!.*low).*US", "exclude-type": "Shadowsocks"], providers), ["US-local", "US-a", "US-b"])
        _ = try accepted("group-native-type", root(["proxies": ["SS-local", "US-local"], "exclude-type": "shadowsocks"]), ["US-local"])
        _ = try accepted("include-multiple-filters", root(["include-all-proxies": true, "filter": "US`JP"]), ["JP-local", "US-local"])
        _ = try accepted("provider-multiple-filters", root(["use": ["a"]], ["a": provider(["JP-a", "US-b"], ["filter": "US`JP"])]), ["US-b", "JP-a"])
        _ = try accepted("rename-multiple-filters", root(["use": ["a"]], ["a": provider(["US"], ["filter": "US`P-US", "override": ["additional-prefix": "P-"]])]), ["P-US", "P-P-US"])
        _ = try accepted("empty-filter", root(["proxies": ["SS-local", "US-local"], "filter": ""]), ["SS-local", "US-local"])
        _ = try accepted("provider-filter", root(["use": ["a"]], ["a": provider(["US-a", "JP-a", "US-low"], ["filter": "US", "exclude-filter": "low", "override": ["additional-prefix": "P-"]])]), ["P-US-a"])
        var types = provider([]); types["payload"] = [node("SS", "ss"), node("TLS")]; types["exclude-type"] = "ss"
        _ = try accepted("provider-raw-type", root(["use": ["a"]], ["a": types]), ["TLS"])
        let rename: [String: Any] = ["proxy-name": [["pattern": "^(US)-(.*)$", "target": "$2/$1"]], "additional-prefix": "[", "additional-suffix": "]", "skip-cert-verify": true, "udp": false]
        let renamed = try accepted("override", root(["use": ["a"], "filter": "\\[.*\\]"], ["a": provider(["US-one"], ["override": rename])]), ["[one/US]"])
        try check(renamed.insecureNodeCount == 1, "effective certificate consent")
        let runtime = try JSONSerialization.jsonObject(with: Data(renamed.runtimeJSON.utf8)) as! [String: Any]
        let p = (runtime["proxy-providers"] as! [String: [String: Any]])["a"]!
        try check(p["override"] == nil && p["filter"] == nil, "no double override")
        try check((p["health-check"] as? [String: Any])?["interval"] as? Int == 600, "health retained")
        try check(((p["payload"] as! [[String: Any]])[0]["udp"] as? Bool) == false, "udp applied")
        let hy = provider([], ["override": ["up": "20 Mbps", "down": "50 Mbps"]]).merging(["payload": [node("HY", "hysteria2")]]) { _, n in n }
        _ = try accepted("bandwidth", root(["use": ["a"]], ["a": hy]), ["HY"])
        let hyNumeric = provider([], ["override": ["up": 20, "down": 50.5]]).merging(["payload": [node("HY", "hysteria2")]]) { _, n in n }
        _ = try accepted("numeric-bandwidth", root(["use": ["a"]], ["a": hyNumeric]), ["HY"])
        for fields: [String: Any] in [["filter": "["], ["filter": 1], ["exclude-filter": true], ["exclude-type": ["ss"]], ["filter": String(repeating: "a", count: 2049)]] {
            try rejected("invalid filter", root(["include-all": true].merging(fields) { _, n in n }, providers))
        }
        try rejected("empty group", root(["include-all": true, "filter": "NOT-PRESENT"], providers))
        try rejected("exclude all explicit", root(["proxies": ["US-local"], "exclude-filter": ".*"]))
        try rejected("empty provider", root(["use": ["a"]], ["a": provider(["US"], ["filter": "JP"])]))
        try rejected("duplicate after rename", root(["use": ["a"]], ["a": provider(["US-a", "US-b"], ["override": ["proxy-name": [["pattern": ".*", "target": "same"]]]])]))
        try rejected("unknown override", root(["use": ["a"]], ["a": provider(["US"], ["override": ["override-expr": ["name = 'x'"]]])]))
        try rejected("invalid override type", root(["use": ["a"]], ["a": provider(["US"], ["override": ["skip-cert-verify": "true"]])]))
        try rejected("invalid rename regex", root(["use": ["a"]], ["a": provider(["US"], ["override": ["proxy-name": [["pattern": "[", "target": "x"]]]])]))
        try rejected("inapplicable override", root(["use": ["a"]], ["a": provider(["US"], ["override": ["up": "20 Mbps"]])]))
        let slowName = String(repeating: "a", count: 110) + "!"
        let start = Date()
        try rejected("regex timeout", root(["use": ["a"]], ["a": provider([slowName], ["filter": "^(a+)+$"])]))
        try check(Date().timeIntervalSince(start) < 5, "regex bounded")
        let before = try json(root(["use": ["a"], "filter": "US"], ["a": provider(["US-old", "US-stay"])]))
        let after = try json(root(["use": ["a"], "filter": "US"], ["a": provider(["US-new", "US-stay"])]))
        let retained = try await ConfigurationImportWorker.shared.validate(after, choices: ["SELECT": "US-stay"])
        try check(retained.prepared.catalog.choices["SELECT"] == "US-stay", "refresh retains valid choice")
        let removed = try await ConfigurationImportWorker.shared.validate(after, choices: ["SELECT": "US-old"])
        try check(removed.prepared.catalog.choices["SELECT"] == "US-new", "removed choice resolves to actual first member")
        try check(try SubscriptionChangeSummary.compare(before, after).contains("策略组：已改变"), "effective group diff")
        let rolledBack = try await ConfigurationImportWorker.shared.validate(before, choices: ["SELECT": "US-old"])
        try check(rolledBack.prepared.catalog.choices["SELECT"] == "US-old", "rollback restores membership and choice")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: directory.appendingPathComponent("manifest.json"))
        print("Selection policy: \(checks) checks passed; \(manifest.count) native differential fixtures exported.")
    }
}
