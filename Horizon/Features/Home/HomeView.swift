import SwiftUI
import NetworkExtension

struct HomeView: View {
    let tunnel: TunnelController
    let telemetry: TelemetryStore
    let visible: Bool
    let entranceVisible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmConnection = false
    @State private var connecting = false
    @State private var showNetworkAlert = false
    @State private var pendingNetworkAlert = false

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("HORIZON").font(.system(size: 29, weight: .medium, design: .rounded)).tracking(5)
                        Spacer()
                        HomePingView(tunnel: tunnel, visible: visible)
                    }
                    .animation(pingLayoutAnimation, value: tunnel.pingReport)
                    .animation(pingLayoutAnimation, value: tunnel.isTestingPing)
                    .animation(pingLayoutAnimation, value: tunnel.status)
                    .padding(.top, 12)
                    .modifier(HomeEntrance(presented: entranceVisible, rise: 6))
                    VStack(spacing: 0) {
                        ZStack {
                            ParticleFieldView(connected: tunnel.status == .connected,
                                animating: visible && scenePhase == .active && settings.particles)
                            Button {
                                guard !tunnel.isApplyingRouting else { return }
                                if tunnel.canStop { tunnel.stop() }
                                else { requestConnection() }
                            } label: {
                                Image(systemName: "power")
                                    .font(.system(size: 35, weight: .light))
                                    .frame(width: 96, height: 96)
                                    .opacity(networkBlocked ? 0.45 : 1)
                                    .animation(transitionAnimation, value: networkBlocked)
                                    .foregroundStyle(tunnel.status == .connected ? ClashStyle.accent(scheme) : .primary)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: tunnel.status == .connected)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .disabled(!networkBlocked && (connecting || tunnel.isAwaitingConnectionStatus || (tunnel.isBusy && !tunnel.isApplyingRouting) || !tunnel.didLoadPreferences ||
                                (!tunnel.canStop && (!tunnel.hasConfiguration || tunnel.status == .disconnecting))))
                            .allowsHitTesting(!tunnel.isApplyingRouting)
                            .accessibilityLabel(tunnel.canStop ? settings.text("断开 VPN", "Disconnect VPN") : settings.text("连接 VPN", "Connect VPN"))
                            .accessibilityIdentifier("home.connection")
                            .accessibilityHint(networkBlocked ? settings.text("无网络连接，轻点查看提示", "No network connection. Tap for details.") : "")
                        }.frame(height: 206)
                        Text(statusTitle).font(.system(size: 30, weight: .medium))
                            .contentTransition(.opacity)
                            .animation(transitionAnimation, value: statusTitle)
                        HStack(spacing: 7) {
                            Circle().fill(tunnel.status == .connected ? ClashStyle.accent(scheme) : .secondary).frame(width: 5, height: 5)
                                .animation(transitionAnimation, value: tunnel.status == .connected)
                            HomeSubscriptionMenu(tunnel: tunnel, visible: visible)
                        }.font(.callout).foregroundStyle(.secondary).padding(.top, 10)
                    }.frame(maxWidth: .infinity).padding(.bottom, 8)
                        .modifier(HomeEntrance(presented: entranceVisible, delay: 0.05))
                    Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5)
                        .modifier(HomeEntrance(presented: entranceVisible, delay: 0.12, rise: 0))
                    if let id = tunnel.activeSubscriptionID {
                        HomeRoutingPickerView(tunnel: tunnel, id: id, visible: visible)
                            .modifier(HomeEntrance(presented: entranceVisible, delay: 0.12))
                    }
                    TrafficChartView(telemetry: telemetry, visible: visible)
                        .modifier(HomeEntrance(presented: entranceVisible, delay: 0.12))
                    Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5)
                        .accessibilityHidden(true)
                        .modifier(HomeEntrance(presented: entranceVisible, delay: 0.16, rise: 0))
                    HomeNodeListView(tunnel: tunnel, visible: visible)
                        // Widen just the node list: the page's 26 pt inset becomes 16 pt.
                        .padding(.horizontal, -10)
                        .modifier(HomeEntrance(presented: entranceVisible, delay: 0.16))
                    VStack(alignment: .leading, spacing: 12) {
                        if showWaiting {
                            Label(settings.text("等待采样", "Waiting for samples"), systemImage: "clock")
                                .font(.callout).foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
//                        if showDiagnostics {
//                            NavigationLink { DiagnosticsView(tunnel: tunnel, managedExternally: true) } label: {
//                                Label(settings.text("连接诊断", "Connection diagnostics"), systemImage: "waveform.path")
//                                    .font(.callout)
//                            }.padding(.top, 4)
//                            .transition(.opacity)
//                        }
                    }
                    .animation(transitionAnimation, value: showWaiting)
                    .animation(transitionAnimation, value: showDiagnostics)
                    .modifier(HomeEntrance(presented: entranceVisible, delay: 0.16))
                }.padding(.horizontal, 26).padding(.bottom, 30)
            }
        }
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .clashScreen().toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .automatic : .hidden, for: .navigationBar)
        .sheet(isPresented: $confirmConnection, onDismiss: {
            if pendingNetworkAlert { pendingNetworkAlert = false; showNetworkAlert = true }
        }) {
            ConnectionConfirmationView { skipNextTime in
                if skipNextTime { settings.confirmVPNConnection = false }
                beginConnection()
            }
        }
        .modifier(NetworkUnavailableAlert(isPresented: $showNetworkAlert))
    }
    private var networkBlocked: Bool { tunnel.network.isOffline && !tunnel.isTunnelActive }
    private func requestConnection() {
        guard !tunnel.network.isOffline else { showNetworkAlert = true; return }
        if settings.confirmVPNConnection { confirmConnection = true }
        else { beginConnection() }
    }
    private func beginConnection() {
        guard !tunnel.network.isOffline else {
            if confirmConnection { pendingNetworkAlert = true } else { showNetworkAlert = true }
            return
        }
        connecting = true
        Task {
            await tunnel.connectCurrentProfile()
            if tunnel.network.isOffline && !tunnel.isTunnelActive { showNetworkAlert = true }
            connecting = false
        }
    }
    private var transitionAnimation: Animation? { reduceMotion || !visible ? nil : .easeInOut(duration: 0.3) }
    private var pingLayoutAnimation: Animation? { reduceMotion || !visible ? nil : .smooth(duration: 0.3) }
    private var showWaiting: Bool { tunnel.status == .connected && telemetry.stale }
    private var showDiagnostics: Bool { !tunnel.isTunnelActive && !tunnel.events.isEmpty }
    private var statusTitle: String {
        if connecting || tunnel.isAwaitingConnectionStatus {
            return settings.statusText(tunnel.connectionTitleStatus(preparing: connecting))
        }
        if !tunnel.didLoadPreferences {
            return tunnel.didFinishInitialRefresh ? settings.text("无法读取状态", "Status unavailable") : settings.text("正在同步", "Syncing")
        }
        if !tunnel.hasConfiguration { return settings.text("准备开始", "Ready to begin") }
        switch tunnel.status {
        case .connected: return settings.text("已连接", "Connected")
        case .connecting: return settings.text("连接中", "Connecting")
        case .reasserting: return settings.text("恢复连接中", "Reconnecting")
        case .disconnecting: return settings.text("正在断开", "Disconnecting")
        default: return settings.text("未连接", "Disconnected")
        }
    }
}
