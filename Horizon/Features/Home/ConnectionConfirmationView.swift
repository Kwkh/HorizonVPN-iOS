import SwiftUI

struct ConnectionConfirmationView: View {
    let onConfirm: (Bool) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var skipNextTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(settings.text("连接 VPN？", "Connect VPN?"), systemImage: "network.badge.shield.half.filled")
                .font(.title2.weight(.medium))
            Text(settings.text("使用当前订阅连接。首次连接仍需允许系统 VPN 配置。",
                               "Connect using this subscription. First use still requires system VPN permission."))
                .font(.callout).foregroundStyle(.secondary)
            Toggle(settings.text("不再提示", "Don't ask again"), isOn: $skipNextTime)
                .tint(Color(uiColor: .systemGreen))
                .accessibilityIdentifier("connection.skipConfirmation")
            HStack {
                Button(settings.text("取消", "Cancel"), role: .cancel) { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(settings.text("连接", "Connect")) {
                    onConfirm(skipNextTime)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(settings.isHorizon || scheme == .dark ? Color.black : Color.white)
                .accessibilityIdentifier("connection.confirm")
            }.controlSize(.large)
        }
        .padding(26)
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
    }
}
