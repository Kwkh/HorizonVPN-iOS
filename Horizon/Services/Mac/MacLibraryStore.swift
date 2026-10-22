#if os(macOS)
import Foundation
import Observation

@MainActor @Observable final class MacLibraryStore {
    private(set) var index = SubscriptionIndex()
    private(set) var ready = false
    var cloudRepository: SubscriptionRepository { worker.repository }
    private(set) var prepared: PrototypeConfiguration.Prepared?
    var busy: Bool { activity.busy }
    @ObservationIgnored private let activity = MacLibraryActivity()
    private(set) var usage: [UUID: SubscriptionDownloader.Usage] = [:]
    private(set) var refreshingIDs: Set<UUID> = []
    var error: String?
    var preview: MacSubscriptionWorker.Preview?
    var certificateDigest: String?
    var revisionPreview: MacSubscriptionWorker.RevisionPreview?
    var subscriptionSwitch: SubscriptionSummary?
    var canActivateSubscription: Bool {
        ready && !busy && !vpn.working && pendingRouting == nil && pendingSelection == nil &&
            subscriptionSwitch == nil && preview == nil && revisionPreview == nil &&
            certificateDigest == nil && error == nil && (vpn.isIdle || vpn.status == .connected)
    }
    let probes: MacProbeStore
    let telemetry = MacTelemetryStore()
    @ObservationIgnored private var certificateAction: CertificateAction = .connect
    private enum CertificateAction { case connect, probe([Int]) }
    private(set) var identity = ""
    var runtimeChoices: [String: String] {
        guard vpn.status == .connected, telemetry.sample?.configurationID == identity, let catalog = prepared?.catalog else { return [:] }
        return RuntimeGroupChoices.names(telemetry.sample?.groupSelections ?? [:], catalog: catalog)
    }
    private(set) var probeScope = ""
    private(set) var routing: ConfigurationRouting = .subscription
    private(set) var pendingRouting: ConfigurationRouting?
    struct PendingSelection: Equatable {
        let scope: String
        let group: Int
        let member: String
    }
    private(set) var pendingSelection: PendingSelection?
    func isSelecting(group: Int, member: String) -> Bool {
        pendingSelection == PendingSelection(scope: probeScope, group: group, member: member)
    }
    var canChangeRouting: Bool {
        prepared != nil && !busy && !vpn.working && pendingRouting == nil && (vpn.isIdle || vpn.status == .connected)
    }

    let offline: Bool
    let vpn: MacVPNController
    private let worker: MacSubscriptionWorker
    @ObservationIgnored private var started = false

