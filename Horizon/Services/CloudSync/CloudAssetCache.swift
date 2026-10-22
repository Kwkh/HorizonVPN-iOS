import Foundation

/// Separate, protected, non-backed-up staging. Filenames are generated from
/// validated digests, never from server paths or provider names.
nonisolated final class CloudAssetCache: @unchecked Sendable {
    let directory: URL
    init(account: String, root: URL? = nil) throws {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSyncStaging", isDirectory: true)
        directory = root.appendingPathComponent(ConfigurationResourceStore.digest(Data(account.utf8)), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func url(_ digest: String) throws -> URL {
        guard CloudSubscriptionVersion.validDigest(digest) else { throw CloudSyncFailure.invalidPayload }
        return directory.appendingPathComponent(digest)
    }
    func put(_ data: Data, digest: String) throws {
        guard !data.isEmpty, data.count <= ConfigurationResourceStore.maximumResourceBytes,
              ConfigurationResourceStore.digest(data) == digest else { throw CloudSyncFailure.invalidPayload }
        let destination = try url(digest)
        if FileManager.default.fileExists(atPath: destination.path), (try? read(digest, bytes: data.count)) != nil { return }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func importFile(_ url: URL, digest: String, bytes: Int) throws {
        guard bytes > 0, bytes <= ConfigurationResourceStore.maximumResourceBytes,
              try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes else { throw CloudSyncFailure.invalidPayload }
        try put(Data(contentsOf: url, options: .mappedIfSafe), digest: digest)
    }
    func read(_ digest: String, bytes: Int) throws -> Data {
        let url = try url(digest)
        guard bytes > 0, bytes <= ConfigurationResourceStore.maximumResourceBytes,
              (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == bytes else { throw CloudSyncFailure.missingAsset }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard ConfigurationResourceStore.digest(data) == digest else { throw CloudSyncFailure.invalidPayload }
        return data
    }
    func contains(_ digest: String, bytes: Int) -> Bool {
        guard let url = try? url(digest) else { return false }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == bytes
    }
    func chunk(_ resource: ConfigurationSnapshot.Resource, index: Int) throws -> Data? {
        let count = (resource.bytes + ConfigurationResourceStore.chunkBytes - 1) / ConfigurationResourceStore.chunkBytes
        guard index >= 0, index < count else { return nil }
        let url = try url(resource.digest)
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == resource.bytes else { throw CloudSyncFailure.missingAsset }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let offset = index * ConfigurationResourceStore.chunkBytes
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: min(ConfigurationResourceStore.chunkBytes, resource.bytes - offset))
    }
}

/// Task-scoped reader for native preflight and replica commit. Writes go to the
/// destination vault; reads can resolve cloud chunks without touching import pending.
nonisolated struct CloudResourceStorage: SubscriptionStorage {
    let cache: CloudAssetCache
    let resources: [ConfigurationSnapshot.Resource]
    let destination: any SubscriptionStorage
    func keys() throws -> [String] { try destination.keys() }
    func read(_ key: String) throws -> Data? {
        for resource in resources {
            let prefix = "dependency-v1-" + resource.digest + "-"
            if key.hasPrefix(prefix), let index = Int(key.dropFirst(prefix.count)), index >= 0 {
                return try cache.chunk(resource, index: index)
            }
        }
        return try destination.read(key)
    }
    func write(_ data: Data, for key: String) throws { try destination.write(data, for: key) }
    func remove(_ key: String) throws { try destination.remove(key) }
}
