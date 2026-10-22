#if os(macOS)
import SwiftUI

/// Probe updates animate locally without rebuilding the Metal scene or chart.
struct MacHomePingView: View {
    let probes: MacProbeStore
    let index: Int
    let enabled: Bool
    let visible: Bool
    let test: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = probes.label(index)
        Button(action: test) {
            Text(label).monospacedDigit().lineLimit(1)
                .contentTransition(.numericText())
                .frame(width: 88, height: 22)
                .padding(8)
        }
        .buttonStyle(.glass)
        .allowsHitTesting(enabled && !probes.isTesting(index))
        .animation(reduceMotion || !visible ? nil : .smooth(duration: 0.3), value: label)
        .accessibilityLabel(MacText.value("测试当前节点延迟", "Test selected node latency"))
        .accessibilityValue(label)
    }
}
#endif
