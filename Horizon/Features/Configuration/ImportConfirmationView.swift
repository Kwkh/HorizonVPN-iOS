import SwiftUI
import NetworkExtension

struct ImportConfirmationView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let tunnel: TunnelController
    let preview: SubscriptionImportPreview
    @State private var makeCurrent: Bool
    @State private var saveFailed = false
    @State private var saving = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Busy work is not a VPN connection transition.
    private var canMakeCurrent: Bool { tunnel.status == .invalid || tunnel.status == .disconnected }
    private var actionColor: Color { settings.isHorizon ? .white : ClashStyle.accent(colorScheme) }

    init(tunnel: TunnelController, preview: SubscriptionImportPreview) {
        self.tunnel = tunnel
        self.preview = preview
        _makeCurrent = State(initialValue: tunnel.isIdle)
    }
    var body: some View {
        NavigationStack {
            List {
                ClashListContent {
                    Section(settings.text("订阅", "Subscription")) {
                        LabeledContent(settings.text("名称", "Name"), value: preview.title)
                            .listRowSeparator(.hidden)
                        Text(settings.text(preview.summary, DiagnosticText.importEnglish(preview.summary)))
                            .listRowSeparator(.hidden)
                        Toggle(settings.text("设为当前订阅", "Set as current"), isOn: $makeCurrent)
                            .tint(Color(uiColor: .systemGreen))
                            .disabled(!canMakeCurrent || saving)
                        if !canMakeCurrent {
                            Text(settings.text("可先保存订阅，再到订阅列表切换并确认重连。", "Save now, then switch from Subscriptions and confirm reconnection."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.listRowBackground(Color.clear)
                    Section {
                        Label { Text(settings.text("结构校验通过", "Structure validated")) } icon: {
                            Image(systemName: "checkmark.seal").foregroundStyle(actionColor)
                        }
                        Label { Text(settings.text("本机钥匙串", "Device Keychain")) } icon: {
                            Image(systemName: "lock").foregroundStyle(actionColor)
                        }
                        HStack {
                            Text(settings.text("iOS 适配 · \(preview.adaptations.count)", "iOS adaptations · \(preview.adaptations.count)"))
                            Spacer()
                            CompatibilityInfoButton(report: tunnel.compatibilityReport).foregroundStyle(actionColor)
                        }
                    }.listRowBackground(Color.clear)
                    if saveFailed {
                        Section {
                            Text(settings.text(tunnel.message, DiagnosticText.importEnglish(tunnel.message))).foregroundStyle(.red)
                        }.listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain).clashScreen()
            .navigationTitle(settings.text("导入订阅", "Import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    InformationButton(title: settings.text("导入说明", "About importing"), paragraphs: [
                        settings.text("保存不会连接 VPN。相同内容与来源会沿用已有订阅和节点选择；内容不同则另存。", "Saving does not connect VPN. Matching content and source reuse the existing subscription and node choices; different content is saved separately."),
                        settings.text("节点、引用和支持范围校验通过；尚未验证服务器证书、节点可用性或实际 DNS 路径。", "Structure and supported fields passed validation. Server certificates, reachability and DNS routing have not been tested."),
                        settings.text("配置和凭据保存于本机钥匙串，与隧道扩展共享。开启 iCloud 同步后，个人订阅及必要依赖也会同步；节点选择仍各设备独立。重启后需先解锁一次。卸载 App 可能保留钥匙串数据。", "Configurations and credentials are stored in this device’s Keychain, shared with the tunnel extension. Optional iCloud sync also syncs personal subscriptions and required dependencies; node choices stay local. Unlock once after restarting. Uninstalling may leave Keychain data.")
                    ]).foregroundStyle(actionColor)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.text("取消", "Cancel")) { dismiss() }.foregroundStyle(actionColor).disabled(saving || tunnel.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving else { return }
                        saving = true; saveFailed = false
                        let activate = makeCurrent && canMakeCurrent
                        Task {
                            if await tunnel.confirmImport(makeCurrent: activate) {
                                dismiss()
                            } else {
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                                    saving = false; saveFailed = true
                                }
                            }
                        }
                    } label: {
                        Text(settings.text("确认保存", "Save"))
                            .opacity(saving ? 0 : 1)
                            .overlay { if saving { ProgressView().tint(actionColor).transition(.opacity) } }
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: saving)
                    }
                    .foregroundStyle(actionColor)
                    .disabled(saving || !tunnel.canManageSubscriptions)
                    .accessibilityLabel(settings.text(saving ? "保存中" : "确认保存", saving ? "Saving" : "Save"))
                    .accessibilityIdentifier("subscription.confirmSave")
                }
            }
            .onChange(of: canMakeCurrent) { _, allowed in if !allowed { makeCurrent = false } }
            .importFailureAlert(isPresented: $saveFailed, detail: tunnel.message)
        }
        .clashTint().interactiveDismissDisabled(saving || tunnel.isBusy)
    }
}
