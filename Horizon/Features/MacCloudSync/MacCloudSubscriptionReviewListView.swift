#if os(macOS)
import SwiftUI

struct MacCloudSubscriptionReviewListView: View {
    @Environment(\.macSubpageTokens) private var subpageTokens
    let library: MacLibraryStore
    @Environment(AppSettings.self) private var settings
    @Environment(MacICloudSubscriptionSyncStore.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Group {
                if sync.reviews.isEmpty {
                    ContentUnavailableView(settings.text("没有待处理变更", "No changes to review"), systemImage: "checkmark.icloud")
                } else {
                    ForEach(sync.reviews) { item in
                        NavigationLink { MacCloudSubscriptionReviewView(item: item, library: library).modifier(MacSubpageTracking(tokens: subpageTokens)) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).foregroundStyle(.primary)
                                Text(item.deleted ? settings.text("已在其他设备删除", "Deleted on another device") : settings.text("有待处理的云端版本", "Cloud revision available"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("cloud.review.\(item.id)")
                    }
                }
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).background(.black)
        .navigationTitle(settings.text("需要处理", "Needs review"))
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.reviews)
    }
}

#Preview {
    let library = MacLibraryStore(offline: true)
    NavigationStack {
        MacCloudSubscriptionReviewListView(library: library)
    }
    .environment(AppSettings(defaults: UserDefaults(suiteName: "Horizon.MacCloudPreview")!))
    .environment(MacICloudSubscriptionSyncStore(repository: library.cloudRepository, permitsNetwork: false))
    .preferredColorScheme(.dark)
    .frame(width: 700, height: 520)
}

#endif
