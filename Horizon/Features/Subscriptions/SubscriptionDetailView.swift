import SwiftUI

struct SubscriptionDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tunnel: TunnelController
    let id: UUID
    @State private var loadingReport = true
    @State private var report: ConfigurationCompatibility?
    @State private var confirmSwitch = false
    @State private var confirmDelete = false
    @State private var renaming: SubscriptionSummary?
    @State private var sharing: SubscriptionSummary?
    @State private var hasShareURL = false
    @State private var operationError: String?

    private var subscription: SubscriptionSummary? { tunnel.subscriptions.first { $0.id == id } }
    private var isCurrent: Bool { tunnel.activeSubscriptionID == id }

    var body: some View {
        List {
            ClashListContent {
                if let subscription {
                    Section {
                        HStack(spacing: 12) {
                            Text(subscription.title).font(.title2).bold().textSelection(.enabled)
                            Spacer(minLength: 0)
                            ProgressView().controlSize(.small)
                                .frame(width: 18, height: 18)
                                .opacity(tunnel.isBusy ? 1 : 0)
                                .accessibilityHidden(!tunnel.isBusy)
                                .accessibilityLabel(settings.text("正在处理…", "Working…"))
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tunnel.isBusy)
                        }
                        Text(settings.subscriptionSummary(subscription)).foregroundStyle(.secondary)
                        if let fileName = subscription.fileName, !fileName.isEmpty { LabeledContent(settings.text("导入文件", "Source file"), value: fileName) }
                        if let date = subscription.importedAt {
                            LabeledContent(settings.text("导入时间", "Imported")) { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                        }
                    }.listRowSeparator(.hidden)
                    Section {
                        Button(tunnel.isTunnelActive ? settings.text("切换并重新连接", "Switch & reconnect") : settings.text("设为当前订阅", "Use configuration")) {
                            if tunnel.isTunnelActive { confirmSwitch = true }
                            else { activate(reconnect: false) }
                        }.disabled(isCurrent || !tunnel.canManageSubscriptions)
                        if isCurrent {
                            NavigationLink(settings.text("节点与策略组", "Nodes & groups")) { NodeSelectionView(tunnel: tunnel) }
                                .disabled(!tunnel.hasConfiguration)
                        }
                        NavigationLink { SubscriptionMaintenanceView(tunnel: tunnel, id: id) } label: {
                            Label(settings.text("刷新与版本历史", "Refresh & revisions"), systemImage: "clock.arrow.circlepath")
                        }
                        if hasShareURL {
                            Button { sharing = subscription } label: {
                                Label(settings.text("分享二维码", "Share QR code"), systemImage: "qrcode")
                            }
                            .accessibilityIdentifier("subscription.shareQRCode")
                        }
                        Button(settings.text("重命名", "Rename")) { renaming = subscription }.disabled(!tunnel.canManageSubscriptions)
                    }
                    Section {
                        Button(settings.text("删除此订阅", "Delete configuration"), role: .destructive) { confirmDelete = true }
                            .disabled(!tunnel.canManageSubscriptions)
                    }
                } else {
                    ContentUnavailableView(settings.text("订阅已删除", "Configuration removed"), systemImage: "doc.badge.minus")
                }
            }
        }
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("订阅详情", "Subscription"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CompatibilityInfoButton(report: report, isLoading: loadingReport)
            }
        }
        .task(id: subscription?.sourceDigest) {
            loadingReport = true
            let value = await tunnel.diagnoseSubscription(id)
            guard !Task.isCancelled else { return }
            report = value; loadingReport = false
        }
        .sheet(item: $renaming) { SubscriptionRenameView(tunnel: tunnel, subscription: $0) }
        .sheet(item: $sharing) { SubscriptionQRCodeView(tunnel: tunnel, subscription: $0) }
        .task(id: subscription?.updatedAt) {
            let available = (try? await tunnel.loadSubscriptionShareURL(id)) != nil
            guard !Task.isCancelled else { return }
            hasShareURL = available
        }
        .alert(settings.text("切换订阅并重新连接？", "Switch and reconnect?"), isPresented: $confirmSwitch) {
            Button(settings.text("取消", "Cancel"), role: .cancel) { }
            Button(settings.text("切换并重连", "Switch & reconnect")) { activate(reconnect: true) }
        } message: { Text(settings.text("将断开当前 VPN，使用这份订阅的规则、DNS 和已保存的节点重新连接。期间网络会短暂中断。", "Disconnects VPN and reconnects with this configuration’s rules, DNS and saved node choices. Network access will be interrupted briefly.")) }
        .alert(settings.text("操作未完成", "Couldn't complete operation"), isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { operationError = nil }
        } message: {
            Text(settings.text(operationError ?? "", DiagnosticText.english(operationError ?? "")))
        }
        .alert(settings.text("删除此订阅？", "Delete this configuration?"), isPresented: $confirmDelete) {
            Button(settings.text("取消", "Cancel"), role: .cancel) { }
            Button(settings.text("删除", "Delete"), role: .destructive) {
                Task {
                    await tunnel.deleteSubscriptions([id])
                    if !tunnel.subscriptions.contains(where: { $0.id == id }) { dismiss() }
                    else { operationError = tunnel.message }
                }
            }
        } message: {
            Text(isCurrent ? settings.text("将删除本机记录和凭据；若正在连接，会先断开。删除后不自动选择其他订阅。原始 YAML 文件保留。", "Removes local credentials and disconnects VPN if active. No other configuration is selected. The source YAML is preserved.") : settings.text("将删除本机记录和凭据。原始 YAML 文件保留，需要恢复时可重新导入。", "Removes local credentials. The source YAML is preserved and can be reimported."))
        }
    }
    private func activate(reconnect: Bool) {
        Task {
            await tunnel.activateSubscription(id, reconnect: reconnect)
            if tunnel.activeSubscriptionID != id { operationError = tunnel.message }
        }
    }
}
