#if os(macOS)
import Foundation
import Observation
import AppKit

/// Injection boundary for offline coordination tests; the real implementation is
/// exactly the same CloudKit engine used by iPhone and iPad.
protocol MacCloudSyncClient: Sendable {
    func connect(allowAccountChange: Bool) async -> CloudSyncSnapshot
    func stop() async
    func tick(sendNow: Bool) async -> CloudSyncSnapshot
    func reconcileCloudLibrary() async -> CloudSyncSnapshot
    func snapshot() async -> CloudSyncSnapshot
    func resolve(_ id: UUID, expectedVersion: UUID, resolution: SubscriptionCloudSyncEngine.Resolution) async throws
}
extension SubscriptionCloudSyncEngine: MacCloudSyncClient { }

@MainActor @Observable final class MacICloudSubscriptionSyncStore {
    private(set) var enabled: Bool
    private(set) var status: CloudSyncSnapshot.Status = .off
    private(set) var lastSync: Date?
    private(set) var reviews: [CloudSyncReviewItem] = []
    private(set) var working = false
    private(set) var reviewFailed = false
    private(set) var blockedCount = 0
    @ObservationIgnored private let permitsNetwork: Bool
    @ObservationIgnored private let registerNotifications: @MainActor () -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let engine: any MacCloudSyncClient
    @ObservationIgnored private let reviewNotices: CloudReviewNoticeTracker
    @ObservationIgnored private weak var library: MacLibraryStore?
    @ObservationIgnored private var allowed = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pendingLibraryRefresh = false
    @ObservationIgnored private var polling = false
    @ObservationIgnored private var automaticTrigger: CloudSyncTrigger?
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var lastRemoteCheck: ContinuousClock.Instant?
    @ObservationIgnored private var pageRefresh: Task<Void, Never>?
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant

