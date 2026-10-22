import SwiftUI

struct SubscriptionSourceView: View {
    let store: SubscriptionMaintenanceStore
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var validationTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                ClashListContent {
                    SecureField("https://…", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    if let message = store.message { Text(settings.text(message, DiagnosticText.importEnglish(message))).foregroundStyle(.secondary) }
                }
            }
            .listStyle(.plain).clashScreen()
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.message)
            .navigationTitle(settings.text("订阅来源", "Subscription source"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(settings.text("取消", "Cancel")) { validationTask?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.text("下一步", "Review")) { validationTask = Task { if await store.stageSource(address) { dismiss() } } }
                        .disabled(address.isEmpty || store.working)
                }
                ToolbarItem(placement: .bottomBar) {
                    InformationButton(title: settings.text("来源链接", "Source URL"), paragraphs: [settings.text("链接可能含凭据，将与配置一起保存到本机钥匙串。不会自动下载或刷新，不会把链接写入日志。旧的一次性导入无法找回来源，需要在此重新输入。", "URLs may contain credentials and are saved in device Keychain. No automatic downloads, refreshes or URL logging. Previous one-time imports need their source entered again.")])
                }
            }
        }.clashTint()
        .onDisappear { validationTask?.cancel() }
    }
}
