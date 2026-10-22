import SwiftUI
import NetworkExtension

@MainActor struct DiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var tunnel = TunnelController()
    @State private var confirmProfile = false
    @State private var confirmStart = false
    @State private var confirmRemove = false
    @State private var selfCheck: PrototypeSelfCheck.Result?
    private let managedExternally: Bool

    init(tunnel: TunnelController? = nil, managedExternally: Bool = false) {
        _tunnel = State(initialValue: tunnel ?? TunnelController())
        self.managedExternally = managedExternally
    }

    @Environment(AppSettings.self) private var settings

    var body: some View {
            List {
                ClashListContent {
                    if !tunnel.permitsNetwork {
                        Section { Text(settings.text("离线界面演示：仅使用虚构订阅，不访问真实钥匙串，VPN 不可用。", "Offline demo: fictional configurations only. No real Keychain access or VPN connections.")).foregroundStyle(.orange) }
                    }
                    Section(settings.text("配置兼容测试", "Configuration checks")) {
                        LabeledContent(settings.text("测试配置", "Configuration"), value: tunnel.hasConfiguration ? settings.text("已存于本机钥匙串", "Saved in local Keychain") : settings.text("缺少配置", "No configuration"))
                        LabeledContent(settings.text("VPN 配置", "VPN profile"), value: tunnel.profileReady ? settings.text("已准备", "Ready") : settings.text("需要准备或更新", "Setup or update required"))
                        Text(settings.text(tunnel.message, DiagnosticText.english(tunnel.message))).font(.footnote)
                        if tunnel.isBusy { ProgressView(settings.text("正在处理…", "Working…")) }
                        Text(settings.text(tunnel.configurationSummary, configurationSummary))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section(settings.text("订阅", "Configurations")) {
                        NavigationLink { SubscriptionListView(tunnel: tunnel) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(settings.text("管理订阅", "Manage configurations"), systemImage: "doc.on.doc")
                                Text(tunnel.activeSubscriptionID == nil ? settings.text("未选择订阅", "No configuration selected") : tunnel.currentSubscriptionTitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        NavigationLink(settings.text("节点与策略组", "Nodes & groups")) { NodeSelectionView(tunnel: tunnel) }
                            .disabled(!tunnel.hasConfiguration)
                    }
                    Section(settings.text("配置与连接", "Configuration & connection")) {
                        Button(settings.text("准备 / 更新 VPN 配置", "Set up / update VPN profile")) { confirmProfile = true }
                            .disabled(!TunnelController.supportsTunnel || !tunnel.didLoadPreferences || !tunnel.isIdle || tunnel.profileReady)
                        Button(settings.text("连接", "Connect")) { confirmStart = true }.disabled(!tunnel.canStart)
                        Button(settings.text("断开", "Disconnect")) { tunnel.stop() }.disabled(!tunnel.canStop)
                        Button(settings.text("刷新系统状态", "Refresh system status")) { Task { await tunnel.refresh() } }.disabled(tunnel.isBusy)
                        Button(settings.text("读取上次断开原因", "Read last disconnect reason")) { Task { await tunnel.readLastDisconnectError() } }
                            .disabled(!tunnel.hasProfile || tunnel.isBusy || tunnel.status != .disconnected)
                    }
                    Section(settings.text("网络测试", "Network tests")) {
                        NavigationLink(settings.text("规则命中", "Rule matches")) { RuleDiagnosticsView(tunnel: tunnel) }
                        NavigationLink(settings.text("DNS 分项诊断", "DNS diagnostics")) { DNSDiagnosticsView(tunnel: tunnel) }
                        NavigationLink {
                            PingTestView(tunnel: tunnel)
                        } label: {
                            Label(settings.text("测试 Ping", "Test Ping"), systemImage: "waveform.path.ecg")
                        }
                        .accessibilityIdentifier("diagnostics.ping")
                    }
                    TunnelStatisticsSection(
                        snapshot: tunnel.snapshot,
                        canRefresh: [.connected, .reasserting].contains(tunnel.status)
                    ) {
                        Task { await tunnel.refreshSnapshot() }
                    }
                    ConnectivityProbeSection(report: tunnel.connectivity,
                        isRunning: tunnel.isProbing, canRun: tunnel.status == .connected && tunnel.canTestPing) {
                        Task { await tunnel.probeConnectivity() }
                    }
                    Section(settings.text("离线验证", "Offline validation")) {
                        Text(selfCheck.map { settings.text($0.summary, "Offline checks \($0.passed)/\($0.total); no network or Keychain access.") } ?? settings.text("未运行离线自检", "Offline checks not run")).font(.footnote)
                        Button(settings.text("运行虚构配置自检", "Run checks with fictional configurations")) { selfCheck = PrototypeSelfCheck.run() }
                    }
                    SessionEventsSection(events: tunnel.events)
                    Section(settings.text("清理", "Cleanup")) {
                        Button(settings.text("移除本应用 VPN 配置", "Remove this app’s VPN profile"), role: .destructive) { confirmRemove = true }
                            .disabled(!tunnel.isIdle || !tunnel.hasProfile)
                    }
                }
            }
            .listStyle(.plain)
            .clashScreen()
            .navigationTitle(settings.text("连接诊断", "Connection diagnostics"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    InformationButton(title: settings.text("网络行为与日志", "Network behavior & logs"), paragraphs: [settings.text(PrototypeConfiguration.policySummary, "Supports Hysteria2, SS/SS2022, Trojan, VMess, VLESS and supported TCP/WS/gRPC combinations, select/url-test/fallback groups, HTTPS/inline providers, supported rules and DNS. iOS uses Packet Tunnel without desktop ports or LAN listeners. Adaptations are listed during import. Connections remain manual."),
                        settings.text("日志仅包含固定阶段、错误码和计数。请在 Mac 控制台筛选 Kenote.Clash.PacketTunnel；不会显示节点地址或凭据。", "Logs contain fixed stages, error codes and counters only. Filter for Kenote.Clash.PacketTunnel in macOS Console. Node addresses and credentials are hidden.")])
                }
            }
            .task { if !managedExternally { await tunnel.monitor() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active && !managedExternally { Task { await tunnel.refresh() } } }
            .alert(settings.text("准备系统 VPN 配置？", "Set up the VPN profile?"), isPresented: $confirmProfile) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("继续", "Continue")) { Task { await tunnel.prepareProfile() } }
            } message: { Text(settings.text("将添加或更新 HORIZON 的系统 VPN 配置，关闭按需连接，保留锁屏连接。此步骤不启动代理；首次添加需要在 iOS 提示中允许。", "Add or update HORIZON’s system VPN profile with on-demand connection disabled and connections retained while locked. This does not connect VPN. Allow the iOS permission request to add the profile.")) }
            .alert(settings.text("连接当前配置？", "Connect this configuration?"), isPresented: $confirmStart) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("连接", "Connect")) { tunnel.start() }
            } message: { Text(settings.text("将启动真实 VPN，安装默认路由与 DNS 设置，可能替换其他 VPN。流量按导入的规则、DNS 和已保存的策略组选择处理；未定义 DNS 时使用导入页说明的默认值。IPv6 关闭时增加 IPv6 拒绝规则。失败可断开恢复网络；不会自动测速。", "Starts VPN with default routes and DNS settings, and may replace another VPN. Traffic follows imported rules, DNS and saved group selections. Missing DNS uses the defaults shown during import. Disabling IPv6 adds an IPv6 reject rule. Disconnect to restore networking after failure. Speed tests do not run automatically.")) }
            .alert(settings.text("移除本应用 VPN 配置？", "Remove this app’s VPN profile?"), isPresented: $confirmRemove) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("移除", "Remove"), role: .destructive) { Task { await tunnel.removeProfile() } }
            } message: { Text(settings.text("下次连接需要重新准备系统 VPN 配置。", "The VPN profile must be set up again before the next connection.")) }
    }

    private var configurationSummary: String {
        guard tunnel.hasConfiguration, let entry = tunnel.subscriptions.first(where: { $0.id == tunnel.activeSubscriptionID }) else {
            return tunnel.hasConfiguration ? "Configuration available" : "No usable configuration"
        }
        return "\(entry.nodeCount) nodes · \(entry.groupCount) groups · \(entry.ruleCount) rules"
    }
}

#Preview { NavigationStack { DiagnosticsView() }.environment(AppSettings()) }
