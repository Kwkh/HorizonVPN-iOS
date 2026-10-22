#if os(macOS)
import SwiftUI

/// A native modal notice does not insert rows or change the configuration layout.
/// Keep alert dismissal and the subsequent navigation in separate transactions.
struct MacCloudReviewPromptModifier: ViewModifier {
    @Environment(\.macSubpageTokens) private var subpageTokens
    let library: MacLibraryStore
    let blocked: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(MacICloudSubscriptionSyncStore.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var showingNotice = false
    @State private var notice: CloudReviewNotice?
    @State private var wantsReview = false
    @State private var destination: CloudReviewDestination?

    private var available: Bool {
        visible && scenePhase == .active && !blocked &&
        library.ready && !library.busy && sync.enabled && !sync.working && destination == nil
    }
    private struct Presentation: Equatable {
        let available: Bool
        let reviews: [CloudSyncReviewItem]
        let showing: Bool
        let navigating: Bool
    }

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true }
            .onDisappear {
                visible = false
                showingNotice = false
                wantsReview = false
            }
            .task(id: Presentation(available: available, reviews: sync.reviews,
                                   showing: showingNotice, navigating: wantsReview)) {
                guard available, !showingNotice, !wantsReview,
                      sync.pendingReviewNotice() != nil else { return }
                // Let pushes, sheet dismissal, and row operations settle first.
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                guard !Task.isCancelled, available,
                      let candidate = sync.pendingReviewNotice() else { return }
                notice = candidate
                showingNotice = true
                sync.acknowledgeReviewNotice(candidate)
            }
            .alert(settings.text("订阅同步", "Subscription sync"), isPresented: $showingNotice) {
                Button(settings.text("稍后", "Later"), role: .cancel) { }
                Button(settings.text("去查看", "Review")) { wantsReview = true }
                    .accessibilityIdentifier("subscriptions.reviewNow")
            } message: {
                Text(settings.text("有订阅同步变更需要确认。", "Subscription sync changes need your review."))
            }
            .task(id: wantsReview && !showingNotice && available) {
                guard wantsReview, !showingNotice, available else { return }
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                guard !Task.isCancelled, wantsReview, !showingNotice, available else { return }
                let target = notice?.destination(in: sync.reviews)
                wantsReview = false
                notice = nil
                withAnimation(reduceMotion ? nil : .default) { destination = target }
            }
            .navigationDestination(item: $destination) { route in
                switch route {
                case .item(let item): MacCloudSubscriptionReviewView(item: item, library: library).modifier(MacSubpageTracking(tokens: subpageTokens))
                case .list: MacCloudSubscriptionReviewListView(library: library).modifier(MacSubpageTracking(tokens: subpageTokens))
                }
            }
    }
}

#endif
