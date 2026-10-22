import CloudKit
import Foundation
import Testing
@testable import Horizon

@MainActor @Suite struct CloudAssetRecordTests {
    private let zone = CKRecordZone.ID(zoneName: "TestAssets")
    private let data = Data("FICTIONAL configuration resource".utf8)

    private func record() -> CKRecord {
        let digest = ConfigurationResourceStore.digest(data)
        let record = CKRecord(recordType: "HorizonAssetV1", recordID: .init(recordName: "a-" + digest, zoneID: zone))
        record.encryptedValues["digest"] = digest
        record.encryptedValues["bytes"] = data.count
        return record
    }

    @Test func conflictAcknowledgesVerifiedLocalContentWithoutDownloadedAsset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try CloudAssetCache(account: "test", root: root)
        let asset = try CloudAssetRecord(record(), zone: zone)
        try cache.put(data, digest: asset.digest)
        #expect(try asset.acknowledgeExisting(in: cache) == asset.digest)
    }

    @Test func conflictCannotAcknowledgeMissingOrCorruptLocalContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try CloudAssetCache(account: "test", root: root)
        let asset = try CloudAssetRecord(record(), zone: zone)
        #expect(throws: CloudSyncFailure.missingAsset) { try asset.acknowledgeExisting(in: cache) }
        try Data(repeating: 0, count: data.count).write(to: cache.url(asset.digest))
        #expect(throws: CloudSyncFailure.invalidPayload) { try asset.acknowledgeExisting(in: cache) }
    }

    @Test func rejectsMismatchedIdentityAndInvalidSize() throws {
        #expect(throws: CloudSyncFailure.invalidPayload) {
            try CloudAssetRecord(record(), zone: .init(zoneName: "Other"))
        }
        let wrongDigest = record()
        wrongDigest.encryptedValues["digest"] = String(repeating: "0", count: 64)
        #expect(throws: CloudSyncFailure.invalidPayload) { try CloudAssetRecord(wrongDigest, zone: zone) }
        for size in [0.0, -1.0, 1.5, Double(ConfigurationResourceStore.maximumResourceBytes) + 1] {
            let invalid = record()
            invalid.encryptedValues["bytes"] = NSNumber(value: size)
            #expect(throws: CloudSyncFailure.invalidPayload) { try CloudAssetRecord(invalid, zone: zone) }
        }
    }
}
