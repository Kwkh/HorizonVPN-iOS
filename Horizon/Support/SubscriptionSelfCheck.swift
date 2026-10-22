import Foundation

/// Fake storage only: never accesses real Keychain items or the network.
nonisolated final class MemorySubscriptionStorage: SubscriptionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var writeFailure: String?
    private var removalFailures: Set<String> = []
    var items: [String: Data] {
        get { lock.withLock { values } }
        set { lock.withLock { values = newValue } }
    }
    var failingWriteKey: String? {
        get { lock.withLock { writeFailure } }
        set { lock.withLock { writeFailure = newValue } }
    }
    var failingRemovals: Set<String> {
        get { lock.withLock { removalFailures } }
        set { lock.withLock { removalFailures = newValue } }
    }
    func keys() throws -> [String] { lock.withLock { Array(values.keys) } }
    func read(_ key: String) throws -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, for key: String) throws {
        try lock.withLock {
            if key == writeFailure { throw PrototypeError.keychain }
            values[key] = data
        }
    }
    func remove(_ key: String) throws {
        try lock.withLock {
            if removalFailures.contains(key) { throw PrototypeError.keychain }
            values.removeValue(forKey: key)
        }
    }
}

enum SubscriptionSelfCheck {
    static func run() -> PrototypeSelfCheck.Result {
        var failures: [String] = [], total = 0
        func check(_ name: String, _ body: () throws -> Bool) {
            total += 1
            do { if try !body() { failures.append(name) } } catch { failures.append(name) }
        }
        let a = StoredConfiguration(source: Data("SYNTHETIC-A".utf8), choices: ["GROUP": "NODE-A"])
        let b = StoredConfiguration(source: Data("SYNTHETIC-B".utf8), choices: ["GROUP": "NODE-B"])
        func add(_ repo: SubscriptionRepository, _ value: StoredConfiguration, _ file: String, active: Bool = true) throws -> UUID {
            try repo.add(value, fileName: file, nodeCount: 2, groupCount: 1, ruleCount: 5, makeCurrent: active)
        }
        check("filename-title-and-control-cleanup") {
            SubscriptionSummary.title(from: "示例订阅.yaml") == "示例订阅" &&
            SubscriptionSummary.title(from: "example.YML") == "example" &&
            SubscriptionSummary.cleanName(" a\n\u{202E}b ") == "ab"
        }
        check("url-import-name-without-filename-and-retained-choices") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try repo.add(a, fileName: nil, displayTitle: "链接订阅", nodeCount: 2, groupCount: 1, ruleCount: 5, makeCurrent: true)
            guard try repo.library().entries[0].fileName == nil else { return false }
            try repo.saveChoices(["GROUP": "CHANGED"], for: first)
            let duplicate = try repo.add(a, fileName: nil, displayTitle: "新名称", nodeCount: 2, groupCount: 1, ruleCount: 5, makeCurrent: false)
            return try duplicate == first && repo.library().entries.count == 1 && repo.library().entries[0].title == "新名称" && repo.activeRecord()?.choices == ["GROUP": "CHANGED"]
        }
        check("url-reimport-preserves-local-source-filename") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml")
            _ = try repo.add(a, fileName: nil, displayTitle: "链接订阅", nodeCount: 2, groupCount: 1, ruleCount: 5, makeCurrent: false)
            return try repo.library().entries[0].fileName == "a.yaml" && repo.library().activeID == first
        }
        check("raw-legacy-migration") {
            let storage = MemorySubscriptionStorage(); storage.items[SubscriptionRepository.legacyKey] = a.source
            let repo = SubscriptionRepository(storage: storage), library = try repo.library()
            return try library.entries.count == 1 && library.entries[0].title == "原有订阅" &&
                (repo.activeRecord()?.source) == a.source && storage.items[SubscriptionRepository.legacyKey] == nil
        }
        check("v2-legacy-migration-retains-choices") {
            let storage = MemorySubscriptionStorage(); storage.items[SubscriptionRepository.legacyKey] = try JSONEncoder().encode(a)
            let repo = SubscriptionRepository(storage: storage)
            _ = try repo.library()
            return try repo.activeRecord()?.choices == a.choices
        }
        check("failed-migration-keeps-legacy") {
            let storage = MemorySubscriptionStorage(); storage.items[SubscriptionRepository.legacyKey] = a.source
            storage.failingWriteKey = SubscriptionRepository.indexKey
            do { _ = try SubscriptionRepository(storage: storage).library(); return false } catch { }
            return storage.items.count == 1 && storage.items[SubscriptionRepository.legacyKey] == a.source
        }
        check("records-switch-and-retain-own-choices") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml"), second = try add(repo, b, "b.yaml", active: false)
            try repo.saveChoices(["GROUP": "CHANGED"], for: first)
            try repo.activate(second)
            guard try repo.activeRecord()?.choices == b.choices else { return false }
            try repo.activate(first)
            return try repo.activeRecord()?.choices == ["GROUP": "CHANGED"] && repo.library().entries.count == 2
        }
        check("reimport-deduplicates-and-keeps-choices") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml")
            try repo.saveChoices(["GROUP": "CHANGED"], for: first)
            let duplicate = try add(repo, a, "renamed.yml")
            let library = try repo.library()
            return try first == duplicate && library.entries.count == 1 && library.entries[0].title == "renamed" &&
                (repo.activeRecord()?.choices) == ["GROUP": "CHANGED"]
        }
        check("same-filename-new-content-does-not-overwrite") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "same.yaml"), second = try add(repo, b, "same.yaml")
            let library = try repo.library()
            return try first != second && library.entries.map(\.title) == ["same", "same (2)"] && (repo.record(first).source) == a.source
        }
        check("failed-import-preserves-active-and-removes-staging") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml")
            let before = storage.items
            storage.failingWriteKey = SubscriptionRepository.indexKey
            do { _ = try add(repo, b, "b.yaml"); return false } catch { }
            return try storage.items == before && (repo.index()?.activeID) == first
        }
        check("rename-and-reload") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let id = try add(repo, a, "a.yaml")
            try repo.rename(id, title: " 自定义名称 ")
            let reloaded = try SubscriptionRepository(storage: storage).library()
            return reloaded.entries[0].title == "自定义名称" && reloaded.entries[0].fileName == "a.yaml" && reloaded.activeID == id
        }
        check("delete-inactive-preserves-current") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml"), second = try add(repo, b, "b.yaml", active: false)
            let library = try repo.delete([second])
            return library.activeID == first && library.entries.count == 1 && storage.items[SubscriptionRepository.recordKey(second)] == nil
        }
        check("delete-current-does-not-auto-select-or-resurrect") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml")
            _ = try add(repo, b, "b.yaml", active: false)
            let library = try repo.delete([first])
            return try library.activeID == nil && library.entries.count == 1 && (repo.activeRecord()) == nil
        }
        check("failed-delete-index-keeps-records") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml"), before = storage.items
            storage.failingWriteKey = SubscriptionRepository.indexKey
            do { _ = try repo.delete([first]); return false } catch { }
            return storage.items == before
        }
        check("cleanup-failure-is-visible-and-retryable") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            let first = try add(repo, a, "a.yaml")
            storage.failingRemovals = [SubscriptionRepository.recordKey(first)]
            let removed = try repo.delete([first])
            guard try removed.entries.isEmpty && removed.cleanupCount == 1 && (repo.activeRecord()) == nil else { return false }
            storage.failingRemovals = []
            return try repo.cleanup().cleanupCount == 0 && storage.items[SubscriptionRepository.recordKey(first)] == nil
        }
        check("abandoned-write-cleanup") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            _ = try add(repo, a, "a.yaml")
            let abandoned = SubscriptionRepository.recordKey(UUID()); storage.items[abandoned] = try JSONEncoder().encode(b)
            _ = try repo.library()
            return try storage.items[abandoned] == nil && (repo.activeRecord()?.source) == a.source
        }
        check("invalid-index-does-not-fall-back-to-legacy") {
            let storage = MemorySubscriptionStorage()
            storage.items[SubscriptionRepository.legacyKey] = a.source
            storage.items[SubscriptionRepository.indexKey] = Data("broken".utf8)
            do { _ = try SubscriptionRepository(storage: storage).activeRecord(); return false } catch { return true }
        }
        check("import-without-selecting") {
            let storage = MemorySubscriptionStorage(), repo = SubscriptionRepository(storage: storage)
            _ = try add(repo, a, "a.yaml", active: false)
            return try repo.library().entries.count == 1 && repo.activeRecord() == nil
        }
        check("delete-all-after-legacy-cleanup-failure") {
            let storage = MemorySubscriptionStorage(); storage.items[SubscriptionRepository.legacyKey] = a.source
            storage.failingRemovals = [SubscriptionRepository.legacyKey]
            let repo = SubscriptionRepository(storage: storage), original = try repo.library()
            let deleted = try repo.delete(Set(original.entries.map(\.id)))
            return try deleted.entries.isEmpty && deleted.cleanupCount == 1 && (repo.activeRecord()) == nil
        }
        return .init(passed: total - failures.count, total: total, failures: failures)
    }
}
