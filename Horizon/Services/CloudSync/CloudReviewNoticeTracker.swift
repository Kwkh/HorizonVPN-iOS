import Foundation

nonisolated struct CloudReviewNotice: Equatable {
    let items: [CloudSyncReviewItem]

    func destination(in current: [CloudSyncReviewItem]) -> CloudReviewDestination? {
        guard !current.isEmpty else { return nil }
        if items.count == 1, let shown = items.first,
           let latest = current.first(where: { $0.id == shown.id && $0.version == shown.version }),
           current.count == 1 {
            return .item(latest)
        }
        // A changed revision or additional pending items must use the live list,
        // never push a stale snapshot that can no longer be reviewed.
        return .list
    }
}

nonisolated enum CloudReviewDestination: Hashable {
    case item(CloudSyncReviewItem)
    case list
}

/// Device-local presentation history, separate from sync acknowledgments.
/// Store only opaque revision IDs, never titles, URLs, credentials or payloads.
@MainActor final class CloudReviewNoticeTracker {
    private let defaults: UserDefaults
    private let key = "cloudSync.reviewNotices.v1." + CloudSyncScope.environment
    private var shown: Set<String>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        shown = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func notice(for items: [CloudSyncReviewItem]) -> CloudReviewNotice? {
        guard items.contains(where: { !shown.contains(identity($0)) }) else { return nil }
        return .init(items: items)
    }

    func acknowledge(_ notice: CloudReviewNotice, current: [CloudSyncReviewItem]) {
        // Retain all pending versions so dismissing a notice stays effective even
        // across navigation, process restarts, and temporary network failures.
        let currentIDs = Set(current.map(identity))
        let historical = shown.subtracting(currentIDs).sorted().prefix(512)
        shown = Set(historical).union(shown.intersection(currentIDs)).union(notice.items.map(identity))
        defaults.set(shown.sorted(), forKey: key)
    }

    private func identity(_ item: CloudSyncReviewItem) -> String {
        item.id.uuidString + ":" + item.version.uuidString
    }
}
