import Foundation
import CloudKit

nonisolated enum CloudSyncScope {
    #if DEBUG
    static let environment = "Development"
    #else
    static let environment = "Production"
    #endif
    static var accountKey: String { "icloud-account-v1-" + environment }
    static func identity(_ account: String) -> String { environment + ":" + account }
}

nonisolated struct CloudSyncEntry: Codable, Sendable {
    enum Review: String, Codable, Hashable { case current, conflict, invalid }
    var localID: UUID?
    var observedMutation: UUID?
    var installed: CloudSubscriptionVersion?
    var base: CloudSubscriptionVersion?
    var outgoing: CloudSubscriptionVersion?
    var incoming: CloudSubscriptionVersion?
    var systemFields: Data?
    var review: Review?
}

nonisolated struct CloudSyncJournal: Codable, Sendable {
    var schema = 1
    var engine: CKSyncEngine.State.Serialization?
    var entries: [UUID: CloudSyncEntry] = [:]
    var fetched: [UUID: CloudSubscriptionVersion] = [:]
    var knownAssets: Set<String> = []
    var quarantined: [UUID: Data] = [:]
    var lastSync: Date?

    static func load(account: String, storage: any SubscriptionStorage) throws -> Self {
        guard let data = try storage.read(key(account)) else { return Self() }
        guard data.count <= 16 * 1024 * 1024,
              let journal = try? JSONDecoder().decode(Self.self, from: data), journal.schema == 1 else { throw CloudSyncFailure.persistence }
        guard journal.entries.count <= 8192, journal.fetched.count <= 8192,
              journal.quarantined.count <= 8192,
              journal.quarantined.values.allSatisfy({ $0.count <= 64 * 1024 }),
              journal.knownAssets.allSatisfy(CloudSubscriptionVersion.validDigest) else { throw CloudSyncFailure.persistence }
        for entry in journal.entries.values {
            for value in [entry.installed, entry.base, entry.outgoing, entry.incoming].compactMap({ $0 }) { try value.validate() }
        }
        for value in journal.fetched.values { try value.validate() }
        return journal
    }
    static func key(_ account: String) -> String { "icloud-journal-v1-" + ConfigurationResourceStore.digest(Data(account.utf8)) }
    func save(account: String, storage: any SubscriptionStorage) throws {
        let data = try JSONEncoder().encode(self)
        guard data.count <= 16 * 1024 * 1024, entries.count <= 8192, fetched.count <= 8192,
              quarantined.count <= 8192 else { throw CloudSyncFailure.limit }
        try storage.write(data, for: Self.key(account))
    }

    func outgoingVersion(_ id: UUID) -> CloudSubscriptionVersion? {
        // A fetched server change tag must never authorize writing the old local
        // payload before the three-way merge or explicit conflict review.
        guard fetched[id] == nil, quarantined[id] == nil,
              let entry = entries[id], entry.review != .conflict else { return nil }
        return entry.outgoing
    }

    var hasPendingTransfers: Bool {
        !fetched.isEmpty || entries.values.contains {
            ($0.outgoing != nil && $0.review != .conflict) || ($0.incoming != nil && $0.review == nil)
        }
    }

    var remoteVersions: [UUID: UUID] {
        var versions = entries.compactMapValues { $0.base?.version }
        for (id, value) in fetched { versions[id] = value.version }
        return versions
    }

    mutating func acknowledgeInstallation(_ id: UUID, value: CloudSubscriptionVersion, mutation: UUID?) {
        guard var entry = entries[id] else { return }
        entry.installed = value
        entry.observedMutation = mutation
        // Do not discard a newer remote revision delivered during an async import.
        if entry.incoming?.version == value.version {
            entry.incoming = nil
            entry.review = nil
        }
        entries[id] = entry
    }

    mutating func reconcileFetched() {
        for (id, remote) in fetched {
            var entry = entries[id] ?? CloudSyncEntry()
            if entry.localID == nil, !remote.deleted {
                if let duplicate = entries.values.first(where: {
                    $0.localID != nil && $0.installed?.sameValue(as: remote) == true
                }) {
                    entry.localID = duplicate.localID; entry.installed = duplicate.installed
                    entry.observedMutation = duplicate.observedMutation
                } else { entry.localID = id }
            }
            if let outgoing = entry.outgoing {
                if outgoing.sameValue(as: remote) {
                    entry.outgoing = nil
                    entry.incoming = entry.installed?.sameValue(as: remote) == true ? nil : remote
                    if entry.incoming == nil { entry.review = nil }
                } else if entry.review == .conflict {
                    // Repeated delivery does not turn an unresolved conflict into
                    // permission to overwrite the remote branch.
                    entry.incoming = remote
                } else if let merged = CloudSubscriptionVersion.merge(base: entry.base, local: outgoing, remote: remote) {
                    entry.outgoing = merged.sameValue(as: remote) ? nil : merged
                    entry.incoming = entry.installed?.sameValue(as: merged) == true ? nil : merged
                    if entry.incoming == nil { entry.review = nil }
                } else {
                    entry.incoming = remote; entry.review = .conflict
                }
            } else if entry.installed?.sameValue(as: remote) != true {
                entry.incoming = remote
                // A previously reviewed revision is replaced by a new revision;
                // re-evaluate current-subscription protection when applying it.
                entry.review = nil
            } else { entry.incoming = nil; entry.review = nil }
            entry.base = remote
            entries[id] = entry
            fetched[id] = nil
        }
    }
}

nonisolated struct CloudSyncReviewItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let version: UUID
    let localID: UUID?
    let title: String
    let deleted: Bool
    let reason: CloudSyncEntry.Review
}

nonisolated struct CloudSyncSnapshot: Sendable {
    enum Status: Sendable, Equatable { case off, syncing, ready, noAccount, accountChanged, failed, quota, configuration, waiting }
    var status: Status
    var lastSync: Date?
    var reviews: [CloudSyncReviewItem] = []
    var libraryChanged = false
    var blockedCount = 0
}
