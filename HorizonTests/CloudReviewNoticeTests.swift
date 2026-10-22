import Foundation
import Testing
@testable import Horizon

@MainActor @Suite struct CloudReviewNoticeTests {
    private func item(id: UUID = UUID(), version: UUID = UUID(), reason: CloudSyncEntry.Review = .current) -> CloudSyncReviewItem {
        .init(id: id, version: version, localID: id, title: "FICTIONAL subscription", deleted: false, reason: reason)
    }

    @Test func laterPersistsAcrossRecreationAndReasonChangesDoNotRepeatNotice() throws {
        let suite = "Horizon.ReviewNoticeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let review = item()
        let tracker = CloudReviewNoticeTracker(defaults: defaults)
        let notice = try #require(tracker.notice(for: [review]))
        tracker.acknowledge(notice, current: [review])
        #expect(tracker.notice(for: [review]) == nil)
        let restored = CloudReviewNoticeTracker(defaults: defaults)
        #expect(restored.notice(for: [item(id: review.id, version: review.version, reason: .invalid)]) == nil)
        #expect(restored.notice(for: [item(id: review.id)]) != nil)
        #expect(!defaults.dictionaryRepresentation().description.contains(review.title))
    }

    @Test func batchedNoticeAcknowledgesOnlyVersionsActuallyShown() throws {
        let suite = "Horizon.ReviewNoticeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = CloudReviewNoticeTracker(defaults: defaults)
        let a = item(), b = item()
        let notice = try #require(tracker.notice(for: [a, b]))
        let newer = item(id: a.id)
        tracker.acknowledge(notice, current: [newer, b])
        #expect(tracker.notice(for: [a, b]) == nil)
        #expect(tracker.notice(for: [newer, b]) != nil)
        #expect(tracker.notice(for: []) == nil)
    }

    @Test func waitingForAnEditorDoesNotAcknowledgeAnything() throws {
        let suite = "Horizon.ReviewNoticeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = CloudReviewNoticeTracker(defaults: defaults)
        let reviews = [item()]
        #expect(tracker.notice(for: reviews) != nil)
        #expect(tracker.notice(for: reviews) != nil)
        #expect(CloudReviewNoticeTracker(defaults: defaults).notice(for: reviews) != nil)
    }

    @Test func singleRevisionRoutesDirectlyButMultipleRevisionsUseLiveList() {
        let a = item(), b = item()
        #expect(CloudReviewNotice(items: [a]).destination(in: [a]) == .item(a))
        #expect(CloudReviewNotice(items: [a, b]).destination(in: [a, b]) == .list)
        #expect(CloudReviewNotice(items: [a]).destination(in: [a, b]) == .list)
    }

    @Test func resolvedOrReplacedRevisionCannotPushStaleReview() {
        let original = item()
        let notice = CloudReviewNotice(items: [original])
        #expect(notice.destination(in: []) == nil)
        #expect(notice.destination(in: [item(id: original.id)]) == .list)
        #expect(notice.destination(in: [item()]) == .list)
    }
}
