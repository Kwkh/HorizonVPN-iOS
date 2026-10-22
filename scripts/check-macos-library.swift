import Foundation
import NetworkExtension

/// Actual Mac worker + native configuration profile. Every record is synthetic and in memory.
@main struct CheckMacLibrary {
    static func main() async throws {
        checkVPNStartup()
        checkUsageMetadata()
        let worker = MacSubscriptionWorker(offline: true)
        try await worker.seedOffline()
        let initial = try await worker.load()
        precondition(initial.index.entries.count == 2 && initial.prepared?.isFixture == true)
        let first = initial.index.entries[0].id
        precondition(initial.usage[first]?.remaining == 70_700_000_000)
        let usageReloaded = await worker.usageSnapshot()
        precondition(usageReloaded[first] == initial.usage[first])
        try await worker.activate(first)
        let activated = try await worker.load()
        precondition(activated.index.activeID == first)
        try await worker.select(group: 0, member: "DIRECT")
        let selected = try await worker.load()
        precondition(selected.prepared?.catalog.choices["Proxy"] == "DIRECT")
        precondition(selected.probeScope == activated.probeScope, "Node selection recreated the grid/probe scope")
        precondition(selected.identity != activated.identity, "Runtime selection identity did not change")
        print("PASS native Mac fixture library, activation and group selection")
        do { _ = try await worker.preview(link: "https://example.invalid/subscription"); fatalError("Offline mode allowed network") }
        catch SubscriptionDownloader.Failure.offline { }
        do { _ = try await worker.requireCertificateConsent(); fatalError("Offline fixture allowed connection") }
        catch PrototypeError.missingConfiguration { }
        print("PASS offline network and connection guards")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
        mode: rule
        proxies:
          - {name: Local test, type: trojan, server: test.example.invalid, port: 443, password: FICTIONAL}
        proxy-groups:
          - {name: Proxy, type: select, proxies: [Local test]}
        rules: ['MATCH,Proxy']
        """.utf8).write(to: url)
        let preview = try await worker.preview(file: url)
        let beforeSave = try await worker.load()
        precondition(beforeSave.index.entries.count == 2, "Preview committed before Save")
        try await worker.save(preview, title: "Synthetic import", makeCurrent: false)
        let saved = try await worker.load()
        precondition(saved.index.entries.count == 3 && saved.index.activeID == first)
        await worker.cancelPreview()
        print("PASS bounded file import, preview isolation and explicit save")
        try Data(repeating: 65, count: PrototypeConfiguration.maximumBytes + 1).write(to: url)
        do { _ = try await worker.preview(file: url); fatalError("Oversize file accepted") }
        catch PrototypeError.invalidFile { }
        let afterReject = try await worker.load()
        precondition(afterReject.index.entries.count == 3)
        print("PASS file size rejection retains previous library")
        try ConfigurationResourceStore.$scopedStorage.withValue(MacMemoryStorage()) {
            try SubscriptionResourceLoader.preflight(preview.prepared)
        }
        precondition(!FileManager.default.fileExists(atPath: ConfigurationResources.directory.path))
        print("PASS native Swift runtime setup and full local preflight; temporary resources removed")
        try await worker.rename(first, title: "Renamed fixture")
        let renamed = try await worker.load()
        precondition(renamed.index.entries.first { $0.id == first }?.title == "Renamed fixture")
        let plan = try await worker.prepareSelection(group: 0, member: "Demo · Personal")
        precondition(plan.before != plan.after)
        try await worker.commitSelection(plan)
        do { try await worker.commitSelection(plan); fatalError("Stale selection was accepted") }
        catch SubscriptionError.staleRevision { }
        print("PASS rename and compare-before-commit selection")
        let record = try await worker.record(first)
        let prepared = try PrototypeConfiguration.prepare(record.source, choices: record.choices)
        let candidate = MacSubscriptionWorker.RevisionPreview(subscriptionID: first, expected: record, prepared: prepared, changes: [])
        try await worker.apply(candidate)
        do { try await worker.apply(candidate); fatalError("Stale revision was accepted") }
        catch SubscriptionError.staleRevision { }
        let updated = try await worker.record(first)
        precondition(updated.revisionNumber == 2 && updated.history?.count == 1)
        let info = try await worker.managementInfo(first)
        precondition(info.revisionNumber == 2 && info.canRefresh && info.history.count == 1)
        precondition(info.history[0].id == updated.history!.first!.id)
        do { _ = try await worker.stageRevision(first, revisionID: UUID()); fatalError("Unknown menu revision accepted") }
        catch SubscriptionError.staleRevision { }
        let rollback = try await worker.stageRevision(first, revisionID: info.history[0].id)
        try await worker.apply(rollback)
        let restored = try await worker.record(first)
        precondition(restored.revisionNumber == 3)
        let usageAfterRollback = await worker.usageSnapshot()
        precondition(usageAfterRollback[first] == initial.usage[first], "Rollback rewound the live account usage")
        print("PASS revision history, stale candidate rejection and offline rollback")
        try await worker.delete(first)
        let deleted = try await worker.load()
        precondition(deleted.index.entries.count == 2 && deleted.index.activeID == nil && deleted.usage[first] == nil)
        for entry in deleted.index.entries { try await worker.delete(entry.id) }
        let empty = try await worker.load()
        precondition(empty.index.entries.isEmpty && empty.prepared == nil)
        print("PASS active and last-subscription deletion")
        try await checkConnectedRefresh()
        try await checkDroppedFile()
        try await checkBackgroundRefresh()
        try await checkDependencyRollback(worker)
        await checkLibraryActivity()
        try await checkSelectionPresentation()
        await checkProbeQueue()
        try await checkSelectionDuringProbes()
        try await checkSmartRouting()
        try await checkCloudSync()
        try await checkConfigurationMultiSelection()
        try await checkMenuBarActions()
        try await checkSubscriptionActivation()
        print("No Keychain, VPN, CloudKit or network request was used.")
    }
    static func checkUsageMetadata() {
        typealias Usage = SubscriptionDownloader.Usage
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = "upload=100; download=200; total=1000"
        let valid = Usage.parse(" UPLOAD = 100 ; Download=200; Total=1000; expire=1900000000; other=ignored", now: now)!
        precondition(valid.used == 300 && valid.remaining == 700 && valid.remainingFraction == 0.7)
        precondition(valid.expiresAt == Date(timeIntervalSince1970: 1_900_000_000) && valid.fetchedAt == now)
        for expiry in ["-1", "null", "", "invalid", "18446744073709551616", "253402300800", "0"] {
            let usage = Usage.parse(quota + "; expire=" + expiry, now: now)!
            precondition(usage.remaining == 700 && usage.expiresAt == nil, "Optional expiry discarded valid quota: \(expiry)")
        }
        let duplicateExpiry = Usage.parse(quota + "; expire=1900000000; expire=1900000001; expire=1900000002")!
        precondition(duplicateExpiry.remaining == 700 && duplicateExpiry.expiresAt == nil)
        for partial in ["total=1000", "upload=100; total=1000", "download=200; total=1000"] {
            let usage = Usage.parse(partial)!
            precondition(usage.total == 1000 && usage.used == nil && usage.remaining == nil && usage.remainingFraction == nil,
                "Incomplete counters invented a remaining allowance")
        }
        let unknownLimit = Usage.parse("upload=100; download=200; total=0")!
        precondition(unknownLimit.used == 300 && unknownLimit.remaining == nil && unknownLimit.remainingFraction == nil)
        precondition(Usage.parse("upload=800; download=300; total=1000")?.remaining == 0)
        let overflow = Usage.parse("upload=18446744073709551615; download=1; total=1000")!
        precondition(overflow.used == UInt64.max && overflow.remaining == 0)
        for invalid in [quota + "; total=1000", "upload=-1; download=0; total=1000", "total=1.5", "total=18446744073709551616", String(repeating: "x", count: 4097)] {
            precondition(Usage.parse(invalid) == nil, "Ambiguous quota was accepted")
        }
        print("PASS provider usage metadata: standard fields, optional expiry sentinels, incomplete counters, zero/over-limit/overflow and ambiguous quota rejection")
    }
    @MainActor static func checkConfigurationMultiSelection() async throws {
        let ids = (0..<6).map { _ in UUID() }
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in
            (id, CGRect(x: (offset % 3) * 110, y: (offset / 3) * 90, width: 100, height: 80))
        })
        var selection = MacConfigurationSelection()
        precondition(selection.click(ids[0], order: ids, toggle: false, range: false))
        precondition(!selection.click(ids[3], order: ids, toggle: true, range: false))
        precondition(selection.ids == Set([ids[0], ids[3]]))
        precondition(!selection.click(ids[3], order: ids, toggle: true, range: false))
        precondition(selection.ids == Set([ids[0]]))
        precondition(!selection.click(ids[5], order: ids, toggle: false, range: true))
        precondition(selection.ids == Set(ids[3...5]))
        selection.beginDrag(extending: false)
        selection.updateDrag(CGRect(x: 5, y: 5, width: 150, height: 100), frames: frames)
        precondition(selection.ids == Set([ids[0], ids[1], ids[3], ids[4]]))
        selection.updateDrag(CGRect(x: 5, y: 5, width: 150, height: 160), frames: frames.filter { [ids[3], ids[4], ids[5]].contains($0.key) })
        precondition(selection.ids == Set([ids[0], ids[1], ids[3], ids[4]]), "Lazy retirement lost earlier selected rows")
        selection.updateDrag(CGRect(x: 5, y: 5, width: 30, height: 30), frames: frames)
        precondition(selection.ids == Set([ids[0]]))
        selection.endDrag(cancelled: true)
        precondition(selection.ids == Set(ids[3...5]) && selection.rectangle == nil)
        selection.beginDrag(extending: true)
        selection.updateDrag(CGRect(x: 5, y: 5, width: 20, height: 20), frames: frames)
        selection.endDrag()
        precondition(selection.ids == Set([ids[0], ids[3], ids[4], ids[5]]))
        selection.context(ids[3])
        precondition(selection.ids.count == 4)
        selection.context(ids[1])
        precondition(selection.ids == Set([ids[1]]))
        selection.selectAll(ids)
        selection.retain(Set(ids.prefix(2)))
        precondition(selection.ids == Set(ids.prefix(2)))
        selection.clear()
        precondition(selection.ids.isEmpty && selection.rectangle == nil)
        print("PASS marquee selection intersects cards, contracts and cancels; modifier clicks never activate; contextual selection and filtering retain valid IDs")
        let library = MacLibraryStore(offline: true, offlineStorage: MacMemoryStorage())
        await library.start()
        let active = library.index.activeID
        let entries = Set(library.index.entries.map(\.id))
        precondition(entries.count == 2)
        let deleted = await library.deleteConfigurations(entries)
        precondition(deleted && library.index.entries.isEmpty && library.index.activeID == nil && library.prepared == nil)
        precondition(library.vpn.isIdle && active != nil)
        print("PASS bulk configuration deletion clears active and last entries without starting VPN")
    }
    static func checkSmartRouting() async throws {
        let geo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Horizon/Resources/GeoData")
        let source = Data("""
        mode: rule
        proxies:
          - {name: A, type: trojan, server: a.example.invalid, port: 443, password: FICTIONAL, skip-cert-verify: true}
          - {name: B, type: trojan, server: b.example.invalid, port: 443, password: FICTIONAL}
        proxy-groups:
          - {name: Proxy, type: select, proxies: [A, B, DIRECT]}
        dns:
          enable: true
          nameserver: ['https://1.1.1.1/dns-query']
          nameserver-policy: {'+.example.com': 'https://8.8.8.8/dns-query'}
        rules: ['DOMAIN,exception.example.com,Proxy', 'DOMAIN,blocked.example.com,REJECT', 'MATCH,Proxy']
        """.utf8)
        let storage = MacMemoryStorage()
        let repository = SubscriptionRepository(storage: storage)
        let worker = MacSubscriptionWorker(offline: true, offlineStorage: storage)
        let originalPrepared = try PrototypeConfiguration.prepare(source)
        var original = StoredConfiguration(source: source, choices: ["Proxy": "B"])
        original.sourceURL = "https://subscription.example.invalid/never-fetch"
        let id = try repository.add(original, fileName: nil, displayTitle: "Routing fixture", nodeCount: 2, groupCount: 1, ruleCount: 3, makeCurrent: true)
        original = try repository.record(id)
        try repository.approveInsecureCertificates(id, expectedDigest: original.contentDigest)
        original = try repository.record(id)
        let plan = try await worker.stageRouting(.smart, bundledDirectory: geo)
        let unchanged = try await worker.record(id)
        precondition(unchanged.source == source && unchanged.revisionID == original.revisionID, "Preparation mutated saved configuration")
        let preservedOriginal = try ConfigurationSnapshot.original(plan.revision.prepared.source)
        precondition(preservedOriginal == source)
        let root = try ConfigurationInput.read(plan.revision.prepared.source, resolveResources: false).root
        precondition(root["rules"] as? [String] == ["DOMAIN,exception.example.com,Proxy", "DOMAIN,blocked.example.com,REJECT", "GEOSITE,cn,DIRECT", "GEOIP,CN,DIRECT", "MATCH,Proxy"])
        let dns = root["dns"] as! [String: Any]
        precondition(dns["nameserver"] as? [String] == ["https://1.1.1.1/dns-query"])
        precondition((dns["nameserver-policy"] as? [String: Any])?["+.example.com"] as? String == "https://8.8.8.8/dns-query")
        precondition(dns["direct-nameserver"] != nil && plan.revision.prepared.catalog.choices["Proxy"] == "B")
        try ConfigurationResourceStore.$scopedStorage.withValue(storage) {
            try SubscriptionResourceLoader.preflight(plan.revision.prepared)
        }
        let committed = try await worker.commitRouting(plan)
        precondition(committed.sourceURL == original.sourceURL && committed.certificateConsentDigest == nil)
        precondition(committed.history?.first?.source == source)
        let smart = try await worker.load()
        precondition(smart.routing == .smart)
        let restarted = MacSubscriptionWorker(offline: true, offlineStorage: storage)
        let reloaded = try await restarted.load()
        precondition(reloaded.routing == .smart && reloaded.identity == smart.identity)
        print("PASS Smart Routing: original rule/DNS priority, local Geo preflight, original YAML/choices/URL retained, version history and reload; certificate consent is not bypassed")

        try await worker.rollbackRouting(plan, committed: committed)
        let approvedRestored = try await worker.record(id)
        precondition(approvedRestored.certificateConsentDigest == original.contentDigest)
        try approvedRestored.requireCertificateConsent(for: originalPrepared)
        let enabledAgain = try await worker.stageRouting(.smart, bundledDirectory: geo)
        _ = try await worker.commitRouting(enabledAgain)

        let back = try await worker.stageRouting(.subscription, bundledDirectory: geo)
        _ = try await worker.commitRouting(back)
        let subscription = try await worker.load()
        precondition(subscription.routing == .subscription && subscription.prepared?.source == source && subscription.prepared?.ruleCount == originalPrepared.ruleCount)
        let stale = try await worker.stageRouting(.smart, bundledDirectory: geo)
        try await worker.select(group: 0, member: "A")
        do { _ = try await worker.commitRouting(stale); fatalError("Routing candidate overwrote newer node choice") }
        catch SubscriptionError.staleRevision { }
        await worker.cancelPreview()
        print("PASS Smart Routing: opt-out restores exact YAML, stale selection rejected without changing source")

        let rollbackPlan = try await worker.stageRouting(.smart, bundledDirectory: geo)
        let rollbackCommit = try await worker.commitRouting(rollbackPlan)
        try await worker.rollbackRouting(rollbackPlan, committed: rollbackCommit)
        let restored = try await worker.record(id)
        precondition(restored.source == rollbackPlan.revision.expected.source && restored.choices == rollbackPlan.revision.expected.choices)
        let failedPlan = try await worker.stageRouting(.smart, bundledDirectory: geo)
        let failedCommit = try await worker.commitRouting(failedPlan)
        try await worker.select(group: 0, member: "B")
        do { try await worker.rollbackRouting(failedPlan, committed: failedCommit); fatalError("Rollback overwrote a newer writer") }
        catch SubscriptionError.staleRevision { }
        print("PASS Smart Routing: failed startup rollback retains prior configuration; rollback CAS protects newer writes")

        let reset = try await worker.stageRouting(.subscription, bundledDirectory: geo)
        _ = try await worker.commitRouting(reset)
        let beforeRunning = try await worker.load()
        try await worker.pinRunning(identity: beforeRunning.identity)
        let choice = try await worker.prepareSelection(group: 0, member: "A", useRunning: true)
        try await worker.commitSelection(choice)
        let saved = try await worker.record(id)
        let newerSource = Data(String(decoding: source, as: UTF8.self).replacingOccurrences(of: "FICTIONAL", with: "FICTIONAL-UPDATED").utf8)
        let newerPrepared = try PrototypeConfiguration.prepare(newerSource, choices: saved.choices)
        try await worker.apply(.init(subscriptionID: id, expected: saved, prepared: newerPrepared, changes: []))
        let runningPlan = try await worker.stageRouting(.smart, useRunning: true, bundledDirectory: geo)
        let preservedLatest = try ConfigurationSnapshot.original(runningPlan.revision.prepared.source)
        precondition(preservedLatest == newerSource)
        precondition(runningPlan.revision.prepared.catalog.choices["Proxy"] == "A")
        let stillRunning = try await worker.load(useRunning: true)
        precondition(stillRunning.routing == .subscription && stillRunning.identity == choice.after)
        _ = try await worker.commitRouting(runningPlan)
        try await worker.releaseRunning()
        let next = try await worker.load()
        precondition(next.routing == .smart && next.prepared?.catalog.choices["Proxy"] == "A")
        print("PASS Smart Routing: connected preparation leaves running snapshot intact, uses latest saved refresh and retains running manual selection")

        let noMatch = Data(String(decoding: newerSource, as: UTF8.self).replacingOccurrences(of: "MATCH,Proxy", with: "MATCH,DIRECT").utf8)
        let nextStored = try await worker.record(id)
        let invalidForSmart = try PrototypeConfiguration.prepare(noMatch)
        try await worker.apply(.init(subscriptionID: id, expected: nextStored, prepared: invalidForSmart, changes: []))
        let beforeReject = try await worker.record(id)
        do { _ = try await worker.stageRouting(.smart, bundledDirectory: geo); fatalError("Unsupported final target accepted") }
        catch is ConfigurationIssue { }
        let afterReject = try await worker.record(id)
        precondition(afterReject.revisionID == beforeReject.revisionID && afterReject.source == beforeReject.source)
        await worker.cancelPreview()
        print("PASS Smart Routing: incompatible final DIRECT rule fails before commit")
    }
    static func checkVPNStartup() {
        var immediateFailure = MacVPNStartup()
        precondition(immediateFailure.observe(.disconnected, elapsed: .zero) == .waiting)
        precondition(immediateFailure.observe(.disconnected, elapsed: .milliseconds(999)) == .waiting)
        precondition(immediateFailure.observe(.disconnected, elapsed: .seconds(1)) == .failed)
        var asyncFailure = MacVPNStartup()
        precondition(asyncFailure.observe(.connecting, elapsed: .milliseconds(100)) == .waiting)
        precondition(asyncFailure.observe(.disconnected, elapsed: .milliseconds(200)) == .failed)
        var successful = MacVPNStartup()
        precondition(successful.observe(.connecting, elapsed: .seconds(2)) == .waiting)
        precondition(successful.observe(.connected, elapsed: .seconds(3)) == .connected)
        var stalled = MacVPNStartup()
        precondition(stalled.observe(.connecting, elapsed: .seconds(30)) == .timedOut)
        var stopping = MacVPNStartup()
        precondition(stopping.observe(.disconnecting, elapsed: .milliseconds(100)) == .failed)
        let plugin = NSError(domain: NEVPNConnectionErrorDomain, code: NEVPNConnectionError.pluginFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "SECRET-CONFIGURATION"])
        guard case .extensionStart = MacVPNFailure.classify(plugin) else { fatalError("Lost extension startup failure") }
        let provider = PrototypeError.physicalNetwork.tunnelError
        guard case .provider(.physicalNetwork) = MacVPNFailure.classify(provider) else { fatalError("Lost provider failure") }
        precondition(!MacText.error(MacVPNFailure.classify(plugin)).contains("SECRET-CONFIGURATION"))
        print("PASS Mac VPN startup: immediate/async failures, connected, stopping, deadline and safe error classification")
    }
    static func checkDroppedFile() async throws {
        let worker = MacSubscriptionWorker(offline: true)
        try await worker.seedOffline()
        let before = try await worker.load()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
        proxies: [{name: Dropped, type: trojan, server: dropped.example.invalid, port: 443, password: FICTIONAL}]
        proxy-groups: [{name: Proxy, type: select, proxies: [Dropped]}]
        rules: ['MATCH,Proxy']
        """.utf8).write(to: url)
        try await worker.importDroppedFile(url, makeCurrent: false)
        let imported = try await worker.load()
        precondition(imported.index.entries.count == before.index.entries.count + 1 && imported.index.activeID == before.index.activeID)
        try Data("definitely not a Clash configuration".utf8).write(to: url)
        do { try await worker.importDroppedFile(url, makeCurrent: false); fatalError("Invalid drop committed") } catch { }
        let rejected = try await worker.load()
        precondition(rejected.index.entries.count == imported.index.entries.count && rejected.identity == imported.identity)
        print("PASS dropped files validate and save directly; invalid drops and existing selection remain untouched")
    }
    @MainActor static func checkConnectedRefresh() async throws {
        let storage = MacMemoryStorage()
        let worker = MacSubscriptionWorker(offline: true, offlineStorage: storage)
        let source = Data("""
        mode: rule
        proxy-providers:
          Demo:
            type: http
            url: https://provider.example.invalid/nodes.yaml
            path: ./providers/demo.yaml
            interval: 3600
        proxy-groups:
          - {name: Proxy, type: select, use: [Demo], proxies: [DIRECT]}
        rules: ['MATCH,Proxy']
        """.utf8)
        let request = try ConfigurationResources.plan(ConfigurationInput.read(source, resolveResources: false).root).first!
        func candidate(_ number: Int) throws -> PrototypeConfiguration.Prepared {
            let body = Data("proxies: [{name: Node-\(number), type: trojan, server: snapshot.example.invalid, port: 443, password: FICTIONAL-\(number)}]".utf8)
            return try PrototypeConfiguration.prepare(ConfigurationResourceStore.stage([(request.key, body)], original: source))
        }
        let original = try candidate(0)
        let preview = MacSubscriptionWorker.Preview(prepared: original, fileName: nil, sourceURL: nil, title: "Running snapshot")
        try await worker.save(preview, title: preview.title, makeCurrent: true)
        let initial = try await worker.load()
        let id = initial.index.activeID!, session = UUID()
        try await worker.pinRunning(identity: initial.identity, sessionID: session)
        for number in 1...12 {
            let expected = try await worker.record(id)
            let updated = try candidate(number)
            try await worker.applyRefresh(.init(subscriptionID: id, expected: expected, prepared: updated, changes: []))
        }
        await worker.cancelPreview()
        let running = try await worker.load(useRunning: true)
        let next = try await worker.load()
        precondition(running.identity == initial.identity && running.prepared?.runtimeJSON == original.runtimeJSON && running.probeScope == initial.probeScope)
        precondition(next.identity != running.identity && next.prepared?.catalog.nodes.first?.name == "Node-12")
        let record = try await worker.record(id)
        precondition(record.history?.contains(where: { $0.source == original.source }) == false, "Fixture did not exercise resource history eviction")
        // The extension uses the ordinary shared storage, not the worker's context.
        let extensionPrepared = try ConfigurationResourceStore.$scopedStorage.withValue(storage) {
            try PrototypeConfiguration.prepare(original.source, choices: original.catalog.choices)
        }
        precondition(extensionPrepared.runtimeJSON == original.runtimeJSON)
        let nodes = try await worker.probeNodes(useRunning: true)
        precondition(nodes.count == 1 && nodes[0].contains("Node-0") && !nodes[0].contains("Node-12"))
        let restarted = MacSubscriptionWorker(offline: true, offlineStorage: storage)
        try await restarted.pinRunning(identity: initial.identity, sessionID: session)
        let resumed = try await restarted.load(useRunning: true)
        precondition(resumed.identity == initial.identity)
        do { try await restarted.pinRunning(identity: initial.identity, sessionID: UUID()); fatalError("Wrong session reused old runtime snapshot") }
        catch SubscriptionError.staleRevision { }
        print("PASS connected refresh preserves source, probe indexes and resources across history eviction and app restart; session mismatch rejected")
        let gate = HeldProbeCounter()
        let probes = MacProbeStore { await gate.run($0) }
        probes.bind(running.probeScope); probes.start(indices: [0], nodes: ["0"])
        for _ in 0..<200 {
            if await gate.startedCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let startedProbeCount = await gate.startedCount
        precondition(startedProbeCount == 1)
        let plan = try await restarted.prepareSelection(group: 0, member: "Node-0", useRunning: true)
        try await restarted.commitSelection(plan)
        let selected = try await restarted.load(useRunning: true)
        precondition(selected.identity == plan.after && selected.prepared?.catalog.choices["Proxy"] == "Node-0")
        probes.bind(selected.probeScope)
        precondition(probes.running && probes.targetCount == 1 && probes.isTesting(0), "Running snapshot selection cancelled its probe")
        await gate.releaseAll()
        for _ in 0..<200 {
            if !probes.running { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(probes.completedCount == 1 && probes.results[0]?.state == .success)
        do { try await restarted.commitSelection(plan); fatalError("Stale running selection accepted") }
        catch SubscriptionError.staleRevision { }
        try await restarted.releaseRunning()
        let disconnected = try await restarted.load(useRunning: true)
        precondition(disconnected.prepared?.catalog.nodes.first?.name == "Node-12")
        precondition(disconnected.prepared?.catalog.choices["Proxy"] != "Node-0", "Removed node leaked into next connection")
        precondition(storage.keys().contains(where: { $0.hasPrefix("mac-running-") }) == false)
        print("PASS running selection remains independent of pending updates; disconnect activates saved version and releases its resource retention root")
    }
    static func checkBackgroundRefresh() async throws {
        let worker = MacSubscriptionWorker(offline: true)
        try await worker.seedOffline()
        let initial = try await worker.load()
        let id = initial.index.entries[0].id
        let stored = try await worker.record(id)
        let prepared = try PrototypeConfiguration.prepare(stored.source, choices: stored.choices)
        let unchanged = MacSubscriptionWorker.RevisionPreview(subscriptionID: id, expected: stored, prepared: prepared, changes: [])
        try await worker.applyRefresh(unchanged)
        let same = try await worker.record(id)
        precondition(same.revisionID == stored.revisionID && same.revisionNumber == stored.revisionNumber && same.history?.count == stored.history?.count)
        let changedSource = Data(String(decoding: stored.source, as: UTF8.self).replacingOccurrences(of: "DEMO-ONLY", with: "FICTIONAL-UPDATED").utf8)
        let changed = try PrototypeConfiguration.prepare(changedSource, choices: stored.choices)
        let candidate = MacSubscriptionWorker.RevisionPreview(subscriptionID: id, expected: stored, prepared: changed, changes: [])
        try await worker.applyRefresh(candidate)
        let updated = try await worker.record(id)
        let snapshot = try await worker.load()
        precondition(updated.source == changedSource && updated.history?.first?.source == stored.source)
        precondition(snapshot.index.activeID == initial.index.activeID && snapshot.usage == initial.usage)
        do { try await worker.applyRefresh(unchanged); fatalError("Stale unchanged refresh accepted") }
        catch SubscriptionError.staleRevision { }
        do { try await worker.applyRefresh(candidate); fatalError("Stale changed refresh accepted") }
        catch SubscriptionError.staleRevision { }
        print("PASS background refresh: unchanged content creates no revision; changed content retains rollback; stale candidates rejected; selection and usage retained")
    }
    static func checkDependencyRollback(_ worker: MacSubscriptionWorker) async throws {
        let source = Data("""
        mode: rule
        proxy-providers:
          Demo:
            type: http
            url: https://provider.example.invalid/nodes.yaml
            path: ./providers/demo.yaml
            interval: 3600
        proxy-groups:
          - {name: Proxy, type: select, use: [Demo]}
        rules: ['MATCH,Proxy']
        """.utf8)
        let request = try ConfigurationResources.plan(ConfigurationInput.read(source, resolveResources: false).root).first!
        func candidate(_ password: String) throws -> PrototypeConfiguration.Prepared {
            let body = Data("proxies: [{name: Snapshot, type: trojan, server: snapshot.example.invalid, port: 443, password: \(password)}]".utf8)
            let staged = try ConfigurationResourceStore.stage([(request.key, body)], original: source)
            return try PrototypeConfiguration.prepare(staged)
        }
        let first = try candidate("FICTIONAL-A")
        let preview = MacSubscriptionWorker.Preview(prepared: first, fileName: nil, sourceURL: nil, title: "Snapshot fixture")
        try await worker.save(preview, title: preview.title, makeCurrent: true)
        let id = try await worker.load().index.activeID!
        let expected = try await worker.record(id)
        let second = try candidate("FICTIONAL-B")
        try await worker.apply(.init(subscriptionID: id, expected: expected, prepared: second, changes: []))
        await worker.cancelPreview() // Force rollback to use persisted version-specific resources.
        let updated = try await worker.record(id)
        let rollback = try await worker.stageRevision(id, revision: updated.history!.first!)
        precondition(rollback.prepared.source == first.source)
        try await worker.apply(rollback)
        let result = try await worker.load()
        precondition(result.prepared?.runtimeJSON == first.runtimeJSON)
        let geo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Horizon/Resources/GeoData")
        let smart = try await worker.stageRouting(.smart, bundledDirectory: geo)
        let smartSnapshot = try ConfigurationSnapshot.read(smart.revision.prepared.source)!
        let firstSnapshot = try ConfigurationSnapshot.read(first.source)!
        precondition(smartSnapshot.resources.first { $0.key == request.key }?.digest == firstSnapshot.resources.first { $0.key == request.key }?.digest)
        _ = try await worker.commitRouting(smart)
        let plain = try await worker.stageRouting(.subscription, bundledDirectory: geo)
        _ = try await worker.commitRouting(plain)
        let plainResult = try await worker.load()
        precondition(plainResult.prepared?.runtimeJSON == first.runtimeJSON)
        try await worker.delete(id)
        print("PASS provider dependency rollback and Smart Routing reuse the corresponding cached version without network")
    }
    @MainActor static func checkLibraryActivity() async {
        let activity = MacLibraryActivity()
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let first = Task {
            await activity.run(showsActivity: false) {
                precondition(!activity.busy)
                events.append("refresh-start")
                await withCheckedContinuation { release = $0 }
                precondition(!activity.busy, "Background refresh dimmed unrelated controls")
                events.append("refresh-end")
                return true
            }
        }
        while release == nil { await Task.yield() }
        precondition(!activity.busy)
        let action = Task {
            events.append("action-request")
            return await activity.run(showsActivity: true) {
                precondition(activity.busy)
                events.append("action")
                return true
            }
        }
        while !events.contains("action-request") { await Task.yield() }
        let second = Task {
            events.append("second-request")
            return await activity.run(showsActivity: false) {
                precondition(!activity.busy)
                events.append("second")
                return true
            }
        }
        while !events.contains("second-request") { await Task.yield() }
        let cancelled = Task {
            events.append("cancel-request")
            return await activity.run(showsActivity: true) {
                fatalError("Cancelled queued action executed")
            }
        }
        while !events.contains("cancel-request") { await Task.yield() }
        cancelled.cancel()
        precondition(!activity.busy && !events.contains("action"))
        release?.resume()
        let results = await (first.value, action.value, second.value, cancelled.value)
        precondition(results.0 && results.1 && results.2 && !results.3 && !activity.busy)
        precondition(events.filter { ["refresh-start", "refresh-end", "action", "second"].contains($0) } == ["refresh-start", "refresh-end", "action", "second"])
        print("PASS background refresh keeps global loading false; queued actions execute serially in order; cancellation releases the queue")
    }
    @MainActor static func checkSelectionPresentation() async throws {
        let library = MacLibraryStore(offline: true)
        await library.start()
        let group = library.prepared!.catalog.groups.first!
        let original = library.prepared!.catalog.choices[group.name]!
        precondition(library.pendingSelection == nil)
        await library.select(group: group.id, member: original)
        precondition(library.pendingSelection == nil, "Current member showed a pending selection")

        let gate = SelectionPresentationGate()
        let background = Task {
            try await library.performCloudReview(localID: nil) { await gate.hold() }
        }
        while !(await gate.entered) { await Task.yield() }
        let selecting = Task { await library.select(group: group.id, member: "DIRECT") }
        while library.pendingSelection == nil { await Task.yield() }
        precondition(library.isSelecting(group: group.id, member: "DIRECT") && !library.busy,
                     "Queued selection did not identify its target")
        precondition(!library.isSelecting(group: group.id + 1, member: "DIRECT") &&
                     !library.isSelecting(group: group.id, member: original), "Unrelated members showed loading")
        await library.select(group: group.id, member: "DIRECT")
        precondition(library.isSelecting(group: group.id, member: "DIRECT"))
        await gate.release()
        try await background.value
        await selecting.value
        precondition(library.error == nil && library.pendingSelection == nil &&
                     library.prepared?.catalog.choices[group.name] == "DIRECT")

        await library.select(group: group.id, member: "MISSING-MEMBER")
        precondition(library.error != nil && library.pendingSelection == nil &&
                     library.prepared?.catalog.choices[group.name] == "DIRECT", "Failed selection retained loading or changed the member")
        library.error = nil

        let cancellationGate = SelectionPresentationGate()
        let blocker = Task {
            try await library.performCloudReview(localID: nil) { await cancellationGate.hold() }
        }
        while !(await cancellationGate.entered) { await Task.yield() }
        let cancelled = Task { await library.select(group: group.id, member: original) }
        while library.pendingSelection == nil { await Task.yield() }
        cancelled.cancel()
        await cancellationGate.release()
        try await blocker.value
        await cancelled.value
        precondition(library.error == nil && library.pendingSelection == nil &&
                     library.prepared?.catalog.choices[group.name] == "DIRECT", "Cancelled selection retained loading or committed")
        print("PASS selection loading identifies only the pending target while queued; duplicate requests, no-op, commit, error and cancellation clear correctly")
    }
    @MainActor static func checkProbeQueue() async {
        let counter = ProbeCounter()
        let probes = MacProbeStore { value in await counter.run(value) }
        let nodes = (0..<13).map(String.init)
        probes.bind("A"); probes.start(indices: [0], nodes: nodes)
        probes.start(indices: Array(1..<13), nodes: nodes)
        while probes.running { try? await Task.sleep(for: .milliseconds(10)) }
        precondition(probes.completedCount == 13 && probes.targetCount == 13)
        let maximum = await counter.maximum
        precondition(maximum <= 5)
        precondition(probes.results.count == 13)
        probes.bind("A")
        precondition(probes.results.count == 13 && probes.targetCount == 13,
            "Reloading unchanged source cleared visible latency results")
        probes.start(indices: [0], nodes: nodes)
        while probes.running { try? await Task.sleep(for: .milliseconds(10)) }
        precondition(probes.completedCount == 1 && probes.targetCount == 1)
        probes.start(indices: Array(0..<13), nodes: nodes)
        probes.bind("B")
        try? await Task.sleep(for: .milliseconds(100))
        precondition(probes.results.isEmpty && !probes.running && probes.targetCount == 0)
        print("PASS five concurrent probes, incremental enqueue, individual rerun and stale completion isolation")
    }
    @MainActor static func checkSelectionDuringProbes() async throws {
        let gate = HeldProbeCounter()
        let probes = MacProbeStore { await gate.run($0) }
        let library = MacLibraryStore(offline: true, probes: probes)
        await library.start()
        let original = library.index.activeID!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        let names = (0..<13).map { "Node-\($0)" }
        let source = "proxies:\n" + names.map {
            "  - {name: \($0), type: trojan, server: probe.example.invalid, port: 443, password: SYNTHETIC}\n"
        }.joined() + "proxy-groups: [{name: SELECT, type: select, proxies: [\(names.joined(separator: ","))]}]\nrules: ['MATCH,SELECT']\n"
        try Data(source.utf8).write(to: url)
        await library.importDroppedFile(url)
        guard let added = library.index.entries.first(where: { $0.title == url.deletingPathExtension().lastPathComponent }) else { fatalError("Fixture import failed") }
        await library.activate(added.id)
        precondition(library.error == nil && library.prepared?.catalog.nodes.count == 13)
        let scope = library.probeScope, identity = library.identity
        probes.start(indices: Array(0..<13), nodes: (0..<13).map(String.init))
        for _ in 0..<200 {
            if await gate.startedCount == 5 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await gate.complete("0")
        for _ in 0..<200 {
            if probes.completedCount == 1, await gate.startedCount == 6 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(probes.completedCount == 1 && probes.running && probes.targetCount == 13)
        let completedAt = probes.results[0]?.testedAt
        precondition(completedAt != nil)
        await library.select(group: 0, member: "Node-6")
        precondition(library.error == nil && library.prepared?.catalog.choices["SELECT"] == "Node-6")
        precondition(library.identity != identity && library.probeScope == scope)
        precondition(probes.running && probes.completedCount == 1 && probes.targetCount == 13)
        precondition(probes.results[0]?.testedAt == completedAt && probes.results[6]?.state == .waiting)
        precondition(library.prepared?.catalog.nodes.map(\.name) == names, "Selection changed grid identities/order")
        await library.select(group: 0, member: "Node-0")
        precondition(probes.running && probes.results[0]?.testedAt == completedAt)
        await gate.releaseAll()
        for _ in 0..<200 {
            if !probes.running { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(probes.completedCount == 13 && probes.targetCount == 13 && probes.results.count == 13)
        precondition(probes.results[0]?.testedAt == completedAt)
        let maximum = await gate.maximum, started = await gate.startedCount
        precondition(maximum == 5 && started == 13, "Selection restarted probes or exceeded five slots")
        await library.activate(original)
        precondition(probes.results.isEmpty && probes.targetCount == 0 && !probes.running)
        print("PASS actual Mac library selection during five-slot batch: completed/in-flight/queued work retained, no restart, stable node order; subscription switch clears results")
    }
}
actor SelectionPresentationGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async {
        await withCheckedContinuation { continuation = $0; entered = true }
    }
    func release() { continuation?.resume(); continuation = nil }
}
actor HeldProbeCounter {
    private var pending: [String: CheckedContinuation<Int32, Never>] = [:]
    private var released = false
    private(set) var maximum = 0
    private(set) var startedCount = 0
    func run(_ value: String) async -> Int32 {
        startedCount += 1
        if released { return Int32(value)! + 20 }
        return await withCheckedContinuation { continuation in
            pending[value] = continuation; maximum = max(maximum, pending.count)
        }
    }
    func complete(_ value: String) { pending.removeValue(forKey: value)?.resume(returning: Int32(value)! + 20) }
    func releaseAll() {
        released = true
        for value in Array(pending.keys) { complete(value) }
    }
}
actor ProbeCounter {
    var active = 0
    var maximum = 0
    func run(_ value: String) async -> Int32 {
        active += 1; maximum = max(maximum, active)
        try? await Task.sleep(for: .milliseconds(35))
        active -= 1
        return Int32(value)! + 20
    }
}


extension CheckMacLibrary {
    @MainActor static func checkSubscriptionActivation() async throws {
        enum Failure: Error { case expected }
        // Every stage uses a fake closure: these tests cannot change a VPN.
        for failingStage in 0...4 {
            var stages: [Int] = []
            func stage(_ n: Int) throws { stages.append(n); if n == failingStage { throw Failure.expected } }
            do {
                try await MacSubscriptionActivationFlow.run(validate: { try stage(1) }, disconnect: { try stage(2) },
                    commit: { try stage(3) }, reconnect: { try stage(4) })
                precondition(failingStage == 0)
            } catch Failure.expected { precondition(failingStage != 0) }
            precondition(stages == Array(1...(failingStage == 0 ? 4 : failingStage)))
        }
        print("PASS subscription switching validates before stop, commits only after stop, and fails closed at every stage")
        let worker = MacSubscriptionWorker(offline: true)
        try await worker.seedOffline()
        let before = try await worker.load()
        try await worker.validateActivation(before.index.entries[0].id)
        let validated = try await worker.load()
        precondition(validated.index.activeID == before.index.activeID)
        do { try await worker.validateActivation(UUID()); fatalError("Missing target accepted") } catch { }
        print("PASS activation prevalidation is read-only and rejects deleted targets")
        let library = MacLibraryStore(offline: true, offlineStorage: MacMemoryStorage())
        await library.start()
        let oldID = library.index.activeID
        let target = library.index.entries.first { $0.id != oldID }!
        library.subscriptionSwitch = target
        let actions = MacMenuBarActions(library: library)
        precondition(!library.canActivateSubscription && !actions.canActivate && !actions.canSelect)
        await library.activate(target.id)
        precondition(library.index.activeID == oldID && library.vpn.isIdle)
        library.subscriptionSwitch = nil // Cancel has no side effects.
        precondition(library.index.activeID == oldID)
        await library.activate(target.id)
        precondition(library.index.activeID == target.id && library.vpn.isIdle && library.error == nil)
        print("PASS pending switch blocks duplicate actions; cancelling preserves selection; idle activation never starts VPN")
    }
}
