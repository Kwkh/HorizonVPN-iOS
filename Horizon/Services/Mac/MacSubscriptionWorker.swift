#if os(macOS)
import Foundation
import Hako

/// Parsing, dependency preparation and Keychain transactions never run on the UI actor.
actor MacSubscriptionWorker {
    struct Snapshot: Sendable {
        let index: SubscriptionIndex
        let prepared: PrototypeConfiguration.Prepared?
        let identity: String
        let usage: [UUID: SubscriptionDownloader.Usage]
        let probeScope: String
        let routing: ConfigurationRouting
    }
    struct Preview: Identifiable, Sendable {
        let id = UUID()
        let prepared: PrototypeConfiguration.Prepared
        let fileName: String?
        let sourceURL: String?
        let title: String
        var usage: SubscriptionDownloader.Usage? = nil
    }
    nonisolated let repository: SubscriptionRepository
    let offline: Bool
    private var probeRuntimeReady = false

    init(offline: Bool, offlineStorage: (any SubscriptionStorage)? = nil) {
        self.offline = offline
        repository = SubscriptionRepository(storage: offline ? (offlineStorage ?? MacMemoryStorage()) : KeychainSubscriptionStorage())
    }
    func seedOffline() throws {
        guard offline, try repository.index() == nil else { return }
        // Reserved .invalid hosts; fixtures are also rejected by the tunnel provider.
        for title in ["Demo · Personal", "Demo · Travel"] {
            let source = Data(Self.fixture.replacingOccurrences(of: "DEMO-NODE", with: title).utf8)
            let prepared = try PrototypeConfiguration.prepare(source)
            var record = StoredConfiguration(source: source, choices: prepared.catalog.choices)
            record.sourceURL = "https://subscription.example.invalid/" + (title == "Demo · Personal" ? "personal" : "travel")
            let id = try repository.add(record,
                fileName: nil, displayTitle: title, nodeCount: prepared.catalog.nodes.count,
                groupCount: prepared.catalog.groups.count, ruleCount: prepared.ruleCount, makeCurrent: true)
            if title == "Demo · Personal" {
                updateUsage(id, usage: SubscriptionDownloader.Usage.parse("upload=300000000; download=29000000000; total=100000000000"))
            }
        }
    }
    func load(useRunning: Bool = false) throws -> Snapshot {
        try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            let index = try repository.library()
            let running = useRunning ? try runningRecord() : nil
            guard running == nil || running?.id == index.activeID else { throw SubscriptionError.staleRevision }
            let record = try running?.record ?? repository.activeRecord()
            let prepared = try record.map { try PrototypeConfiguration.prepare($0.source, choices: $0.choices) }
            return Snapshot(index: index, prepared: prepared, identity: prepared.map { RuntimeIdentity.fingerprint(source: $0.source, choices: $0.catalog.choices) } ?? "", usage: usageSnapshot().filter { id, _ in index.entries.contains { $0.id == id } },
                probeScope: (index.activeID?.uuidString ?? "") + (record?.contentDigest ?? ""),
                routing: try record.map { try ConfigurationRouting.mode(in: $0.source) } ?? .subscription)
        }
    }
    // A protected, durable copy of the running source keeps node indexes and dependencies
    // alive even after multiple refreshes evict its ordinary revision history.
    private struct Running: Codable {
        let id: UUID
        var record: StoredConfiguration
        var sessionID: UUID?
    }
    private static let runningKey = "mac-running-configuration-v1"
    private func runningRecord() throws -> Running? {
        guard let data = try repository.storage.read(Self.runningKey) else { return nil }
        return try JSONDecoder().decode(Running.self, from: data)
    }
    func pinRunning(identity: String, sessionID: UUID? = nil) throws {
        if var running = try runningRecord(), running.id == (try repository.index()?.activeID),
           RuntimeIdentity.fingerprint(source: running.record.source, choices: running.record.choices) == identity,
           running.sessionID == nil || sessionID == nil || running.sessionID == sessionID {
            if let sessionID, running.sessionID == nil {
                running.sessionID = sessionID
                try repository.storage.write(JSONEncoder().encode(running), for: Self.runningKey)
            }
            return
        }
        guard let id = try repository.index()?.activeID else { throw PrototypeError.missingConfiguration }
        var record = try repository.record(id)
        let prepared = try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            try PrototypeConfiguration.prepare(record.source, choices: record.choices)
        }
        record.choices = prepared.catalog.choices
        guard RuntimeIdentity.fingerprint(source: record.source, choices: record.choices) == identity else { throw SubscriptionError.staleRevision }
        record.history = nil; record.lastUsable = nil
        // The resource collector treats this record as a live root for both processes.
        try repository.storage.write(JSONEncoder().encode(Running(id: id, record: record, sessionID: sessionID)), for: Self.runningKey)
    }
    func releaseRunning() throws {
        if let running = try runningRecord(), let saved = try? repository.record(running.id) {
            let prepared = try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
                try PrototypeConfiguration.prepare(saved.source, choices: saved.choices)
            }
            var choices = prepared.catalog.choices
            // Preserve manual choices by name only when they still exist in the next version.
            for group in prepared.catalog.groups where group.allowsSelection {
                if let member = running.record.choices[group.name], group.members.contains(member) { choices[group.name] = member }
            }
            if choices != prepared.catalog.choices { try repository.saveChoices(choices, for: running.id) }
        }
        try repository.storage.remove(Self.runningKey)
    }
    func importDroppedFile(_ file: URL, makeCurrent: Bool) async throws {
        defer { ConfigurationResourceStore.discardPending() }
        let candidate = try await preview(file: file)
        try Task.checkCancellation()
        try save(candidate, title: candidate.title, makeCurrent: makeCurrent)
    }
    func preview(file: URL) async throws -> Preview {
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        guard try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]).isRegularFile == true,
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= PrototypeConfiguration.maximumBytes else { throw PrototypeError.invalidFile }
        // A bounded read also covers files changing after the metadata check.
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PrototypeConfiguration.maximumBytes + 1) ?? Data()
        guard data.count <= PrototypeConfiguration.maximumBytes else { throw PrototypeError.invalidFile }
        return try await preview(data: data, fileName: file.lastPathComponent, sourceURL: nil,
                                 title: SubscriptionSummary.title(from: file.lastPathComponent))
    }
    func preview(link: String) async throws -> Preview {
        guard !offline else { throw SubscriptionDownloader.Failure.offline }
        let payload = try await SubscriptionImportLoader.load(link, permitsNetwork: true)
        var result = try await preview(data: payload.data, fileName: nil, sourceURL: payload.sourceURL,
                                       title: MacText.value("URL 订阅", "URL configuration"))
        result.usage = payload.usage
        return result
    }
    private func preview(data: Data, fileName: String?, sourceURL: String?, title: String) async throws -> Preview {
        try await ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            let source = try await SubscriptionResourceLoader.prepare(data, permitsNetwork: !offline)
            try Task.checkCancellation()
            let prepared = try PrototypeConfiguration.prepare(source)
            if !offline { try SubscriptionResourceLoader.preflight(prepared) }
            return Preview(prepared: prepared, fileName: fileName, sourceURL: sourceURL, title: title)
        }
    }
    func save(_ preview: Preview, title: String, makeCurrent: Bool) throws {
        var record = StoredConfiguration(source: preview.prepared.source, choices: preview.prepared.catalog.choices)
        record.sourceURL = preview.sourceURL
        let id = try repository.add(record, fileName: preview.fileName, displayTitle: title,
            nodeCount: preview.prepared.catalog.nodes.count, groupCount: preview.prepared.catalog.groups.count,
            ruleCount: preview.prepared.ruleCount, makeCurrent: makeCurrent)
        updateUsage(id, usage: preview.usage)
        ConfigurationResourceStore.discardPending()
    }
    func cloudIndex() throws -> SubscriptionIndex { try repository.library() }
    func cancelPreview() { ConfigurationResourceStore.discardPending() }
    func validateActivation(_ id: UUID) throws {
        try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            let record = try repository.record(id)
            _ = try PrototypeConfiguration.prepare(record.source, choices: record.choices)
        }
    }
    func activate(_ id: UUID) throws {
        try validateActivation(id)
        try repository.activate(id)
    }
    func select(group: Int, member: String) throws {
        let snapshot = try load()
        guard let id = snapshot.index.activeID, let prepared = snapshot.prepared,
              let group = prepared.catalog.groups.first(where: { $0.id == group }),
              group.allowsSelection, group.members.contains(member) else { throw PrototypeError.missingConfiguration }
        var choices = prepared.catalog.choices
        choices[group.name] = member
        try repository.saveChoices(choices, for: id)
    }
    func requireCertificateConsent(useRunning: Bool = false) throws -> String? {
        let running = useRunning ? try runningRecord() : nil
        guard let stored = try running?.record ?? repository.activeRecord(), let prepared = try load(useRunning: useRunning).prepared else { throw PrototypeError.missingConfiguration }
        guard !prepared.isFixture, !offline else { throw PrototypeError.missingConfiguration }
        do { try stored.requireCertificateConsent(for: prepared); return nil }
        catch PrototypeError.certificateConsent { return stored.contentDigest }
    }
    func approveCertificate(_ digest: String) throws {
        guard let id = try repository.index()?.activeID else { throw PrototypeError.missingConfiguration }
        try repository.approveInsecureCertificates(id, expectedDigest: digest)
    }
    struct Selection: Sendable {
        let id: UUID
        let expected: StoredConfiguration
        let updated: PrototypeConfiguration.Prepared
        let group: Int
        let member: Int
        let previous: Int
        let before: String
        let after: String
        var usesRunning: Bool = false
    }
    func prepareSelection(group index: Int, member: String, useRunning: Bool = false) throws -> Selection {
        let running = useRunning ? try runningRecord() : nil
        guard let id = try running?.id ?? repository.index()?.activeID else { throw PrototypeError.missingConfiguration }
        var stored = try running?.record ?? repository.record(id)
        return try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            let current = try PrototypeConfiguration.prepare(stored.source, choices: stored.choices)
            guard let group = current.catalog.groups.first(where: { $0.id == index }), group.allowsSelection,
                  let memberIndex = group.members.firstIndex(of: member) else { throw PrototypeError.missingConfiguration }
            stored.choices = current.catalog.choices
            var choices = stored.choices; choices[group.name] = member
            let updated = try PrototypeConfiguration.prepare(stored.source, choices: choices)
            return Selection(id: id, expected: stored, updated: updated,
                group: index, member: memberIndex, previous: group.members.firstIndex(of: stored.choices[group.name] ?? "") ?? 0,
                before: RuntimeIdentity.fingerprint(source: stored.source, choices: stored.choices),
                after: RuntimeIdentity.fingerprint(source: stored.source, choices: updated.catalog.choices), usesRunning: running != nil)
        }
    }
    func commitSelection(_ selection: Selection) throws {
        if selection.usesRunning {
            guard var running = try runningRecord(), running.id == selection.id,
                  running.record.revisionID == selection.expected.revisionID,
                  running.record.source == selection.expected.source,
                  running.record.choices == selection.expected.choices else { throw SubscriptionError.staleRevision }
            running.record.choices = selection.updated.catalog.choices
            try repository.storage.write(JSONEncoder().encode(running), for: Self.runningKey)
            return
        }
        guard try repository.index()?.activeID == selection.id else { throw SubscriptionError.staleRevision }
        let stored = try repository.record(selection.id)
        let current = try PrototypeConfiguration.prepare(stored.source, choices: stored.choices)
        guard stored.revisionID == selection.expected.revisionID, stored.source == selection.expected.source,
              current.catalog.choices == selection.expected.choices else { throw SubscriptionError.staleRevision }
        try repository.saveChoices(selection.updated.catalog.choices, for: selection.id)
    }
    struct RevisionPreview: Identifiable, Sendable {
        let id = UUID()
        let subscriptionID: UUID
        let expected: StoredConfiguration
        let prepared: PrototypeConfiguration.Prepared
        let changes: [String]
    }
    struct RoutingChange: Sendable {
        let revision: RevisionPreview
        let runningIdentity: String?
    }
    /// Uses the same opt-in overlay and cached/bundled resources as mobile.
    /// Preparation never downloads, rewrites the original YAML, or changes the saved revision.
    func stageRouting(_ mode: ConfigurationRouting, useRunning: Bool = false,
                      bundledDirectory: URL? = nil) async throws -> RoutingChange {
        try await ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            guard let id = try repository.index()?.activeID else { throw PrototypeError.missingConfiguration }
            let stored = try repository.record(id)
            let running = useRunning ? try runningRecord() : nil
            guard !useRunning || running?.id == id else { throw SubscriptionError.staleRevision }
            let source = try await SubscriptionResourceLoader.prepare(ConfigurationSnapshot.original(stored.source),
                permitsNetwork: false, previousSource: stored.source, routing: mode,
                reuseDependencies: true, bundledDirectory: bundledDirectory)
            let base = try PrototypeConfiguration.prepare(source)
            var choices = base.catalog.choices
            for group in base.catalog.groups where group.allowsSelection {
                if let member = (running?.record.choices ?? stored.choices)[group.name], group.members.contains(member) {
                    choices[group.name] = member
                }
            }
            let prepared = try PrototypeConfiguration.prepare(source, choices: choices)
            if !offline { try SubscriptionResourceLoader.preflight(prepared) }
            try Task.checkCancellation()
            return RoutingChange(revision: RevisionPreview(subscriptionID: id, expected: stored, prepared: prepared,
                changes: try SubscriptionChangeSummary.compare(stored.source, source)),
                runningIdentity: running.map { RuntimeIdentity.fingerprint(source: $0.record.source, choices: $0.record.choices) })
        }
    }
    func commitRouting(_ change: RoutingChange) throws -> StoredConfiguration {
        let preview = change.revision
        guard try repository.index()?.activeID == preview.subscriptionID else { throw SubscriptionError.staleRevision }
        if let identity = change.runningIdentity {
            guard let running = try runningRecord(), running.id == preview.subscriptionID,
                  RuntimeIdentity.fingerprint(source: running.record.source, choices: running.record.choices) == identity else {
                throw SubscriptionError.staleRevision
            }
        }
        try applyRefresh(preview)
        return try repository.record(preview.subscriptionID)
    }
    /// Failed startup restores only the exact revision this transaction committed.
    /// A newer writer is never overwritten, and failed startup never grants certificate consent.
    func rollbackRouting(_ change: RoutingChange, committed: StoredConfiguration) throws {
        let preview = change.revision
        guard try repository.index()?.activeID == preview.subscriptionID else { throw SubscriptionError.staleRevision }
        let original = preview.expected
        try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            let prepared = try PrototypeConfiguration.prepare(original.source, choices: original.choices)
            try repository.replace(preview.subscriptionID, expected: committed, source: original.source,
                choices: original.choices, sourceURL: original.sourceURL,
                nodeCount: prepared.catalog.nodes.count, groupCount: prepared.catalog.groups.count, ruleCount: prepared.ruleCount,
                verifiedAt: original.verifiedAt)
            if original.certificateConsentDigest == original.contentDigest {
                try repository.approveInsecureCertificates(preview.subscriptionID, expectedDigest: original.contentDigest)
            }
        }
        try repository.storage.remove(Self.runningKey)
    }
    struct ManagementInfo: Sendable {
        struct Revision: Identifiable, Sendable {
            let id: UUID
            let number: Int
            let date: Date
        }
        let revisionNumber: Int
        let canRefresh: Bool
        let history: [Revision]
    }
    // Menus receive metadata only; YAML, credentials and source URLs stay in the worker.
    func managementInfo(_ id: UUID) throws -> ManagementInfo {
        let stored = try repository.record(id)
        return ManagementInfo(revisionNumber: stored.revisionNumber ?? 1, canRefresh: stored.sourceURL != nil,
            history: (stored.history ?? []).map { .init(id: $0.id, number: $0.number, date: $0.date) })
    }
    func stageRevision(_ id: UUID, revisionID: UUID) async throws -> RevisionPreview {
        guard let revision = try repository.record(id).history?.first(where: { $0.id == revisionID }) else {
            throw SubscriptionError.staleRevision
        }
        return try await stageRevision(id, revision: revision)
    }
    func record(_ id: UUID) throws -> StoredConfiguration { try repository.record(id) }
    func rename(_ id: UUID, title: String) throws { try repository.rename(id, title: title) }
    func delete(_ id: UUID) throws {
        _ = try repository.delete([id])
        updateUsage(id, usage: nil)
    }
    private static let usageKey = "mac-account-usage-v1"
    func usageSnapshot() -> [UUID: SubscriptionDownloader.Usage] {
        guard let data = try? repository.storage.read(Self.usageKey),
              let value = try? JSONDecoder().decode([UUID: SubscriptionDownloader.Usage].self, from: data) else { return [:] }
        return value
    }
    private func updateUsage(_ id: UUID, usage: SubscriptionDownloader.Usage?) {
        var values = usageSnapshot()
        values[id] = usage
        // Optional display metadata cannot turn a committed import into a reported failure.
        if let data = try? JSONEncoder().encode(values) { try? repository.storage.write(data, for: Self.usageKey) }
    }
    func stageRevision(_ id: UUID, revision: SubscriptionRevision? = nil) async throws -> RevisionPreview {
        try await ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            let stored = try repository.record(id)
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            let data: Data
            var usage: SubscriptionDownloader.Usage?
            if let revision {
                guard stored.history?.contains(where: { $0.id == revision.id }) == true else { throw SubscriptionError.staleRevision }
                data = revision.source
            } else {
                guard !offline, let link = stored.sourceURL else { throw SubscriptionError.missingEntry }
                let response = try await SubscriptionDownloader.fetchResponse(link, deadline: deadline)
                data = response.data; usage = response.usage
            }
            let source = try await SubscriptionResourceLoader.prepare(ConfigurationSnapshot.original(data), permitsNetwork: !offline && revision == nil,
                previousSource: revision?.source ?? stored.source,
                routing: try ConfigurationRouting.mode(in: revision?.source ?? stored.source), reuseDependencies: revision != nil, deadline: deadline)
            let base = try PrototypeConfiguration.prepare(source)
            let choices = (revision?.choices ?? stored.choices).filter { key, value in
                base.catalog.groups.contains { $0.name == key && $0.allowsSelection && $0.members.contains(value) }
            }
            let prepared = try PrototypeConfiguration.prepare(source, choices: choices)
            if !offline { try SubscriptionResourceLoader.preflight(prepared) }
            try Task.checkCancellation()
            // Usage describes the live account, so history rollback must not rewind it.
            if revision == nil { updateUsage(id, usage: usage) }
            return RevisionPreview(subscriptionID: id, expected: stored, prepared: prepared,
                changes: try SubscriptionChangeSummary.compare(stored.source, source))
        }
    }
    func applyRefresh(_ preview: RevisionPreview) throws {
        if preview.prepared.source == preview.expected.source && preview.prepared.catalog.choices == preview.expected.choices {
            let current = try repository.record(preview.subscriptionID)
            guard current.revisionID == preview.expected.revisionID, current.source == preview.expected.source,
                  current.choices == preview.expected.choices, current.sourceURL == preview.expected.sourceURL else {
                throw SubscriptionError.staleRevision
            }
            // Account usage can change without creating an identical configuration revision.
            ConfigurationResourceStore.discardPending()
        } else {
            try apply(preview)
        }
    }
    func apply(_ preview: RevisionPreview) throws {
        try repository.replace(preview.subscriptionID, expected: preview.expected, source: preview.prepared.source,
            choices: preview.prepared.catalog.choices, sourceURL: preview.expected.sourceURL,
            nodeCount: preview.prepared.catalog.nodes.count, groupCount: preview.prepared.catalog.groups.count,
            ruleCount: preview.prepared.ruleCount)
        ConfigurationResourceStore.discardPending()
    }
    func probeNodes(useRunning: Bool = false) throws -> [String] {
        let running = useRunning ? try runningRecord() : nil
        return try ConfigurationResourceStore.$scopedStorage.withValue(repository.storage) {
            guard let prepared = try load(useRunning: useRunning).prepared, let stored = try running?.record ?? repository.activeRecord() else { throw PrototypeError.missingConfiguration }
            if !offline { try stored.requireCertificateConsent(for: prepared) }
            // Adapter-only tests never start a VPN, listener or configuration DNS/rules.
            if !offline && !probeRuntimeReady { try CoreRuntime.setup(in: ConfigurationResources.directory); probeRuntimeReady = true }
            guard let root = try JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as? [String: Any] else { throw PrototypeError.invalidFile }
            let raw = ConfigurationResources.nodes(root)
            return try prepared.catalog.nodes.map { node in
                guard let value = raw.first(where: { $0["name"] as? String == node.name }) else { throw PrototypeError.invalidFile }
                return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            }
        }
    }
    private static let fixture = """
    mode: rule
    proxies:
      - name: DEMO-NODE
        type: trojan
        server: demo.example.invalid
        port: 443
        password: DEMO-ONLY
    proxy-groups:
      - name: Proxy
        type: select
        proxies: [DEMO-NODE, DIRECT]
    rules:
      - MATCH,Proxy
    """
}

/// Offline runs cannot read or mutate the user's Keychain or subscriptions.
nonisolated final class MacMemoryStorage: SubscriptionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func keys() -> [String] { lock.lock(); defer { lock.unlock() }; return Array(items.keys) }
    func read(_ key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return items[key] }
    func write(_ data: Data, for key: String) { lock.lock(); defer { lock.unlock() }; items[key] = data }
    func remove(_ key: String) { lock.lock(); defer { lock.unlock() }; items.removeValue(forKey: key) }
}

#endif
