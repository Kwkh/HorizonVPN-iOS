#if os(macOS)
import SwiftUI

/// A compact readout shared across sidebar destinations; no extra IPC polling.
struct MacSidebarTrafficView: View {
    let telemetry: MacTelemetryStore
    let active: Bool
    let visible: Bool
    let offline: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            // Keep this slot mounted so sidebar rows and scrolling never reflow.
            // The plot's display clock pauses on Home; the shared history remains.
            MacTrafficChart(telemetry: telemetry, active: active && visible, compact: true)
                .transaction { $0.animation = nil }
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visible)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
            if offline {
                Text(MacText.value("离线预览 · 虚构订阅", "Offline preview · Demo data"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }
}
#endif
