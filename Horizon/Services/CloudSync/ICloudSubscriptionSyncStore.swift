import Foundation
import Observation
import UIKit

@MainActor @Observable final class ICloudSubscriptionSyncStore {
    private(set) var enabled: Bool
    private(set) var status: CloudSyncSnapshot.Status = .off
    private(set) var lastSync: Date?
    private(set) var reviews: [CloudSyncReviewItem] = []
    private(set) var working = false
    private(set) var reviewFailed = false
    private(set) var blockedCount = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let engine: SubscriptionCloudSyncEngine
    @ObservationIgnored private let reviewNotices: CloudReviewNoticeTracker
    @ObservationIgnored private weak var tunnel: TunnelController?
    @ObservationIgnored private var allowed = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pendingLibraryRefresh = false
    @ObservationIgnored private var polling = false
    @ObservationIgnored private var automaticTrigger: CloudSyncTrigger?

    init(defaults: UserDefaults = .standard, repository: SubscriptionRepository = ConfigurationVault.repository) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "cloudSync.enabled")
        engine = SubscriptionCloudSyncEngine(repository: repository)
        reviewNotices = CloudReviewNoticeTracker(defaults: defaults)
    }

    func pendingReviewNotice() -> CloudReviewNotice? {
        guard enabled, !working else { return nil }
        return reviewNotices.notice(for: reviews)
    }

    func acknowledgeReviewNotice(_ notice: CloudReviewNotice) {
        reviewNotices.acknowledge(notice, current: reviews)
    }
    func observe(tunnel: TunnelController, allowed: Bool) async {
        self.tunnel = tunnel; self.allowed = allowed && tunnel.permitsNetwork
        if enabled, !self.allowed, status == .off { status = .waiting }
        guard self.allowed, enabled else { return }
        let ticket = generation
        let trigger = CloudSyncTrigger { [weak self] in await self?.syncAutomatically() }
        automaticTrigger = trigger
        let observer = NotificationCenter.default.addObserver(
            forName: SubscriptionRepository.didCommitLocalChange, object: nil, queue: nil
        ) { [weak trigger] _ in
            Task { @MainActor in trigger?.request() }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            trigger.cancel()
            if automaticTrigger === trigger { automaticTrigger = nil }
        }
        if let initial = beginSync(connect: true) {
            await withTaskCancellationHandler { await initial.value } onCancel: { initial.cancel() }
        } else {
            // An earlier manual operation may still be finishing at foreground entry.
            trigger.request(after: .zero)
        }
        while !Task.isCancelled, enabled, self.allowed, ticket == generation {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !working, !polling else { continue }
            let value = await poll()
            guard !Task.isCancelled, enabled, self.allowed, ticket == generation else { return }
            if working {
                // A new send can reserve the store while the poll is suspended.
                // Keep its library refresh, but do not replace the newer UI status.
                pendingLibraryRefresh = pendingLibraryRefresh || value.libraryChanged
                continue
            }
            await publish(value)
        }
    }
    func setAllowed(_ allowed: Bool) { self.allowed = allowed }
    func enable() {
        guard tunnel?.permitsNetwork == true else { return }
        enabled = true; defaults.set(true, forKey: "cloudSync.enabled")
        if !allowed { status = .waiting }
    }
    func disable() {
        enabled = false; defaults.set(false, forKey: "cloudSync.enabled")
        generation = UUID(); operation?.cancel(); operation = nil
        automaticTrigger?.cancel()
        status = .off; working = false; reviews = []
        blockedCount = 0
        Task { await engine.stop() }
    }
    @discardableResult func retry(allowAccountChange: Bool = false) -> Bool {
        beginSync(connect: true, restart: true, allowAccountChange: allowAccountChange) != nil
    }
    @discardableResult func syncNow() -> Bool { beginSync() != nil }

    /// Reserve the operation before scheduling it, so taps and automatic triggers
    /// cannot start two sends during the same main-actor turn. UI states stay unchanged.
    private func beginSync(connect: Bool = false, restart: Bool = false,
                           allowAccountChange: Bool = false) -> Task<Void, Never>? {
        guard enabled, allowed, !working else { return nil }
        let ticket = generation
        working = true; status = .syncing
        let task = Task {
            defer { if generation == ticket { working = false } }
            guard await waitForPolling(ticket) else { return }
            if restart { await engine.stop() }
            guard enabled, allowed, ticket == generation, !Task.isCancelled else { return }
            let value: CloudSyncSnapshot
            if connect {
                UIApplication.shared.registerForRemoteNotifications()
                value = await engine.connect(allowAccountChange: allowAccountChange)
            } else { value = await engine.tick(sendNow: true) }
            guard enabled, allowed, ticket == generation, !Task.isCancelled else { return }
            await publish(value)
        }
        operation = task
        return task
    }
    private func syncAutomatically() async {
        let ticket = generation
        // Retain one coalesced request if a manual send/review or local poll is busy.
        while enabled, allowed, ticket == generation, !Task.isCancelled, working || polling {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard enabled, allowed, ticket == generation, !Task.isCancelled,
              let task = beginSync() else { return }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    private func waitForPolling(_ ticket: UUID) async -> Bool {
        while polling, enabled, allowed, ticket == generation, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return enabled && allowed && ticket == generation && !Task.isCancelled
    }
    private func poll() async -> CloudSyncSnapshot {
        polling = true
        defer { polling = false }
        return await engine.tick()
    }
    func resolve(_ item: CloudSyncReviewItem, resolution: SubscriptionCloudSyncEngine.Resolution) {
        guard enabled, allowed, !working, let tunnel else { return }
        let ticket = generation
        working = true; reviewFailed = false
        operation = Task {
            defer { if ticket == generation { working = false } }
            guard await waitForPolling(ticket) else { return }
            do {
                try await tunnel.performCloudReview(localID: item.localID) { [engine] in
                    try await engine.resolve(item.id, expectedVersion: item.version, resolution: resolution)
                }
                let value = await engine.snapshot()
                guard enabled, allowed, ticket == generation, !Task.isCancelled else { return }
                await publish(value)
                automaticTrigger?.request()
            } catch { if ticket == generation { reviewFailed = true } }
        }
    }
    private func publish(_ value: CloudSyncSnapshot) async {
        guard enabled else { return }
        status = value.status; lastSync = value.lastSync; reviews = value.reviews
        blockedCount = value.blockedCount
        pendingLibraryRefresh = pendingLibraryRefresh || value.libraryChanged
        if pendingLibraryRefresh, let tunnel, await tunnel.reloadCloudSubscriptionSummaries() { pendingLibraryRefresh = false }
    }
}
