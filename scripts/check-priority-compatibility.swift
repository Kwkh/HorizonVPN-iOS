import Foundation

@main struct PriorityCompatibilityCheck {
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try condition() else { fatalError("Priority compatibility: " + label) }; checks += 1
        }
        func json(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]) }
        func runtime(_ p: PrototypeConfiguration.Prepared) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(p.runtimeJSON.utf8)) as! [String: Any] }
        let dir = URL(fileURLWithPath: ".build/research/priority-compatibility")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func export(_ name: String, _ p: PrototypeConfiguration.Prepared) throws {
            let destination = dir.appendingPathComponent(name)
            try ConfigurationResources.install(p.source, in: destination)
            try Data(p.runtimeJSON.utf8).write(to: destination.appendingPathComponent("runtime.json"))
        }
        let ss: [String: Any] = ["name": "A", "type": "ss", "server": "node.example.invalid", "port": 443, "cipher": "aes-128-gcm", "password": "FICTIONAL-ONLY", "udp": true]
        func prepared(_ node: [String: Any]) throws -> PrototypeConfiguration.Prepared { try PrototypeConfiguration.prepare(json(["proxies": [node]])) }
        func refuses(_ root: [String: Any]) throws {
            let data = try json(root)
            try check((try? PrototypeConfiguration.prepare(data)) == nil, "bad input rejected")
            try check(!ConfigurationCompatibility.inspect(data).canUse, "diagnostics agree with rejection")
        }
        for (i, fields) in [
            ["tfo": true, "ip-version": "ipv4-prefer"],
            ["udp-over-tcp": true, "udp-over-tcp-version": 2],
            ["smux": ["enabled": true, "protocol": "h2mux", "padding": true, "max-connections": 2, "min-streams": 4, "only-tcp": true]],
            ["plugin": "obfs", "plugin-opts": ["mode": "http", "host": "cdn.example.invalid"]],
            ["plugin": "obfs", "plugin-opts": ["mode": "tls"]],
            ["plugin": "v2ray-plugin", "plugin-opts": ["mode": "websocket", "path": "/ws", "host": "cdn.example.invalid", "mux": false]],
            ["plugin": "v2ray-plugin", "plugin-opts": ["mode": "websocket", "tls": true, "skip-cert-verify": true, "headers": ["X-Test": "example"]], "client-fingerprint": "chrome"]
        ].enumerated() {
            let node = ss.merging(fields) { _, new in new }, p = try prepared(node)
            let actual = (try runtime(p)["proxies"] as! [[String: Any]])[0]
            for (key, value) in fields { try check(NSDictionary(dictionary: ["v": actual[key]!]).isEqual(to: ["v": value]), "node option retained " + key) }
            try check(ConfigurationCompatibility.inspect(p.source).canUse, "node diagnostic accepted")
            try check(p.insecureNodeCount == (i == 6 ? 1 : 0), "plugin consent counted")
            try export("node-\(i)", p)
        }
        for fields: [String: Any] in [["ip-version": "bad"], ["tfo": "true"], ["mptcp": true], ["smux": ["enabled": true, "brutal-opts": ["enabled": true]]], ["smux": ["enabled": true, "max-streams": -1]], ["plugin": "unknown", "plugin-opts": [:]], ["plugin": "v2ray-plugin", "plugin-opts": ["mode": "quic"]], ["plugin": "v2ray-plugin", "plugin-opts": ["mode": "websocket", "skip-cert-verify": true]], ["client-fingerprint": "chrome"], ["udp-over-tcp-version": 3]] {
            try refuses(["proxies": [ss.merging(fields) { _, v in v }]])
        }
        var vmess = ExtendedCompatibilitySelfCheck.nodes.first { $0["name"] as? String == "vmess-tcp" }!
        vmess["global-padding"] = true; vmess["authenticated-length"] = true
        try export("vmess-flags", prepared(vmess))
        let auth = Data("aes-128-gcm:FICTIONAL-ONLY".utf8).base64EncodedString()
        for (i, plugin) in ["obfs-local;obfs=tls;obfs-host=cdn.example.invalid", "v2ray-plugin;tls;host=cdn.example.invalid;path=/a\\;b;skip-cert-verify"].enumerated() {
            let query = plugin.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            let uri = "ss://\(auth)@node.example.invalid:443/?plugin=\(query)#EXAMPLE"
            let node = try NodeURI.parse(uri, index: 0)
            try check(node["plugin"] as? String == (i == 0 ? "obfs" : "v2ray-plugin"), "SIP002 mapping")
            if i == 1 { try check((node["plugin-opts"] as! [String: Any])["path"] as? String == "/a;b", "SIP002 escaping") }
            let p = try PrototypeConfiguration.prepare(Data(uri.utf8)); try export("uri-\(i)", p)
        }
        for plugin in ["v2ray-plugin;server", "obfs-local;obfs=tls;obfs=http", "v2ray-plugin;tls=bad", "other"] {
            let uri = "ss://\(auth)@node.example.invalid:443/?plugin=" + plugin.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            try check((try? NodeURI.parse(uri, index: 0)) == nil, "bad SIP002 plugin rejected")
        }
        var b = ss; b["name"] = "B"
        for strategy in ["consistent-hashing", "round-robin", "sticky-sessions"] {
            let root: [String: Any] = ["proxies": [ss, b], "proxy-groups": [["name": "BALANCE", "type": "load-balance", "strategy": strategy, "proxies": ["A", "B"]]], "rules": ["MATCH,BALANCE"]]
            let p = try PrototypeConfiguration.prepare(json(root))
            try check(!p.catalog.groups[0].allowsSelection && p.catalog.resolvedTarget() == nil, "automatic group not fabricated as selected node")
            try check(ConfigurationCompatibility.inspect(p.source).canUse, "load-balance diagnostic")
            try export("balance-" + strategy, p)
        }
        try refuses(["proxies": [ss], "proxy-groups": [["name": "X", "type": "select", "strategy": "round-robin", "proxies": ["A"]]], "rules": ["MATCH,X"]])
        let dnsBase: [String: Any] = ["nameserver": ["1.1.1.1"], "default-nameserver": ["1.1.1.1"], "use-hosts": true]
        let domainProvider: [String: Any] = ["domains": ["type": "inline", "behavior": "domain", "payload": ["+.example.invalid"]]]
        var root: [String: Any] = ["proxies": [ss], "proxy-groups": [["name": "SELECT", "type": "select", "proxies": ["A"]]], "rules": ["MATCH,SELECT"], "rule-providers": domainProvider, "hosts": ["host.example.invalid": ["192.0.2.5", "2001:db8::5"]]]
        root["dns"] = dnsBase.merging(["nameserver-policy": ["rule-set:domains": ["https://1.1.1.1/dns-query#SELECT"], "+.local.invalid,exact.invalid": "system"]]) { _, v in v }
        let dnsPrepared = try PrototypeConfiguration.prepare(json(root), bootstrapServers: ["192.0.2.53"])
        try check(dnsPrepared.needsSystemBootstrap && dnsPrepared.runtimeJSON.contains("192.0.2.53"), "system resolver snapshot")
        try check(ConfigurationCompatibility.inspect(dnsPrepared.source).canUse, "DNS policy diagnostics")
        try export("dns-ruleset-hosts", dnsPrepared)
        for fields: [String: Any] in [["nameserver": ["https://1.1.1.1/dns-query#MISSING"]], ["proxy-server-nameserver": ["https://1.1.1.1/dns-query#SELECT"]], ["nameserver-policy": ["rule-set:missing": "1.1.1.1"]], ["nameserver": ["https://1.1.1.1/dns-query#SELECT&h3=true"]]] {
            var invalid = root; invalid["dns"] = dnsBase.merging(fields) { _, v in v }; try refuses(invalid)
        }
        var invalid = root; invalid["hosts"] = ["host.example.invalid": "not-an-address"]; try refuses(invalid)
        for (name, fields) in [("policy", ["nameserver-policy": ["geosite:cn": ["1.1.1.1"]]]), ("fallback", ["fallback": ["1.0.0.1"], "fallback-filter": ["geoip": false, "geosite": ["cn"]]])] {
            var geo = root; geo["dns"] = dnsBase.merging(fields) { _, v in v }
            let raw = try json(geo), plan = try ConfigurationResources.plan(geo)
            try check(plan.contains { $0.key == "geo:geosite:dat" }, "DNS-only GeoSite planned")
            let snapshot = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false, bundledDirectory: URL(fileURLWithPath: "Horizon/Resources/GeoData"))
            let p = try PrototypeConfiguration.prepare(snapshot)
            try check(ConfigurationCompatibility.inspect(snapshot).canUse, "GeoSite diagnostics")
            try export("dns-geosite-" + name, p)
        }
        let orderedYAML = """
        proxies:
          - {name: A, type: ss, server: node.example.invalid, port: 443, cipher: aes-128-gcm, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [A]}
        rules: ['MATCH,SELECT']
        rule-providers:
          z: {type: inline, behavior: domain, payload: ['+.example.invalid']}
          a: {type: inline, behavior: domain, payload: ['+.example.invalid']}
        dns:
          nameserver: ['1.1.1.1']
          default-nameserver: ['1.1.1.1']
          nameserver-policy:
            'rule-set:z': ['https://1.1.1.1/dns-query#SELECT']
            'rule-set:a': ['1.0.0.1']
        """
        let ordered = try PrototypeConfiguration.prepare(Data(orderedYAML.utf8))
        try check(ordered.runtimeJSON.range(of: "rule-set:z")!.lowerBound < ordered.runtimeJSON.range(of: "rule-set:a")!.lowerBound, "YAML policy precedence preserved")
        try export("dns-order", ordered)
        let padded = Data((orderedYAML + "\n#" + String(repeating: " ", count: 900_000)).utf8)
        let envelope = try ConfigurationSnapshot(original: padded, resources: []).encoded()
        try check(envelope.count > 1024 * 1024 && envelope.count < 2 * 1024 * 1024, "large snapshot Base64 overhead")
        try check(try ConfigurationSnapshot.original(envelope) == padded, "near-limit snapshot remains readable")
        try check(try PrototypeConfiguration.prepare(envelope).catalog.nodes.count == 1, "near-limit snapshot imports")
        let jsonOrdered = #"{"proxies":[{"name":"A","type":"ss","server":"node.example.invalid","port":443,"cipher":"aes-128-gcm","password":"FICTIONAL"}],"dns":{"nameserver":["1.1.1.1"],"default-nameserver":["1.1.1.1"],"nameserver-policy":{"z.example.invalid":"https:\/\/1.1.1.1/dns-query","a.example.invalid":"1.0.0.1"}}}"#
        let orderedJSON = try PrototypeConfiguration.prepare(Data(jsonOrdered.utf8))
        try check(orderedJSON.runtimeJSON.range(of:"z.example.invalid")!.lowerBound < orderedJSON.runtimeJSON.range(of:"a.example.invalid")!.lowerBound, "JSON escaped slash and policy order")
        try export("dns-order-json", orderedJSON)
        // Retired mainland-direct snapshots must recover original policy without network or storage writes.
        let rollbackRoot: [String: Any] = ["proxies": [ss], "geox-url": [:],
            "proxy-groups": [["name": "Proxy", "type": "select", "proxies": ["A"]]],
            "rules": ["MATCH,Proxy"]]
        let rollbackOriginal = try json(rollbackRoot)
        let fakeGeo = ConfigurationSnapshot.Resource(key: "geo:geosite:dat", digest: String(repeating: "a", count: 64), bytes: 1)
        func retiredSnapshot(_ original: Data, enabled: Bool, resources: [ConfigurationSnapshot.Resource]) throws -> Data {
            let envelope = try ConfigurationSnapshot(original: original, resources: resources).encoded()
            var object = try JSONSerialization.jsonObject(with: envelope.dropFirst(ConfigurationSnapshot.prefix.count)) as! [String: Any]
            object["mainlandDirect"] = enabled
            return ConfigurationSnapshot.prefix + (try json(object))
        }
        let retired = try retiredSnapshot(rollbackOriginal, enabled: true, resources: [fakeGeo])
        try check(try ConfigurationSnapshot.read(retired)!.resources.isEmpty, "retired option removes only added Geo")
        try check(try ConfigurationSnapshot.original(retired) == rollbackOriginal, "rollback preserves original bytes")
        try check(try runtime(PrototypeConfiguration.prepare(retired))["rules"] as? [String] == ["MATCH,Proxy"], "rollback restores original rules")
        try check(try PrototypeConfiguration.prepare(retired).runtimeJSON == PrototypeConfiguration.prepare(rollbackOriginal).runtimeJSON, "rollback restores original DNS and runtime")
        var needsGeo = rollbackRoot; needsGeo["rules"] = ["GEOSITE,cn,DIRECT", "MATCH,Proxy"]
        let requiredGeo = try retiredSnapshot(json(needsGeo), enabled: true, resources: [fakeGeo])
        try check(try ConfigurationSnapshot.read(requiredGeo)!.resources == [fakeGeo], "original Geo dependency retained")
        let inactiveRetired = try retiredSnapshot(rollbackOriginal, enabled: false, resources: [fakeGeo])
        try check((try? PrototypeConfiguration.prepare(inactiveRetired)) == nil, "normal resource mismatch still rejected")
        let unexpected = ConfigurationSnapshot.Resource(key: "rule:unexpected", digest: String(repeating: "b", count: 64), bytes: 1)
        let invalidRetired = try retiredSnapshot(rollbackOriginal, enabled: true, resources: [fakeGeo, unexpected])
        try check((try? PrototypeConfiguration.prepare(invalidRetired)) == nil, "rollback does not hide unexpected providers")
        // A limit increase must cover include-all, core filtering, provider projection and URI lists.
        let nodes: [[String: Any]] = (0..<512).map { i in var n = ss; n["name"] = "N\(i)"; return n }
        let groups: [[String: Any]] = (0..<64).map { i in ["name": "G\(i)", "type": "select", "include-all-proxies": true, "filter": "^N"] }
        let rules = (0..<8191).map { "DOMAIN,d\($0).example.invalid,DIRECT" } + ["MATCH,G0"]
        let large: [String: Any] = ["proxies": nodes, "proxy-groups": groups, "rules": rules]
        let raw = try json(large), start = ContinuousClock.now
        let p = try PrototypeConfiguration.prepare(raw)
        print("Large fixture: \(raw.count) bytes; Swift + subprocess bridge preparation \(start.duration(to: .now)); 512 nodes / 64 groups / 8192 rules.")
        try check(p.catalog.nodes.count == 512 && p.catalog.groups.count == 64 && p.catalog.groups.allSatisfy { $0.members.count == 512 }, "large complete membership")
        try export("large", p)
        try check(try PrototypeConfiguration.prepare(json(["proxies": nodes])).catalog.nodes.count == 512, "large node-only template")
        let projected = try ConfigurationSelectionPolicy.provider(nodes, options: ["filter": "^N", "override": ["tfo": true, "ip-version": "ipv4"]], at: "fixture")
        try check(projected.count == 512 && projected.allSatisfy { $0["tfo"] as? Bool == true && $0["ip-version"] as? String == "ipv4" }, "large provider override")
        let uris = (0..<512).map { "ss://\(auth)@node.example.invalid:443#N\($0)" }.joined(separator: "\n")
        try check(try PrototypeConfiguration.prepare(Data(uris.utf8)).catalog.nodes.count == 512, "512 URI list")
        var overflow = large; var extra = ss; extra["name"] = "OVERFLOW"
        overflow["proxies"] = nodes + [extra]
        try check((try? PrototypeConfiguration.prepare(json(overflow))) == nil, "513 nodes blocked")
        overflow = large; overflow["rules"] = rules + ["MATCH,DIRECT"]
        try check((try? PrototypeConfiguration.prepare(json(overflow))) == nil, "8193 rules blocked")
        overflow = large; overflow["proxy-groups"] = groups + [["name": "OVER", "type": "select", "proxies": ["N0"]]]
        try check((try? PrototypeConfiguration.prepare(json(overflow))) == nil, "65 groups blocked")
        try check((try? ConfigurationInput.read(Data(repeating: 32, count: PrototypeConfiguration.maximumBytes + 1))) == nil, "size cap retained")
        print("Priority compatibility: \(checks) checks passed; synthetic data, no network or credentials.")
    }
}
