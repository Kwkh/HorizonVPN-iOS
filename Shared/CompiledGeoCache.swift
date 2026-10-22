import Foundation
import CryptoKit

/// Preflight compiles in the main app; the extension installs verified artifacts for
/// the exact source snapshot and pinned ABI instead of rebuilding large Geo categories.
nonisolated enum CompiledGeoCache {
    private static let namespace = "compiled-geo-v1-"
    private static let abi = "hako-9437767346a63957c60bf027b6d9fb27e51d89c4-mrs-v1"
    private static let directories = ["compiled-geosite", "compiled-geoip"]
    private static let chunk = 256 * 1024
    private static let lock = NSLock()
    private static var staged = Set<String>()
    private struct Entry: Codable { let path: String; let digest: String; let bytes: Int }
    private struct Manifest: Codable { let entries: [Entry] }
    private static func prefix(_ source: Data) -> String {
        namespace + ConfigurationResourceStore.digest(Data(abi.utf8) + source) + "-"
    }
    private static func valid(_ entry: Entry) -> Bool {
        let p = entry.path.split(separator: "/", omittingEmptySubsequences: false)
        return p.count == 2 && directories.contains(String(p[0])) && !p[1].contains("..") &&
            p[1].range(of: "^[a-z0-9_@!,.\\-]+\\.mrs$", options: .regularExpression) != nil &&
            entry.digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil &&
            entry.bytes > 0 && entry.bytes <= 8 * 1024 * 1024
    }
    static func publish(source: Data, directory: URL, storage: any SubscriptionStorage) throws {
        guard try ConfigurationSnapshot.read(source)?.resources.contains(where: { $0.key == "geo:geosite:dat" || $0.key == "geo:geoip:dat" }) == true else { return }
        let base = prefix(source)
        lock.lock(); staged.insert(base); lock.unlock()
        var entries: [Entry] = [], total = 0
        for folder in directories {
            let root = directory.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey]).sorted(by: { $0.path < $1.path }) where url.pathExtension == "mrs" {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw PrototypeError.coreStorage }
                let data = try Data(contentsOf: url)
                let entry = Entry(path: folder + "/" + url.lastPathComponent, digest: ConfigurationResourceStore.digest(data), bytes: data.count)
                total += data.count
                guard valid(entry), total <= 16 * 1024 * 1024, entries.count < 128 else { throw PrototypeError.coreStorage }
                for (i, offset) in stride(from: 0, to: data.count, by: chunk).enumerated() {
                    try storage.write(data.subdata(in: offset..<min(offset + chunk, data.count)), for: base + entry.digest + "-" + String(i))
                }
                entries.append(entry)
            }
        }
        guard !entries.isEmpty else { throw PrototypeError.coreValidation }
        // Commit last; an interrupted preflight cannot expose half an artifact set.
        try storage.write(JSONEncoder().encode(Manifest(entries: entries)), for: base + "manifest")
    }
    static func restore(source: Data, directory: URL, storage: any SubscriptionStorage) throws -> Bool {
        let base = prefix(source)
        guard let data = try storage.read(base + "manifest") else { return false }
        guard data.count <= 128 * 1024, let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.entries.isEmpty, manifest.entries.count <= 128,
              manifest.entries.allSatisfy(valid), Set(manifest.entries.map(\.path)).count == manifest.entries.count,
              manifest.entries.reduce(0, { $0 + $1.bytes }) <= 16 * 1024 * 1024 else { throw PrototypeError.coreStorage }
        for folder in directories {
            let url = directory.appendingPathComponent(folder)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for entry in manifest.entries {
            let url = directory.appendingPathComponent(entry.path)
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw PrototypeError.coreStorage }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            var hash = SHA256(), count = 0
            for i in 0..<((entry.bytes + chunk - 1) / chunk) {
                try autoreleasepool {
                    guard let bytes = try storage.read(base + entry.digest + "-" + String(i)), bytes.count <= chunk else { throw PrototypeError.coreStorage }
                    count += bytes.count; hash.update(data: bytes); try file.write(contentsOf: bytes)
                }
            }
            guard count == entry.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == entry.digest else { throw PrototypeError.coreStorage }
        }
        return true
    }
    static func collect(sources: [Data], storage: any SubscriptionStorage) throws {
        let live = Set(sources.map(prefix))
        lock.lock(); let retained = live.union(staged); lock.unlock()
        for key in try storage.keys() where key.hasPrefix(namespace) && !retained.contains(where: { key.hasPrefix($0) }) { try storage.remove(key) }
    }
    static func discardStaged() { lock.lock(); staged.removeAll(); lock.unlock() }
}
