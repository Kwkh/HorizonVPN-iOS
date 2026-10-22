import SwiftUI

struct CloudSubscriptionReviewListView: View {
    let tunnel: TunnelController
    @Environment(AppSettings.self) private var settings
    @Environment(ICloudSubscriptionSyncStore.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            ClashListContent {
                if sync.reviews.isEmpty {
                    ContentUnavailableView(settings.text("没有待处理变更", "No changes to review"), systemImage: "checkmark.icloud")
                } else {
                    ForEach(sync.reviews) { item in
                        NavigationLink { CloudSubscriptionReviewView(item: item, tunnel: tunnel) } label: {
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
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("需要处理", "Needs review"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.reviews)
    }
}
