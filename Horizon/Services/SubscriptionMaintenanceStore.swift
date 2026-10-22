import Foundation
import Observation
import OSLog

@MainActor @Observable
final class SubscriptionMaintenanceStore {
    struct Review: Identifiable {
        let id = UUID()
        let expected: StoredConfiguration
        let prepared: PrototypeConfiguration.Prepared
        let sourceURL: String?
        let verifiedAt: Date?
        let changes: [String]
        let rollback: Bool
        let assessment: RoutingAssessment
        let report: ConfigurationCompatibility
    }
    let id: UUID
    let tunnel: TunnelController
    private(set) var record: StoredConfiguration?
    private(set) var report: ConfigurationCompatibility?
    private(set) var review: Review?
    private(set) var working = false
    private(set) var message: String?
    private(set) var pendingRouting: ConfigurationRouting?
    @ObservationIgnored private var task: Task<Void, Never>?
    init(id: UUID, tunnel: TunnelController) { self.id = id; self.tunnel = tunnel }
    var revisions: [SubscriptionRevision] {
        guard let record else { return [] }
        var values = record.history ?? []
        if let usable = record.lastUsable, usable.id != record.revisionID, !values.contains(where: { $0.id == usable.id }) { values.append(usable) }
        return values
    }
    private(set) var hasGeoResources = false
    private(set) var assessment: RoutingAssessment?
    private(set) var loading = true
    func load() async {
        loading = record == nil
        defer { loading = false }
        do {
            let value = try await tunnel.loadSubscriptionRecord(id)
            if record?.source == value.source, record?.choices == value.choices, report != nil {
                try Task.checkCancellation()
                record = value
                return
            }
            let diagnosis = try await ConfigurationImportWorker.shared.diagnose(value.source)
            try Task.checkCancellation()
            let hasGeo = try await ConfigurationImportWorker.shared.hasGeoResources(value.source)
            try Task.checkCancellation()
            let assessment = try await ConfigurationImportWorker.shared.routingAssessment(value.source)
            let routing = try await ConfigurationImportWorker.shared.routingMode(value.source)
            try Task.checkCancellation()
            record = value; report = diagnosis; hasGeoResources = hasGeo; self.assessment = assessment; self.routing = routing
        }
        catch is CancellationError { }
        catch { record = nil; report = nil; hasGeoResources = false; message = "订阅无法读取；未更改现有记录。" }
    }
    func cancel() { task?.cancel() }
    func discardReview() { review = nil; ConfigurationResourceStore.discardPending() }
    func refresh(updateGeo: Bool = false) {
        guard !working, !loading, tunnel.canManageSubscriptions else { return }
        guard tunnel.permitsNetwork else { message = "离线演示不下载订阅。"; return }
        discardReview()
        working = true; message = nil
        task = Task {
            defer { working = false; task = nil; if review == nil { ConfigurationResourceStore.discardPending() } }
            await load()
            guard !Task.isCancelled, let expected = record, expected.sourceURL != nil || updateGeo else { message = "请先设置来源链接。"; return }
            do {
                let deadline = ContinuousClock.now.advanced(by: .seconds(30))
                let downloaded: Data
                if let url = expected.sourceURL { downloaded = try await SubscriptionDownloader.fetch(url, deadline: deadline) }
                else { downloaded = try ConfigurationSnapshot.original(expected.source) }
                let data = try await ConfigurationImportWorker.shared.resources(downloaded, permitsNetwork: tunnel.permitsNetwork,
                    previousSource: expected.source, updateGeo: updateGeo, routing: try ConfigurationRouting.mode(in: expected.source), deadline: deadline)
                try Task.checkCancellation()
                if data == expected.source { message = "订阅内容没有变化。"; return }
                await stage(data, expected: expected, sourceURL: expected.sourceURL, rollback: false, choices: expected.choices)
            } catch is CancellationError { message = "已取消刷新；现有版本保留。" }
            catch let error as ConfigurationIssue { message = error.detail }
            catch let error as SubscriptionDownloader.Failure { message = error.safeReason + "；现有版本保留。" }
            catch { message = "下载失败；现有版本保留。" }
        }
    }
    func changeRouting(_ mode: ConfigurationRouting, applyImmediately: Bool = false) {
        guard !working, !loading, tunnel.canManageSubscriptions else { return }
        if applyImmediately { applyRoutingDirectly(mode); return }
        discardReview(); working = true; message = nil
        task = Task {
            defer { working = false; task = nil; if review == nil { ConfigurationResourceStore.discardPending() } }
            await load()
            guard !Task.isCancelled, let expected = record else { return }
            do {
                let data = try await ConfigurationImportWorker.shared.routingCandidate(mode, stored: expected)
                try Task.checkCancellation()
                await stage(data, expected: expected, sourceURL: expected.sourceURL, rollback: false, choices: expected.choices)
            } catch is CancellationError { }
            catch let issue as ConfigurationIssue { message = issue.detail }
            catch { message = "分流方案准备失败；原配置保持不变。" }
        }
    }
    private(set) var routing: ConfigurationRouting = .subscription
    /// Lightweight Home state: detailed diagnostics are loaded only on their pages.
    func loadRouting() async {
        loading = record == nil
        defer { loading = false }
        do {
            let value = try await tunnel.loadSubscriptionRecord(id)
            let mode = try await ConfigurationImportWorker.shared.routingMode(value.source)
            try Task.checkCancellation()
            record = value
            routing = mode
        } catch is CancellationError { }
        catch { record = nil; message = "订阅无法读取；未更改现有记录。" }
    }
    private func applyRoutingDirectly(_ mode: ConfigurationRouting) {
        guard tunnel.activeSubscriptionID == id else { return }
        review = nil
        working = true; pendingRouting = mode; message = nil
        task = Task {
            let totalStart = ContinuousClock.now
            defer {
                Self.logRoutingPhase("total", since: totalStart)
                pendingRouting = nil; working = false; task = nil
            }
            await ConfigurationImportWorker.shared.discardPendingResources()
            do {
                var phaseStart = ContinuousClock.now
                let expected = try await tunnel.loadSubscriptionRecord(id)
                Self.logRoutingPhase("read", since: phaseStart)
                phaseStart = .now
                let data = try await ConfigurationImportWorker.shared.routingCandidate(mode, stored: expected)
                Self.logRoutingPhase("candidate", since: phaseStart)
                phaseStart = .now
                let prepared = try await ConfigurationImportWorker.shared.validateRouting(data, choices: expected.choices)
                Self.logRoutingPhase("validation", since: phaseStart)
                try Task.checkCancellation()
                guard !prepared.isFixture || !tunnel.permitsNetwork else { throw PrototypeError.missingConfiguration }
                guard tunnel.activeSubscriptionID == id else { throw SubscriptionError.staleRevision }
                phaseStart = .now
                let success = await tunnel.applySubscriptionRevision(id, expected: expected, prepared: prepared,
                    sourceURL: expected.sourceURL, reconnect: true, routingChange: true)
                Self.logRoutingPhase("apply-and-reconnect", since: phaseStart)
                let failure = success ? nil : tunnel.message
                phaseStart = .now
                await loadRouting()
                Self.logRoutingPhase("read-result", since: phaseStart)
                if let failure { message = failure }
            } catch is CancellationError { }
            catch let issue as ConfigurationIssue { message = issue.detail }
            catch let error as SubscriptionError { message = error.summary }
            catch { message = "分流方案准备失败；原配置保持不变。" }
            await ConfigurationImportWorker.shared.discardPendingResources()
        }
    }
    private static func logRoutingPhase(_ phase: String, since start: ContinuousClock.Instant) {
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        // Fixed stage names and timings only; no URLs, configuration text or node names.
        Logger(subsystem: "Kenote.Clash", category: "RoutingPerformance")
            .info("phase=\(phase, privacy: .public) milliseconds=\(milliseconds, privacy: .public)")
    }
    func stageSource(_ input: String) async -> Bool {
        guard !working, !loading, tunnel.canManageSubscriptions else { return false }
        working = true
        await load()
        guard let record else { working = false; return false }
        defer { working = false }
        do {
            let url = try SubscriptionDownloader.validatedURL(input).absoluteString
            await stage(record.source, expected: record, sourceURL: url, rollback: false, choices: record.choices, verifiedAt: record.verifiedAt)
            return review != nil
        } catch { message = "需要完整 HTTPS 地址，不接受内嵌账号密码或片段。"; return false }
    }
    func rollback(_ revision: SubscriptionRevision) {
        guard !working, !loading, tunnel.canManageSubscriptions else { return }
        working = true
        task = Task {
            defer { working = false; task = nil }
            await load()
            guard !Task.isCancelled, let record, revisions.contains(where: { $0.id == revision.id }) else { return }
            await stage(revision.source, expected: record, sourceURL: record.sourceURL, rollback: true,
                choices: revision.choices, verifiedAt: revision.verifiedAt)
        }
    }
    private func stage(_ data: Data, expected: StoredConfiguration, sourceURL: String?, rollback: Bool,
                       choices: [String: String], verifiedAt: Date? = nil) async {
        do {
            let validated = try await ConfigurationImportWorker.shared.validate(data, choices: choices)
            report = validated.report
            let prepared = validated.prepared
            guard !prepared.isFixture || !tunnel.permitsNetwork else { throw PrototypeError.missingConfiguration }
            let changes = try await ConfigurationImportWorker.shared.changes(expected.source, data)
                + ["需重新选择的策略组：\(choices.count - choices.filter { prepared.catalog.choices[$0.key] == $0.value }.count)", sourceURL == expected.sourceURL ? "来源链接保持不变。" : "来源链接将更新并保存到本机钥匙串。"]
            let assessment = try await ConfigurationImportWorker.shared.routingAssessment(data)
            try Task.checkCancellation()
            review = .init(expected: expected, prepared: prepared, sourceURL: sourceURL, verifiedAt: verifiedAt,
                           changes: changes, rollback: rollback, assessment: assessment, report: validated.report)
            message = nil
        } catch is CancellationError { message = "已取消刷新；现有版本保留。" }
        catch let failure as ConfigurationImportWorker.Failure { report = failure.report; message = failure.issue.detail }
        catch { message = "候选版本校验失败；现有版本保留。" }
    }
    func apply(reconnect: Bool) async -> Bool {
        guard !working, review != nil else { return false }
        working = true
        defer { working = false }
        return await applyPreparedReview(reconnect: reconnect)
    }
    private func applyPreparedReview(reconnect: Bool) async -> Bool {
        guard let review else { return false }
        let success = await tunnel.applySubscriptionRevision(id, expected: review.expected,
            prepared: review.prepared, sourceURL: review.sourceURL, reconnect: reconnect, verifiedAt: review.verifiedAt)
        if success {
            // Keep the presented sheet stable until its owner dismisses it.
            await load()
            message = nil
        } else {
            let failure = tunnel.message
            // Read the actual saved revision, including any startup recovery.
            await load()
            message = failure
        }
        return success
    }
}
