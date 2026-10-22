import SwiftUI

/// Both mobile home styles use the existing validated subscription switch flow.
struct HomeSubscriptionMenu: View {
    let tunnel: TunnelController
    let visible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var switchTarget: SubscriptionSummary?
    @State private var confirmSwitch = false
    @State private var pendingID: UUID?
    @State private var operationError: String?

    private var title: String {
        tunnel.hasConfiguration ? tunnel.currentSubscriptionTitle : "—"
    }
    private var canChoose: Bool {
        visible && pendingID == nil && !confirmSwitch && tunnel.canManageSubscriptions
    }
    private var animation: Animation? { reduceMotion || !visible ? nil : .smooth(duration: 0.3) }

    var body: some View {
        Menu {
            ForEach(tunnel.subscriptions) { subscription in
                Button { requestSwitch(subscription) } label: {
                    if subscription.id == tunnel.activeSubscriptionID {
                        Label(subscription.title, systemImage: "checkmark")
                    } else {
                        Text(subscription.title)
                    }
                }
                .disabled(!canChoose || subscription.id == tunnel.activeSubscriptionID)
                .accessibilityIdentifier("home.subscription.choose.\(subscription.id)")
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .contentTransition(.opacity)
                    // Animate content inside a stable Text, not insertion/removal
                    // of a label whose parent is simultaneously being scrolled.
                    .animation(animation, value: title)
                    .lineLimit(1).truncationMode(.middle)
                    // On iPad, keep the indicator next to the title; the parent
                    // row's spacer supplies the distance to the trailing Ping.
                    .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? nil : .infinity,
                        alignment: .leading)
                ZStack {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .opacity(pendingID == nil ? 1 : 0)
                    ProgressView().controlSize(.small)
                        .opacity(pendingID == nil ? 0 : 1)
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                .animation(animation, value: pendingID)
            }
            // Ancestor movement follows scrolling immediately; local symbol/text
            // transitions share this geometry instead of chasing global positions.
            .geometryGroup()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tunnel.subscriptions.isEmpty || !tunnel.libraryReady)
        // Temporary controller locks should not dim and restore the home label.
        // Menu actions recheck this guard, including accessibility activation.
        .allowsHitTesting(canChoose)
        .accessibilityLabel(settings.text("切换订阅", "Switch subscription"))
        .accessibilityValue(pendingID == nil ? title : settings.text("正在切换订阅", "Switching subscription"))
        .accessibilityIdentifier("home.subscription.menu")
        .alert(settings.text("切换订阅并重新连接？", "Switch and reconnect?"),
            isPresented: $confirmSwitch, presenting: switchTarget) { subscription in
            Button(settings.text("取消", "Cancel"), role: .cancel) { switchTarget = nil }
            Button(settings.text("切换并重连", "Switch & reconnect")) { activate(subscription, reconnect: true) }
        } message: { subscription in
            Text(settings.text("切换到“\(subscription.title)”并重新连接，网络会短暂中断。",
                "Switch to “\(subscription.title)” and reconnect. Network access will be interrupted briefly."))
        }
        .alert(settings.text("切换未完成", "Could not switch"), isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { operationError = nil }
        } message: {
            Text(settings.text(operationError ?? "", DiagnosticText.importEnglish(operationError ?? "")))
        }
    }

    private func requestSwitch(_ subscription: SubscriptionSummary) {
        guard canChoose, subscription.id != tunnel.activeSubscriptionID,
              tunnel.subscriptions.contains(where: { $0.id == subscription.id }) else { return }
        if tunnel.isTunnelActive {
            switchTarget = subscription
            confirmSwitch = true
        } else {
            activate(subscription, reconnect: false)
        }
    }

    private func activate(_ subscription: SubscriptionSummary, reconnect: Bool) {
        guard pendingID == nil, tunnel.canManageSubscriptions,
              subscription.id != tunnel.activeSubscriptionID,
              tunnel.subscriptions.contains(where: { $0.id == subscription.id }) else { return }
        pendingID = subscription.id
        Task { @MainActor in
            await tunnel.activateSubscription(subscription.id, reconnect: reconnect)
            if tunnel.activeSubscriptionID != subscription.id { operationError = tunnel.message }
            pendingID = nil
            switchTarget = nil
        }
    }
}
