#if os(macOS)
import CloudKit
import Foundation

/// A read-only inventory independent of CKSyncEngine's incremental bookmarks.
/// Fetch metadata only; dependency files are fetched and validated by the importer.
nonisolated enum MacCloudSubscriptionInventory {
    struct Page: Sendable {
        let records: [CKRecord]
        let moreComing: Bool
    }

    static func load(database: CKDatabase, zone: CKRecordZone.ID) async throws -> [CKRecord] {
        let pager = Pager(database: database, zone: zone)
        return try await load { try await pager.next() }
    }

    static func load(nextPage: @Sendable () async throws -> Page) async throws -> [CKRecord] {
        var records: [CKRecord.ID: CKRecord] = [:]
        var examined = 0
        for _ in 0..<4096 {
            try Task.checkCancellation()
            let page = try await nextPage()
            examined += page.records.count
            guard examined <= 131_072 else { throw CloudSyncFailure.limit }
            for record in page.records where record.recordType == "HorizonSubscriptionV1" {
                records[record.recordID] = record
            }
            guard records.count <= 8192 else { throw CloudSyncFailure.limit }
            if !page.moreComing { return Array(records.values) }
        }
        throw CloudSyncFailure.limit
    }

    private actor Pager {
        let database: CKDatabase
        let zone: CKRecordZone.ID
        var token: CKServerChangeToken?

        init(database: CKDatabase, zone: CKRecordZone.ID) { self.database = database; self.zone = zone }

        func next() async throws -> Page {
            let result = try await database.recordZoneChanges(inZoneWith: zone, since: token,
                desiredKeys: ["payload", "digest", "bytes"], resultsLimit: 500)
            var records: [CKRecord] = []
            // A failed page must never look like a complete, empty inventory.
            for modification in result.modificationResultsByID.values {
                records.append(try modification.get().record)
            }
            guard !result.moreComing || result.changeToken != token else { throw CloudSyncFailure.persistence }
            token = result.changeToken
            return Page(records: records, moreComing: result.moreComing)
        }
    }
}
#endif
