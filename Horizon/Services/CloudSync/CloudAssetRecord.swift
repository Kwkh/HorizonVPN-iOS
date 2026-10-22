import CloudKit
import Foundation

nonisolated struct CloudAssetRecord {
    let digest: String
    let bytes: Int

    init(_ record: CKRecord, zone: CKRecordZone.ID) throws {
        guard record.recordType == "HorizonAssetV1", record.recordID.zoneID == zone,
              let digest = record.encryptedValues["digest"] as? String,
              CloudSubscriptionVersion.validDigest(digest),
              record.recordID.recordName == "a-" + digest,
              let size = record.encryptedValues["bytes"] as? NSNumber,
              size.doubleValue > 0,
              size.doubleValue <= Double(ConfigurationResourceStore.maximumResourceBytes),
              size.doubleValue == Double(size.intValue) else { throw CloudSyncFailure.invalidPayload }
        self.digest = digest
        self.bytes = size.intValue
    }

    func acknowledgeExisting(in cache: CloudAssetCache) throws -> String {
        // A serverRecordChanged response deliberately has no downloaded CKAsset
        // fileURL. These immutable records are addressed by content digest: verify
        // the local bytes we tried to upload, then acknowledge the existing record.
        // Incoming assets still require a full download and digest validation.
        _ = try cache.read(digest, bytes: bytes)
        return digest
    }
}
