import SwiftUI

struct SubscriptionMaintenanceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: SubscriptionMaintenanceStore
    @State private var editingSource = false
    init(tunnel: TunnelController, id: UUID) { _store = State(initialValue: .init(id: id, tunnel: tunnel)) }
    var body: some View {
        List {
            ClashListContent {
                Section {
                    LabeledContent(settings.text("来源", "Source"), value: store.record?.sourceURL == nil ? settings.text("未保存链接", "No URL saved") : settings.text("已保护的 HTTPS 链接", "Protected HTTPS URL"))
                    Button(settings.text("设置来源链接", "Set source URL")) { editingSource = true }.disabled(store.working || store.loading)
                    Button(settings.text("手动刷新", "Refresh now")) { store.refresh() }
                        .disabled(store.record?.sourceURL == nil || store.loading || store.working || !store.tunnel.canManageSubscriptions)
                    if store.hasGeoResources {
                        Button(settings.text("更新 Geo 数据", "Update Geo data")) { store.refresh(updateGeo: true) }
                            .disabled(store.working || store.loading || !store.tunnel.canManageSubscriptions)
                    }
                    SubscriptionOperationStatus(busy: store.working, message: store.message)
                    if store.working { Button(settings.text("取消", "Cancel")) { store.cancel() } }
                }
                if let record = store.record {
                    Section(settings.text("当前版本", "Current revision")) {
                        Text("v\(record.revisionNumber ?? 1)").monospacedDigit().contentTransition(.numericText())
                        Text(record.verifiedAt == nil ? settings.text("连通性未验证", "Connectivity not verified") : settings.text("曾有请求成功", "Previous request succeeded"))
                    }
                }
                Section(settings.text("版本历史", "Revision history")) {
                    ForEach(store.revisions) { revision in
                        Button { store.rollback(revision) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("v\(revision.number)")
                                    Text(revision.date, format: .dateTime.month().day().hour().minute()).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: revision.verifiedAt == nil ? "clock.arrow.circlepath" : "checkmark.shield")
                            }
                        }.disabled(store.working || store.loading || !store.tunnel.canManageSubscriptions)
                    }
                    if store.revisions.isEmpty { Text(settings.text("暂无历史版本", "No previous revisions")).foregroundStyle(.secondary) }
                }
            }
        }
        .listStyle(.plain).clashScreen()
        .opacity(store.record == nil ? 0 : 1)
        .overlay {
            if store.record == nil {
                if store.loading { ProgressView(settings.text("正在读取…", "Loading…")) }
                else { ContentUnavailableView(settings.text("订阅无法读取", "Configuration unavailable"), systemImage: "exclamationmark.circle") }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.record != nil)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(settings.text("订阅维护", "Subscription maintenance"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CompatibilityInfoButton(report: store.report) } }
        .sheet(isPresented: $editingSource) { SubscriptionSourceView(store: store) }
        .sheet(item: Binding(get: { editingSource ? nil : store.review }, set: { if $0 == nil { store.discardReview() } })) {
            SubscriptionRevisionReviewView(store: store, review: $0)
        }
        .task { await store.load() }
        .onDisappear { store.cancel() }
    }
}
