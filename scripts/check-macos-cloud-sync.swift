import Foundation
import CloudKit

/// In-memory coordinator, never constructs CKContainer or sends a network request.
actor MacCloudClientFixture: MacCloudSyncClient {
    var connects = 0
    var sends = 0
    var stops = 0
    var inventories = 0
    var cancelledSends = 0
    private var holdSend = false
    private var sendGate: CheckedContinuation<Void, Never>?
    var changed = false
    private var metadataRecovery: (@Sendable () async throws -> Void)?
    func connect(allowAccountChange: Bool) async -> CloudSyncSnapshot {
        connects += 1
        return .init(status: .ready, lastSync: Date())
    }
    func tick(sendNow: Bool) async -> CloudSyncSnapshot {
        if sendNow {
            sends += 1
            if holdSend {
                holdSend = false
                await withCheckedContinuation { sendGate = $0 }
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        if sendNow, Task.isCancelled { cancelledSends += 1 }
        let commit = changed; changed = false
        return .init(status: .ready, lastSync: Date(), libraryChanged: commit)
    }
    func reconcileCloudLibrary() async -> CloudSyncSnapshot {
        inventories += 1
        if let recovery = metadataRecovery {
            metadataRecovery = nil
            do { try await recovery() } catch { fatalError("Synthetic metadata recovery failed: \(error)") }
            return .init(status: .ready, lastSync: Date(), libraryChanged: true)
        }
        return .init(status: .ready, lastSync: Date())
    }
    func stageMetadataRecovery(_ recovery: @escaping @Sendable () async throws -> Void) {
        metadataRecovery = recovery
    }
    func holdNextSend() { holdSend = true }
    func releaseSend() { let gate = sendGate; sendGate = nil; gate?.resume() }
    func reportCommit() { changed = true }
    func stop() async { stops += 1 }
    func snapshot() -> CloudSyncSnapshot { .init(status: .ready, lastSync: Date()) }
    func resolve(_ id: UUID, expectedVersion: UUID, resolution: SubscriptionCloudSyncEngine.Resolution) async throws { }
}

/// Deterministically advance the configuration-page clock without waiting five
/// wall-clock seconds or constructing a CloudKit client.
actor MacCloudPageWaitFixture {
    private var pending: (UUID, CheckedContinuation<Void, Error>)?
    private(set) var delays: [Duration] = []
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                precondition(pending == nil)
                delays.append(duration)
                pending = (id, continuation)
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func resume() { let next = pending; pending = nil; next?.1.resume() }
    private func cancel(_ id: UUID) {
        guard pending?.0 == id else { return }
        let next = pending; pending = nil; next?.1.resume(throwing: CancellationError())
    }
}

actor MacCloudInventoryFixture {
    var pages: [MacCloudSubscriptionInventory.Page]
    var calls = 0
    init(_ pages: [MacCloudSubscriptionInventory.Page]) { self.pages = pages }
    func next() throws -> MacCloudSubscriptionInventory.Page {
        calls += 1
        guard !pages.isEmpty else { throw CloudSyncFailure.unavailable }
        return pages.removeFirst()
    }
}

extension CheckMacLibrary {
    @MainActor static func checkCloudSync() async throws {
        let storage = MacMemoryStorage()
        let library = MacLibraryStore(offline: true, offlineStorage: storage)
        await library.start()
        precondition(library.ready)
        let repository = library.cloudRepository
        let initialID = library.index.activeID!
        let initialScope = library.probeScope, initialIdentity = library.identity
        let initialRecord = try repository.record(initialID)
        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cache = try CloudAssetCache(account: "SYNTHETIC", root: cacheRoot)
        let importer = ConfigurationImportWorker.shared
        let exported = try await importer.exportCloud(initialID, repository: repository, cache: cache)
        precondition(exported.sourceURL == initialRecord.sourceURL && exported.resources.isEmpty)
        let destinationStorage = MacMemoryStorage()
        let destination = SubscriptionRepository(storage: destinationStorage)
        _ = try await importer.installCloud(exported, localID: exported.id, expectedMutation: nil,
            allowCurrent: false, repository: destination, cache: cache)
        let restored = try destination.record(exported.id)
        precondition(restored.source == initialRecord.source && restored.sourceURL == initialRecord.sourceURL)
        precondition(restored.certificateConsentDigest == nil && restored.history == nil)
        try requireCloud(destination.index()?.activeID == nil)
        print("PASS Mac cloud payload round trip, private URL retained, selection and approvals stay local")

        var incoming = exported
        incoming.title = "Cloud update"
        let mutation = try repository.index()?.syncMutations?[initialID.uuidString]
        do {
            _ = try await importer.installCloud(incoming, localID: initialID, expectedMutation: mutation,
                allowCurrent: false, repository: repository, cache: cache)
            fatalError("Automatic cloud update replaced selected subscription")
        } catch SubscriptionError.staleRevision { }
        var deleted = incoming
        deleted.deleted = true; deleted.originalDigest = nil; deleted.originalBytes = 0; deleted.sourceURL = nil
        do {
            _ = try await importer.installCloud(deleted, localID: initialID, expectedMutation: mutation,
                allowCurrent: false, repository: repository, cache: cache)
            fatalError("Automatic cloud delete removed selected subscription")
        } catch SubscriptionError.staleRevision { }
        try requireCloud(repository.record(initialID).source == initialRecord.source)
        print("PASS automatic cloud update and deletion cannot change selected Mac subscription")

        let newID = UUID()
        incoming.id = newID
        _ = try await importer.installCloud(incoming, localID: newID, expectedMutation: nil,
            allowCurrent: false, repository: repository, cache: cache)
        let reloaded = await library.reloadCloudSubscriptionSummaries()
        precondition(reloaded && library.index.entries.contains { $0.id == newID })
        precondition(library.index.activeID == initialID && library.identity == initialIdentity && library.probeScope == initialScope)
        precondition(!library.busy && library.vpn.isIdle)
        print("PASS incoming cloud additions update cards without rebuilding runtime or latency scope")

        let corrupt = Data("proxies: [{name: Invalid, type: not-supported, server: invalid.example.invalid, port: 443}]".utf8)
        let digest = ConfigurationResourceStore.digest(corrupt)
        try cache.put(corrupt, digest: digest)
        var invalid = incoming
        invalid.originalDigest = digest; invalid.originalBytes = corrupt.count
        let beforeInvalid = try repository.record(newID)
        let newMutation = try repository.index()?.syncMutations?[newID.uuidString]
        do {
            _ = try await importer.installCloud(invalid, localID: newID, expectedMutation: newMutation,
                allowCurrent: false, repository: repository, cache: cache)
            fatalError("Invalid cloud configuration installed")
        } catch { }
        try requireCloud(repository.record(newID).source == beforeInvalid.source)
        print("PASS invalid cloud configuration rejected before replacing local record")

        try destination.activate(exported.id)
        try destination.saveChoices(["Proxy": "DIRECT"], for: exported.id)
        let destinationWorker = MacSubscriptionWorker(offline: true, offlineStorage: destinationStorage)
        let geo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Horizon/Resources/GeoData")
        let smart = try await destinationWorker.stageRouting(.smart, bundledDirectory: geo)
        _ = try await destinationWorker.commitRouting(smart)
        var updated = exported
        let updatedSource = initialRecord.source + Data("\n# synthetic cloud revision\n".utf8)
        updated.originalDigest = ConfigurationResourceStore.digest(updatedSource); updated.originalBytes = updatedSource.count
        try cache.put(updatedSource, digest: updated.originalDigest!)
        let smartMutation = try destination.index()?.syncMutations?[exported.id.uuidString]
        _ = try await importer.installCloud(updated, localID: exported.id, expectedMutation: smartMutation,
            allowCurrent: true, repository: destination, cache: cache)
        let localSmart = try await destinationWorker.load()
        precondition(localSmart.routing == .smart && localSmart.prepared?.catalog.choices["Proxy"] == "DIRECT")
        let localSmartRecord = try destination.record(exported.id)
        try requireCloud(ConfigurationSnapshot.original(localSmartRecord.source) == updatedSource)
        let portableSmart = try await importer.exportCloud(exported.id, repository: destination, cache: cache)
        precondition(portableSmart.resources.isEmpty && portableSmart.originalDigest == updated.originalDigest)
        print("PASS cloud update preserves Mac Smart Routing, cached local Geo assets and node choices; exports original YAML only")

        // Explicit review uses the same serialized library gate as all user edits.
        try await library.performCloudReview(localID: initialID) {
            _ = try await importer.installCloud(deleted, localID: initialID, expectedMutation: mutation,
                allowCurrent: true, repository: repository, cache: cache)
        }
        precondition(library.index.activeID == nil && library.prepared == nil && library.vpn.isIdle)
        print("PASS explicit review reloads selected configuration without starting VPN")

        var journal = CloudSyncJournal()
        var local = exported; local.title = "Local rename"; local.version = UUID()
        journal.entries[exported.id] = .init(localID: exported.id, installed: local, base: exported, outgoing: local)
        journal.fetched[exported.id] = deleted
        journal.reconcileFetched()
        precondition(journal.entries[exported.id]?.review == .conflict && journal.outgoingVersion(exported.id) == nil)
        try journal.save(account: "Production:FICTIONAL", storage: storage)
        let restoredJournal = try CloudSyncJournal.load(account: "Production:FICTIONAL", storage: storage)
        precondition(restoredJournal.entries[exported.id]?.review == .conflict)
        try requireCloud(CloudSyncJournal.load(account: "Development:FICTIONAL", storage: storage).entries.isEmpty)
        print("PASS deletion conflicts persist and development/production journals stay isolated")

        // A full read must traverse every page even if the first page has only
        // assets, or the incremental bookmark has already delivered one head.
        let zone = CKRecordZone.ID(zoneName: "PersonalSubscriptionsV1")
        var heads: [CKRecord] = []
        for number in 0..<4 {
            var value = exported; value.id = UUID(); value.title = "Cloud fixture \(number)"
            let record = CKRecord(recordType: "HorizonSubscriptionV1", recordID: .init(recordName: "s-" + value.id.uuidString, zoneID: zone))
            record.encryptedValues["payload"] = try JSONEncoder().encode(value)
            heads.append(record)
        }
        let asset = CKRecord(recordType: "HorizonAssetV1", recordID: .init(recordName: "a-fixture", zoneID: zone))
        let pages = MacCloudInventoryFixture([
            .init(records: [asset], moreComing: true),
            .init(records: [heads[0], heads[1]], moreComing: true),
            .init(records: [heads[1], heads[2], heads[3]], moreComing: false)
        ])
        let complete = try await MacCloudSubscriptionInventory.load { try await pages.next() }
        precondition(complete.count == 4)
        let inventoryCalls = await pages.calls; precondition(inventoryCalls == 3)
        let recovered = SubscriptionRepository(storage: MacMemoryStorage())
        let firstValue = try JSONDecoder().decode(CloudSubscriptionVersion.self, from: heads[0].encryptedValues["payload"] as! Data)
        _ = try await importer.installCloud(firstValue, localID: firstValue.id, expectedMutation: nil,
            allowCurrent: false, repository: recovered, cache: cache)
        for record in complete {
            let value = try JSONDecoder().decode(CloudSubscriptionVersion.self, from: record.encryptedValues["payload"] as! Data)
            if value.id == firstValue.id { continue }
            _ = try await importer.installCloud(value, localID: value.id, expectedMutation: nil,
                allowCurrent: false, repository: recovered, cache: cache)
        }
        try requireCloud(recovered.index()?.entries.count == 4 && recovered.index()?.activeID == nil)
        print("PASS paged metadata inventory recovers 4 of 4 subscriptions from a 1-subscription library without selecting or connecting")
        let broken = MacCloudInventoryFixture([.init(records: [heads[0]], moreComing: true)])
        do {
            _ = try await MacCloudSubscriptionInventory.load { try await broken.next() }
            fatalError("Failed inventory page reported success")
        } catch CloudSyncFailure.unavailable { }
        let cancelled = Task { try await MacCloudSubscriptionInventory.load { try await Task.sleep(for: .seconds(20)); return .init(records: [], moreComing: false) } }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled inventory reported success") } catch is CancellationError { }
        print("PASS incomplete and cancelled inventories cannot report a complete cloud library")

        let instant = ContinuousClock.now
        precondition(!MacICloudSubscriptionSyncStore.shouldCheckRemote(last: instant, foreground: true, now: instant.advanced(by: .seconds(29))))
        precondition(MacICloudSubscriptionSyncStore.shouldCheckRemote(last: instant, foreground: true, now: instant.advanced(by: .seconds(30))))
        precondition(!MacICloudSubscriptionSyncStore.shouldCheckRemote(last: instant, foreground: false, now: instant.advanced(by: .seconds(119))))
        precondition(MacICloudSubscriptionSyncStore.shouldCheckRemote(last: instant, foreground: false, now: instant.advanced(by: .seconds(120))))
        print("PASS bounded remote checks recover delayed pushes at 30 seconds foreground / 120 seconds without focus")

        let suite = "HorizonMacCloudFixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = MacCloudClientFixture()
        var clock = ContinuousClock.now
        var registrations = 0
        let sync = MacICloudSubscriptionSyncStore(defaults: defaults, repository: repository,
            client: client, now: { clock }, registerNotifications: { registrations += 1 })
        await sync.observe(library: library, allowed: true)
        precondition(!sync.enabled && registrations == 0 && !(sync.syncNow()))
        let unusedConnects = await client.connects; precondition(unusedConnects == 0)
        defaults.set(true, forKey: "cloudSync.enabled")
        let offline = MacICloudSubscriptionSyncStore(defaults: defaults, repository: repository,
            permitsNetwork: false, client: client, registerNotifications: { fatalError("Offline APNs registration") })
        offline.enable()
        await offline.observe(library: library, allowed: true)
        precondition(!offline.enabled && !offline.syncNow() && !offline.retry())
        print("PASS sync requires opt-in; offline preview cannot register APNs or initiate cloud requests")

        sync.enable()
        let observation = Task { await sync.observe(library: library, allowed: true) }
        try await Task.sleep(for: .milliseconds(150))
        let initialConnects = await client.connects; precondition(initialConnects == 1)
        precondition(registrations == 1 && sync.status == .ready && sync.lastSync != nil)
        let launchInventories = await client.inventories; precondition(launchInventories == 1)
        let lateCommit = try repository.add(.init(source: initialRecord.source), fileName: "Manual.yaml",
            displayTitle: "Commit retained across inventory snapshot", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
        await client.reportCommit()
        let accepted = sync.syncNow(), duplicate = sync.syncNow()
        precondition(accepted && !duplicate && sync.working)
        try await Task.sleep(for: .milliseconds(200))
        precondition(!sync.working && sync.status == .ready)
        precondition(library.index.entries.contains { $0.id == lateCommit })
        let manualInventories = await client.inventories; precondition(manualInventories == 2)
        let before = await client.sends
        for _ in 0..<3 { NotificationCenter.default.post(name: SubscriptionRepository.didCommitLocalChange, object: nil) }
        try await Task.sleep(for: .milliseconds(850))
        let after = await client.sends; precondition(after == before + 1)
        sync.setForeground(false)
        NotificationCenter.default.post(name: SubscriptionRepository.didCommitLocalChange, object: nil)
        try await Task.sleep(for: .milliseconds(800))
        let unfocusedSends = await client.sends; precondition(unfocusedSends == after + 1)
        sync.setForeground(true)
        try await Task.sleep(for: .milliseconds(250))
        let focusedSends = await client.sends; precondition(focusedSends == unfocusedSends + 1)
        print("PASS loss of focus retains local-change observation; return to foreground fetches without restarting synchronization")
        // Page refresh matches manual completeness, stays coalesced, and cannot restart the library.
        let beforePageInventories = await client.inventories
        precondition(!MacICloudSubscriptionSyncStore.shouldRefreshConfigurationPage(last: clock, now: clock.advanced(by: .milliseconds(4999))))
        precondition(MacICloudSubscriptionSyncStore.shouldRefreshConfigurationPage(last: clock, now: clock.advanced(by: .seconds(5))))
        precondition(MacICloudSubscriptionSyncStore.shouldRefreshConfigurationPage(last: nil, now: clock))
        sync.configurationPageEntered()
        try await Task.sleep(for: .milliseconds(150))
        let skippedPage = await client.sends; precondition(skippedPage == focusedSends)
        clock = clock.advanced(by: .seconds(5))
        for _ in 0..<5 { sync.configurationPageEntered() }
        precondition(!library.busy)
        try await Task.sleep(for: .milliseconds(250))
        let fetchedPage = await client.sends; precondition(fetchedPage == focusedSends + 1)
        let pageInventories = await client.inventories; precondition(pageInventories == beforePageInventories + 1)
        sync.configurationPageEntered()
        try await Task.sleep(for: .milliseconds(150))
        let repeatedPage = await client.sends; precondition(repeatedPage == fetchedPage && !library.busy)
        print("PASS configuration entry fetches once, deduplicates rapid navigation, preserves local controls and checks cloud metadata")

        func waitForPage(_ condition: @MainActor () async -> Bool) async throws {
            for _ in 0..<100 {
                if await condition() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            fatalError("Timed out waiting for the page clock fixture")
        }
        let pageWait = MacCloudPageWaitFixture()
        let pageClock = Task {
            await sync.observeConfigurationPage { try await pageWait.sleep($0) }
        }
        try await waitForPage { await pageWait.delays.count == 1 }
        let initialDelays = await pageWait.delays
        precondition(initialDelays == [.seconds(5)])
        // Model an incremental fetch which reports success but omits a cloud
        // subscription. The metadata path used by Sync now can recover it.
        var missing = exported
        missing.id = UUID(); missing.title = "Automatic metadata recovery"
        let missingVersion = missing
        await client.stageMetadataRecovery {
            _ = try await importer.installCloud(missingVersion, localID: missingVersion.id,
                expectedMutation: nil, allowCurrent: false, repository: repository, cache: cache)
        }
        for round in 1...2 {
            clock = clock.advanced(by: .seconds(5))
            await pageWait.resume()
            try await waitForPage { await pageWait.delays.count == round + 1 }
            if round == 1 {
                precondition(library.index.entries.contains { $0.id == missingVersion.id },
                    "Automatic five-second refresh missed a subscription which manual metadata reconciliation can recover")
                precondition(library.vpn.isIdle && !library.busy)
            }
            let count = await client.sends
            precondition(count == fetchedPage + round && !library.busy, "page round=\(round), sends=\(count), baseline=\(fetchedPage), busy=\(library.busy)")
        }
        let recurringInventories = await client.inventories
        precondition(recurringInventories == pageInventories + 2)
        let recurringDelays = await pageWait.delays
        precondition(recurringDelays == [.seconds(5), .seconds(5), .seconds(5)])
        pageClock.cancel(); await pageClock.value
        let afterLeaving = await client.sends
        clock = clock.advanced(by: .seconds(5))
        await pageWait.resume()
        try await Task.sleep(for: .milliseconds(150))
        let stoppedPage = await client.sends
        precondition(stoppedPage == afterLeaving)
        print("PASS visible configuration page repeatedly fetches every five seconds, recovers incremental omissions through metadata, keeps controls enabled and stops on exit")

        // A non-page fallback must have the same completeness and publish path,
        // while ordinary local processing ticks must not enumerate metadata.
        var fallback = exported
        fallback.id = UUID(); fallback.title = "Fallback metadata recovery"
        let fallbackVersion = fallback
        await client.stageMetadataRecovery {
            _ = try await importer.installCloud(fallbackVersion, localID: fallbackVersion.id,
                expectedMutation: nil, allowCurrent: false, repository: repository, cache: cache)
        }
        let inventoriesBeforeFallback = await client.inventories
        clock = clock.advanced(by: .seconds(30))
        try await waitForPage { library.index.entries.contains { $0.id == fallbackVersion.id } }
        let inventoriesAfterFallback = await client.inventories
        precondition(inventoriesAfterFallback == inventoriesBeforeFallback + 1)
        precondition(!sync.working && !library.busy && library.vpn.isIdle)
        try await Task.sleep(for: .milliseconds(3200))
        let inventoriesAfterLocalTick = await client.inventories
        precondition(inventoriesAfterLocalTick == inventoriesAfterFallback)
        print("PASS non-page remote fallback recovers and publishes missing subscriptions; local ticks do not enumerate metadata")

        // Enter before the cooldown ends: wait only the remaining interval,
        // then fetch. Leaving during that fetch must not cancel its import.
        precondition(sync.syncNow())
        try await Task.sleep(for: .milliseconds(200))
        let sendsBeforeEarlyEntry = await client.sends
        clock = clock.advanced(by: .seconds(4))
        let earlyWait = MacCloudPageWaitFixture()
        let earlyClock = Task {
            await sync.observeConfigurationPage { try await earlyWait.sleep($0) }
        }
        try await waitForPage { await earlyWait.delays.count == 1 }
        let earlyDelays = await earlyWait.delays
        precondition(earlyDelays == [.seconds(1)])
        clock = clock.advanced(by: .seconds(1))
        await client.holdNextSend()
        await earlyWait.resume()
        try await waitForPage { await client.sends == sendsBeforeEarlyEntry + 1 }
        precondition(!library.busy && sync.working)
        earlyClock.cancel()
        await client.releaseSend()
        await earlyClock.value
        let afterEarly = await client.sends
        let cancelledPageSends = await client.cancelledSends
        precondition(afterEarly == sendsBeforeEarlyEntry + 1 && cancelledPageSends == 0 && !sync.working)
        print("PASS early entry fetches at its remaining deadline; cancelling the page clock preserves an already started store-owned sync")

        observation.cancel(); await observation.value
        let lateID = try repository.add(.init(source: initialRecord.source + Data("\n# unique late commit\n".utf8)), fileName: "Late.yaml",
            displayTitle: "Committed during foreground cancellation", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
        precondition(!library.index.entries.contains { $0.id == lateID })
        let foreground = Task { await sync.observe(library: library, allowed: true) }
        try await Task.sleep(for: .milliseconds(150))
        let returnedConnects = await client.connects; precondition(returnedConnects == 2)
        precondition(library.index.entries.contains { $0.id == lateID })
        sync.disable()
        foreground.cancel(); await foreground.value
        try await Task.sleep(for: .milliseconds(100))
        precondition(!sync.enabled && sync.status == .off && !sync.working && sync.reviews.isEmpty)
        precondition(!defaults.bool(forKey: "cloudSync.enabled"))
        let stops = await client.stops; precondition(stops == 1)
        print("PASS manual sends reserve immediately, edits coalesce, foreground fetches, disabling stops coordinator")
    }
}

private func requireCloud(_ value: @autoclosure () throws -> Bool) throws { let passed = try value(); precondition(passed) }
