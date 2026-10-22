import Foundation
import CryptoKit

/// One protected item per source; the extension loads only the active source.
/// All writers live in the main App. Index replacement is the commit point.
nonisolated struct SubscriptionRepository: Sendable {
    private static let transactionLock = NSRecursiveLock()
    static func transaction<T>(_ operation: () throws -> T) rethrows -> T {
        transactionLock.lock(); defer { transactionLock.unlock() }
        return try operation()
    }
    static let indexKey = "subscriptions-index-v1"
    static let legacyKey = "hy2-salamander-v1"
    /// Local commits only; contains no subscription names, URLs or credentials.
    static let didCommitLocalChange = Notification.Name("Horizon.subscriptionDidCommitLocalChange")
    static func recordKey(_ id: UUID) -> String { "subscription-" + id.uuidString }
    let storage: any SubscriptionStorage

    func index() throws -> SubscriptionIndex? {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard let data = try storage.read(Self.indexKey) else { return nil }
        guard let index = try? JSONDecoder().decode(SubscriptionIndex.self, from: data) else { throw SubscriptionError.invalidLibrary }
        try index.validate()
        return index
    }
    private func save(_ index: SubscriptionIndex) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        try index.validate()
        try storage.write(JSONEncoder().encode(index), for: Self.indexKey)
    }
    private func digest(_ source: Data) -> String { SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined() }
    private func legacyRecord() throws -> StoredConfiguration? {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard let data = try storage.read(Self.legacyKey) else { return nil }
        if let record = try? JSONDecoder().decode(StoredConfiguration.self, from: data), record.format == "clash-vault-v2" { return record }
        return StoredConfiguration(source: data)
    }
    func record(_ id: UUID) throws -> StoredConfiguration {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        let keyID = try index()?.entries.first(where: { $0.id == id }).map { $0.storageID ?? $0.id } ?? id
        guard let data = try storage.read(Self.recordKey(keyID)),
              let record = try? JSONDecoder().decode(StoredConfiguration.self, from: data), record.format == "clash-vault-v2" else {
            throw SubscriptionError.missingEntry
        }
        return record
    }
    /// Read-only path used by the extension, including upgrade fallback.
    func activeRecord() throws -> StoredConfiguration? {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard let index = try index() else { return try legacyRecord() }
        guard let id = index.activeID else { return nil }
        return try record(id)
    }
    /// Migration preserves the old item until both the new source and index commit.
    func library() throws -> SubscriptionIndex {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        if try index() != nil { return try cleanup() }
        guard let legacy = try legacyRecord() else {
            if try storage.keys().contains(where: { $0.hasPrefix("subscription-") || $0.hasPrefix("dependency-v1-") }) {
                try save(SubscriptionIndex())
                return try cleanup()
            }
            return SubscriptionIndex()
        }
        let id = UUID()
        let summary = SubscriptionSummary(id: id, title: "原有订阅", fileName: nil, importedAt: nil,
            updatedAt: Date(), sourceDigest: digest(legacy.source), nodeCount: 0, groupCount: 0, ruleCount: 0)
        let migrated = SubscriptionIndex(entries: [summary], activeID: id, needsLegacyCleanup: true)
        try commitNewRecord(legacy, id: id, index: migrated)
        return try cleanup()
    }
    private func commitNewRecord(_ record: StoredConfiguration, id: UUID, index: SubscriptionIndex) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        try ConfigurationResourceStore.persist(record.source, storage: storage)
        try storage.write(JSONEncoder().encode(record), for: Self.recordKey(id))
        do { try save(index) }
        catch { try? storage.remove(Self.recordKey(id)); throw error }
    }
    /// Byte-identical reimports update the filename but retain saved choices.
    /// Same-name/different-content imports create a separate record.
    func add(_ record: StoredConfiguration, fileName: String?, displayTitle: String? = nil, nodeCount: Int, groupCount: Int,
             ruleCount: Int, makeCurrent: Bool) throws -> UUID {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        var library = try library()
        let hash = digest(record.source)
        let cleanFile = fileName.map { SubscriptionSummary.cleanName($0) }
        let base = displayTitle.map { SubscriptionSummary.cleanName($0) } ?? SubscriptionSummary.title(from: cleanFile ?? "")
        guard !base.isEmpty else { throw SubscriptionError.invalidTitle }
        if let position = try library.entries.firstIndex(where: {
            guard $0.sourceDigest == hash else { return false }
            return try self.record($0.id).sourceURL == record.sourceURL
        }) {
            let id = library.entries[position].id
            // Verify existence and source before treating it as a duplicate.
            guard try self.record(id).source == record.source else { throw SubscriptionError.invalidLibrary }
            if let cleanFile { library.entries[position].fileName = cleanFile }
            library.entries[position].title = uniqueTitle(base, entries: library.entries.filter { $0.id != id })
            library.entries[position].updatedAt = Date()
            library.entries[position].nodeCount = nodeCount
            library.entries[position].groupCount = groupCount
            library.entries[position].ruleCount = ruleCount
            if makeCurrent { library.activeID = id }
            library.noteMutation(id)
            try save(library)
            NotificationCenter.default.post(name: Self.didCommitLocalChange, object: nil)
            return id
        }
        guard library.entries.count < 128 else { throw SubscriptionError.tooMany }
        let id = UUID(), now = Date()
        library.entries.append(.init(id: id, title: uniqueTitle(base, entries: library.entries), fileName: cleanFile,
            importedAt: now, updatedAt: now, sourceDigest: hash, nodeCount: nodeCount, groupCount: groupCount, ruleCount: ruleCount))
        if makeCurrent { library.activeID = id }
        library.noteMutation(id)
        try commitNewRecord(record, id: id, index: library)
        NotificationCenter.default.post(name: Self.didCommitLocalChange, object: nil)
        return id
    }
    func replace(_ id: UUID, expected: StoredConfiguration, source: Data, choices: [String: String],
                 sourceURL: String?, nodeCount: Int, groupCount: Int, ruleCount: Int,
                 verifiedAt: Date? = nil) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        var library = try library()
        guard let position = library.entries.firstIndex(where: { $0.id == id }) else { throw SubscriptionError.missingEntry }
        let current = try record(id)
        guard current.revisionID == expected.revisionID, current.source == expected.source,
              current.choices == expected.choices, current.sourceURL == expected.sourceURL else { throw SubscriptionError.staleRevision }
        var next = StoredConfiguration(source: source, choices: choices)
        if source == current.source { next.certificateConsentDigest = current.certificateConsentDigest }
        next.sourceURL = sourceURL
        next.revisionNumber = (current.revisionNumber ?? 1) + 1
        next.verifiedAt = verifiedAt
        next.startupConfirmed = source == current.source && choices == current.choices ? current.startupConfirmed : false
        next.history = Array(([current.snapshotRevision] + (current.history ?? [])).prefix(5))
        next.lastUsable = current.verifiedAt != nil ? current.snapshotRevision : current.lastUsable
        let oldKey = library.entries[position].storageID ?? id
        let newKey = UUID()
        library.format = "clash-subscriptions-v2" // Older readers must fail closed before orphan cleanup.
        library.entries[position].storageID = newKey
        library.entries[position].sourceDigest = digest(source)
        library.entries[position].updatedAt = Date()
        library.entries[position].nodeCount = nodeCount
        library.entries[position].groupCount = groupCount
        library.entries[position].ruleCount = ruleCount
        library.noteMutation(id)
        library.pendingDeletion.append(oldKey)
        try commitNewRecord(next, id: newKey, index: library)
        NotificationCenter.default.post(name: Self.didCommitLocalChange, object: nil)
        _ = try? cleanup()
    }
    func markStartupConfirmed(_ id: UUID, source: Data, choices: [String: String]) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard let entry = try index()?.entries.first(where: { $0.id == id }) else { return }
        var value = try record(id)
        guard value.source == source, value.choices == choices else { return }
        value.startupConfirmed = true
        try storage.write(JSONEncoder().encode(value), for: Self.recordKey(entry.storageID ?? id))
    }
    func markUsable(_ id: UUID, source: Data, choices: [String: String]) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard let entry = try index()?.entries.first(where: { $0.id == id }) else { return }
        var record = try record(id)
        guard record.source == source, record.choices == choices else { return }
        record.verifiedAt = Date()
        record.lastUsable = record.snapshotRevision
        try storage.write(JSONEncoder().encode(record), for: Self.recordKey(entry.storageID ?? id))
    }
    private func uniqueTitle(_ base: String, entries: [SubscriptionSummary]) -> String {
        let used = Set(entries.map(\.title))
        if !used.contains(base) { return base }
        var number = 2
        while used.contains(String(base.prefix(90)) + " (\(number))") { number += 1 }
        return String(base.prefix(90)) + " (\(number))"
    }
    func activate(_ id: UUID) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        var library = try library()
        guard library.entries.contains(where: { $0.id == id }) else { throw SubscriptionError.missingEntry }
        _ = try record(id)
        library.activeID = id
        try save(library)
    }
    func saveChoices(_ choices: [String: String], for id: UUID) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard try library().activeID == id else { throw SubscriptionError.missingEntry }
        var record = try record(id)
        guard record.choices != choices else { return }
        if record.verifiedAt != nil { record.lastUsable = record.snapshotRevision }
        record.verifiedAt = nil
        record.revisionID = UUID()
        record.choices = choices
        let keyID = try library().entries.first(where: { $0.id == id }).map { $0.storageID ?? $0.id } ?? id
        try storage.write(JSONEncoder().encode(record), for: Self.recordKey(keyID))
    }
    func approveInsecureCertificates(_ id: UUID, expectedDigest: String) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        let index = try library()
        guard index.activeID == id, let summary = index.entries.first(where: { $0.id == id }) else { throw SubscriptionError.staleRevision }
        var record = try record(id)
        guard record.contentDigest == expectedDigest else { throw SubscriptionError.staleRevision }
        record.certificateConsentDigest = expectedDigest
        try storage.write(JSONEncoder().encode(record), for: Self.recordKey(summary.storageID ?? id))
    }
    func rename(_ id: UUID, title: String) throws {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        let title = SubscriptionSummary.cleanName(title)
        guard !title.isEmpty else { throw SubscriptionError.invalidTitle }
        var library = try library()
        guard let index = library.entries.firstIndex(where: { $0.id == id }) else { throw SubscriptionError.missingEntry }
        library.entries[index].title = uniqueTitle(title, entries: library.entries.filter { $0.id != id })
        library.noteMutation(id)
        try save(library)
        NotificationCenter.default.post(name: Self.didCommitLocalChange, object: nil)
    }
    func delete(_ ids: Set<UUID>, performCleanup: Bool = true, notifyLocalChange: Bool = true) throws -> SubscriptionIndex {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        var library = try index() ?? library()
        let removed = Set(library.entries.map(\.id)).intersection(ids)
        guard !removed.isEmpty else { return library }
        let removedKeys = Set(library.entries.filter { removed.contains($0.id) }.map { $0.storageID ?? $0.id })
        library.entries.removeAll { removed.contains($0.id) }
        for id in removed { library.noteMutation(id, deleted: true) }
        if let active = library.activeID, removed.contains(active) { library.activeID = nil }
        library.pendingDeletion = Array(Set(library.pendingDeletion).union(removedKeys))
        try save(library)
        if notifyLocalChange { NotificationCenter.default.post(name: Self.didCommitLocalChange, object: nil) }
        return performCleanup ? try cleanup() : library
    }
    /// Pending deletions cannot be selected, even if Keychain cleanup fails.
    func cleanup() throws -> SubscriptionIndex {
        Self.transactionLock.lock(); defer { Self.transactionLock.unlock() }
        guard var library = try index() else { return SubscriptionIndex() }
        // A process termination between source write and index commit can leave
        // an unreferenced item. Recover only this repository's UUID namespace.
        let referenced = Set(library.entries.map { $0.storageID ?? $0.id })
        guard let keys = try? storage.keys() else { return library }
        let stored = Set(keys.compactMap { key -> UUID? in
            guard key.hasPrefix("subscription-") else { return nil }
            return UUID(uuidString: String(key.dropFirst("subscription-".count)))
        })
        let abandoned = stored.subtracting(referenced).subtracting(library.pendingDeletion)
        if !abandoned.isEmpty {
            library.pendingDeletion += abandoned
            do { try save(library) } catch { return library }
        }
        let original = library.cleanupCount
        library.pendingDeletion = library.pendingDeletion.filter { id in
            do { try storage.remove(Self.recordKey(id)); return false } catch { return true }
        }
        if library.needsLegacyCleanup {
            do { try storage.remove(Self.legacyKey); library.needsLegacyCleanup = false } catch { }
        }
        if library.cleanupCount != original {
            do { try save(library) } catch { return try index() ?? library }
        }
        // Never collect if any retained record cannot be read: leaking storage temporarily is safer than deleting live resources.
        do {
            var sources: [Data] = []
            for entry in library.entries {
                let record = try record(entry.id)
                sources.append(record.source)
                sources += (record.history ?? []).map(\.source)
                if let usable = record.lastUsable { sources.append(usable.source) }
            }
            try ConfigurationResourceStore.collect(sources: sources, storage: storage)
        } catch { }
        return library
    }

    /// Replica writes cannot activate subscriptions, bypass local revision checks or
    /// touch the current subscription without an explicit foreground review.
    @discardableResult func installReplica(id: UUID, title: String, fileName: String?, record: StoredConfiguration,
                        nodeCount: Int, groupCount: Int, ruleCount: Int,
                        expectedMutation: UUID?, allowCurrent: Bool,
                        expectedRecord: StoredConfiguration?,
                        resources: any SubscriptionStorage) throws -> UUID {
        try Self.transaction {
            var library = try self.library()
            guard library.syncMutations?[id.uuidString] == expectedMutation,
                  allowCurrent || library.activeID != id else { throw SubscriptionError.staleRevision }
            let title = SubscriptionSummary.cleanName(title)
            guard !title.isEmpty else { throw SubscriptionError.invalidTitle }
            let position = library.entries.firstIndex { $0.id == id }
            if let expectedRecord {
                let current = try self.record(id)
                guard current.revisionID == expectedRecord.revisionID, current.source == expectedRecord.source,
                      current.choices == expectedRecord.choices, current.sourceURL == expectedRecord.sourceURL else {
                    throw SubscriptionError.staleRevision
                }
            } else if position != nil { throw SubscriptionError.staleRevision }
            guard position != nil || library.entries.count < 128 else { throw SubscriptionError.tooMany }
            var next = record
            if let position {
                let current = try self.record(id)
                next.revisionNumber = (current.revisionNumber ?? 1) + 1
                next.history = Array(([current.snapshotRevision] + (current.history ?? [])).prefix(5))
                next.lastUsable = current.verifiedAt != nil ? current.snapshotRevision : current.lastUsable
                if next.source == current.source { next.certificateConsentDigest = current.certificateConsentDigest }
                library.pendingDeletion.append(library.entries[position].storageID ?? id)
            }
            let key = UUID()
            let summary = SubscriptionSummary(id: id, title: uniqueTitle(title, entries: library.entries.filter { $0.id != id }),
                fileName: fileName.map(SubscriptionSummary.cleanName), importedAt: position.map { library.entries[$0].importedAt } ?? Date(),
                updatedAt: Date(), sourceDigest: digest(next.source), storageID: key,
                nodeCount: nodeCount, groupCount: groupCount, ruleCount: ruleCount)
            if let position { library.entries[position] = summary } else { library.entries.append(summary) }
            library.format = "clash-subscriptions-v2"
            library.noteMutation(id)
            // The scoped reader writes validated chunks into the destination vault.
            // Its staging namespace is separate from normal import previews and GC.
            try ConfigurationResourceStore.persist(next.source, storage: storage, sourceStorage: resources)
            try commitNewRecord(next, id: key, index: library)
            return library.syncMutations![id.uuidString]!
        }
    }

    @discardableResult func deleteReplica(_ id: UUID, expectedMutation: UUID?, allowCurrent: Bool) throws -> UUID? {
        try Self.transaction {
            let library = try self.library()
            guard library.syncMutations?[id.uuidString] == expectedMutation,
                  allowCurrent || library.activeID != id else { throw SubscriptionError.staleRevision }
            return try delete([id], performCleanup: false, notifyLocalChange: false).syncMutations?[id.uuidString]
        }
    }
}
