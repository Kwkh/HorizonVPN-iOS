import SwiftUI

/// Native glass control whose intrinsic width animates with its current title.
struct HorizonConnectionButton: View {
    enum Action: Equatable { case connect, disconnect, cancel, stopping }
    let action: Action
    let disabled: Bool
    let unavailable: Bool
    var networkUnavailable = false
    let onTap: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        switch action {
        case .connect: settings.text("连接", "Connect")
        case .disconnect, .stopping: settings.text("断开", "Disconnect")
        case .cancel: settings.text("取消", "Cancel")
        }
    }
    private var isDisabled: Bool { disabled || action == .stopping }
    private var symbol: String {
        // A preferences refresh can temporarily disable interaction without
        // changing connection readiness. Do not turn that into arrow → x → arrow.
        action == .connect ? (unavailable ? "xmark" : "arrow.up.right") : "power"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                Text(title).contentTransition(.opacity)
            }
            .font(.callout.weight(.medium))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 20).frame(minHeight: 44)
            .opacity(networkUnavailable ? 0.45 : 1)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        .disabled(isDisabled)
        .accessibilityLabel(action == .stopping ? settings.text("正在断开 VPN", "Disconnecting VPN") : title)
        .accessibilityIdentifier("home.connection")
        .accessibilityHint(networkUnavailable ? settings.text("无网络连接，轻点查看提示", "No network connection. Tap for details.") : "")
        // Animate the native glass and its label in one coordinate space. The
        // flexible outer frame owns centering INSIDE the animation boundary;
        // the capsule still takes only its current title's intrinsic width.
        .geometryGroup()
        .frame(maxWidth: .infinity, alignment: .center)
        // Keep this transaction local: never animate the surrounding hero or chart.
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: action)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: title)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isDisabled)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: symbol)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: networkUnavailable)
    }
}