    init(offline: Bool, probes: MacProbeStore? = nil, offlineStorage: (any SubscriptionStorage)? = nil) {
        self.offline = offline
        self.probes = probes ?? MacProbeStore()
        worker = MacSubscriptionWorker(offline: offline, offlineStorage: offlineStorage)
        vpn = MacVPNController(offline: offline)
    }
    var activeTitle: String { index.entries.first { $0.id == index.activeID }?.title ?? MacText.value("尚未选择订阅", "No configuration selected") }
    func start() async {
        guard !started else { return }
        started = true
        await perform {
            try await self.worker.seedOffline()
            try await self.vpn.load()
            try await self.reconcileConnection()
            self.ready = true
        }
    }
    /// Automatic sync only changes non-selected records. Do not rebuild the current
    /// runtime or invalidate in-flight latency results when updating the grid.
    func reloadCloudSubscriptionSummaries() async -> Bool {
        guard ready else { return false }
        return await activity.run(showsActivity: false) {
            guard let index = try? await self.worker.cloudIndex() else { return false }
            self.index = index
            return true
        }
    }
    func performCloudReview(localID: UUID?, operation: @Sendable () async throws -> Void) async throws {
        var failure: Error?
        let succeeded = await activity.run(showsActivity: false) {
            do {
                guard self.ready, !(localID == self.index.activeID && !self.vpn.isIdle) else {
                    throw CloudSyncFailure.currentSubscription
                }
                try Task.checkCancellation()
                try await operation()
                try await self.refresh()
                return true
            } catch { failure = error; return false }
        }
        if !succeeded { throw failure ?? CancellationError() }
    }
    private func refresh() async throws {
        let snapshot = try await worker.load(useRunning: !vpn.isIdle)
        index = snapshot.index; prepared = snapshot.prepared; identity = snapshot.identity; usage = snapshot.usage; probeScope = snapshot.probeScope
        routing = snapshot.routing
        probes.bind(probeScope)
    }
    func changeRouting(_ mode: ConfigurationRouting) {
        guard canChangeRouting, mode != routing else { return }
        pendingRouting = mode
        // Owned by the service: changing pages cannot cancel a partially applied transaction.
        Task {
            defer { pendingRouting = nil }
            await perform(showsActivity: false) {
                let wasConnected = self.vpn.status == .connected
                guard self.vpn.isIdle || wasConnected else { throw SubscriptionError.staleRevision }
                if wasConnected { try await self.pinConnectedConfiguration() }
                let change: MacSubscriptionWorker.RoutingChange
                do { change = try await self.worker.stageRouting(mode, useRunning: wasConnected) }
                catch { await self.worker.cancelPreview(); throw error }
                var committed: StoredConfiguration?
                do {
                    // The current tunnel stays intact throughout parsing, resource preparation and preflight.
                    if wasConnected {
                        guard self.vpn.status == .connected else { throw SubscriptionError.staleRevision }
                        try await self.vpn.disconnectAndWait()
                    }
                    else { guard self.vpn.isIdle else { throw SubscriptionError.staleRevision } }
                    committed = try await self.worker.commitRouting(change)
                    try await self.worker.releaseRunning()
                    try await self.refresh()
                    if wasConnected {
                        if let digest = try await self.worker.requireCertificateConsent() {
                            self.certificateAction = .connect; self.certificateDigest = digest
                        } else { try await self.beginConnection() }
                    }
                } catch {
                    let failure = error
                    await self.worker.cancelPreview()
                    if let committed {
                        // Wait for a failed start's stop request before restoring its source.
                        try await self.vpn.disconnectAndWait()
                        try await self.worker.rollbackRouting(change, committed: committed)
                    }
                    if self.vpn.isIdle { try await self.worker.releaseRunning() }
                    try await self.refresh()
                    // Surface the failure; do not silently reconnect an unverified pending refresh.
                    throw failure
                }
            }
        }
    }
    // Status changes serialize behind library transactions, avoiding a disconnect
    // halfway through a refresh from publishing a stale running snapshot.
    func connectionChanged() async {
        await perform(showsActivity: false) { try await self.reconcileConnection() }
    }
    private func reconcileConnection() async throws {
        if vpn.isIdle { try await worker.releaseRunning() }
        else if vpn.status == .connected { try await pinConnectedConfiguration() }
        try await refresh()
    }
    private func pinConnectedConfiguration() async throws {
        guard let data = await vpn.message(Data("telemetry.v2".utf8)),
              let sample = try? JSONDecoder().decode(LiveTelemetry.self, from: data) else { throw PrototypeError.start }
        try await worker.pinRunning(identity: sample.configurationID, sessionID: sample.sessionID)
    }
    /// Ordinary requests never interrupt an active tunnel without confirmation.
    func activate(_ id: UUID, reconnect: Bool = false) async {
        guard canActivateSubscription, id != index.activeID,
              let target = index.entries.first(where: { $0.id == id }) else { return }
        if !vpn.isIdle && !reconnect { subscriptionSwitch = target; return }
        await perform {
            let wasConnected = self.vpn.status == .connected
            guard self.vpn.isIdle || (wasConnected && reconnect) else { throw SubscriptionError.staleRevision }
            try await MacSubscriptionActivationFlow.run(
                validate: { try await self.worker.validateActivation(id) },
                disconnect: {
                    if wasConnected { try await self.vpn.disconnectAndWait() }
                    guard self.vpn.isIdle else { throw SubscriptionError.staleRevision }
                },
                commit: {
                    try await self.worker.releaseRunning()
                    try await self.worker.activate(id)
                    try await self.refresh()
                },
                reconnect: {
                    guard wasConnected else { return }
                    if let digest = try await self.worker.requireCertificateConsent() {
                        self.certificateAction = .connect; self.certificateDigest = digest
                    } else { try await self.beginConnection() }
                })
        }
    }
    func select(group: Int, member: String) async {
        guard pendingSelection == nil, vpn.isIdle || vpn.status == .connected, prepared?.catalog.groups.first(where: { $0.id == group }).map({ prepared?.catalog.choices[$0.name] != member }) == true else { return }
        let scope = probeScope
        // Present the requested target even while waiting behind a background
        // transaction. Keep it until commit/refresh, failure or cancellation ends.
        pendingSelection = PendingSelection(scope: scope, group: group, member: member)
        defer { pendingSelection = nil }
        await perform {
            guard scope == self.probeScope, self.vpn.isIdle || self.vpn.status == .connected else { throw SubscriptionError.staleRevision }
            if self.vpn.isIdle { try await self.worker.releaseRunning() }
            let plan = try await self.worker.prepareSelection(group: group, member: member, useRunning: self.vpn.status == .connected)
            var sessionID: UUID?
            if self.vpn.status == .connected {
                guard let data = await self.vpn.message(Data("telemetry.v2".utf8)),
                      let sample = try? JSONDecoder().decode(LiveTelemetry.self, from: data), sample.configurationID == plan.before else { throw PrototypeError.start }
                sessionID = sample.sessionID
                guard await self.switchRuntime(plan, session: sample.sessionID, restoring: false) == true else { throw PrototypeError.start }
            }
            do { try await self.worker.commitSelection(plan) }
            catch {
                if let sessionID, await self.switchRuntime(plan, session: sessionID, restoring: true) != true { self.vpn.disconnect() }
                throw error
            }
            try await self.refresh()
        }
    }
    private func switchRuntime(_ plan: MacSubscriptionWorker.Selection, session: UUID, restoring: Bool) async -> Bool? {
        let before = restoring ? plan.after : plan.before, after = restoring ? plan.before : plan.after
        let command = SelectionCommand(requestID: UUID(), sessionID: session, configurationID: before,
            group: plan.group, member: restoring ? plan.previous : plan.member)
        if let payload = try? JSONEncoder().encode(command), let data = await vpn.message(payload),
           let reply = try? JSONDecoder().decode(SelectionReply.self, from: data), reply.requestID == command.requestID, reply.sessionID == session {
            if reply.accepted, reply.configurationID == after { return true }
            if !reply.accepted, reply.configurationID == before { return false }
        }
        if let data = await vpn.message(Data("telemetry.v2".utf8)), let sample = try? JSONDecoder().decode(LiveTelemetry.self, from: data), sample.sessionID == session {
            if sample.configurationID == after { return true }
            if sample.configurationID == before { return false }
        }
        // An unknown runtime selection must never be represented as the saved one.
        vpn.disconnect(); return nil
    }
    func importFile(_ url: URL) async {
        probes.cancel()
        await perform { self.preview = try await self.worker.preview(file: url) }
    }
    func importDroppedFile(_ url: URL) async {
        await perform {
            // Drops add to the library without changing an existing selection/session.
            try await self.worker.importDroppedFile(url, makeCurrent: false)
            try await self.refresh()
        }
    }
    func importLink(_ link: String) async {
        probes.cancel()
        await perform { self.preview = try await self.worker.preview(link: link) }
    }
    func save(_ preview: MacSubscriptionWorker.Preview, title: String, makeCurrent: Bool) async -> Bool {
        guard !makeCurrent || vpn.isIdle else { return false }
        return await perform {
            guard !makeCurrent || self.vpn.isIdle else { throw SubscriptionError.staleRevision }
            if self.vpn.isIdle { try await self.worker.releaseRunning() }
            try await self.worker.save(preview, title: title, makeCurrent: makeCurrent)
            try await self.refresh()
        }
    }
    func cancelPreview() async { await worker.cancelPreview() }
    func connect() async {
        guard vpn.isIdle, pendingRouting == nil else { return }
        await perform {
            guard self.vpn.isIdle else { return }
            try await self.worker.releaseRunning()
            if let digest = try await self.worker.requireCertificateConsent() { self.certificateAction = .connect; self.certificateDigest = digest; return }
            try await self.beginConnection()
        }
    }
    private func beginConnection() async throws {
        guard vpn.isIdle else { return }
        let snapshot = try await worker.load()
        try await worker.pinRunning(identity: snapshot.identity)
        do { try await vpn.connect(); try await refresh() }
        catch { if vpn.isIdle { try? await worker.releaseRunning() }; throw error }
    }
    func approveAndConnect(_ digest: String) async {
        let showsActivity = if case .connect = certificateAction { true } else { false }
        await perform(showsActivity: showsActivity) {
            try await self.worker.approveCertificate(digest)
            // Recheck the exact active revision after crossing the worker boundary.
            guard try await self.worker.requireCertificateConsent(useRunning: !self.vpn.isIdle) == nil else { throw PrototypeError.certificateConsent }
            switch self.certificateAction {
            case .connect: try await self.beginConnection()
            case .probe(let indices): self.probes.start(indices: indices, nodes: try await self.worker.probeNodes(useRunning: !self.vpn.isIdle))
            }
        }
    }
    func managementInfo(_ id: UUID) async throws -> MacSubscriptionWorker.ManagementInfo {
        try await worker.managementInfo(id)
    }
    func stageRevision(_ id: UUID, revisionID: UUID) async {
        probes.cancel()
        await perform { self.revisionPreview = try await self.worker.stageRevision(id, revisionID: revisionID) }
    }
    func record(_ id: UUID) async throws -> StoredConfiguration { try await worker.record(id) }
    func rename(_ id: UUID, title: String) async -> Bool {
        await perform { try await self.worker.rename(id, title: title); try await self.refresh() }
    }
    func delete(_ id: UUID) async -> Bool {
        guard vpn.isIdle || id != index.activeID else { return false }
        return await perform {
            guard self.vpn.isIdle || id != self.index.activeID else { throw SubscriptionError.staleRevision }
            if self.vpn.isIdle { try await self.worker.releaseRunning() }
            try await self.worker.delete(id); try await self.refresh()
        }
    }
    func deleteConfigurations(_ ids: Set<UUID>) async -> Bool {
        guard !ids.isEmpty else { return false }
        return await perform {
            if let active = self.index.activeID, !self.vpn.isIdle, ids.contains(active) { throw SubscriptionError.staleRevision }
            if self.vpn.isIdle { try await self.worker.releaseRunning() }
            do {
                for entry in self.index.entries where ids.contains(entry.id) {
                    try await self.worker.delete(entry.id)
                }
            } catch {
                // A storage error can interrupt a batch; publish committed deletions.
                try? await self.refresh()
                throw error
            }
            try await self.refresh()
        }
    }
    func stageRevision(_ id: UUID, revision: SubscriptionRevision? = nil) async {
        guard !busy else { return }
        if revision == nil { guard refreshingIDs.insert(id).inserted else { return } }
        defer { if revision == nil { refreshingIDs.remove(id) } }
        probes.cancel()
        await perform(showsActivity: revision != nil) {
            self.revisionPreview = try await self.worker.stageRevision(id, revision: revision)
            self.usage = await self.worker.usageSnapshot()
        }
    }
    func refreshInBackground(_ id: UUID) async {
        guard !offline, !busy, vpn.isIdle || vpn.status == .connected || id != index.activeID else { return }
        guard refreshingIDs.insert(id).inserted else { return }
        defer { refreshingIDs.remove(id) }
        await perform(showsActivity: false) {
            do {
                let candidate = try await self.worker.stageRevision(id)
                guard self.vpn.isIdle || self.vpn.status == .connected || id != self.index.activeID else { throw SubscriptionError.staleRevision }
                if self.vpn.status == .connected, id == self.index.activeID {
                    try await self.pinConnectedConfiguration()
                }
                // No tunnel restart or selection command: commit the next connection's source only.
                try await self.worker.applyRefresh(candidate)
                try await self.refresh()
            } catch { await self.worker.cancelPreview(); throw error }
        }
    }
    func applyRevision(_ preview: MacSubscriptionWorker.RevisionPreview) async -> Bool {
        guard vpn.isIdle || vpn.status == .connected || preview.subscriptionID != index.activeID else { return false }
        return await perform {
            guard self.vpn.isIdle || self.vpn.status == .connected || preview.subscriptionID != self.index.activeID else { throw SubscriptionError.staleRevision }
            if self.vpn.status == .connected, preview.subscriptionID == self.index.activeID {
                try await self.pinConnectedConfiguration()
            }
            try await self.worker.applyRefresh(preview)
            try await self.refresh()
        }
    }
    func test(_ indices: [Int]) async {
        guard !offline, !busy else { return }
        let scope = probeScope
        // Probe preparation still serializes with library writes, but its loading
        // belongs to the probe control, never the page's Connect/Disconnect button.
        await perform(showsActivity: false) {
            guard scope == self.probeScope else { throw SubscriptionError.staleRevision }
            if let digest = try await self.worker.requireCertificateConsent(useRunning: !self.vpn.isIdle) {
                self.certificateAction = .probe(indices); self.certificateDigest = digest; return
            }
            self.probes.start(indices: indices, nodes: try await self.worker.probeNodes(useRunning: !self.vpn.isIdle))
        }
    }
    @discardableResult private func perform(showsActivity: Bool = true, _ operation: () async throws -> Void) async -> Bool {
        await activity.run(showsActivity: showsActivity) {
            do { try await operation(); return true }
            catch is CancellationError { return false }
            catch { self.error = MacText.error(error); return false }
        }
    }
}

/// Ordered, fail-fast stages: validate while the old connection is still intact;
/// commit only after the system confirms that it has stopped.
@MainActor enum MacSubscriptionActivationFlow {
    static func run(validate: () async throws -> Void, disconnect: () async throws -> Void,
                    commit: () async throws -> Void, reconnect: () async throws -> Void) async throws {
        try await validate()
        try await disconnect()
        try await commit()
        try await reconnect()
    }
}
#endif
