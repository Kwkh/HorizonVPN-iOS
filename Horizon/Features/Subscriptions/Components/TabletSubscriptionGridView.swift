import SwiftUI

struct TabletSubscriptionGridView: View {
    let tunnel: TunnelController
    let selecting: Bool
    let selected: Set<UUID>
    let pendingID: UUID?
    let canChoose: Bool
    let choose: (SubscriptionSummary) -> Void
    let details: (UUID) -> Void
    let delete: (UUID) -> Void
    let importURL: () -> Void
    let importFile: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabletCardGrid {
            ViewThatFits(in: .horizontal) {
                HStack { summary; Spacer(); imports }
                VStack(alignment: .leading, spacing: 16) { summary; imports }
            }
            if tunnel.subscriptions.isEmpty {
                ContentUnavailableView(settings.text("还没有订阅", "No configurations yet"), systemImage: "doc.badge.plus")
            }
        } content: {
            ForEach(tunnel.subscriptions) { subscription in
                VStack(alignment: .leading, spacing: 8) {
                    Button { choose(subscription) } label: {
                        SubscriptionRowView(subscription: subscription, isCurrent: subscription.id == tunnel.activeSubscriptionID,
                            isPending: pendingID == subscription.id)
                            .frame(minHeight: 90, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GridSelectionStyle())
                    .disabled(!canChoose)
                    .accessibilityIdentifier("subscription.choose.\(subscription.id)")
                    .accessibilityAddTraits((selecting ? selected.contains(subscription.id) : subscription.id == tunnel.activeSubscriptionID) ? .isSelected : [])
                    HStack {
                        if selecting {
                            Image(systemName: selected.contains(subscription.id) ? "checkmark.circle.fill" : "circle")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Spacer()
                        Button { details(subscription.id) } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(settings.text("\(subscription.title) 详情", "Details for \(subscription.title)"))
                        .accessibilityIdentifier("subscription.details.\(subscription.id)")
                    }.frame(minHeight: 44)
                }
                .modifier(TabletCardStyle(selected: selecting ? selected.contains(subscription.id) : subscription.id == tunnel.activeSubscriptionID))
                .contextMenu {
                    Button(role: .destructive) { delete(subscription.id) } label: {
                        Label(settings.text("删除", "Delete"), systemImage: "trash")
                    }.disabled(!canChoose || selecting)
                }
            }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.text("已保存 · \(tunnel.subscriptions.count)", "Saved · \(tunnel.subscriptions.count)"))
                .font(.title3.weight(.medium)).contentTransition(.numericText())
        }
    }
    private var imports: some View {
        HStack(spacing: 12) {
            Button(action: importURL) { Label(settings.text("链接导入", "Import URL"), systemImage: "link") }
                .accessibilityIdentifier("subscriptions.importURL")
            Button(action: importFile) { Label(settings.text("导入文件", "Import file"), systemImage: "doc.badge.plus") }
        }.buttonStyle(.bordered).disabled(!tunnel.canManageSubscriptions)
    }
}

private struct GridSelectionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
