import Foundation
import Testing
@testable import Horizon

@Suite(.serialized) struct OfflineGeoImportTests {
    private func source(dat: Bool = false, geosite: Bool = false) throws -> Data {
        var root = try PrototypeConfiguration.decode(Data(PrototypeSelfCheck.fixture.utf8))
        let last = (root["rules"] as! [String]).last!
        root["rules"] = ["GEOIP,CN,DIRECT"] + (geosite ? ["GEOSITE,cn,DIRECT"] : []) + [last]
        root["geodata-mode"] = dat
        return try JSONSerialization.data(withJSONObject: root)
    }
    @Test func packagedAssetsAllowOfflinePreflight() async throws {
        #expect(await ConfigurationImportWorker.shared.isMainThreadForTest() == false)
        for dat in [false, true] {
            let raw = try source(dat: dat, geosite: dat)
            let snapshot = try await ConfigurationImportWorker.shared.resources(raw, permitsNetwork: false, deadline: .now.advanced(by: .seconds(30)))
            let decoded = try ConfigurationSnapshot.read(snapshot)
            let resources = try #require(decoded).resources
            #expect(resources.count == (dat ? 2 : 1))
            #expect(resources.allSatisfy { $0.bundledVersion != nil })
            let checked = try await ConfigurationImportWorker.shared.validate(snapshot)
            #expect(checked.report.canUse)
            #expect(checked.prepared.adaptations.contains { $0.contains("内置 Geo") })
            #expect(try ConfigurationSnapshot.original(snapshot) == raw)
            let reused = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false, previousSource: snapshot)
            #expect(reused == snapshot)
        }
    }
    @Test func dnsOnlyGeoPreflightUsesPackagedAssets() async throws {
        let fixture = await MainActor.run { PrototypeSelfCheck.fixture }
        for dat in [false, true] {
            var root = try PrototypeConfiguration.decode(Data(fixture.utf8))
            root["geodata-mode"] = dat
            root["dns"] = ["listen": "0.0.0.0:1053", "prefer-h3": false,
                           "nameserver": ["223.5.5.5"], "fallback": ["1.1.1.1"],
                           "default-nameserver": ["1.1.1.1"]] as [String: Any]
            let raw = try JSONSerialization.data(withJSONObject: root)
            let snapshot = try await ConfigurationImportWorker.shared.resources(raw, permitsNetwork: false, deadline: .now.advanced(by: .seconds(30)))
            let checked = try await ConfigurationImportWorker.shared.validate(snapshot)
            #expect(checked.report.canUse)
            let runtime = try JSONSerialization.jsonObject(with: Data(checked.prepared.runtimeJSON.utf8)) as! [String: Any]
            let dns = runtime["dns"] as! [String: Any]
            #expect(dns["listen"] == nil)
            #expect(dns["prefer-h3"] as? Bool == false)
            #expect((dns["fallback-filter"] as? [String: Any])?["geoip-code"] as? String == "CN")
            #expect(try ConfigurationSnapshot.read(snapshot)?.resources.count == 1)
        }
    }
    @Test func customGeoDoesNotSilentlyUseBundledData() async throws {
        var root = try ConfigurationInput.read(source(), resolveResources: false).root
        root["geox-url"] = ["mmdb": "https://private.example.invalid/custom?token=FICTIONAL"]
        let raw = try JSONSerialization.data(withJSONObject: root)
        do {
            _ = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false)
            Issue.record("Custom Geo was silently replaced")
        } catch let issue as ConfigurationIssue {
            #expect(issue.detail.contains("自定义来源"))
            #expect(!issue.detail.contains("FICTIONAL"))
        }
    }
    @Test func explicitGeoUpdateRequiresNetworkAndKeepsOldSnapshot() async throws {
        let raw = try source()
        let snapshot = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false)
        do {
            _ = try await SubscriptionResourceLoader.prepare(raw, permitsNetwork: false, previousSource: snapshot, updateGeo: true)
            Issue.record("Explicit update was silently satisfied by old data")
        } catch is ConfigurationIssue { }
        #expect(try await ConfigurationImportWorker.shared.validate(snapshot).report.canUse)
    }
}

extension ConfigurationImportWorker {
    func isMainThreadForTest() -> Bool { Thread.isMainThread }
}
