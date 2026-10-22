import Foundation
import CryptoKit

/// Portable, secret-bearing metadata. Encoded only in CloudKit encrypted fields
/// or the protected local journal. Device choices, routing and approvals are absent.
nonisolated struct CloudSubscriptionVersion: Codable, Equatable, Sendable {
    var schema = 1
    var id: UUID
    var version = UUID()
    var parent: UUID?
    var title: String
    var fileName: String?
    var sourceURL: String?
    var originalDigest: String?
    var originalBytes = 0
    var resources: [ConfigurationSnapshot.Resource] = []
    var deleted = false

    func validate() throws {
        guard schema == 1, title == SubscriptionSummary.cleanName(title), !title.isEmpty,
              title.utf8.count <= 500,
              fileName == nil || fileName == SubscriptionSummary.cleanName(fileName!),
              sourceURL == nil || ConfigurationResources.validURL(sourceURL!),
              resources.count <= 35, Set(resources.map(\.key)).count == resources.count,
              resources.allSatisfy({ Self.validDigest($0.digest) && $0.bytes > 0 && $0.bytes <= ConfigurationResourceStore.maximumResourceBytes && $0.key.utf8.count <= 1024 && $0.bundledVersion == nil }),
              resources.reduce(0, { $0 + $1.bytes }) <= ConfigurationResourceStore.maximumTotalBytes,
              deleted ? (originalDigest == nil && originalBytes == 0 && resources.isEmpty && sourceURL == nil) :
                (originalDigest.map(Self.validDigest) == true && originalBytes > 0 && originalBytes <= PrototypeConfiguration.maximumBytes)
        else { throw CloudSyncFailure.invalidPayload }
    }
    static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    var contentIdentity: String {
        struct Content: Encodable { let sourceURL: String?; let digest: String?; let bytes: Int; let resources: [ConfigurationSnapshot.Resource]; let deleted: Bool }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(Content(sourceURL: sourceURL, digest: originalDigest, bytes: originalBytes,
            resources: resources.sorted { $0.key < $1.key }, deleted: deleted))) ?? Data()
        return ConfigurationResourceStore.digest(data)
    }
    func sameValue(as other: Self) -> Bool {
        title == other.title && fileName == other.fileName && contentIdentity == other.contentIdentity
    }
    /// Three-way merge: no clock ordering, and source URL/content/dependencies are
    /// one semantic field. Concurrent edits to that field require review.
    static func merge(base: Self?, local: Self, remote: Self) -> Self? {
        if local.sameValue(as: remote) { return remote }
        guard let base, !local.deleted, !remote.deleted, !base.deleted else { return nil }
        func field<T: Equatable>(_ before: T, _ a: T, _ b: T) -> T? {
            if a == b || b == before { return a }
            if a == before { return b }
            return nil
        }
        guard let title = field(base.title, local.title, remote.title),
              let name = field(base.fileName, local.fileName, remote.fileName),
              let content = field(base.contentIdentity, local.contentIdentity, remote.contentIdentity) else { return nil }
        var result = content == local.contentIdentity ? local : remote
        result.title = title; result.fileName = name
        result.version = UUID(); result.parent = remote.version
        return result
    }
    static func conflictCopyID(_ id: UUID, _ version: UUID) -> UUID {
        let bytes = Array(SHA256.hash(data: Data((id.uuidString + version.uuidString).utf8)))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

nonisolated enum CloudSyncFailure: Error, Equatable {
    case invalidPayload, missingAsset, accountChanged, unavailable, currentSubscription, conflict, persistence, limit
}
