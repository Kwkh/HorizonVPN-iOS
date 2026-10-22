import Foundation
import CryptoKit

/// Internal, versioned envelope. Original subscription bytes are preserved verbatim.
/// Large immutable dependencies are stored once in protected Keychain chunks, never in logs.
nonisolated struct ConfigurationSnapshot: Codable, Sendable {
    static let prefix = Data("HORIZON-SNAPSHOT-1\n".utf8)
    struct Resource: Codable, Equatable, Sendable {
        let key: String
        let digest: String
        let bytes: Int
        var bundledVersion: String? = nil
    }
    let original: Data
    let resources: [Resource]
    var routing: ConfigurationRouting? = nil
    static func read(_ data: Data) throws -> Self? {
        guard data.starts(with: prefix) else { return nil }
        // JSON encodes original bytes as Base64; allow the bounded 1 MiB source plus envelope.
        guard data.count <= 2 * 1024 * 1024,
              let value = try? JSONDecoder().decode(Self.self, from: data.dropFirst(prefix.count)),
              value.original.count <= PrototypeConfiguration.maximumBytes,
              !value.original.starts(with: prefix), value.resources.count <= 35,
              Set(value.resources.map(\.key)).count == value.resources.count,
              value.resources.allSatisfy({ $0.bytes > 0 && $0.bytes <= ConfigurationResourceStore.maximumResourceBytes && $0.digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil && ($0.bundledVersion == nil || $0.bundledVersion?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil) }),
              value.resources.reduce(0, { $0 + $1.bytes }) <= ConfigurationResourceStore.maximumTotalBytes else {
            throw ConfigurationValidation.issue("订阅依赖快照损坏；原有版本未被替换。")
        }
        // Read snapshots saved by the retired mainland-routing experiment using
        // their original policy. Drop only Geo dependencies added by that option;
        // retain original dependencies and all normal snapshot validation.
        struct RetiredOptions: Decodable { let mainlandDirect: Bool? }
        if (try? JSONDecoder().decode(RetiredOptions.self, from: data.dropFirst(prefix.count)))?.mainlandDirect == true {
            let root = try ConfigurationInput.read(value.original, resolveResources: false).root
            let required = Set(try ConfigurationResources.plan(root).map(\.key))
            let addedGeoKeys: Set<String> = ["geo:geosite:dat", "geo:geoip:dat", "geo:geoip:mmdb"]
            return Self(original: value.original, resources: value.resources.filter {
                !addedGeoKeys.contains($0.key) || required.contains($0.key)
            })
        }
        return value
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return Self.prefix + (try encoder.encode(self))
    }
    static func original(_ data: Data) throws -> Data { try read(data)?.original ?? data }
}

