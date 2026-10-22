import Foundation

@main struct SmartRoutingCheck {
    static func main() async throws {
        var count = 0
        func check(_ ok: @autoclosure () throws -> Bool, _ label: String) throws {
            guard try ok() else { fatalError("Smart routing: " + label) }; count += 1
        }
        let base = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        let bundled = URL(fileURLWithPath: "Horizon/Resources/GeoData")
        func encode(_ root: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: root, options: .sortedKeys) }
        func prepare(_ raw: Data, mode: ConfigurationRouting = .smart, previous: Data? = nil) async throws -> Data {
            try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false, previousSource: previous,
                routing: mode, reuseDependencies: previous != nil, bundledDirectory: bundled)
        }
        func runtime(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(PrototypeConfiguration.prepare(data).runtimeJSON.utf8)) as! [String: Any]
        }
        let original = try encode(base)
        let smart = try await prepare(original)
        try check(try ConfigurationSnapshot.original(smart) == original, "original bytes preserved")
        try check(try ConfigurationRouting.mode(in: smart) == .smart, "option survives serialization")
        let root = try runtime(smart), dns = root["dns"] as! [String: Any]
        let originalRules = base["rules"] as! [String]
        try check(root["rules"] as? [String] == Array(originalRules.dropLast()) + ["GEOSITE,cn,DIRECT", "GEOIP,CN,DIRECT", originalRules.last!], "insert only before final")
        try check((dns["direct-nameserver"] as? [String])?.allSatisfy { $0.hasSuffix("#DIRECT") } == true, "encrypted direct resolvers bypass proxy")
        try check(try ConfigurationSnapshot.read(smart)!.resources.count == 2, "two verified bundled datasets")
        try check(ConfigurationCompatibility.inspect(smart).canUse, "diagnosis accepts smart config")
        let dir = URL(fileURLWithPath: ".build/research/smart-routing")
        try ConfigurationResources.install(smart, in: dir)
        try Data(PrototypeConfiguration.prepare(smart).runtimeJSON.utf8).write(to: dir.appendingPathComponent("runtime.json"))
        let restored = try await prepare(original, mode: .subscription, previous: smart)
        try check(restored == original, "disable restores exact source without extra dependencies")
        let again = try await prepare(original, previous: smart)
        try check(again == smart, "refresh retains mode/resources, no duplicate rules")
        let storage = MemorySubscriptionStorage()
        ConfigurationResourceStore.testStorage = storage
        let repo = SubscriptionRepository(storage: storage)
        let before = StoredConfiguration(source: original)
        let id = try repo.add(before, fileName: "Fixture.yaml", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: true)
        try ConfigurationResourceStore.persist(smart, storage: storage)
        ConfigurationResourceStore.discardPending()
        let persistedDirectory = dir.appendingPathComponent("persisted")
        try ConfigurationResources.install(smart, in: persistedDirectory)
        for resource in try ConfigurationSnapshot.read(smart)!.resources {
            let name = resource.key == "geo:geosite:dat" ? "GeoSite.dat" : "geoip.metadb"
            try check(ConfigurationResourceStore.digest(Data(contentsOf: persistedDirectory.appendingPathComponent(name))) == resource.digest,
                      "persisted resource streaming preserves digest")
        }
        try check(try PrototypeConfiguration.prepare(smart).ruleCount == originalRules.count + 2, "reload from persisted resources")
        // Transfer a multi-chunk synthetic artifact; matching semantics are tested with
        // real compiled Geo data by the pinned-core tests.
        let cacheStore = MemorySubscriptionStorage()
        let compiled = dir.appendingPathComponent("cache-source/compiled-geosite")
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        let artifact = Data(repeating: 73, count: 600_000)
        try artifact.write(to: compiled.appendingPathComponent("cn.mrs"))
        try CompiledGeoCache.publish(source: smart, directory: compiled.deletingLastPathComponent(), storage: cacheStore)
        try CompiledGeoCache.collect(sources: [], storage: cacheStore)
        let cacheTarget = dir.appendingPathComponent("cache-target")
        try check(try CompiledGeoCache.restore(source: smart, directory: cacheTarget, storage: cacheStore), "staged preflight artifacts survive library cleanup")
        try check(try Data(contentsOf: cacheTarget.appendingPathComponent("compiled-geosite/cn.mrs")) == artifact, "multi-chunk compiled artifact restored exactly")
        try check(try !CompiledGeoCache.restore(source: original, directory: cacheTarget, storage: cacheStore), "cache cannot cross source identities")
        let chunkKey = cacheStore.items.keys.first(where: { $0.hasSuffix("-0") })!
        try cacheStore.write(Data([0]), for: chunkKey)
        do { _ = try CompiledGeoCache.restore(source: smart, directory: cacheTarget, storage: cacheStore); fatalError("corrupt cache accepted") }
        catch { count += 1 }
        CompiledGeoCache.discardStaged()
        try CompiledGeoCache.collect(sources: [smart], storage: cacheStore)
        try check(!cacheStore.items.isEmpty, "active and rollback source keeps its cache")
        try CompiledGeoCache.collect(sources: [], storage: cacheStore)
        try check(cacheStore.items.isEmpty, "unreferenced compiled cache collected")
        // Reload staging before the atomic commit, just like the candidate pipeline.
        _ = try await prepare(original)
        let prepared = try PrototypeConfiguration.prepare(smart)
        try repo.replace(id, expected: before, source: smart, choices: prepared.catalog.choices, sourceURL: nil,
                         nodeCount: 1, groupCount: 1, ruleCount: prepared.ruleCount)
        let current = try repo.record(id)
        try check(current.history?.first?.source == original, "prior revision retained")
        try check(try ConfigurationRouting.mode(in: current.source) == .smart, "per-subscription persistence")
        try repo.replace(id, expected: current, source: original, choices: before.choices, sourceURL: nil, nodeCount: 1, groupCount: 1, ruleCount: 1)
        try check(try repo.record(id).source == original, "manual rollback source intact")
        // Existing exceptions precede the domestic defaults; custom DNS is not overwritten.
        var complex = base
        complex["rules"] = ["DOMAIN,weixin.qq.com,REJECT", "DOMAIN,force.example.invalid," + prepared.catalog.matchTarget, originalRules.last!]
        complex["dns"] = ["nameserver": ["9.9.9.9"], "nameserver-policy": ["+.example.invalid": "8.8.8.8"],
                          "direct-nameserver": ["223.6.6.6"], "ipv6": false]
        let custom = try await prepare(encode(complex))
        let customRoot = try runtime(custom), customDNS = customRoot["dns"] as! [String: Any]
        try check((customRoot["rules"] as! [String]).prefix(2) == (complex["rules"] as! [String]).prefix(2), "exceptions retain priority")
        try check(customDNS["direct-nameserver"] as? [String] == ["223.6.6.6"], "explicit direct DNS preserved")
        try check(customDNS["nameserver"] as? [String] == ["9.9.9.9"], "explicit foreign DNS preserved")
        try check(customDNS["ipv6"] as? Bool == false, "explicit DNS IPv6 preserved")
        var missingDirect = complex
        var existingDNS = missingDirect["dns"] as! [String: Any]
        existingDNS.removeValue(forKey: "direct-nameserver")
        missingDirect["dns"] = existingDNS
        let amendedDNS = try runtime(await prepare(encode(missingDirect)))["dns"] as! [String: Any]
        try check(amendedDNS["direct-nameserver-follow-policy"] as? Bool == true, "existing domain policies retain direct precedence")
        try check((amendedDNS["nameserver-policy"] as? NSDictionary) == (customDNS["nameserver-policy"] as? NSDictionary), "existing domain policy unchanged")
        var tooMany = base
        tooMany["rules"] = Array(repeating: "DOMAIN,example.invalid,DIRECT", count: PrototypeConfiguration.maximumRules - 1) + [originalRules.last!]
        do { _ = try await prepare(encode(tooMany)); fatalError("rule overflow accepted") } catch { count += 1 }
        var customGeo = base
        customGeo["geox-url"] = ["geosite": "https://rules.example.invalid/custom.dat"]
        do { _ = try await prepare(encode(customGeo)); fatalError("missing custom Geo silently substituted") } catch { count += 1 }
        try ConfigurationResources.install(custom, in: dir.appendingPathComponent("custom"))
        try Data(PrototypeConfiguration.prepare(custom).runtimeJSON.utf8).write(to: dir.appendingPathComponent("custom/runtime.json"))
        var directFinal = base; directFinal["rules"] = ["MATCH,DIRECT"]
        do { _ = try await prepare(encode(directFinal)); fatalError("direct fallback accepted") } catch { count += 1 }
        // Nodes-only YAML and URI snapshots must pass through the same overlay and Geo expansion.
        let nodesOnly = try encode(["proxies": base["proxies"]!])
        let nodes = try await prepare(nodesOnly)
        try check(try PrototypeConfiguration.prepare(nodes).ruleCount == 3, "nodes-only template")
        let uri = Data("trojan://synthetic-password@node.example.invalid:443#Example".utf8)
        let links = try await prepare(uri)
        try check(try PrototypeConfiguration.prepare(links).ruleCount == 3, "URI uses shared expansion")
        let uriDir = dir.appendingPathComponent("uri")
        try ConfigurationResources.install(links, in: uriDir)
        try check(FileManager.default.fileExists(atPath: uriDir.appendingPathComponent("GeoSite.dat").path), "URI resources install without YAML-only parse")
        // Structural warnings are deliberately conservative and never expose payloads.
        let cleanAssessment = try RoutingAssessment.inspect(smart)
        try check(!cleanAssessment.preservesDNS, "generated DNS is not reported as source override")
        try check(!cleanAssessment.needsReview, "simple proxy fallback has no override warning")
        let assessed = RoutingAssessment.inspect(root: ["rules": [
            "DOMAIN-SUFFIX,cn,PROXY", "DOMAIN,service.cn,REJECT", "GEOIP,CN,PROXY,no-resolve",
            "GEOSITE,cn,DIRECT", "DOMAIN,private-service.invalid,PROXY",
            "RULE-SET,private-list,PROXY", "AND,((NETWORK,TCP),(DST-PORT,443)),PROXY", "MATCH,PROXY"],
            "dns": ["nameserver": ["9.9.9.9"]]])
        try check(assessed.domesticRuleNumbers == [1, 2, 3], "source indices retained without exposing payloads")
        try check(RoutingAssessment.inspect(root: ["rules": ["PROCESS-NAME,desktop,PROXY", "MATCH,PROXY"]]).otherOverrides == 0, "disabled process rules do not produce routing overrides")
        try check(assessed.domesticOverrides == 3, "domestic override categories including no-resolve")
        try check(assessed.otherOverrides == 1, "unknown destinations explicitly require verification")
        try check(assessed.indirectRules == 2, "rule sets and compound conditions never guessed")
        try check(assessed.preservesDNS, "source DNS override disclosed")
        try check(!assessed.explanations(english: false).joined().contains("private-service") &&
                  !assessed.explanations(english: true).joined().contains("private-list"), "assessment hides rule payloads")
        var nested = base
        var nodesArray = base["proxies"] as! [[String: Any]]
        let firstName = nodesArray[0]["name"] as! String
        var second = nodesArray[0]; second["name"] = "Second"; nodesArray.append(second)
        nested["proxies"] = nodesArray
        nested["proxy-groups"] = [["name": "Outer", "type": "select", "proxies": ["Inner"]],
                                  ["name": "Inner", "type": "select", "proxies": [firstName, "Second", "DIRECT"]]]
        nested["rules"] = ["MATCH,Outer"]
        nested["ipv6"] = false
        let nestedSource = try await prepare(encode(nested))
        let choices = ["Outer": "Inner", "Inner": "Second"]
        let selected = try PrototypeConfiguration.prepare(nestedSource, choices: choices)
        try check(selected.catalog.choices == choices, "nested selections survive smart overlay")
        try check(try RoutingAssessment.inspect(nestedSource).fallbackMayBeDirect, "nested DIRECT member disclosed")
        try check(try (runtime(nestedSource)["dns"] as! [String: Any])["ipv6"] as? Bool == false, "root IPv6 off passed to generated DNS")
        nested["rules"] = ["DOMAIN,new.example.invalid,DIRECT", "MATCH,Outer"]
        let updated = try await prepare(encode(nested), previous: nestedSource)
        let updatedPrepared = try PrototypeConfiguration.prepare(updated, choices: choices)
        try check(updatedPrepared.catalog.choices == choices && updatedPrepared.ruleCount == 4, "refresh retains selected nested node without duplicate domestic rules")
        let otherID = try repo.add(StoredConfiguration(source: nestedSource, choices: choices), fileName: "Nested.yaml", nodeCount: 2, groupCount: 2, ruleCount: 3, makeCurrent: false)
        try repo.activate(otherID)
        try repo.saveChoices(["Outer": "Inner", "Inner": firstName], for: otherID)
        let switched = try repo.record(otherID)
        try check(try ConfigurationRouting.mode(in: switched.source) == .smart && switched.choices["Inner"] == firstName, "node switch preserves per-subscription mode")
        try check(try ConfigurationRouting.mode(in: repo.record(id).source) == .subscription, "another subscription remains unchanged")
        try repo.replace(otherID, expected: switched, source: updated, choices: updatedPrepared.catalog.choices,
                         sourceURL: nil, nodeCount: 2, groupCount: 2, ruleCount: 4)
        let revised = try repo.record(otherID)
        let historical = revised.history!.first!
        try repo.replace(otherID, expected: revised, source: historical.source, choices: historical.choices,
                         sourceURL: nil, nodeCount: 2, groupCount: 2, ruleCount: 3)
        let rolledBack = try repo.record(otherID)
        try check(rolledBack.source == nestedSource && rolledBack.choices == switched.choices, "rollback restores routing snapshot and chosen node together")
        // Remote rule-set snapshot plus Geo overlay; no public downloads.
        var providerRoot = base
        providerRoot["rule-providers"] = ["Domestic": ["type": "http", "behavior": "domain", "format": "yaml", "url": "https://rules.example.invalid/domestic.yaml", "interval": 3600]]
        providerRoot["rules"] = ["RULE-SET,Domestic,DIRECT", originalRules.last!]
        let payload = Data("payload:\n  - '+.example.cn'\n".utf8)
        let providerSnapshot = try ConfigurationResourceStore.stage([("rule:Domestic", payload)], original: encode(providerRoot))
        let providerSmart = try await prepare(encode(providerRoot), previous: providerSnapshot)
        let providerPrepared = try PrototypeConfiguration.prepare(providerSmart)
        try check(providerPrepared.ruleCount == 4, "remote rules preserved before smart fallbacks")
        try check(try ConfigurationSnapshot.read(providerSmart)!.resources.count == 3, "remote rule snapshot retained with bundled Geo")
        let providerAgain = try await prepare(encode(providerRoot), previous: providerSmart)
        try check(providerAgain == providerSmart, "provider refresh keeps identical dependency snapshot")
        let providerOff = try await prepare(encode(providerRoot), mode: .subscription, previous: providerSmart)
        try check(try ConfigurationSnapshot.read(providerOff)!.resources.map(\.key) == ["rule:Domestic"], "disable smart removes only its Geo dependencies")
        var supplied = base
        supplied.removeValue(forKey: "proxies")
        supplied["proxy-providers"] = ["Remote": ["type": "http", "url": "https://nodes.example.invalid/list", "interval": 3600]]
        supplied["proxy-groups"] = [["name": "Imported", "type": "select", "use": ["Remote"]]]
        supplied["rules"] = ["MATCH,Imported"]
        let suppliedRaw = try encode(supplied)
        let suppliedSnapshot = try ConfigurationResourceStore.stage([("proxy:Remote", encode(["proxies": nodesArray]))], original: suppliedRaw)
        let suppliedSmart = try await prepare(suppliedRaw, previous: suppliedSnapshot)
        let suppliedPrepared = try PrototypeConfiguration.prepare(suppliedSmart, choices: ["Imported": "Second"])
        try check(suppliedPrepared.catalog.nodes.count == 2 && suppliedPrepared.catalog.choices["Imported"] == "Second", "remote nodes remain selectable under smart routing")
        try check(try ConfigurationSnapshot.read(suppliedSmart)!.resources.count == 3, "proxy provider snapshot coexists with Geo resources")
        for mode in ["fake-ip", "redir-host"] {
            var dnsRoot = base
            let explicit: [String: Any] = ["enable": true, "enhanced-mode": mode, "ipv6": true,
                "nameserver": ["https://dns.example.invalid/dns-query"],
                "nameserver-policy": ["+.example.cn": ["223.5.5.5"]],
                "direct-nameserver-follow-policy": false]
            dnsRoot["dns"] = explicit
            let value = try await prepare(encode(dnsRoot))
            let decodedDNS = try runtime(value)["dns"] as! [String: Any]
            try check(decodedDNS["enhanced-mode"] as? String == mode && decodedDNS["ipv6"] as? Bool == true, "existing DNS mode and IPv6 retained: " + mode)
            try check(decodedDNS["direct-nameserver-follow-policy"] as? Bool == false, "explicit direct policy switch retained: " + mode)
        }
        var unknown = try JSONSerialization.jsonObject(with: smart.dropFirst(ConfigurationSnapshot.prefix.count)) as! [String: Any]
        unknown["routing"] = "future-version"
        try check((try? ConfigurationSnapshot.read(ConfigurationSnapshot.prefix + encode(unknown))) == nil, "unknown routing version fails closed")
        print("Smart routing: \(count) checks passed; no public network or device Keychain.")
    }
}