    init(defaults: UserDefaults = .standard, repository: SubscriptionRepository, permitsNetwork: Bool = true, client: (any MacCloudSyncClient)? = nil, now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }, registerNotifications: @escaping @MainActor () -> Void = { NSApplication.shared.registerForRemoteNotifications() }) {
        self.defaults = defaults
        self.now = now
        self.permitsNetwork = permitsNetwork
        self.registerNotifications = registerNotifications
        enabled = permitsNetwork && defaults.bool(forKey: "cloudSync.enabled")
        engine = client ?? SubscriptionCloudSyncEngine(repository: repository)
        reviewNotices = CloudReviewNoticeTracker(defaults: defaults)
    }

    func pendingReviewNotice() -> CloudReviewNotice? {
        guard enabled, !working else { return nil }
        return reviewNotices.notice(for: reviews)
    }

    func acknowledgeReviewNotice(_ notice: CloudReviewNotice) {
        reviewNotices.acknowledge(notice, current: reviews)
    }
    func observe(library: MacLibraryStore, allowed: Bool) async {
        self.library = library; self.allowed = allowed && permitsNetwork && library.ready
        if enabled, !self.allowed, status == .off { status = .waiting }
        guard self.allowed, enabled else { return }
        // Reconcile summaries after foreground entry even if the previous task
        // was cancelled just after a replica commit consumed libraryChanged.
        pendingLibraryRefresh = true
        let ticket = generation
        let trigger = CloudSyncTrigger { [weak self] in await self?.syncAutomatically() }
        automaticTrigger = trigger
        let observer = NotificationCenter.default.addObserver(
            forName: SubscriptionRepository.didCommitLocalChange, object: nil, queue: nil
        ) { [trigger] _ in
            Task { @MainActor in trigger.request() }
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
            if ticket == generation { pendingLibraryRefresh = pendingLibraryRefresh || value.libraryChanged }
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
    func setAllowed(_ allowed: Bool) { self.allowed = allowed && permitsNetwork }
    func enable() {
        guard permitsNetwork else { return }
        enabled = true; defaults.set(true, forKey: "cloudSync.enabled")
        if !allowed { status = .waiting }
    }
    func disable() {
        enabled = false; defaults.set(false, forKey: "cloudSync.enabled")
        generation = UUID(); operation?.cancel(); operation = nil
        automaticTrigger?.cancel()
        pageRefresh?.cancel(); pageRefresh = nil
        status = .off; working = false; reviews = []
        blockedCount = 0
        Task { await engine.stop() }
    }
    @discardableResult func retry(allowAccountChange: Bool = false) -> Bool {
        beginSync(connect: true, restart: true, allowAccountChange: allowAccountChange) != nil
    }
    @discardableResult func syncNow() -> Bool { beginSync() != nil }

    /// The selected destination owns this clock; a started sync remains owned by
    /// the store so navigating away only cancels future checks, not an import.
    func observeConfigurationPage(wait: @Sendable (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }) async {
        let ticket = generation
        while enabled, ticket == generation, !Task.isCancelled {
            // The destination and the root observation can start in either order.
            guard allowed else {
                do { try await wait(.milliseconds(100)) } catch { return }
                continue
            }
            configurationPageEntered()
            if let refresh = pageRefresh { await refresh.value }
            guard enabled, allowed, ticket == generation, !Task.isCancelled else { return }
            let remaining = lastRemoteCheck.map { now().duration(to: $0.advanced(by: .seconds(5))) }
                ?? .milliseconds(100)
            do { try await wait(max(.milliseconds(50), remaining)) } catch { return }
        }
    }

    /// Owned here rather than by the destination's task: leaving the page must
    /// not cancel a CloudKit fetch halfway through applying downloaded records.
    func configurationPageEntered() {
        guard enabled, allowed, pageRefresh == nil else { return }
        let ticket = generation
        pageRefresh = Task {
            defer { if ticket == generation { pageRefresh = nil } }
            while enabled, allowed, ticket == generation, !Task.isCancelled, working || polling {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard enabled, allowed, ticket == generation, !Task.isCancelled,
                  Self.shouldRefreshConfigurationPage(last: lastRemoteCheck, now: now()),
                  let task = beginSync() else { return }
            await task.value
        }
    }

    static func shouldRefreshConfigurationPage(last: ContinuousClock.Instant?,
                                               now: ContinuousClock.Instant = .now) -> Bool {
        last.map { $0.duration(to: now) >= .seconds(5) } ?? true
    }

    func setForeground(_ foreground: Bool) {
        let returning = foreground && !self.foreground
        self.foreground = foreground
        if returning { automaticTrigger?.request(after: .zero) }
    }

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
            let value = await checkRemoteLibrary(ticket: ticket, connect: connect,
                allowAccountChange: allowAccountChange)
            lastRemoteCheck = now()
            if ticket == generation { pendingLibraryRefresh = pendingLibraryRefresh || value.libraryChanged }
            guard enabled, allowed, ticket == generation, !Task.isCancelled else { return }
            await publish(value)
        }
        operation = task
        return task
    }
    /// Every explicit remote round uses the same completeness check as Sync now.
    /// Local three-second processing ticks do not enumerate the cloud library.
    private func checkRemoteLibrary(ticket: UUID, connect: Bool = false,
                                    allowAccountChange: Bool = false) async -> CloudSyncSnapshot {
        var value: CloudSyncSnapshot
        if connect {
            registerNotifications()
            value = await engine.connect(allowAccountChange: allowAccountChange)
        } else { value = await engine.tick(sendNow: true) }
        guard enabled, allowed, ticket == generation, !Task.isCancelled else { return value }
        // snapshot() consumes this flag; preserve it before the inventory takes
        // another snapshot, including when only the incremental round committed.
        pendingLibraryRefresh = pendingLibraryRefresh || value.libraryChanged
        if value.status == .ready || value.status == .waiting {
            value = await engine.reconcileCloudLibrary()
        }
        if ticket == generation { pendingLibraryRefresh = pendingLibraryRefresh || value.libraryChanged }
        return value
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
        // Push delivery is opportunistic. A bounded check also works when the Mac
        // stays open or loses keyboard focus, without animating the manual button.
        let remote = Self.shouldCheckRemote(last: lastRemoteCheck, foreground: foreground, now: now())
        let ticket = generation
        let value = remote ? await checkRemoteLibrary(ticket: ticket) : await engine.tick(sendNow: false)
        if remote, ticket == generation { lastRemoteCheck = now() }
        return value
    }
    static func shouldCheckRemote(last: ContinuousClock.Instant?, foreground: Bool,
                                  now: ContinuousClock.Instant = .now) -> Bool {
        let interval: Duration = foreground ? .seconds(30) : .seconds(120)
        return last.map { $0.duration(to: now) >= interval } ?? true
    }
    func resolve(_ item: CloudSyncReviewItem, resolution: SubscriptionCloudSyncEngine.Resolution) {
        guard enabled, allowed, !working, let library else { return }
        let ticket = generation
        working = true; reviewFailed = false
        operation = Task {
            defer { if ticket == generation { working = false } }
            guard await waitForPolling(ticket) else { return }
            do {
                try await library.performCloudReview(localID: item.localID) { [engine] in
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
        if pendingLibraryRefresh, let library, await library.reloadCloudSubscriptionSummaries() { pendingLibraryRefresh = false }
    }
}

#endif
