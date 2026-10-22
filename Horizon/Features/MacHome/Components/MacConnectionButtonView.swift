#if os(macOS)
import SwiftUI

/// Keep transient operation locks separate from the native glass appearance.
struct MacConnectionButtonView: View {
    let idle: Bool
    let unavailable: Bool
    let enabled: Bool
    let frameChanged: (CGRect) -> Void
    let onTap: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { idle ? settings.text("连接", "Connect") : settings.text("断开连接", "Disconnect") }
    private var symbol: String { unavailable ? "xmark" : idle ? "arrow.up.right" : "stop" }

    var body: some View {
        Button {
            guard enabled && !unavailable else { return }
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                Text(title).contentTransition(.opacity)
            }
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
        .disabled(unavailable)
        .allowsHitTesting(enabled)
        .accessibilityLabel(title)
        .accessibilityRespondsToUserInteraction(enabled && !unavailable)
        .accessibilityIdentifier("mac.home.connection")
        // Measure the capsule before the centering frame so wall hover remains
        // excluded only beneath the button, not across the full scene width.
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("mac.home.scene"))
        } action: { frameChanged($0) }
        .geometryGroup()
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: idle)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: unavailable)
    }
}
#endif
