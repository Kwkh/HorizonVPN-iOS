import Foundation

/// CPU-heavy parsing and core preflight run serially off the UI actor.
actor ConfigurationImportWorker {
    static let shared = ConfigurationImportWorker()
    struct Validated: Sendable {
        let prepared: PrototypeConfiguration.Prepared
        let report: ConfigurationCompatibility
    }
    struct LoadedLibrary: Sendable {
        let library: SubscriptionIndex
        let prepared: PrototypeConfiguration.Prepared?
        let configurationID: String?
        let sourceDigest: String?
    }
    struct Failure: Error {
        let report: ConfigurationCompatibility
        let issue: ConfigurationIssue
    }
    private var preparedCache: [(String, PrototypeConfiguration.Prepared)] = []
    private var reportCache: [(String, ConfigurationCompatibility)] = []
    func prepareStored(_ stored: StoredConfiguration) throws -> PrototypeConfiguration.Prepared {
        let key = RuntimeIdentity.fingerprint(source: stored.source, choices: stored.choices)
        if let cached = preparedCache.first(where: { $0.0 == key }) { return cached.1 }
        try Task.checkCancellation()
        let value = try PrototypeConfiguration.prepare(stored.source, choices: stored.choices)
        try Task.checkCancellation()
        preparedCache.insert((key, value), at: 0)
        preparedCache = Array(preparedCache.prefix(2))
        return value
    }
    func readRecord(_ id: UUID, repository: SubscriptionRepository) throws -> StoredConfiguration {
        try Task.checkCancellation()
        return try repository.record(id)
    }
    func checkRevision(_ id: UUID, expected: StoredConfiguration, repository: SubscriptionRepository) throws {
        try Task.checkCancellation()
        let current = try repository.record(id)
        guard current.revisionID == expected.revisionID, current.source == expected.source,
              current.choices == expected.choices, current.sourceURL == expected.sourceURL else { throw SubscriptionError.staleRevision }
    }
    func discardPendingResources() { ConfigurationResourceStore.discardPending() }
    func replaceRevision(_ id: UUID, expected: StoredConfiguration, prepared: PrototypeConfiguration.Prepared,
                         sourceURL: String?, verifiedAt: Date?, repository: SubscriptionRepository) throws {
        try Task.checkCancellation()
        // The controller holds isBusy across this await. Encoding, Keychain writes
        // and resource GC stay off MainActor; replace rechecks the expected revision.
        try repository.replace(id, expected: expected, source: prepared.source, choices: prepared.catalog.choices,
            sourceURL: sourceURL, nodeCount: prepared.catalog.nodes.count, groupCount: prepared.catalog.groups.count,
            ruleCount: prepared.ruleCount, verifiedAt: verifiedAt)
        // No cancellation check after commit: the caller must learn it committed
        // before deciding whether startup failure requires recovery.
    }
    func confirmStartup(_ id: UUID, source: Data, choices: [String: String], repository: SubscriptionRepository) throws {
        try repository.markStartupConfirmed(id, source: source, choices: choices)
    }
    func certificateConsentDigest(_ id: UUID, prepared: PrototypeConfiguration.Prepared,
                                  repository: SubscriptionRepository) throws -> String? {
        let stored = try repository.record(id)
        guard stored.source == prepared.source else { throw PrototypeError.missingConfiguration }
        do { try stored.requireCertificateConsent(for: prepared); return nil }
        catch PrototypeError.certificateConsent { return stored.contentDigest }
    }
    func loadLibrary(_ repository: SubscriptionRepository) throws -> LoadedLibrary {
        let library = try repository.library()
        let prepared = try repository.activeRecord().map { try prepareStored($0) }
        // Fingerprinting a large configuration also belongs off the UI executor.
        return .init(library: library, prepared: prepared,
            configurationID: prepared.map { RuntimeIdentity.fingerprint(source: $0.source, choices: $0.catalog.choices) },
            sourceDigest: prepared.map { ConfigurationResourceStore.digest($0.source) })
    }
    func diagnose(_ source: Data) throws -> ConfigurationCompatibility {
        try Task.checkCancellation()
        let key = ConfigurationResourceStore.digest(source)
        if let cached = reportCache.first(where: { $0.0 == key }) { return cached.1 }
        let report = ConfigurationCompatibility.inspect(source)
        try Task.checkCancellation()
        reportCache.insert((key, report), at: 0); reportCache = Array(reportCache.prefix(2))
        return report
    }
    func routingMode(_ source: Data) throws -> ConfigurationRouting { try ConfigurationRouting.mode(in: source) }
    func routingAssessment(_ source: Data) throws -> RoutingAssessment { try RoutingAssessment.inspect(source) }
    func hasGeoResources(_ source: Data) throws -> Bool { try ConfigurationSnapshot.read(source)?.resources.contains(where: { $0.key.hasPrefix("geo:") }) == true }
    func changes(_ before: Data, _ after: Data) throws -> [String] { try SubscriptionChangeSummary.compare(before, after) }
    func activate(_ id: UUID, repository: SubscriptionRepository) throws { try repository.activate(id) }
    func subscriptionIndex(_ repository: SubscriptionRepository) throws -> SubscriptionIndex {
        try repository.index() ?? repository.library()
    }

    func exportCloud(_ id: UUID, repository: SubscriptionRepository, cache: CloudAssetCache) throws -> CloudSubscriptionVersion {
        let (summary, stored) = try SubscriptionRepository.transaction {
            guard let summary = try subscriptionIndex(repository).entries.first(where: { $0.id == id }) else { throw SubscriptionError.missingEntry }
            return (summary, try repository.record(id))
        }
        // Dependencies are immutable and hash-checked. Copy outside the repository
        // lock; the caller rechecks the mutation generation before queuing upload.
        // A concurrent delete/GC can fail this export safely and retry next pass.
        let snapshot = try ConfigurationSnapshot.read(stored.source)
        let original = try ConfigurationSnapshot.original(stored.source)
        let required = Set(try ConfigurationResources.plan(ConfigurationInput.read(original, resolveResources: false).root).map(\.key))
        let resources = (snapshot?.resources ?? []).filter { required.contains($0.key) }
            .map { ConfigurationSnapshot.Resource(key: $0.key, digest: $0.digest, bytes: $0.bytes) }
            .sorted { $0.key < $1.key }
        guard Set(resources.map(\.key)) == required else { throw CloudSyncFailure.missingAsset }
        for resource in resources {
            try cache.put(ConfigurationResourceStore.load(resource, storage: repository.storage), digest: resource.digest)
        }
        let digest = ConfigurationResourceStore.digest(original)
        try cache.put(original, digest: digest)
        let value = CloudSubscriptionVersion(id: id, title: summary.title, fileName: summary.fileName,
            sourceURL: stored.sourceURL, originalDigest: digest, originalBytes: original.count, resources: resources)
        try value.validate()
        return value
    }

    @discardableResult func installCloud(_ value: CloudSubscriptionVersion, localID: UUID, expectedMutation: UUID?,
                      allowCurrent: Bool, repository: SubscriptionRepository, cache: CloudAssetCache) throws -> UUID? {
        try value.validate()
        if value.deleted {
            return try repository.deleteReplica(localID, expectedMutation: expectedMutation, allowCurrent: allowCurrent)
        }
        guard let digest = value.originalDigest else { throw CloudSyncFailure.invalidPayload }
        let original = try cache.read(digest, bytes: value.originalBytes)
        guard !original.starts(with: ConfigurationSnapshot.prefix) else { throw CloudSyncFailure.invalidPayload }
        let index = try repository.library()
        let previous = try index.entries.contains(where: { $0.id == localID }) ? repository.record(localID) : nil
        let mode = try previous.map { try ConfigurationRouting.mode(in: $0.source) } ?? .subscription
        let requests = try ConfigurationResources.plan(mode.apply(ConfigurationInput.read(original, resolveResources: false)).root)
        var resources = value.resources
        // Preserve device-local smart routing without fetching any provider URL.
        for request in requests where !resources.contains(where: { $0.key == request.key }) {
            guard mode == .smart, request.key.hasPrefix("geo:"),
                  let old = try previous.flatMap({ try ConfigurationSnapshot.read($0.source) })?.resources.first(where: { $0.key == request.key }) else {
                throw CloudSyncFailure.missingAsset
            }
            resources.append(old)
        }
        guard Set(requests.map(\.key)) == Set(resources.map(\.key)) else { throw CloudSyncFailure.invalidPayload }
        let reader = CloudResourceStorage(cache: cache, resources: value.resources, destination: repository.storage)
        return try ConfigurationResourceStore.$scopedStorage.withValue(reader) {
            let source = resources.isEmpty && mode == .subscription ? original :
                try ConfigurationSnapshot(original: original, resources: resources, routing: mode == .subscription ? nil : mode).encoded()
            let prepared = try validate(source, choices: previous?.choices ?? [:]).prepared
            var stored = StoredConfiguration(source: prepared.source, choices: prepared.catalog.choices)
            stored.sourceURL = value.sourceURL
            return try repository.installReplica(id: localID, title: value.title, fileName: value.fileName, record: stored,
                nodeCount: prepared.catalog.nodes.count, groupCount: prepared.catalog.groups.count, ruleCount: prepared.ruleCount,
                expectedMutation: expectedMutation, allowCurrent: allowCurrent, expectedRecord: previous, resources: reader)
        }
    }
    func saveChoices(_ choices: [String: String], id: UUID, repository: SubscriptionRepository) throws { try repository.saveChoices(choices, for: id) }
    func saveImport(_ stored: StoredConfiguration, fileName: String?, title: String, prepared: PrototypeConfiguration.Prepared,
                    makeCurrent: Bool, repository: SubscriptionRepository) throws {
        _ = try repository.add(stored, fileName: fileName, displayTitle: title,
            nodeCount: prepared.catalog.nodes.count, groupCount: prepared.catalog.groups.count,
            ruleCount: prepared.ruleCount, makeCurrent: makeCurrent)
    }
    func standaloneNodes(_ prepared: PrototypeConfiguration.Prepared) throws -> [String] {
        try Task.checkCancellation()
        // Only adapters are created; configuration DNS/rules and providers are not started.
        #if os(iOS)
        try CoreRuntime.setup(in: ConfigurationResources.directory)
        #endif
        guard let root = try JSONSerialization.jsonObject(with: Data(prepared.runtimeJSON.utf8)) as? [String: Any] else {
            throw PrototypeError.invalidFile
        }
        let nodes = ConfigurationResources.nodes(root)
        var result: [String] = []
        for node in prepared.catalog.nodes {
            guard let raw = nodes.first(where: { $0["name"] as? String == node.name }) else { throw PrototypeError.invalidFile }
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.withoutEscapingSlashes])
            guard data.count <= 65536 else { throw PrototypeError.invalidFile }
            result.append(String(decoding: data, as: UTF8.self))
        }
        return result
    }
    func resources(_ data: Data, permitsNetwork: Bool, previousSource: Data? = nil,
                   updateGeo: Bool = false, routing: ConfigurationRouting = .subscription, deadline: ContinuousClock.Instant) async throws -> Data {
        try await SubscriptionResourceLoader.prepare(data, permitsNetwork: permitsNetwork,
            previousSource: previousSource, updateGeo: updateGeo, routing: routing, deadline: deadline)
    }
    func routingCandidate(_ mode: ConfigurationRouting, stored: StoredConfiguration) async throws -> Data {
        // Validate the original/current source before applying a policy; malformed input is never repaired silently.
        _ = try prepareStored(stored)
        return try await SubscriptionResourceLoader.prepare(ConfigurationSnapshot.original(stored.source),
            permitsNetwork: false, previousSource: stored.source, routing: mode, reuseDependencies: true)
    }
    func validate(_ data: Data, choices: [String: String] = [:]) throws -> Validated {
        try Task.checkCancellation()
        let candidate = try? PrototypeConfiguration.prepare(data)
        let report = ConfigurationCompatibility.inspect(data, prepared: candidate)
        do {
            let base = try candidate ?? PrototypeConfiguration.prepare(data)
            var retained: [String: String] = [:]
            for group in base.catalog.groups where group.allowsSelection {
                if let choice = choices[group.name], group.members.contains(choice) { retained[group.name] = choice }
            }
            let prepared = retained.isEmpty ? base : try PrototypeConfiguration.prepare(data, choices: retained)
            try Task.checkCancellation()
            #if os(iOS) || HORIZON_NATIVE_MAC
            try SubscriptionResourceLoader.preflight(prepared)
            #endif
            try Task.checkCancellation()
            return Validated(prepared: prepared, report: report)
        } catch is CancellationError { throw CancellationError() }
        catch let issue as ConfigurationIssue { throw Failure(report: report, issue: issue) }
        catch let error as PrototypeError { throw Failure(report: report, issue: ConfigurationIssue(code: error, detail: error.summary)) }
        catch { throw Failure(report: report, issue: ConfigurationIssue(code: .coreValidation, detail: PrototypeError.coreValidation.summary)) }
    }
    /// Home needs a runnable configuration, not a human-readable import report.
    /// Keep the same selection filtering and native preflight as the review path.
    func validateRouting(_ data: Data, choices: [String: String]) throws -> PrototypeConfiguration.Prepared {
        try Task.checkCancellation()
        let base = try PrototypeConfiguration.prepare(data)
        var retained: [String: String] = [:]
        for group in base.catalog.groups where group.allowsSelection {
            if let choice = choices[group.name], group.members.contains(choice) { retained[group.name] = choice }
        }
        let prepared = retained.isEmpty ? base : try PrototypeConfiguration.prepare(data, choices: retained)
        try Task.checkCancellation()
        #if os(iOS)
        try SubscriptionResourceLoader.preflight(prepared)
        #endif
        try Task.checkCancellation()
        // The commit reloads these exact bytes and choices. Reuse parsing only;
        // do not cache/skip preflight or its resource publication side effects.
        let key = RuntimeIdentity.fingerprint(source: prepared.source, choices: prepared.catalog.choices)
        preparedCache.removeAll { $0.0 == key }
        preparedCache.insert((key, prepared), at: 0)
        preparedCache = Array(preparedCache.prefix(2))
        return prepared
    }
}
