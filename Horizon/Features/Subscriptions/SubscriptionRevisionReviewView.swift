import SwiftUI

struct SubscriptionRevisionReviewView: View {
    let store: SubscriptionMaintenanceStore
    let review: SubscriptionMaintenanceStore.Review
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var confirmReconnect = false
    @State private var showingInfo = false
    @State private var showingFailure = false
    private var needsReconnect: Bool { store.tunnel.activeSubscriptionID == store.id && store.tunnel.isTunnelActive &&
        (review.expected.source != review.prepared.source || review.expected.choices != review.prepared.catalog.choices) }
    var body: some View {
        NavigationStack {
            List {
                ClashListContent {
                    Section(settings.text("变更摘要", "Changes")) {
                        ForEach(visibleChanges, id: \.self) {
                            Text(settings.text($0, DiagnosticText.importEnglish($0)))
                                .listRowSeparator(.hidden)
                        }
                    }.listRowBackground(Color.clear)
                    if review.assessment.needsReview {
                        Section {
                            Label(settings.text("存在优先规则或 DNS 策略", "Existing rule or DNS overrides"), systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }.listRowBackground(Color.clear)
                    }
                    Section {
                        Button {
                            if needsReconnect { confirmReconnect = true }
                            else { apply(false) }
                        } label: {
                            HStack {
                                Text(needsReconnect ? settings.text("应用并重新连接", "Apply & reconnect") : settings.text("保存版本", "Save revision"))
                                Spacer()
                                SubscriptionRowActivity(busy: store.working)
                            }.contentShape(Rectangle())
                        }
                        .disabled(store.working || !store.tunnel.canManageSubscriptions)
                        .alert(settings.text("保存未完成", "Couldn't save revision"), isPresented: $showingFailure) {
                            Button(settings.text("好", "OK"), role: .cancel) { }
                        } message: {
                            Text(settings.text(store.message ?? "请重试。", DiagnosticText.importEnglish(store.message ?? "请重试。")))
                        }
                        .padding(.top, 14)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.primary.opacity(contrast == .increased ? 0.35 : (colorScheme == .dark ? 0.14 : 0.17)))
                                .frame(height: 0.5)
                                .padding(.horizontal, 8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .listRowSeparator(.hidden)
                    }.listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain).clashScreen().navigationTitle(review.rollback ? settings.text("回滚预览", "Review rollback") : settings.text("更新预览", "Review update"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingInfo = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel(settings.text("更新详情", "Update details"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.text("取消", "Cancel")) { store.discardReview(); dismiss() }.disabled(store.working)
                }
            }
            .alert(settings.text("应用版本并重连？", "Apply and reconnect?"), isPresented: $confirmReconnect) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("应用", "Apply")) { apply(true) }
            } message: {
                Text(settings.text("将短暂断开 VPN。新版本启动失败时，恢复更新前的版本并尝试重连一次；连接成功不等于所有节点可用。", "VPN will briefly disconnect. If startup fails, restore the previous revision and try reconnecting once. A running tunnel does not prove node reachability."))
            }
        }.clashTint().interactiveDismissDisabled(store.working)
            .sheet(isPresented: $showingInfo) { SubscriptionRevisionInfoView(review: review) }
    }
    private var visibleChanges: [String] {
        let changes = review.changes.filter {
            !$0.contains("未改变") && $0 != "节点新增 0 · 删除 0 · 字段变化 0" &&
            $0 != "需重新选择的策略组：0" && $0 != "来源链接保持不变。" &&
            !$0.hasPrefix("依赖资源变化：0 项")
        }.map { value in
            if value.hasPrefix("分流：智能分流") { return settings.text("分流：智能分流", "Routing: Smart routing") }
            if value.hasPrefix("分流：恢复遵循订阅") { return settings.text("分流：遵循订阅", "Routing: Follow configuration") }
            if value.hasPrefix("依赖资源变化：") {
                let count = value.dropFirst("依赖资源变化：".count).prefix(while: { $0.isNumber })
                return settings.text("依赖更新：\(count) 项", "Resources updated: \(count)")
            }
            if value == "来源链接将更新并保存到本机钥匙串。" { return settings.text("来源链接将更新", "Source URL will change") }
            return value
        }
        return changes.isEmpty ? [settings.text("配置内容未变化", "Configuration unchanged")] : changes
    }
    private func apply(_ reconnect: Bool) {
        Task {
            if await store.apply(reconnect: reconnect) { dismiss() }
            else { showingFailure = true }
        }
    }
}
