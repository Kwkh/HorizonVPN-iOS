import ActivityKit
import SwiftUI

struct VPNActivityPingButton: View {
    let sessionID: UUID
    let chinese: Bool
    let state: VPNActivityAttributes.ContentState
    let stale: Bool
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { state.probeLabel(chinese: chinese, stale: stale) }
    private var testing: Bool { state.probe == .running && !stale }

    var body: some View {
        // Keep a stable label and hit region inside the native intent button.
        // The fixed hit region must not depend on the current result's text width.
        Button(intent: PingCurrentNodeIntent(sessionID: sessionID.uuidString)) {
            Text(title)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: title)
                .invalidatableContent()
                .padding(.horizontal, 10)
                .frame(width: 112, height: 44)
                .contentShape(.interaction, Capsule())
        }
        .buttonStyle(PingFeedbackStyle(testing: testing))
        // Repeated taps while testing are coalesced by the service.
        .disabled(!enabled)
        .accessibilityLabel(chinese ? "测试当前节点" : "Ping current node")
        .accessibilityValue(title)
    }
}

/// Keep press feedback local to the system button, without waiting for an
/// ActivityKit update or animating the label's size and position.
private struct PingFeedbackStyle: ButtonStyle {
    let testing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = configuration.isPressed || testing
        configuration.label
            .background {
                // Animate the view opacity, not the shape's fill style. Do not
                // add invalidatableContent(false): it breaks intent hit testing
                // on the remote Live Activity surface (see the routing audit).
                Capsule()
                    .fill(.white)
                    .opacity(highlighted ? 0.22 : 0.12)
                    .animation(reduceMotion || luminanceReduced ? nil : .easeInOut(duration: 0.3),
                               value: highlighted)
            }
    }
}
