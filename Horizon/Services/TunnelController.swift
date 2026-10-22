import Foundation
import NetworkExtension
import Observation

@MainActor @Observable
final class TunnelController {
    struct Event: Identifiable {
        let id = UUID()
        let date = Date()
        let message: String
    }
    private(set) var status: NEVPNStatus = .invalid
    private var titleHandoff = ConnectionTitleHandoff()
    @ObservationIgnored private var titleHandoffTimeout: Task<Void, Never>?
    var isAwaitingConnectionStatus: Bool { titleHandoff.isPending }
    func connectionTitleStatus(preparing: Bool) -> NEVPNStatus {
        titleHandoff.titleStatus(system: status, preparing: preparing)
    }
    private(set) var hasProfile = false
    private(set) var profileReady = false
    private(set) var hasConfiguration = false
    private(set) var isBusy = false
    private(set) var isApplyingRouting = false
    private(set) var isSwitchingNode = false
    private(set) var didLoadPreferences = false
    private(set) var didFinishInitialRefresh = false
    private(set) var lastRefreshSucceeded = false
    private(set) var message = "尚未读取系统 VPN 配置。"
    private(set) var events: [Event] = []
    private(set) var snapshot: TunnelSnapshot?
    private(set) var connectivity: ConnectivityReport?
    private(set) var isProbing = false
    var isDiagnosingDNS = false
    @ObservationIgnored private var probeTicket = UUID()
    private(set) var pingReport: PingReport?
    private(set) var pingDate: Date?
    private(set) var isTestingPing = false
    @ObservationIgnored private var pingTicket = UUID()
    @ObservationIgnored private var revisionOperation: UUID?
    private(set) var compatibilityReport: ConfigurationCompatibility?
    enum CertificateAction { case connect, ping, batch, node(Int) }
    struct CertificateApproval: Identifiable {
        var action: CertificateAction = .connect
        var connects: Bool { if case .connect = action { return true }; return false }
        let id: UUID
        let digest: String
        let nodeCount: Int
    }
    private(set) var certificateApproval: CertificateApproval?
    func dismissCertificateApproval() { certificateApproval = nil }
    func approveCertificates(_ request: CertificateApproval) async {
        certificateApproval = nil
        guard isIdle, activeSubscriptionID == request.id else { return }
        do {
            try repository.approveInsecureCertificates(request.id, expectedDigest: request.digest)
            switch request.action {
            case .connect: await connectCurrentProfile()
            case .ping: await testPing()
            case .batch: batchProbes.start(using: self)
            case .node(let index): batchProbes.start(using: self, node: index)
            }
        } catch { record(safeSummary(error)) }
    }
    private func certificatesReady() -> Bool {
        do {
            try checkCertificateConsent()
            return true
        } catch { record(safeSummary(error)); return false }
    }
    func authorizeProbe(_ action: CertificateAction) -> Bool {
        // Connected configurations already passed the same version-bound consent.
        if status == .connected { return true }
        do { try checkCertificateConsent(); return true }
        catch { certificateApproval?.action = action; record(safeSummary(error)); return false }
    }
    func standaloneNodes() async throws -> [String] {
        guard permitsNetwork, !network.isOffline, let prepared = preparedConfiguration else { throw PrototypeError.missingConfiguration }
        return try await ConfigurationImportWorker.shared.standaloneNodes(prepared)
    }
    @ObservationIgnored private var standalonePing: StandaloneProbeSession?
    func cancelForegroundProbes(preservingNodeProbes: Bool = false) {
        if !preservingNodeProbes { batchProbes.cancel(using: self) }
        if standalonePing != nil {
            standalonePing?.cancel(); standalonePing = nil
            pingTicket = UUID(); isTestingPing = false; pingReport = nil; pingDate = nil
        }
    }
    private func checkCertificateConsent() throws {
        guard let id = activeSubscriptionID else { throw PrototypeError.missingConfiguration }
        let stored = try repository.record(id)
        guard let prepared = preparedConfiguration, prepared.source == stored.source else { throw PrototypeError.missingConfiguration }
        do { try stored.requireCertificateConsent(for: prepared) }
        catch {
            certificateApproval = .init(id: id, digest: stored.contentDigest, nodeCount: prepared.insecureNodeCount)
            throw error
        }
    }
    @ObservationIgnored private var candidateSourceURL: String?
    private(set) var importPreview: SubscriptionImportPreview?
    @ObservationIgnored private var candidate: PrototypeConfiguration.Prepared?
    @ObservationIgnored private var manager: NETunnelProviderManager?
    private(set) var runtimeGroupChoices: [String: String] = [:]
    var selectedNode: String? { catalog?.resolvedTarget(runtimeChoices: runtimeGroupChoices) }
    func selectedMember(_ group: ConfigurationCatalog.Group) -> String? {
        runtimeGroupChoices[group.name] ?? catalog?.choices[group.name]
    }
    private(set) var catalog: ConfigurationCatalog?
    private(set) var configurationSummary = "缺少配置"
    private(set) var unifiedDelay = true
    private(set) var subscriptions: [SubscriptionSummary] = []
    private(set) var activeSubscriptionID: UUID?
    private(set) var pendingCleanupCount = 0
    @ObservationIgnored private var subscriptionCleanup: SubscriptionCleanupCoordinator?
    @ObservationIgnored private var isCleaningSubscriptions = false
    @ObservationIgnored private var subscriptionCleanupRevision = UUID()
    var showsSubscriptionProgress: Bool { isBusy }
    private(set) var libraryReady = false
    let batchProbes = BatchProbeStore()
    private(set) var configurationID = ""
    @ObservationIgnored private var connectionEpoch = UUID()
    @ObservationIgnored private let repository: SubscriptionRepository
    let permitsNetwork: Bool
    let network: NetworkAvailability

