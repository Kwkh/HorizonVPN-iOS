import SwiftUI

struct SubscriptionRenameView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let tunnel: TunnelController
    let subscription: SubscriptionSummary
    @State private var name: String
    @State private var failed = false

    init(tunnel: TunnelController, subscription: SubscriptionSummary) {
        self.tunnel = tunnel
        self.subscription = subscription
        _name = State(initialValue: subscription.title)
    }
    var body: some View {
        NavigationStack {
            Form {
                ClashListContent {
                    Section(settings.text("显示名称", "Display name")) {
                        TextField(settings.text("订阅名称", "Subscription name"), text: $name).textInputAutocapitalization(.never)
                    }
                    if failed { Text(settings.text(tunnel.message, DiagnosticText.english(tunnel.message))).foregroundStyle(.red) }
                }
            }
            .listStyle(.plain).clashScreen()
            .navigationTitle(settings.text("重命名", "Rename"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    InformationButton(title: settings.text("重命名说明", "About renaming"), paragraphs: [settings.text("只修改 App 内的名称，原始 YAML 文件不变。", "Only changes the name in this app. The source YAML stays unchanged.")])
                }
                ToolbarItem(placement: .cancellationAction) { Button(settings.text("取消", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.text("保存", "Save")) {
                        Task {
                            if await tunnel.renameSubscription(subscription.id, title: name) { dismiss() }
                            else { failed = true }
                        }
                    }.disabled(SubscriptionSummary.cleanName(name).isEmpty || !tunnel.canManageSubscriptions)
                }
            }
        }
    }
}
