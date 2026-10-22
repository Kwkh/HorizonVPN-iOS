import SwiftUI

struct HorizonInformationView: View {
    let tunnel: TunnelController
    let telemetry: TelemetryStore
    let visible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                HomeSubscriptionMenu(tunnel: tunnel, visible: visible)
                    .font(.title3)
                Spacer(minLength: 16)
                HomePingView(tunnel: tunnel, visible: visible)
            }
            .offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : 0)
            .animation(pingLayoutAnimation, value: tunnel.pingReport)
            .animation(pingLayoutAnimation, value: tunnel.isTestingPing)
            if let id = tunnel.activeSubscriptionID {
                HomeRoutingPickerView(tunnel: tunnel, id: id, visible: visible)
            }
            Rectangle().fill(.white.opacity(0.16)).frame(height: 0.5)
            TrafficChartView(telemetry: telemetry, visible: visible)
            Rectangle().fill(.white.opacity(0.16)).frame(height: 0.5)
                .accessibilityHidden(true)
            HomeNodeListView(tunnel: tunnel, visible: visible)
                // Widen just the node list: the page's 26 pt inset becomes 16 pt.
                .padding(.horizontal, -6)
//            if !tunnel.isTunnelActive && !tunnel.events.isEmpty {
//                NavigationLink { DiagnosticsView(tunnel: tunnel, managedExternally: true) } label: {
//                    Label(settings.text("连接诊断", "Connection diagnostics"), systemImage: "waveform.path")
//                }.transition(.opacity)
//            }
        }
        // Only the header animates Ping geometry. Connection/subscription changes
        // must not interpolate the graph or the lazy node inventory's layout.
    }
    private var pingLayoutAnimation: Animation? { reduceMotion || !visible ? nil : .smooth(duration: 0.3) }
}
