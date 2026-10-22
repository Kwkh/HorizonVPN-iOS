import Foundation

@main struct DNSCompatibilityCheck {
    static func main() async throws {
        var count = 0
        func check(_ ok: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try ok() else { fatalError("DNS regression: " + label) }; count += 1
        }
        let base = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        let basic: [String: Any] = ["nameserver": ["223.5.5.5"], "default-nameserver": ["1.1.1.1"]]
        func normalized(_ fields: [String: Any]) throws -> ConfigurationDNS.Result {
            try ConfigurationDNS.prepare(basic.merging(fields) { _, new in new }, ipv6: true, bootstrap: ["1.1.1.1"])
        }
        for listener in ["", "0.0.0.0:1053", "127.0.0.1:53", "[::]:1053"] {
            let result = try normalized(["listen": listener, "prefer-h3": false])
            try check(result.value["listen"] == nil, "listener removed")
            try check(result.value["prefer-h3"] as? Bool == false, "H3 false retained")
            try check(result.notes.contains { $0.contains("不开放") }, "listener disclosed")
        }
        for fields: [String: Any] in [["listen": 1053], ["listen": "example.invalid:53"], ["listen": "0.0.0.0:70000"], ["listen": "0.0.0.0:53/path"], ["prefer-h3": true], ["prefer-h3": "false"], ["fallback-filter": ["geoip": "true"]], ["fallback-filter": ["geoip-code": "CN,US"]]] {
            try check((try? normalized(fields)) == nil, "invalid/unsupported rejected")
        }
        for dat in [false, true] {
            for explicit in [false, true] {
                var dns = basic
                dns["fallback"] = ["1.1.1.1"]
                dns["listen"] = "0.0.0.0:1053"
                dns["prefer-h3"] = false
                if explicit { dns["fallback-filter"] = ["geoip": true, "geoip-code": "cn"] }
                var root = base; root["dns"] = dns; root["geodata-mode"] = dat
                let raw = try JSONSerialization.data(withJSONObject: root)
                let requests = try ConfigurationResources.plan(root)
                try check(requests.count == 1 && requests[0].key == (dat ? "geo:geoip:dat" : "geo:geoip:mmdb"), "DNS-only Geo planned")
                try check((try? PrototypeConfiguration.prepare(raw)) == nil, "missing snapshot blocked")
                let snapshot = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false, bundledDirectory: URL(fileURLWithPath: "Horizon/Resources/GeoData"))
                let prepared = try PrototypeConfiguration.prepare(snapshot)
                let runtime = try JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as! [String: Any]
                let resultDNS = runtime["dns"] as! [String: Any]
                let filter = resultDNS["fallback-filter"] as! [String: Any]
                try check(filter["geoip"] as? Bool == true && filter["geoip-code"] as? String == "CN", "defaults/country retained")
                try check(resultDNS["listen"] == nil && resultDNS["prefer-h3"] as? Bool == false, "runtime adaptation")
                try check(ConfigurationCompatibility.inspect(snapshot).canUse, "info report accepts")
                try check(try ConfigurationSnapshot.original(snapshot) == raw, "original retained")
                let dir = URL(fileURLWithPath: ".build/research/dns-\(dat ? "dat" : "mmdb")")
                try ConfigurationResources.install(snapshot, in: dir)
                try Data(prepared.runtimeJSON.utf8).write(to: dir.appendingPathComponent("runtime.json"))
            }
        }
        let disabled = try normalized(["fallback": ["1.1.1.1"], "fallback-filter": ["geoip": false, "geoip-code": "US"]])
        try check((disabled.value["fallback-filter"] as? [String: Any])?["geoip-code"] == nil, "inactive code does not compile extra Geo category")
        var root = base; root["dns"] = basic.merging(["fallback": ["1.1.1.1"], "fallback-filter": ["geoip": false]]) { _, new in new }
        try check(try ConfigurationResources.plan(root).isEmpty, "geoip false needs no resource")
        try check(try PrototypeConfiguration.prepare(JSONSerialization.data(withJSONObject: root)).catalog.nodes.count == 1, "geoip false usable")
        root["geodata-mode"] = true
        root["dns"] = basic.merging(["fallback": ["1.1.1.1"], "fallback-filter": ["geoip": true, "geoip-code": "ZZ"]]) { _, new in new }
        let missingCategory = try await SubscriptionResourceLoader.prepare(JSONSerialization.data(withJSONObject: root), permitsNetwork: false, bundledDirectory: URL(fileURLWithPath: "Horizon/Resources/GeoData"))
        let rejected = (try? ConfigurationResources.install(missingCategory, in: URL(fileURLWithPath: ".build/research/dns-missing-category"))) == nil
        try check(rejected, "missing DNS-only DAT category blocked")
        print("DNS compatibility: \(count) checks passed; synthetic input, no network requests.")
    }
}