    init(repository: SubscriptionRepository? = nil, permitsNetwork: Bool = true, network: NetworkAvailability? = nil) {
        self.repository = repository ?? ConfigurationVault.repository
        self.permitsNetwork = permitsNetwork
        self.network = network ?? NetworkAvailability(monitorSystem: permitsNetwork)
    }
    var currentSubscriptionTitle: String {
        subscriptions.first(where: { $0.id == activeSubscriptionID })?.title ?? "未选择订阅"
    }
    var canManageSubscriptions: Bool { libraryReady && !isBusy && !isAwaitingConnectionStatus }

    func reloadCloudSubscriptionSummaries() async -> Bool {
        guard !isBusy else { return false }
        guard let index = try? await ConfigurationImportWorker.shared.subscriptionIndex(repository), !isBusy else { return false }
        if subscriptions != index.entries { subscriptions = index.entries }
        updatePendingCleanup(index.cleanupCount)
        return true
    }

    /// Explicit cloud review is the only path allowed to replace the selected
    /// subscription. It cannot stop/start VPN or interleave a foreground mutation.
    func performCloudReview(localID: UUID?, operation: @Sendable () async throws -> Void) async throws {
        if permitsNetwork, manager != nil { updateStatus() }
        guard canManageSubscriptions, !(localID == activeSubscriptionID && isTunnelActive) else {
            throw CloudSyncFailure.currentSubscription
        }
        isBusy = true
        defer { isBusy = false }
        try await operation()
        try await reloadConfiguration()
    }
    var isTunnelActive: Bool { [.connected, .connecting, .reasserting, .disconnecting].contains(status) }

    static var supportsTunnel: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
    private var providerID: String { (Bundle.main.bundleIdentifier ?? "Kenote.Clash") + ".PacketTunnel" }
    var statusText: String {
        switch status {
        case .invalid: "无有效 VPN 配置"
        case .disconnected: "未连接"
        case .connecting: "连接中"
        case .connected: "系统隧道已连接"
        case .reasserting: "等待网络恢复"
        case .disconnecting: "正在断开"
        @unknown default: "未知系统状态"
        }
    }
    var isIdle: Bool { [.disconnected, .invalid].contains(status) && !isBusy }
    var canStart: Bool { !network.isOffline && permitsNetwork && Self.supportsTunnel && didLoadPreferences && profileReady && libraryReady && hasConfiguration && isIdle }
    var canStop: Bool { [.connecting, .connected, .reasserting].contains(status) }
    var canTestPing: Bool { canTestBatch && (selectedNode != nil || (status == .connected && catalog?.groups.contains(where: { $0.name == catalog?.matchTarget }) == true)) }
    var canEnqueueNodeProbe: Bool { !network.isOffline && !isBusy && !isDiagnosingDNS && permitsNetwork && [.connected, .disconnected, .invalid].contains(status) && catalog != nil && !isTestingPing && !isProbing }
    var canTestBatch: Bool { canEnqueueNodeProbe && !batchProbes.isRunning }


    func engineMessage(_ data: Data, limit: Int = 2048) async -> Data? {
        guard status == .connected, let session = manager?.connection as? NETunnelProviderSession else { return nil }
        let epoch = connectionEpoch
        let result: Data? = await withCheckedContinuation { continuation in
            let reply = SnapshotReply(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reply.finish(nil) }
            do { try session.sendProviderMessage(data) { data in Task { @MainActor in reply.finish(data) } } }
            catch { reply.finish(nil) }
        }
        guard !Task.isCancelled, epoch == connectionEpoch, status == .connected,
              let result, result.count <= limit else { return nil }
        return result
    }
    func liveSample() async -> LiveTelemetry? {
        guard let data = await engineMessage(Data("telemetry.v2".utf8)),
              let sample = try? JSONDecoder().decode(LiveTelemetry.self, from: data),
              sample.version == 2, sample.configurationID == configurationID else { return nil }
        if let catalog { runtimeGroupChoices = RuntimeGroupChoices.names(sample.groupSelections ?? [:], catalog: catalog) }
        return sample
    }
    func liveHistory() async -> TelemetryHistory? {
        guard let data = await engineMessage(Data(TelemetryHistory.command.utf8), limit: TelemetryHistory.maximumBytes),
              let history = try? JSONDecoder().decode(TelemetryHistory.self, from: data),
              history.isValid(configurationID: configurationID, now: ProcessInfo.processInfo.systemUptime) else { return nil }
        if let catalog {
            runtimeGroupChoices = RuntimeGroupChoices.names(history.latest?.groupSelections ?? [:], catalog: catalog)
        }
        return history
    }

