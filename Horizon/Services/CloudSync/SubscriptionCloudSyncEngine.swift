import CloudKit
import Foundation
import OSLog

/// Main-app-only cloud coordinator. Server records never become runnable until
/// the normal configuration worker has validated a complete, portable snapshot.
actor SubscriptionCloudSyncEngine: CKSyncEngineDelegate {
    static let containerIdentifier = "iCloud.Kenote.Clash"
    private static let zone = CKRecordZone.ID(zoneName: "PersonalSubscriptionsV1")
    private static let logger = Logger(subsystem: "Kenote.Clash", category: "CloudSync")
    private let repository: SubscriptionRepository
    private var container: CKContainer?
    private var engine: CKSyncEngine?
    private var cache: CloudAssetCache?
    private var account: String?
    private var journal = CloudSyncJournal()
    private var suspended = true
    private var processing = false
    private var connected = false
    private var status: CloudSyncSnapshot.Status = .off
    private var libraryChanged = false
    private var session = UUID()
    private var fetchFailed = false
    private var retryAfter: Date?
    private var localFailures: Set<UUID> = []

    init(repository: SubscriptionRepository = ConfigurationVault.repository) { self.repository = repository }

    func connect(allowAccountChange: Bool = false) async -> CloudSyncSnapshot {
        if engine != nil {
            // Foreground entry explicitly fetches instead of waiting for a push.
            if connected && !suspended { return await tick(sendNow: true) }
            await stop()
        }
        let ticket = UUID(); session = ticket
        status = .syncing
        do {
            let container = CKContainer(identifier: Self.containerIdentifier)
            self.container = container
            guard try await container.accountStatus() == .available else { status = .noAccount; return snapshot() }
            let account = try await container.userRecordID().recordName
            guard session == ticket, !Task.isCancelled else { throw CancellationError() }
            let previous = try repository.storage.read(CloudSyncScope.accountKey).map { String(decoding: $0, as: UTF8.self) }
            guard previous == nil || previous == account || allowAccountChange else {
                status = .accountChanged; return snapshot()
            }
            let scope = CloudSyncScope.identity(account)
            journal = try CloudSyncJournal.load(account: scope, storage: repository.storage)
            for (id, data) in journal.quarantined {
                if let value = try? JSONDecoder().decode(CloudSubscriptionVersion.self, from: data),
                   value.id == id, (try? value.validate()) != nil {
                    journal.fetched[id] = value; journal.quarantined[id] = nil
                }
            }
            cache = try CloudAssetCache(account: scope)
            self.account = account
            try repository.storage.write(Data(account.utf8), for: CloudSyncScope.accountKey)
            suspended = false
            var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                stateSerialization: journal.engine, delegate: self)
            configuration.automaticallySync = true
            let engine = CKSyncEngine(configuration)
            self.engine = engine
            // Fetch before enrolling local items, including when a restored local
            // library is empty. Cloud contents cannot be inferred from that library.
            try await engine.fetchChanges()
            guard session == ticket, !suspended else { throw CancellationError() }
            connected = true
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zone))])
            return await tick(sendNow: true)
        } catch is CancellationError { return snapshot() }
        catch { status = safeStatus(error); logFailure(error, stage: "connect"); return snapshot() }
    }

    func stop() async {
        session = UUID(); suspended = true; connected = false
        let old = engine; engine = nil
        await old?.cancelOperations()
        status = .off
    }

    func tick(sendNow: Bool = false) async -> CloudSyncSnapshot {
        if sendNow, (!connected || suspended) { return await connect() }
        guard !suspended, connected, let engine, let cache else { return snapshot() }
        if !sendNow, let retryAfter, retryAfter > Date() { return snapshot() }
        guard !processing else { return snapshot() }
        processing = true
        let ticket = session
        defer { processing = false }
        do {
            if sendNow {
                retryAfter = nil
                for id in journal.entries.keys where journal.entries[id]?.review == .invalid { journal.entries[id]?.review = nil }
            }
            try await captureLocal(cache: cache)
            try check(ticket)
            try reconcileFetched()
            try persist()
            try await applyIncoming(cache: cache, ticket: ticket)
            try check(ticket)
            try persist()
            enqueueOutgoing(engine)
            if sendNow {
                status = .syncing
                try await engine.fetchChanges()
                try check(ticket)
                try reconcileFetched()
                try persist()
                try await applyIncoming(cache: cache, ticket: ticket)
                try check(ticket)
                enqueueOutgoing(engine)
                try await engine.sendChanges()
                try check(ticket)
            }
            if journal.hasPendingTransfers {
                status = .waiting
            } else {
                if journal.lastSync != nil, [.syncing, .ready].contains(status) { status = .ready }
            }
            try persist()
        } catch is CancellationError { }
        catch { status = safeStatus(error); logFailure(error, stage: "sync-round") }
        return snapshot()
    }

    func snapshot() -> CloudSyncSnapshot {
        let reviews = journal.entries.compactMap { id, entry -> CloudSyncReviewItem? in
            guard let incoming = entry.incoming, let review = entry.review else { return nil }
            return .init(id: id, version: incoming.version, localID: entry.localID, title: incoming.title, deleted: incoming.deleted, reason: review)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        // Fetch/send callbacks finish before pending replicas have necessarily been
        // validated and installed. They cannot certify an incomplete library.
        let reportedStatus: CloudSyncSnapshot.Status = status == .ready ?
            (!journal.quarantined.isEmpty || !localFailures.isEmpty ? .failed : journal.hasPendingTransfers ? .waiting : .ready) : status
        let value = CloudSyncSnapshot(status: reportedStatus, lastSync: journal.lastSync, reviews: reviews, libraryChanged: libraryChanged,
            blockedCount: journal.quarantined.count + localFailures.count)
        libraryChanged = false
        return value
    }

    #if os(macOS)
    /// Manual/launch repair: enumerate all subscription heads without changing
    /// incremental tokens, deleting local records, or downloading every cloud asset.
    func reconcileCloudLibrary() async -> CloudSyncSnapshot {
        guard connected, !suspended, !processing, let engine, let cache else { return snapshot() }
        processing = true
        defer { processing = false }
        let ticket = session
        do {
            let before = journal.remoteVersions
            let records = try await MacCloudSubscriptionInventory.load(database: engine.database, zone: Self.zone)
            try check(ticket)
            let after = journal.remoteVersions
            var rejected = 0
            for record in records {
                // An automatic fetch or send may acknowledge a newer head while
                // the full inventory is paging. Preserve that newer observation.
                if let id = UUID(uuidString: String(record.recordID.recordName.dropFirst(2))),
                   after[id] != before[id] { continue }
                if !receive(record) { rejected += 1 }
            }
            try reconcileFetched()
            try persist()
            try await applyIncoming(cache: cache, ticket: ticket)
            try check(ticket)
            try persist()
            enqueueOutgoing(engine)
            if rejected > 0 { status = .failed }
            else if journal.hasPendingTransfers { status = .waiting }
            else { status = .ready; journal.lastSync = Date() }
            let local = try await ConfigurationImportWorker.shared.subscriptionIndex(repository)
            let pending = journal.hasPendingTransfers
            Self.logger.notice("Mac inventory completed: cloudHeads=\(records.count, privacy: .public), localSubscriptions=\(local.entries.count, privacy: .public), pending=\(pending, privacy: .public), rejected=\(rejected, privacy: .public)")
        } catch is CancellationError { }
        catch { status = safeStatus(error); logFailure(error, stage: "mac-inventory") }
        return snapshot()
    }
    #endif

    private func check(_ ticket: UUID) throws {
        try Task.checkCancellation()
        guard ticket == session, !suspended else { throw CancellationError() }
    }
    private func persist() throws {
        guard let account else { throw CloudSyncFailure.accountChanged }
        try journal.save(account: CloudSyncScope.identity(account), storage: repository.storage)
    }

    private func captureLocal(cache: CloudAssetCache) async throws {
        let index = try await ConfigurationImportWorker.shared.subscriptionIndex(repository)
        localFailures.formIntersection(Set(index.entries.map(\.id)))
        let ticket = session
        for summary in index.entries {
            try check(ticket)
            let bindings = journal.entries.filter { $0.value.localID == summary.id }.map(\.key)
            let ids = bindings.isEmpty ? [summary.id] : bindings
            for cloudID in ids {
                guard journal.quarantined[cloudID] == nil else { continue }
                var entry = journal.entries[cloudID] ?? CloudSyncEntry(localID: summary.id)
                let mutation = index.syncMutations?[summary.id.uuidString]
                let hasAssets = entry.installed.map { requiredAssets($0).allSatisfy { cache.contains($0.0, bytes: $0.1) } } ?? false
                guard entry.installed == nil || entry.observedMutation != mutation || !hasAssets else { continue }
                var value: CloudSubscriptionVersion
                do {
                    value = try await ConfigurationImportWorker.shared.exportCloud(summary.id, repository: repository, cache: cache)
                    localFailures.remove(summary.id)
                } catch let error as CloudSyncFailure where error == .missingAsset || error == .invalidPayload {
                    localFailures.insert(summary.id); status = .failed
                    continue
                } catch is ConfigurationIssue {
                    localFailures.insert(summary.id); status = .failed
                    continue
                }
                try check(ticket)
                value.id = cloudID
                // Pin the generation read with the exported bytes; if a foreground
                // write intervened, the next pass must export again, not acknowledge it.
                let after = try await ConfigurationImportWorker.shared.subscriptionIndex(repository)
                guard after.syncMutations?[summary.id.uuidString] == mutation else { continue }
                // CKSyncEngine callbacks can arrive while the worker is exporting.
                // Retain their latest server change tag and acknowledged base.
                entry = journal.entries[cloudID] ?? entry
                if entry.installed?.sameValue(as: value) != true {
                    value.parent = entry.base?.version
                    if entry.review == .conflict {
                        entry.outgoing = value
                    } else if let incoming = entry.incoming, let installed = entry.installed {
                        if let merged = CloudSubscriptionVersion.merge(base: installed, local: value, remote: incoming) {
                            entry.outgoing = merged; entry.incoming = merged
                        } else { entry.outgoing = value; entry.review = .conflict }
                    } else { entry.outgoing = value }
                    entry.installed = value
                }
                entry.observedMutation = mutation
                journal.entries[cloudID] = entry
            }
        }
        for (cloudID, var entry) in journal.entries where journal.quarantined[cloudID] == nil {
            guard let id = entry.localID, !index.entries.contains(where: { $0.id == id }),
                  index.syncDeletedIDs?.contains(id) == true,
                  entry.observedMutation != index.syncMutations?[id.uuidString] else { continue }
            var deleted = CloudSubscriptionVersion(id: cloudID, parent: entry.base?.version, title: entry.installed?.title ?? "Deleted subscription")
            deleted.deleted = true
            entry.outgoing = deleted; entry.installed = deleted
            if entry.incoming != nil { entry.review = .conflict }
            entry.observedMutation = index.syncMutations?[id.uuidString]
            journal.entries[cloudID] = entry
        }
        try persist() // Outgoing bytes and generations survive termination before send.
    }

    private func reconcileFetched() throws { journal.reconcileFetched() }

    private func applyIncoming(cache: CloudAssetCache, ticket: UUID) async throws {
        for (id, entry) in journal.entries {
            guard let value = entry.incoming, entry.review == nil else { continue }
            let index = try await ConfigurationImportWorker.shared.subscriptionIndex(repository)
            try check(ticket)
            let localID = entry.localID ?? id
            if index.activeID == localID {
                journal.entries[id]?.review = .current
                continue
            }
            do {
                try await ensureAssets(value, ticket: ticket)
                let committed = try await ConfigurationImportWorker.shared.installCloud(value, localID: localID,
                    expectedMutation: entry.observedMutation, allowCurrent: false, repository: repository, cache: cache)
                // Once the worker commits, acknowledge it durably even if the
                // observation task was cancelled while awaiting the worker.
                libraryChanged = true
                if session == ticket {
                    journal.acknowledgeInstallation(id, value: value, mutation: committed)
                    try persist()
                }
                try check(ticket)
            } catch SubscriptionError.staleRevision {
                // A foreground edit/activation won. Capture it on the next pass.
                continue
            } catch {
                if error is CancellationError { throw error }
                // Keep incomplete/unsupported versions retryable and reviewable;
                // never replace a working local item on validation failure.
                let failureStatus = safeStatus(error)
                logFailure(error, stage: "replica-install")
                if failureStatus == .waiting {
                    retryAfter = Date().addingTimeInterval(max(30, (error as? CKError)?.retryAfterSeconds ?? 0))
                } else { journal.entries[id]?.review = .invalid }
                status = failureStatus
            }
        }
    }

    private func requiredAssets(_ value: CloudSubscriptionVersion) -> [(String, Int)] {
        var assets = value.resources.map { ($0.digest, $0.bytes) }
        if let digest = value.originalDigest { assets.append((digest, value.originalBytes)) }
        return assets
    }
    private func ensureAssets(_ value: CloudSubscriptionVersion, ticket: UUID) async throws {
        guard let cache, let database = engine?.database else { throw CloudSyncFailure.unavailable }
        for (digest, bytes) in requiredAssets(value) {
            if (try? cache.read(digest, bytes: bytes)) != nil { continue }
            let record = try await database.record(for: assetID(digest))
            try check(ticket)
            try acceptAsset(record)
            _ = try cache.read(digest, bytes: bytes)
        }
    }
    private func enqueueOutgoing(_ engine: CKSyncEngine) {
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for id in journal.entries.keys {
            guard let value = journal.outgoingVersion(id) else { continue }
            changes += requiredAssets(value).filter { !journal.knownAssets.contains($0.0) }.map { .saveRecord(assetID($0.0)) }
            changes.append(.saveRecord(subscriptionID(id)))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }
    private func subscriptionID(_ id: UUID) -> CKRecord.ID { .init(recordName: "s-" + id.uuidString, zoneID: Self.zone) }
    private func assetID(_ digest: String) -> CKRecord.ID { .init(recordName: "a-" + digest, zoneID: Self.zone) }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, !suspended, let cache else { return nil }
        do {
            var assets: [String: Int] = [:]
            for id in journal.entries.keys {
                if let value = journal.outgoingVersion(id) {
                    for (digest, bytes) in requiredAssets(value) where !journal.knownAssets.contains(digest) { assets[digest] = bytes }
                }
            }
            // Publish dependencies before heads, with bounded batches and memory.
            if !assets.isEmpty {
                var records: [CKRecord] = []
                for (digest, bytes) in assets.sorted(by: { $0.key < $1.key }) {
                    let id = assetID(digest)
                    guard context.options.scope.contains(.saveRecord(id)) else { continue }
                    _ = try cache.read(digest, bytes: bytes)
                    let record = CKRecord(recordType: "HorizonAssetV1", recordID: id)
                    record.encryptedValues["digest"] = digest
                    record.encryptedValues["bytes"] = Int64(bytes)
                    record["file"] = CKAsset(fileURL: try cache.url(digest))
                    records.append(record)
                    if records.count == 2 { break }
                }
                return records.isEmpty ? nil : .init(recordsToSave: records)
            }
            var records: [CKRecord] = []
            for (id, entry) in journal.entries {
                guard let value = journal.outgoingVersion(id), context.options.scope.contains(.saveRecord(subscriptionID(id))) else { continue }
                let record: CKRecord
                if let fields = entry.systemFields,
                   let coder = try? NSKeyedUnarchiver(forReadingFrom: fields) {
                    coder.requiresSecureCoding = true
                    guard let saved = CKRecord(coder: coder) else { throw CloudSyncFailure.persistence }
                    coder.finishDecoding(); record = saved
                } else { record = CKRecord(recordType: "HorizonSubscriptionV1", recordID: subscriptionID(id)) }
                record.encryptedValues["payload"] = try JSONEncoder().encode(value)
                records.append(record)
                if records.count == 10 { break }
            }
            return records.isEmpty ? nil : .init(recordsToSave: records)
        } catch {
            status = safeStatus(error)
            return nil
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, !suspended else { return }
        do {
            switch event {
            case .stateUpdate(let event): journal.engine = event.stateSerialization
            case .accountChange(let event):
                switch event.changeType {
                case .signIn(let current) where current.recordName == account: break
                default:
                    suspended = true; connected = false; status = .accountChanged
                    Self.logger.notice("Cloud sync suspended after an account-change callback")
                    CloudSyncCallbackTask.run { await syncEngine.cancelOperations() }
                }
            case .fetchedRecordZoneChanges(let event):
                let heads = event.modifications.filter { $0.record.recordType == "HorizonSubscriptionV1" }.count
                let assets = event.modifications.filter { $0.record.recordType == "HorizonAssetV1" }.count
                Self.logger.notice("Cloud batch received: subscriptionHeads=\(heads, privacy: .public), assets=\(assets, privacy: .public)")
                for modification in event.modifications {
                    if !receive(modification.record) { fetchFailed = true }
                }
                // Physical record deletion/zone purge is not a user tombstone.
                // Stop instead of guessing, resurrecting records or wiping local data.
                if !event.deletions.isEmpty { suspended = true; status = .configuration }
            case .fetchedDatabaseChanges(let event):
                if event.deletions.contains(where: { $0.zoneID == Self.zone }) { suspended = true; status = .configuration }
            case .sentRecordZoneChanges(let event):
                for record in event.savedRecords {
                    if record.recordType == "HorizonAssetV1" {
                        let digest = String(record.recordID.recordName.dropFirst(2))
                        journal.knownAssets.insert(digest)
                    } else {
                        let value = try decode(record)
                        if var entry = journal.entries[value.id] {
                            entry.systemFields = systemFields(record); entry.base = value
                            if entry.outgoing?.version == value.version { entry.outgoing = nil }
                            journal.entries[value.id] = entry
                        }
                    }
                }
                for failure in event.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                        if server.recordType == "HorizonAssetV1" {
                            guard let cache else { throw CloudSyncFailure.unavailable }
                            let asset = try CloudAssetRecord(server, zone: Self.zone)
                            journal.knownAssets.insert(try asset.acknowledgeExisting(in: cache))
                            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                        }
                        else {
                            try accept(server)
                            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                        }
                    } else if failure.error.code == .zoneNotFound {
                        // A genuinely new zone may be created. Never recreate a
                        // previously synced zone after cloud data was reset.
                        if journal.entries.values.contains(where: { $0.base != nil }) { suspended = true; status = .configuration }
                        else { syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zone))]) }
                    } else { status = safeStatus(failure.error); logFailure(failure.error, stage: "record-send") }
                }
                if event.failedRecordSaves.isEmpty && !event.savedRecords.isEmpty { journal.lastSync = Date(); status = .ready }
            case .sentDatabaseChanges(let event):
                if let failure = event.failedZoneSaves.first { status = safeStatus(failure.error) }
            case .willFetchChanges:
                fetchFailed = false
            case .didFetchRecordZoneChanges(let event):
                if let error = event.error { fetchFailed = true; status = safeStatus(error) }
            case .didFetchChanges:
                if !fetchFailed {
                    journal.lastSync = Date()
                    if !suspended { status = .ready }
                }
            default: break
            }
            try persist()
        } catch {
            // A failed durable journal write must prevent further sends. The local
            // library and mutation ledger remain intact for explicit retry.
            suspended = true; status = safeStatus(error)
            // Log only classification/codes, never NSError descriptions, payloads,
            // subscription URLs, account record names or node credentials.
            let category = error is CloudSyncFailure ? "journal" : error is CKError ? "cloudkit" : error is PrototypeError ? "keychain-or-local" : "encoding-or-local"
            let code = (error as? CKError)?.code.rawValue ?? 0
            Self.logger.error("Cloud sync delegate suspended: category=\(category, privacy: .public), cloudKitCode=\(code, privacy: .public)")
            CloudSyncCallbackTask.run { await syncEngine.cancelOperations() }
        }
    }

    private func decode(_ record: CKRecord) throws -> CloudSubscriptionVersion {
        guard record.recordType == "HorizonSubscriptionV1", record.recordID.zoneID == Self.zone,
              let data = record.encryptedValues["payload"] as? Data, data.count <= 64 * 1024 else { throw CloudSyncFailure.invalidPayload }
        let value = try JSONDecoder().decode(CloudSubscriptionVersion.self, from: data)
        try value.validate()
        guard record.recordID == subscriptionID(value.id) else { throw CloudSyncFailure.invalidPayload }
        return value
    }
    @discardableResult private func receive(_ record: CKRecord) -> Bool {
        do { try accept(record); return true }
        catch {
            if record.recordType == "HorizonSubscriptionV1", record.recordID.zoneID == Self.zone,
               record.recordID.recordName.hasPrefix("s-"),
               let id = UUID(uuidString: String(record.recordID.recordName.dropFirst(2))),
               let payload = record.encryptedValues["payload"] as? Data, payload.count <= 64 * 1024 {
                journal.quarantined[id] = payload
                journal.fetched[id] = nil
                engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }
            status = .failed
            logFailure(error, stage: "record-receive")
            return false
        }
    }
    private func logFailure(_ error: Error, stage: String) {
        // Never log descriptions, titles, URLs, record/account IDs or credentials.
        let category = error is CloudSyncFailure ? "payload-or-cache" : error is CKError ? "cloudkit" :
            error is SubscriptionError ? "local-revision" : error is ConfigurationIssue ? "configuration-validation" : "local-storage-or-validation"
        let code = (error as? CKError)?.code.rawValue ?? 0
        Self.logger.error("Cloud sync operation incomplete: stage=\(stage, privacy: .public), category=\(category, privacy: .public), cloudKitCode=\(code, privacy: .public)")
    }
    private func accept(_ record: CKRecord) throws {
        if record.recordType == "HorizonAssetV1" { try acceptAsset(record); return }
        let value = try decode(record)
        journal.quarantined[value.id] = nil
        journal.fetched[value.id] = value
        var entry = journal.entries[value.id] ?? CloudSyncEntry()
        entry.systemFields = systemFields(record)
        journal.entries[value.id] = entry
    }
    private func acceptAsset(_ record: CKRecord) throws {
        let asset = try CloudAssetRecord(record, zone: Self.zone)
        guard let url = (record["file"] as? CKAsset)?.fileURL,
              let cache else { throw CloudSyncFailure.invalidPayload }
        try cache.importFile(url, digest: asset.digest, bytes: asset.bytes)
        journal.knownAssets.insert(asset.digest)
    }
    private func systemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding()
        return coder.encodedData
    }
    private func safeStatus(_ error: Error) -> CloudSyncSnapshot.Status {
        guard let error = error as? CKError else { return .failed }
        switch error.code {
        case .notAuthenticated: return .noAccount
        case .quotaExceeded: return .quota
        case .badContainer, .badDatabase, .permissionFailure, .missingEntitlement, .serverRejectedRequest: return .configuration
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy: return .waiting
        default: return .failed
        }
    }

    enum Resolution: Sendable { case useCloud, keepLocal, keepBoth }
    func resolve(_ id: UUID, expectedVersion: UUID, resolution: Resolution) async throws {
        guard !suspended, !processing, let cache, let entry = journal.entries[id], let incoming = entry.incoming,
              incoming.version == expectedVersion else {
            throw CloudSyncFailure.unavailable
        }
        processing = true; defer { processing = false }
        let ticket = session
        let index = try await ConfigurationImportWorker.shared.subscriptionIndex(repository)
        let localID = entry.localID ?? id
        guard index.syncMutations?[localID.uuidString] == entry.observedMutation else { throw SubscriptionError.staleRevision }
        switch resolution {
        case .useCloud:
            try await ensureAssets(incoming, ticket: ticket)
            let committed = try await ConfigurationImportWorker.shared.installCloud(incoming, localID: localID,
                expectedMutation: entry.observedMutation, allowCurrent: true, repository: repository, cache: cache)
            try check(ticket)
            journal.entries[id]?.observedMutation = committed
            journal.entries[id]?.installed = incoming; journal.entries[id]?.outgoing = nil
            journal.entries[id]?.incoming = nil; journal.entries[id]?.review = nil
            libraryChanged = true
        case .keepLocal:
            var local = try await ConfigurationImportWorker.shared.exportCloud(localID, repository: repository, cache: cache)
            try check(ticket)
            if incoming.deleted {
                // Keeping a deleted subscription creates a new cloud identity,
                // preserving the tombstone for devices returning from offline.
                let newID = CloudSubscriptionVersion.conflictCopyID(id, incoming.version)
                local.id = newID; local.parent = nil
                journal.entries[newID] = CloudSyncEntry(localID: localID, observedMutation: entry.observedMutation,
                    installed: local, outgoing: local)
                journal.entries[id]?.localID = nil; journal.entries[id]?.installed = incoming
                journal.entries[id]?.outgoing = nil
            } else {
                local.id = id; local.parent = incoming.version
                journal.entries[id]?.outgoing = local; journal.entries[id]?.installed = local
            }
            journal.entries[id]?.incoming = nil; journal.entries[id]?.review = nil
        case .keepBoth:
            guard !incoming.deleted else { throw CloudSyncFailure.conflict }
            var copy = incoming
            let copyID = CloudSubscriptionVersion.conflictCopyID(id, incoming.version)
            copy.id = copyID; copy.version = UUID(); copy.parent = nil
            copy.title = SubscriptionSummary.cleanName(String(copy.title.prefix(80)) + " (iCloud)")
            try await ensureAssets(copy, ticket: ticket)
            guard !index.entries.contains(where: { $0.id == copyID }) else { throw CloudSyncFailure.conflict }
            try await ConfigurationImportWorker.shared.installCloud(copy, localID: copyID,
                expectedMutation: nil, allowCurrent: false, repository: repository, cache: cache)
            var local = try await ConfigurationImportWorker.shared.exportCloud(localID, repository: repository, cache: cache)
            try check(ticket)
            local.id = id; local.parent = incoming.version
            journal.entries[id]?.outgoing = local; journal.entries[id]?.incoming = nil; journal.entries[id]?.review = nil
            let after = try await ConfigurationImportWorker.shared.subscriptionIndex(repository)
            journal.entries[copyID] = CloudSyncEntry(localID: copyID, observedMutation: after.syncMutations?[copyID.uuidString], installed: copy, outgoing: copy)
            libraryChanged = true
        }
        try persist()
        if let engine { enqueueOutgoing(engine) }
    }
}