/// Separate namespace from subscription records. A library commit is still the only activation point.
/// Pending bytes are process-local until the user confirms import/update.
nonisolated enum ConfigurationResourceStore {
    @TaskLocal static var scopedStorage: (any SubscriptionStorage)?
    static let maximumResourceBytes = 32 * 1024 * 1024
    static let maximumTotalBytes = 64 * 1024 * 1024
    static let chunkBytes = 256 * 1024
    private static let lock = NSLock()
    private static var pending: [String: Data] = [:]
    #if os(macOS)
    static var testStorage: (any SubscriptionStorage)?
    #endif
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func key(_ digest: String, _ index: Int) -> String { "dependency-v1-" + digest + "-" + String(index) }
    static func stage(_ values: [(String, Data)], original: Data, bundledVersions: [String: String] = [:], routing: ConfigurationRouting = .subscription) throws -> Data {
        guard !values.isEmpty || routing != .subscription else { return original }
        guard values.count <= 35, values.reduce(0, { $0 + $1.1.count }) <= maximumTotalBytes,
              values.allSatisfy({ !$0.1.isEmpty && $0.1.count <= maximumResourceBytes }) else {
            throw ConfigurationValidation.issue("依赖超过限制：最多 35 项、单项 32 MiB、总计 64 MiB。")
        }
        let resources = values.map { ConfigurationSnapshot.Resource(key: $0.0, digest: digest($0.1), bytes: $0.1.count, bundledVersion: bundledVersions[$0.0]) }
        lock.lock()
        let additions = Dictionary(values.map { (digest($0.1), $0.1) }, uniquingKeysWith: { a, _ in a })
        let merged = pending.merging(additions) { _, new in new }
        guard merged.values.reduce(0, { $0 + $1.count }) <= maximumTotalBytes else {
            lock.unlock()
            throw ConfigurationValidation.issue("候选依赖内存已达上限，请取消其他预览后重试。")
        }
        pending = merged
        lock.unlock()
        return try ConfigurationSnapshot(original: original, resources: resources.sorted { $0.key < $1.key }, routing: routing == .subscription ? nil : routing).encoded()
    }
    static func load(_ resource: ConfigurationSnapshot.Resource, storage: (any SubscriptionStorage)? = nil) throws -> Data {
        lock.lock(); let candidate = pending[resource.digest]; lock.unlock()
        if let candidate, candidate.count == resource.bytes { return candidate }
        let storage: any SubscriptionStorage = try storage ?? defaultStorage()
        var data = Data(); data.reserveCapacity(resource.bytes)
        for index in 0..<((resource.bytes + chunkBytes - 1) / chunkBytes) {
            guard let part = try storage.read(key(resource.digest, index)), part.count <= chunkBytes else {
                throw ConfigurationValidation.issue("依赖快照缺失；请手动刷新或回滚，未从网络自动补齐。")
            }
            data.append(part)
        }
        guard data.count == resource.bytes, digest(data) == resource.digest else { throw ConfigurationValidation.issue("依赖快照完整性检查失败。") }
        return data
    }
    static func write(_ resource: ConfigurationSnapshot.Resource, to url: URL, storage: (any SubscriptionStorage)? = nil) throws {
        lock.lock(); let staged = pending[resource.digest]; lock.unlock()
        if let staged {
            guard staged.count == resource.bytes, digest(staged) == resource.digest else { throw ConfigurationValidation.issue("依赖完整性失败。") }
            try staged.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return
        }
        let store = try storage ?? defaultStorage()
        let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw PrototypeError.coreStorage }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = try FileHandle(forWritingTo: temporary)
        defer { try? file.close() }
        var hash = SHA256(), bytes = 0
        for i in 0..<((resource.bytes + chunkBytes - 1) / chunkBytes) {
            // Security/Foundation may autorelease backing NSData buffers. Release each chunk
            // before reading the next one; a tunnel cannot retain a full Geo database here.
            try autoreleasepool {
                guard let part = try store.read(key(resource.digest, i)), part.count <= chunkBytes else { throw ConfigurationValidation.issue("依赖分片缺失。") }
                bytes += part.count; hash.update(data: part); try file.write(contentsOf: part)
            }
        }
        guard bytes == resource.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == resource.digest else { throw ConfigurationValidation.issue("依赖完整性失败。") }
        try file.synchronize()
        if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: url) }
    }
    private static func defaultStorage() throws -> any SubscriptionStorage {
        if let scopedStorage { return scopedStorage }
        #if os(iOS) || HORIZON_NATIVE_MAC
        return KeychainSubscriptionStorage()
        #else
        guard let testStorage else { throw ConfigurationValidation.issue("离线测试未配置依赖存储。") }
        return testStorage
        #endif
    }
    static func persist(_ source: Data, storage: any SubscriptionStorage, sourceStorage: (any SubscriptionStorage)? = nil) throws {
        guard let snapshot = try ConfigurationSnapshot.read(source) else { return }
        for resource in snapshot.resources {
            let data = try load(resource, storage: sourceStorage ?? storage)
            for (index, offset) in stride(from: 0, to: data.count, by: chunkBytes).enumerated() {
                let part = data.subdata(in: offset..<min(data.count, offset + chunkBytes))
                let name = key(resource.digest, index)
                if try storage.read(name) != part { try storage.write(part, for: name) }
            }
        }
    }
    static func discardPending() {
        lock.lock(); pending.removeAll(); lock.unlock()
        CompiledGeoCache.discardStaged()
    }
    /// Called only after an index commit; old/current/history/last-known-good all remain live.
    static func collect(sources: [Data], storage: any SubscriptionStorage) throws {
        #if os(macOS)
        // The native Mac app may save a new subscription while the extension keeps
        // running the old one. Both raw and compiled dependencies remain live until
        // the app observes a fully disconnected tunnel and releases this root.
        struct RunningRoot: Decodable { let record: StoredConfiguration }
        var sources = sources
        if let data = try storage.read("mac-running-configuration-v1") {
            sources.append(try JSONDecoder().decode(RunningRoot.self, from: data).record.source)
        }
        #endif
        try CompiledGeoCache.collect(sources: sources, storage: storage)
        var retained = Set<String>()
        for source in sources {
            for resource in try ConfigurationSnapshot.read(source)?.resources ?? [] {
                for i in 0..<((resource.bytes + chunkBytes - 1) / chunkBytes) { retained.insert(key(resource.digest, i)) }
            }
        }
        for key in try storage.keys() where key.hasPrefix("dependency-v1-") && !retained.contains(key) {
            try storage.remove(key)
        }
    }
}