    func monitor() async {
        let notifications = NotificationCenter.default.notifications(named: .NEVPNStatusDidChange)
        await refresh()
        for await notification in notifications {
            guard !Task.isCancelled else { return }
            guard let connection = notification.object as? NEVPNConnection,
                  connection === manager?.connection else { continue }
            updateStatus(fromNotification: true)
        }
    }
    func refresh() async {
        lastRefreshSucceeded = false
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        // Complete even on errors so launch never traps the user behind a loading view.
        defer { didFinishInitialRefresh = true }
        if !permitsNetwork {
            #if DEBUG
            if !didLoadPreferences, ProcessInfo.processInfo.environment["CLASH_STARTUP_AUDIT"] != nil {
                let audit = ProcessInfo.processInfo.environment["CLASH_STARTUP_AUDIT"]
                try? await Task.sleep(for: .milliseconds(audit == "slow" ? 1200 : 350))
                if audit == "failure" { record("离线启动测试：模拟状态读取失败。"); return }
            }
            #endif
            do {
                try await reloadConfiguration()
                status = .disconnected
                #if DEBUG
                // Isolated in-memory demo only. Never changes Network Extension preferences.
                if ProcessInfo.processInfo.environment["CLASH_STARTUP_AUDIT"] == "connected" { status = .connected }
                #endif
                didLoadPreferences = true
            }
            catch { record(safeSummary(error)) }
            return
        }
        do {
            try await reloadConfiguration()
            guard Self.supportsTunnel else {
                record("模拟器仅供界面检查；Packet Tunnel 验收需要真机。")
                return
            }
            let profiles = try await NETunnelProviderManager.loadAllFromPreferences()
            let matches = profiles.filter {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
            }
            guard matches.count <= 1 else {
                manager = nil; hasProfile = false; profileReady = false; didLoadPreferences = false; status = .invalid
                record("发现多个本应用的 VPN 配置；请在系统设置中确认后重试。")
                return
            }
            manager = matches.first
            hasProfile = manager != nil
            profileReady = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["purpose"] as? String == PrototypeConfiguration.policyVersion
            didLoadPreferences = true
            updateStatus()
            lastRefreshSucceeded = true
            record(hasConfiguration ? "本机已保存测试配置。" : "请先导入测试 YAML；不会自动连接。")
        } catch { record(safeSummary(error)) }
    }
    @discardableResult func prepareImport(_ url: URL) async -> Bool {
        guard canManageSubscriptions else { return false }
        cancelImport()
        isBusy = true
        defer { isBusy = false }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let input = try handle.read(upToCount: PrototypeConfiguration.maximumBytes + 1) ?? Data()
            compatibilityReport = nil
            let data = try await ConfigurationImportWorker.shared.resources(input, permitsNetwork: permitsNetwork, deadline: deadline)
            let validated = try await ConfigurationImportWorker.shared.validate(data)
            compatibilityReport = validated.report
            let prepared = validated.prepared
            try Task.checkCancellation()
            guard !prepared.isFixture || !permitsNetwork else { throw PrototypeError.missingConfiguration }
            candidate = prepared
            let fileName = SubscriptionSummary.cleanName(url.lastPathComponent)
            importPreview = .init(fileName: fileName, title: SubscriptionSummary.title(from: fileName),
                                  summary: prepared.summary, adaptations: prepared.adaptations)
            return true
        } catch let failure as ConfigurationImportWorker.Failure {
            compatibilityReport = failure.report
            ConfigurationResourceStore.discardPending(); record(safeSummary(failure.issue)); return false
        } catch { ConfigurationResourceStore.discardPending(); record(safeSummary(error)); return false }
    }
    @discardableResult func prepareDownloadedImport(_ input: Data, title: String, sourceURL: String? = nil, deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async -> Bool {
        guard canManageSubscriptions else { return false }
        cancelImport()
        isBusy = true
        defer { isBusy = false }
        do {
            compatibilityReport = nil
            let data = try await ConfigurationImportWorker.shared.resources(input, permitsNetwork: permitsNetwork, deadline: deadline)
            let validated = try await ConfigurationImportWorker.shared.validate(data)
            compatibilityReport = validated.report
            let prepared = validated.prepared
            try Task.checkCancellation()
            guard !prepared.isFixture || !permitsNetwork else { throw PrototypeError.missingConfiguration }
            candidateSourceURL = try sourceURL.map { try SubscriptionDownloader.validatedURL($0).absoluteString }
            let name = SubscriptionSummary.cleanName(title)
            guard !name.isEmpty else { throw SubscriptionError.invalidTitle }
            candidate = prepared
            importPreview = .init(fileName: nil, title: name, summary: prepared.summary, adaptations: prepared.adaptations)
            return true
        } catch let failure as ConfigurationImportWorker.Failure {
            compatibilityReport = failure.report
            ConfigurationResourceStore.discardPending(); record(safeSummary(failure.issue)); return false
        } catch { ConfigurationResourceStore.discardPending(); record(safeSummary(error)); return false }
    }
    func importFailed() { record("文件未能读取；现有配置保持不变。") }
    func cancelImport() { candidate = nil; candidateSourceURL = nil; importPreview = nil; ConfigurationResourceStore.discardPending() }
    @discardableResult func confirmImport(makeCurrent: Bool) async -> Bool {
        guard canManageSubscriptions, let candidate, let preview = importPreview,
              !makeCurrent || isIdle else { return false }
        isBusy = true; defer { isBusy = false }
        do {
            var stored = StoredConfiguration(source: candidate.source, choices: candidate.catalog.choices)
            stored.sourceURL = candidateSourceURL
            try await ConfigurationImportWorker.shared.saveImport(stored, fileName: preview.fileName, title: preview.title, prepared: candidate,
                makeCurrent: makeCurrent, repository: repository)
            try await reloadConfiguration()
            self.candidate = nil; candidateSourceURL = nil
            // The presentation owner clears the preview on dismissal. Clearing it
            // here swaps the URL sheet back to its input page before dismiss runs.
            record("订阅已保存；相同内容沿用已有记录和节点选择，不会覆盖其他订阅。")
            return true
        } catch { record(safeSummary(error)); return false }
    }
    /// Called after a concrete, user-confirmed profile installation/migration.
    func prepareProfile() async {
        guard permitsNetwork, Self.supportsTunnel, didLoadPreferences, isIdle else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let profile = manager ?? NETunnelProviderManager()
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = providerID
            configuration.serverAddress = "Horizon"
            configuration.providerConfiguration = ["purpose": PrototypeConfiguration.policyVersion]
            configuration.disconnectOnSleep = false
            configuration.includeAllNetworks = false
            profile.protocolConfiguration = configuration
            profile.localizedDescription = "Horizon"
            profile.isEnabled = true
            profile.isOnDemandEnabled = false
            profile.onDemandRules = []
            try await profile.saveToPreferences()
            manager = profile
            didLoadPreferences = false
            try await profile.loadFromPreferences()
            didLoadPreferences = true
            hasProfile = true
            profileReady = true
            updateStatus()
            record("VPN 配置已准备；仅手动连接。")
        } catch { record("VPN 配置未就绪，可能未授权或签名有误。" + safeSummary(error)) }
    }
    /// Explicit user action from either home style; this never enables on-demand connection.
    func connectCurrentProfile() async {
        guard isIdle, !isAwaitingConnectionStatus else { return }
        let presentationTicket = titleHandoff.begin()
        defer { titleHandoff.preparationEnded(presentationTicket) }
        cancelForegroundProbes()
        isBusy = true
        do { try await reloadConfiguration() }
        catch { isBusy = false; record(safeSummary(error)); return }
        isBusy = false
        guard !network.isOffline else { record("当前无网络连接，请检查 Wi-Fi 或蜂窝数据。"); return }
        guard certificatesReady() else { return }
        if !profileReady { await prepareProfile() }
        if profileReady { start() }
    }
    func start() {
        guard !titleHandoff.isStarting else { return }
        cancelForegroundProbes()
        guard !network.isOffline else { record("当前无网络连接，请检查 Wi-Fi 或蜂窝数据。"); return }
        guard canStart, manager != nil else { return }
        guard certificatesReady() else { return }
        let presentationTicket = titleHandoff.id ?? titleHandoff.begin()
        titleHandoff.enqueue(presentationTicket)
        scheduleTitleHandoffTimeout(presentationTicket)
        if let id = activeSubscriptionID, let current = try? repository.record(id), current.startupConfirmed == false {
            let ticket = UUID()
            revisionOperation = ticket
            isBusy = true
            Task {
                defer {
                    isBusy = false; revisionOperation = nil
                    finishTitleHandoff(presentationTicket)
                }
                do {
                    try await startRevisionAndWait(ticket)
                    try? repository.markStartupConfirmed(id, source: current.source, choices: current.choices)
                    record("新版本已启动；节点可达性仍需验证。")
                } catch {
                    guard revisionOperation == ticket else { return }
                    if error as? PrototypeError == .certificateConsent { record(safeSummary(error)); return }
                    if let previous = current.lastUsable ?? current.history?.first {
                        await recoverRevision(id, source: previous.source, choices: previous.choices,
                            sourceURL: current.sourceURL, verifiedAt: previous.verifiedAt, ticket: ticket)
                    } else { record("新版本启动失败，暂无历史版本可恢复。") }
                }
            }
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let profile = try await enabledManagerForStart()
                guard titleHandoff.id == presentationTicket else { return }
                guard !network.isOffline else { throw PrototypeError.start }
                titleHandoff.submit()
                try profile.connection.startVPNTunnel() // No credentials in start options or preferences.
                record("已请求连接；系统连接状态不代表节点和 DNS 已通过验收。")
                updateStatus()
            } catch { finishTitleHandoff(presentationTicket); record(safeSummary(error)); updateStatus() }
        }
    }

    private func enabledManagerForStart() async throws -> NETunnelProviderManager {
        guard permitsNetwork, Self.supportsTunnel, let profile = manager else { throw PrototypeError.start }
        try await VPNProfileActivation.prepare(
            load: { try await profile.loadFromPreferences() },
            validate: {
                guard let configuration = profile.protocolConfiguration as? NETunnelProviderProtocol,
                      configuration.providerBundleIdentifier == self.providerID,
                      configuration.providerConfiguration?["purpose"] as? String == PrototypeConfiguration.policyVersion else {
                    throw PrototypeError.start
                }
            },
            isEnabled: { profile.isEnabled },
            enableAndSave: {
                profile.isEnabled = true
                // Keep the app's manual-connect policy; never acquire another app's profile.
                profile.isOnDemandEnabled = false
                profile.onDemandRules = []
                try await profile.saveToPreferences()
            })
        return profile
    }

    func stop() {
        guard canStop else { return }
        if let ticket = titleHandoff.id { finishTitleHandoff(ticket) }
        revisionOperation = nil // An explicit stop cancels automatic recovery.
        manager?.connection.stopVPNTunnel()
        record("已请求断开，等待系统状态。")
        updateStatus()
    }
    func refreshSnapshot() async {
        guard [.connected, .reasserting].contains(status),
              let session = manager?.connection as? NETunnelProviderSession else { return }
        let data: Data? = await withCheckedContinuation { continuation in
            let reply = SnapshotReply(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { reply.finish(nil) }
            do {
                try session.sendProviderMessage(Data("snapshot.v1".utf8)) { data in
                    Task { @MainActor in reply.finish(data) }
                }
            } catch { reply.finish(nil) }
        }
        guard [.connected, .reasserting].contains(status) else { return }
        guard let data, data.count <= 2048, let value = try? JSONDecoder().decode(TunnelSnapshot.self, from: data) else {
            record("扩展统计暂不可用；请检查真机固定阶段日志。")
            return
        }
        snapshot = value
    }
    func probeConnectivity() async {
        guard status == .connected, canTestPing,
              let session = manager?.connection as? NETunnelProviderSession else { return }
        let ticket = UUID()
        probeTicket = ticket
        isProbing = true
        connectivity = nil
        defer { if probeTicket == ticket { isProbing = false } }
        let data: Data? = await withCheckedContinuation { continuation in
            let reply = SnapshotReply(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 75) { reply.finish(nil) }
            do {
                try session.sendProviderMessage(Data("connectivity.v1".utf8)) { data in
                    Task { @MainActor in reply.finish(data) }
                }
            } catch { reply.finish(nil) }
        }
        guard probeTicket == ticket, status == .connected else { return }
        guard let data, data.count <= 2048,
              let report = try? JSONDecoder().decode(ConnectivityReport.self, from: data) else {
            record("联网诊断未返回结果；可以断开恢复网络后重试。")
            return
        }
        connectivity = report
        await refreshSnapshot()
    }
    func testPing() async {
        guard canTestPing, authorizeProbe(.ping) else { return }
        if status != .connected { await testStandalonePing(); return }
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let ticket = UUID()
        pingTicket = ticket
        pingReport = nil
        pingDate = nil
        isTestingPing = true
        defer { if pingTicket == ticket { isTestingPing = false } }
        let report: PingReport = await withCheckedContinuation { continuation in
            let reply = PingReply(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + PingReport.responseTimeout) {
                reply.finish(PingReport(outcome: .timedOut))
            }
            do {
                try session.sendProviderMessage(Data("ping.v1".utf8)) { data in
                    Task { @MainActor in
                        guard let data, data.count <= 512,
                              let result = try? JSONDecoder().decode(PingReport.self, from: data) else {
                            reply.finish(PingReport(outcome: .unavailable))
                            return
                        }
                        reply.finish(result)
                    }
                }
            } catch { reply.finish(PingReport(outcome: .unavailable)) }
        }
        // A response from an earlier connection must never repopulate the UI.
        guard pingTicket == ticket, status == .connected else { return }
        pingReport = report
        if report.outcome == .success, let id = activeSubscriptionID, let stored = try? repository.record(id),
           RuntimeIdentity.fingerprint(source: stored.source, choices: stored.choices) == configurationID {
            try? repository.markUsable(id, source: stored.source, choices: stored.choices)
        }
        pingDate = Date()
    }
    private func testStandalonePing() async {
        guard let name = selectedNode, let index = catalog?.nodes.firstIndex(where: { $0.name == name }) else { return }
        let ticket = UUID(); pingTicket = ticket
        isTestingPing = true; pingReport = nil; pingDate = nil
        let session = StandaloneProbeSession(); standalonePing = session
        defer { if pingTicket == ticket { isTestingPing = false; standalonePing = nil } }
        do {
            let nodes = try await standaloneNodes()
            guard pingTicket == ticket, !Task.isCancelled else { return }
            let delay = await session.test(node: nodes[index], unified: unifiedDelay)
            guard pingTicket == ticket, !Task.isCancelled else { return }
            pingReport = delay == -3 ? PingReport(outcome: .timedOut) : PingReport(coreDelay: delay)
            pingDate = Date()
        } catch {
            if pingTicket == ticket { pingReport = PingReport(outcome: .unavailable); pingDate = Date() }
        }
    }
    func readLastDisconnectError() async {
        guard !isBusy, let manager, status == .disconnected else { return }
        isBusy = true
        defer { isBusy = false }
        let error = await withCheckedContinuation { continuation in
            manager.connection.fetchLastDisconnectError { continuation.resume(returning: $0) }
        }
        record(error.map(safeSummary) ?? "系统未提供断开原因，请结合设备日志判断。")
    }
    func removeProfile() async {
        guard isIdle, let manager else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await manager.removeFromPreferences()
            self.manager = nil; hasProfile = false; profileReady = false; status = .invalid; didLoadPreferences = true
            record("本应用的 VPN 配置已移除；钥匙串配置可单独删除。")
        } catch { record(safeSummary(error)) }
    }
    private func finishTitleHandoff(_ ticket: UUID) {
        guard titleHandoff.id == ticket else { return }
        titleHandoff.finish(ticket)
        titleHandoffTimeout?.cancel()
        titleHandoffTimeout = nil
    }
    private func scheduleTitleHandoffTimeout(_ ticket: UUID) {
        titleHandoffTimeout?.cancel()
        titleHandoffTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self, self.titleHandoff.id == ticket else { return }
            self.updateStatus()
            self.finishTitleHandoff(ticket)
        }
    }
    func refreshWidgetConnectionStatus() { updateStatus() }
    private func publishWidgetConnection() {
        guard permitsNetwork else { return }
        let phase: ConnectionWidgetState.Phase
        switch status {
        case .connected: phase = .connected
        case .connecting: phase = .connecting
        case .reasserting: phase = .reconnecting
        case .disconnecting: phase = .disconnecting
        default: phase = hasConfiguration && profileReady ? .disconnected : .unavailable
        }
        ConnectionWidgetState.publish(phase: phase, subscription: hasConfiguration ? currentSubscriptionTitle : "")
    }
    private func updateStatus(fromNotification: Bool = false) {
        defer { publishWidgetConnection() }
        let current = manager?.connection.status ?? .invalid
        titleHandoff.observe(current, notification: fromNotification)
        if !titleHandoff.isPending {
            titleHandoffTimeout?.cancel()
            titleHandoffTimeout = nil
        }
        if status != current {
            cancelForegroundProbes()
            pingTicket = UUID(); isTestingPing = false; pingReport = nil; pingDate = nil
            connectionEpoch = UUID()
            status = current; if current != .connected { runtimeGroupChoices = [:] }; record("系统状态：" + statusText)
            if current != .connected { batchProbes.invalidate(using: self) }
        }
        if ![.connected, .reasserting].contains(current) {
            snapshot = nil
            connectivity = nil
            probeTicket = UUID()
            isProbing = false
        }
    }
    private func safeSummary(_ error: Error) -> String {
        if let error = error as? SubscriptionError { return error.summary }
        if let issue = error as? ConfigurationIssue { return issue.detail + "（\(issue.code.rawValue)）" }
        if let error = error as? PrototypeError { return error.summary + "（\(error.rawValue)）" }
        let ns = error as NSError
        if ns.domain == TunnelDiagnostics.errorDomain, let known = PrototypeError(rawValue: ns.code) {
            return known.summary + "（\(ns.code)）"
        }
        return TunnelDiagnostics.safeErrorSummary(error)
    }
    private func record(_ text: String) {
        message = text
        events.insert(Event(message: text), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }
    private func reloadConfiguration() async throws {
        defer { if didLoadPreferences { publishWidgetConnection() } }
        do {
            let loaded = try await ConfigurationImportWorker.shared.loadLibrary(repository)
            try Task.checkCancellation()
            let library = loaded.library
            subscriptions = library.entries; activeSubscriptionID = library.activeID
            libraryReady = true
            updatePendingCleanup(library.cleanupCount)
            if let prepared = loaded.prepared {
                applyConfiguration(prepared, identity: loaded.configurationID, sourceDigest: loaded.sourceDigest)
            }
            else { clearPreparedConfiguration() }
        } catch {
            // Never keep a selectable cached configuration after a failed storage reload.
            libraryReady = false; clearPreparedConfiguration()
            throw error
        }
    }
    private func clearPreparedConfiguration() {
        cancelForegroundProbes()
        hasConfiguration = false; catalog = nil; configurationSummary = "缺少配置"
        preparedConfiguration = nil; configurationID = ""; runtimeGroupChoices = [:]
        pingReport = nil; pingDate = nil
        batchProbes.bind(scope: "", catalog: nil, using: self)
    }
    @ObservationIgnored private var preparedConfiguration: PrototypeConfiguration.Prepared?
    private func applyConfiguration(_ prepared: PrototypeConfiguration.Prepared, identity: String? = nil, sourceDigest: String? = nil,
                                    preservingNodeProbes: Bool = false) {
        let identity = identity ?? RuntimeIdentity.fingerprint(source: prepared.source, choices: prepared.catalog.choices)
        if configurationID != identity {
            runtimeGroupChoices = [:]
            cancelForegroundProbes(preservingNodeProbes: preservingNodeProbes)
        }
        preparedConfiguration = prepared
        let scope = (activeSubscriptionID?.uuidString ?? "") + ":" + (sourceDigest ?? ConfigurationResourceStore.digest(prepared.source))
        batchProbes.bind(scope: scope, catalog: prepared.catalog, using: self)
        configurationID = identity
        unifiedDelay = prepared.unifiedDelay
        hasConfiguration = true
        catalog = prepared.catalog
        configurationSummary = prepared.summary
    }
    var canDiagnoseDNS: Bool {
        permitsNetwork && status == .connected && !isBusy && !isDiagnosingDNS && !isTestingPing && !isProbing && !batchProbes.isRunning
    }
    var canSelectMember: Bool {
        !isBusy && !isDiagnosingDNS && !isTestingPing && !isProbing &&
        (isIdle || (permitsNetwork && status == .connected))
    }
    @discardableResult func selectMember(group index: Int, member: Int, expectedConfigurationID: String) async -> Bool {
        guard expectedConfigurationID == configurationID, canSelectMember else { return false }
        isBusy = true; isSwitchingNode = true
        defer { isSwitchingNode = false; isBusy = false }
        do {
            guard let id = activeSubscriptionID else { throw PrototypeError.missingConfiguration }
            var stored = try await ConfigurationImportWorker.shared.readRecord(id, repository: repository)
            let prepared = try await ConfigurationImportWorker.shared.prepareStored(stored)
            guard prepared.catalog.groups.indices.contains(index) else { return false }
            let group = prepared.catalog.groups[index]
            guard group.allowsSelection, group.members.indices.contains(member), prepared.catalog.choices[group.name] != group.members[member] else { return false }
            let oldMember = group.members.firstIndex(of: prepared.catalog.choices[group.name] ?? group.members[0]) ?? 0
            stored.choices = prepared.catalog.choices
            stored.choices[group.name] = group.members[member]
            let updated = try await ConfigurationImportWorker.shared.prepareStored(stored)
            let nextID = RuntimeIdentity.fingerprint(source: stored.source, choices: updated.catalog.choices)
            var sample: LiveTelemetry?
            if status == .connected {
                guard let value = await liveSample() else { throw PrototypeError.start }
                sample = value
                let outcome = await selectRuntime(group: index, member: member, session: value.sessionID,
                    before: configurationID, after: nextID)
                if outcome == nil {
                    manager?.connection.stopVPNTunnel()
                    record("切换结果无法确认，已请求断开；保留原选择，请检查系统状态后重新连接。")
                    return false
                }
                guard outcome == true else { record("内核未接受切换；选择保持不变。请等待其他测试结束后重试。"); return false }
            }
            do { try await ConfigurationImportWorker.shared.saveChoices(stored.choices, id: id, repository: repository) }
            catch {
                if let sample {
                    let restored = await selectRuntime(group: index, member: oldMember, session: sample.sessionID,
                        before: nextID, after: configurationID)
                    if restored != true { manager?.connection.stopVPNTunnel() }
                }
                throw error
            }
            // Only choices changed. bind() still clears probes if subscription content changes.
            applyConfiguration(updated, preservingNodeProbes: true)
            clearConnectionResults(preservingNodeProbes: true)
            record(sample == nil ? "选择已保存，下次连接生效。" : "节点已切换；新连接使用新选择，已有连接保留原路径。")
            return true
        } catch { record(safeSummary(error)); return false }
    }
    /// Lost replies are reconciled using session + configuration identity, not optimistic UI.
    private func selectRuntime(group: Int, member: Int, session: UUID, before: String, after: String) async -> Bool? {
        let request = SelectionCommand(requestID: UUID(), sessionID: session, configurationID: before, group: group, member: member)
        if let payload = try? JSONEncoder().encode(request), let data = await engineMessage(payload),
           let reply = try? JSONDecoder().decode(SelectionReply.self, from: data),
           reply.requestID == request.requestID, reply.sessionID == session {
            if reply.accepted && reply.configurationID == after { return true }
            if !reply.accepted && reply.configurationID == before { return false }
        }
        if let data = await engineMessage(Data("telemetry.v2".utf8)),
           let value = try? JSONDecoder().decode(LiveTelemetry.self, from: data), value.sessionID == session {
            if value.configurationID == after { return true }
            if value.configurationID == before { return false }
        }
        return nil
    }

    /// Called after the UI confirms disruption when a tunnel is active.
    func activateSubscription(_ id: UUID, reconnect: Bool) async {
        guard canManageSubscriptions, id != activeSubscriptionID else { return }
        isBusy = true
        var shouldReconnect = false
        defer { isBusy = false }
        do {
            let stored = try await ConfigurationImportWorker.shared.readRecord(id, repository: repository)
            _ = try await ConfigurationImportWorker.shared.prepareStored(stored)
            shouldReconnect = isTunnelActive && reconnect
            try await disconnectForSubscriptionChange()
            try await ConfigurationImportWorker.shared.activate(id, repository: repository)
            try await reloadConfiguration()
            clearConnectionResults()
            record("当前订阅已切换，使用这份订阅保存的节点选择。")
            if shouldReconnect {
                isBusy = false
                start()
            }
        } catch { record(safeSummary(error)) }
    }
    func deleteSubscriptions(_ ids: Set<UUID>, allowDisconnect: Bool = true) async {
        guard canManageSubscriptions, !ids.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let active = activeSubscriptionID, ids.contains(active) {
                // A full swipe cannot authorize a tunnel that started after the row action.
                if permitsNetwork, manager != nil { updateStatus() }
                guard allowDisconnect || !isTunnelActive else {
                    record("当前订阅正在连接；请确认断开 VPN 后再删除。")
                    return
                }
                try await disconnectForSubscriptionChange()
            }
            let library = try await SubscriptionDeletionWorker.commit(ids, repository: repository)
            // Publish the committed removal before the potentially long credential/Geo cleanup.
            // Deleting another subscription cannot change the active parsed configuration.
            subscriptions = library.entries
            activeSubscriptionID = library.activeID
            if activeSubscriptionID == nil {
                hasConfiguration = false; catalog = nil; configurationSummary = "缺少配置"
                configurationID = ""; runtimeGroupChoices = [:]; preparedConfiguration = nil
                batchProbes.bind(scope: "", catalog: nil, using: self)
                clearConnectionResults()
            }
            updatePendingCleanup(library.cleanupCount)
            subscriptionCleanup?.request()
            record("所选订阅已删除；原始 YAML 文件保留。")
        } catch { record(safeSummary(error)) }
    }
    @discardableResult func renameSubscription(_ id: UUID, title: String) async -> Bool {
        guard canManageSubscriptions else { return false }
        isBusy = true; defer { isBusy = false }
        do { try repository.rename(id, title: title); try await reloadConfiguration(); record("订阅名称已更新。"); return true }
        catch { record(safeSummary(error)); return false }
    }
    func setSubscriptionCleanupActive(_ active: Bool) {
        if subscriptionCleanup == nil {
            subscriptionCleanup = SubscriptionCleanupCoordinator { [weak self] in
                await self?.cleanupSubscriptionsIfNeeded() ?? true
            }
        }
        subscriptionCleanup?.setActive(active)
        if active { requestSubscriptionCleanup() }
    }

    func requestSubscriptionCleanup() {
        guard pendingCleanupCount > 0 else { return }
        subscriptionCleanup?.request()
    }

    private func updatePendingCleanup(_ count: Int) {
        subscriptionCleanupRevision = UUID()
        let changed = pendingCleanupCount != count
        pendingCleanupCount = count
        if changed { requestSubscriptionCleanup() }
    }

    /// Maintenance never owns the UI busy flag or republishes parsed configuration.
    /// The repository transaction serializes cleanup with foreground/cloud commits.
    func cleanupSubscriptionsIfNeeded() async -> Bool {
        guard pendingCleanupCount > 0 else { return true }
        guard canManageSubscriptions, !isCleaningSubscriptions else { return false }
        isCleaningSubscriptions = true
        defer { isCleaningSubscriptions = false }
        let revision = subscriptionCleanupRevision
        do {
            let cleaned = try await SubscriptionDeletionWorker.cleanup(repository: repository)
            // A deletion/cloud commit may publish a newer index while this
            // immutable worker result is returning to MainActor.
            guard revision == subscriptionCleanupRevision else { return false }
            pendingCleanupCount = cleaned.cleanupCount
            return pendingCleanupCount == 0
        }
        catch { return false }
    }
    private func disconnectForSubscriptionChange() async throws {
        guard permitsNetwork, let manager else { return }
        updateStatus()
        guard isTunnelActive else { return }
        manager.connection.stopVPNTunnel()
        record("正在断开当前隧道，完成后再更新订阅。")
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            updateStatus()
            if [.disconnected, .invalid].contains(status) { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw SubscriptionError.stopTimeout
    }
    func dnsConfigurationSummary(english: Bool = true) -> [String] {
        guard let stored = try? repository.activeRecord(),
              let root = try? PrototypeConfiguration.decode(stored.source) else { return [] }
        let dns = root["dns"] as? [String: Any] ?? [:]
        let mode = dns["enhanced-mode"] as? String ?? (root["dns"] == nil ? "redir-host" : "core default")
        let safeMode = ["normal", "redir-host", "fake-ip", "core default"].contains(mode) ? mode : "unknown"
        let ipv6 = root["dns"] == nil ? (ConfigurationValidation.boolean(root["ipv6"]) ?? true) : (ConfigurationValidation.boolean(dns["ipv6"]) ?? false)
        let nameservers = (dns["nameserver"] as? [String])?.count ?? 1
        let policies = (dns["nameserver-policy"] as? [String: Any])?.count ?? 0
        if english {
            return ["DNS mode: " + safeMode, "Nameservers: \(nameservers)",
                "Domain policies: \(policies)", "DNS IPv6: " + (ipv6 ? "on" : "off")]
        }
        let modeLabel = safeMode == "core default" ? "内核默认" : safeMode == "unknown" ? "未知" : safeMode
        return ["DNS 模式：" + modeLabel, "上游数量：\(nameservers)",
            "域名策略：\(policies)", "DNS IPv6：" + (ipv6 ? "开启" : "关闭")]
    }
    func subscriptionRecord(_ id: UUID) throws -> StoredConfiguration { try repository.record(id) }
    func diagnoseSubscription(_ id: UUID) async -> ConfigurationCompatibility? {
        guard let stored = try? await ConfigurationImportWorker.shared.readRecord(id, repository: repository) else { return nil }
        return try? await ConfigurationImportWorker.shared.diagnose(stored.source)
    }
    func loadSubscriptionRecord(_ id: UUID) async throws -> StoredConfiguration {
        try await ConfigurationImportWorker.shared.readRecord(id, repository: repository)
    }
    func loadSubscriptionShareURL(_ id: UUID) async throws -> String {
        let stored = try await loadSubscriptionRecord(id)
        return try SubscriptionQRShare.sourceURL(stored.sourceURL)
    }
    /// The review sheet explicitly authorizes interruption and one recovery attempt.
    func applySubscriptionRevision(_ id: UUID, expected: StoredConfiguration,
        prepared: PrototypeConfiguration.Prepared, sourceURL: String?, reconnect: Bool,
        verifiedAt: Date? = nil, routingChange: Bool = false) async -> Bool {
        guard canManageSubscriptions else { return false }
        let active = activeSubscriptionID == id
        let runtimeChanged = expected.source != prepared.source || expected.choices != prepared.catalog.choices
        guard !active || !runtimeChanged || !isTunnelActive || reconnect else { return false }
        isApplyingRouting = routingChange
        isBusy = true
        let ticket = UUID()
        revisionOperation = ticket
        defer { isBusy = false; isApplyingRouting = false; revisionOperation = nil }
        var committed = false
        var interrupted = false
        let wasConnected = active && runtimeChanged && isTunnelActive
        do {
            try await ConfigurationImportWorker.shared.checkRevision(id, expected: expected, repository: repository)
            try checkRevisionOperation(ticket)
            if wasConnected {
                interrupted = true
                try await disconnectForSubscriptionChange()
            }
            try checkRevisionOperation(ticket)
            try await ConfigurationImportWorker.shared.replaceRevision(id, expected: expected, prepared: prepared,
                sourceURL: sourceURL, verifiedAt: verifiedAt, repository: repository)
            committed = true
            try await reloadConfiguration()
            if active && runtimeChanged { clearConnectionResults() }
            if wasConnected && reconnect {
                try await startRevisionAndWait(ticket)
                try? await ConfigurationImportWorker.shared.confirmStartup(id, source: prepared.source,
                    choices: prepared.catalog.choices, repository: repository)
            }
            record(wasConnected ? "新版本已启动；节点可达性仍需 Ping 或真实请求验证。" : "版本已保存，历史版本可手动回滚；未自动连接。")
            return true
        } catch {
            guard revisionOperation == ticket else { return false }
            if committed && error as? PrototypeError == .certificateConsent {
                record(safeSummary(error))
                return true // Saved, awaiting explicit approval; not a failed core startup.
            }
            if interrupted {
                if committed {
                    await recoverRevision(id, source: expected.source, choices: expected.choices,
                        sourceURL: expected.sourceURL, verifiedAt: expected.verifiedAt, ticket: ticket)
                } else {
                    do {
                        try await disconnectForSubscriptionChange()
                        try await startRevisionAndWait(ticket)
                        record("更新未保存；原版本保持不变并已重新启动。")
                    } catch { record("更新未保存；原版本仍在，请手动检查连接。") }
                }
            } else { record(safeSummary(error)) }
            return false
        }
    }
    private func checkRevisionOperation(_ ticket: UUID) throws {
        try Task.checkCancellation()
        guard revisionOperation == ticket else { throw CancellationError() }
    }
    private func recoverRevision(_ id: UUID, source: Data, choices: [String: String],
                                 sourceURL: String?, verifiedAt: Date?, ticket: UUID) async {
        do {
            try checkRevisionOperation(ticket)
            try await disconnectForSubscriptionChange()
            try checkRevisionOperation(ticket)
            let failed = try await ConfigurationImportWorker.shared.readRecord(id, repository: repository)
            let fallback = try await ConfigurationImportWorker.shared.prepareStored(StoredConfiguration(source: source, choices: choices))
            try checkRevisionOperation(ticket)
            try await ConfigurationImportWorker.shared.replaceRevision(id, expected: failed, prepared: fallback,
                sourceURL: sourceURL, verifiedAt: verifiedAt, repository: repository)
            try await reloadConfiguration(); clearConnectionResults()
            try await startRevisionAndWait(ticket)
            try? await ConfigurationImportWorker.shared.confirmStartup(id, source: source, choices: choices, repository: repository)
            record("新版本启动失败；已恢复保留版本并重新启动。请检查真实请求。")
        } catch {
            guard revisionOperation == ticket else { return }
            record("恢复未完成，已保留历史版本；请检查 VPN 状态，在版本历史中手动恢复。")
        }
    }
    private func startRevisionAndWait(_ ticket: UUID) async throws {
        try checkRevisionOperation(ticket)
        guard permitsNetwork, Self.supportsTunnel, manager != nil else { throw PrototypeError.start }
        guard let id = activeSubscriptionID, let prepared = preparedConfiguration else { throw PrototypeError.missingConfiguration }
        let consent = try await ConfigurationImportWorker.shared.certificateConsentDigest(id, prepared: prepared, repository: repository)
        try checkRevisionOperation(ticket)
        if let consent {
            certificateApproval = .init(id: id, digest: consent, nodeCount: prepared.insecureNodeCount)
            throw PrototypeError.certificateConsent
        }
        let profile = try await enabledManagerForStart()
        try checkRevisionOperation(ticket)
        titleHandoff.submit()
        try profile.connection.startVPNTunnel()
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        var observedStart = false
        while ContinuousClock.now < deadline {
            try checkRevisionOperation(ticket)
            updateStatus()
            if status == .connected {
                if let sample = await liveSample(), sample.configurationID == configurationID {
                    try checkRevisionOperation(ticket)
                    return
                }
            }
            if [.connecting, .connected, .reasserting].contains(status) { observedStart = true }
            if observedStart && [.invalid, .disconnected].contains(status) { throw PrototypeError.start }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw PrototypeError.start
    }
    private func clearConnectionResults(preservingNodeProbes: Bool = false) {
        cancelForegroundProbes(preservingNodeProbes: preservingNodeProbes)
        pingTicket = UUID(); probeTicket = UUID()
        pingReport = nil; pingDate = nil; connectivity = nil; snapshot = nil
        isTestingPing = false; isProbing = false
    }
}

@MainActor private final class PingReply {
    private var continuation: CheckedContinuation<PingReport, Never>?
    init(_ continuation: CheckedContinuation<PingReport, Never>) { self.continuation = continuation }
    func finish(_ report: PingReport) { let current = continuation; continuation = nil; current?.resume(returning: report) }
}

@MainActor private final class SnapshotReply {
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func finish(_ data: Data?) { let current = continuation; continuation = nil; current?.resume(returning: data) }
}
