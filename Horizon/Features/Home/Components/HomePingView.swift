import SwiftUI
import NetworkExtension

/// A compact entry point to the same selected-node test used by the full Ping page.
struct HomePingView: View {
    let tunnel: TunnelController
    let visible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingConnectionHint = false

    var body: some View {
        Button {
            guard !tunnel.isBusy, !tunnel.isApplyingRouting else { return }
            guard tunnel.canTestPing else {
                showingConnectionHint = true
                return
            }
            Task { await tunnel.testPing() }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    if tunnel.isTestingPing {
                        ProgressView().controlSize(.small).transition(.opacity)
                    } else {
                        Image(systemName: symbol)
                            .contentTransition(reduceMotion || !visible ? .identity : .symbolEffect(.replace))
                            .transition(.opacity)
                    }
                }.frame(width: 22, height: 22)
                Text("Ping")
                Text(result).monospacedDigit()
                    .contentTransition(.numericText(value: Double(tunnel.pingReport?.milliseconds ?? 0)))
                    .layoutPriority(1)
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8).frame(minHeight: 32)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        // Let adjacent subscription text yield width before compressing the Ping result.
        .layoutPriority(1)
        // Subscription/node commits lock interaction without flashing the glass
        // capsule's disabled palette. The action guard also covers accessibility.
        .disabled(tunnel.isTestingPing || tunnel.batchProbes.isRunning)
        .allowsHitTesting(!tunnel.isBusy && !tunnel.isApplyingRouting)
        // Match the parent layout's 0.3-second smooth transition for sibling movement.
        .animation(animation, value: tunnel.isTestingPing)
        .animation(animation, value: result)
        .animation(animation, value: symbol)
        .alert(settings.text("暂时无法测速", "Cannot test yet"), isPresented: $showingConnectionHint) {
            Button(settings.text("知道了", "OK"), role: .cancel) { }
        } message: {
            Text(settings.text("请确认网络可用，并在节点页选择可测试的节点。", "Check your network and select a testable node in Nodes."))
        }
        .accessibilityLabel(settings.text("测试当前节点 Ping", "Test selected node Ping"))
        .accessibilityValue(result)
        .accessibilityHint(settings.text("通过所选节点测量 HTTP 延迟，无需连接 VPN", "Measure HTTP latency through the selected node. VPN is optional."))
        .accessibilityIdentifier("home.ping")
    }

    private var animation: Animation? { reduceMotion || !visible ? nil : .smooth(duration: 0.3) }
    private var symbol: String {
        guard !tunnel.network.isOffline && tunnel.hasConfiguration else { return "wifi.slash" }
        return tunnel.pingReport?.outcome == .timedOut ? "wifi.exclamationmark" : "wifi"
    }
    private var result: String {
        if tunnel.isTestingPing { return "…" }
        guard let report = tunnel.pingReport else { return "—" }
        switch report.outcome {
        case .success: return "\(report.milliseconds ?? 0) ms"
        case .timedOut: return settings.text("超时", "Timeout")
        case .failed: return settings.text("失败", "Failed")
        case .busy: return settings.text("忙碌", "Busy")
        case .unavailable: return settings.text("不可用", "Unavailable")
        }
    }
}
