import SwiftUI

struct NodePingButton: View {
    let tunnel: TunnelController
    let index: Int
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var result: BatchProbeStatus.Result? {
        tunnel.batchProbes.results.first { $0.id == index }
    }
    private var running: Bool { tunnel.batchProbes.isTesting(index) }
    private var label: String {
        switch result?.state {
        case .success: "\(result?.milliseconds ?? 0) ms"
        case .timedOut: settings.text("超时", "Timeout")
        case .failed: settings.text("失败", "Failed")
        default: "Ping"
        }
    }
    var body: some View {
        Button { tunnel.batchProbes.start(using: tunnel, node: index) } label: {
            HStack(spacing: 5) {
                if running { ProgressView().controlSize(.small) }
                else {
                    Text(label).monospacedDigit().contentTransition(.numericText())
                }
            }
            .foregroundStyle(.tint)
            .font(.callout).lineLimit(1).minimumScaleFactor(0.8)
            .frame(minWidth: 54, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(NodePingButtonStyle(preserveAppearance: !tunnel.network.isOffline &&
            (tunnel.batchProbes.isRunning || tunnel.isSwitchingNode)))
        .disabled(!tunnel.canEnqueueNodeProbe || !tunnel.batchProbes.canEnqueue(index))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: label)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: running)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: tunnel.canEnqueueNodeProbe)
        .accessibilityLabel(settings.text("测试节点 \(index + 1)", "Test node \(index + 1)"))
        .accessibilityValue(running ? settings.text("正在测速", "Testing") : label)
        .accessibilityIdentifier("nodes.ping.\(index)")
    }
}

/// A temporary probe or node-selection lock must not dim node results. The Button stays
/// disabled for hit testing and accessibility; normal unavailable states still dim.
private struct NodePingButtonStyle: ButtonStyle {
    let preserveAppearance: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled || preserveAppearance ? (configuration.isPressed ? 0.65 : 1) : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
