import SwiftUI

/// The parent coordinates profile installation; this sheet never starts VPN.
struct VPNSetupView: View {
    let preparing: Bool
    let checkingNetwork: Bool
    let canPrepare: Bool
    let unavailableReason: String?
    let errorMessage: String?
    let onAdd: () -> Void
    let onLater: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(settings.text("添加 VPN 配置？", "Add VPN profile?"), systemImage: "network.badge.shield.half.filled")
                .font(.title2.weight(.medium))
            Text(settings.text("添加后会进行一次轻量联网检查；若系统询问，请允许使用网络。此过程不会连接 VPN，也不会发送订阅凭据。可稍后设置。",
                               "After adding the profile, a brief Internet check lets iOS request network access if needed. This does not connect VPN or send subscription credentials. You can set up later."))
                .font(.callout).foregroundStyle(.secondary)
            if checkingNetwork {
                Text(settings.text("正在检查网络；若出现系统提示，请选择允许。", "Checking Internet access. Allow the system prompt if one appears."))
                    .font(.callout).foregroundStyle(.secondary).transition(.opacity)
            }
            if let message = errorMessage ?? unavailableReason {
                Text(message).font(.callout).foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                    .contentTransition(.opacity).transition(.opacity)
            }
            HStack {
                Button(settings.text("稍后", "Not now"), action: onLater)
                    .disabled(preparing && !checkingNetwork)
                    .accessibilityIdentifier("onboarding.vpnLater")
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        if preparing { ProgressView().tint(.primary) }
                        Text(settings.text(preparing ? (checkingNetwork ? "检查网络…" : "正在添加…") : (errorMessage == nil ? "添加配置" : "重试"), preparing ? (checkingNetwork ? "Checking…" : "Adding…") : (errorMessage == nil ? "Add profile" : "Retry")))
                            .contentTransition(.opacity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(settings.isHorizon || scheme == .dark ? Color.black : Color.white)
                .disabled(preparing || !canPrepare)
                .accessibilityIdentifier("onboarding.vpnAdd")
            }.controlSize(.large)
        }
        .padding(26)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: preparing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: checkingNetwork)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: errorMessage)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(preparing && !checkingNetwork)
    }
}
