import SwiftUI
import NetworkExtension

struct RootTabView: View {
    let tunnel: TunnelController
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var selected = 0
    @State private var homeEntered = false
    @State private var showVPNSetup = false
    @State private var preparingVPN = false
    @State private var checkingNetwork = false
    @State private var vpnSetupTask: Task<Void, Never>?
    @State private var vpnSetupError: String?
    @State private var liveActivity = VPNLiveActivityController.shared
    @State private var telemetry = TelemetryStore()
    @State private var cloudSync = ICloudSubscriptionSyncStore()
    @State private var firstLaunch = FirstLaunchExperience(preview: FirstLaunchExperience.previewRequested)

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabletRootView(tunnel: tunnel, telemetry: telemetry, selected: $selected,
                    hidesNavigation: firstLaunch.suppressesTabBar,
                    replayIntroduction: replayIntroduction) { homeContent }
            } else {
                phoneTabs
            }
        }
        .environment(liveActivity)
        .environment(cloudSync)
        .environment(\.cloudReviewPromptBlocked, firstLaunch.suppressesTabBar || showVPNSetup ||
            preparingVPN || tunnel.certificateApproval != nil)
        .task(id: "\(canStartCloudSync)-\(cloudSync.enabled)") {
            cloudSync.setAllowed(canStartCloudSync && tunnel.permitsNetwork)
            await cloudSync.observe(tunnel: tunnel, allowed: canStartCloudSync)
        }
        .task(id: "\(scenePhase == .active)-\(settings.liveActivityEnabled)-\(tunnel.status.rawValue)-\(firstLaunch.suppressesTabBar)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLASH_ACTIVITY_PREVIEW"] == "1" { return }
            #endif
            guard scenePhase == .active, firstLaunch.resolved, !firstLaunch.suppressesTabBar else { return }
            while !Task.isCancelled {
                await liveActivity.synchronize(tunnel: tunnel, settings: settings)
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(settings.isHorizon ? .white : ClashStyle.accent(scheme))
        .allowsHitTesting(!firstLaunch.isShowingGuide)
        .accessibilityHidden(firstLaunch.isShowingGuide)
        .overlay {
            if firstLaunch.isShowingGuide, let id = firstLaunch.requestID {
                HorizonGuideView(destinationFrame:firstLaunch.sceneFrame,
                    sceneReady:firstLaunch.preparedSceneID == id,
                    prepareScene: { firstLaunch.prepareScene(id,rotation:$0,time:$1,clock:$2) },
                    continueToScene: { firstLaunch.beginScene(id) })
                    .id(id)
                    .transition(.identity)
            }
        }
        .task { AutomatedSelfCheck.runIfRequested() }
        #if DEBUG
        .task { await LiveActivityPreview.runIfRequested() }
        #endif
        .task {
            if tunnel.permitsNetwork { ConnectionWidgetService.shared.controller = tunnel }
            await tunnel.monitor()
        }
        .task(id: canStartNetworkMonitoring) {
            guard canStartNetworkMonitoring else { return }
            tunnel.network.startMonitoring()
        }
        .alert(settings.text("允许跳过证书校验？", "Allow unverified certificates?"),
            isPresented: Binding(get: { tunnel.certificateApproval != nil }, set: { if !$0 { tunnel.dismissCertificateApproval() } }),
            presenting: tunnel.certificateApproval) { request in
                Button(settings.text("取消", "Cancel"), role: .cancel) { tunnel.dismissCertificateApproval() }
                Button(request.connects ? settings.text("允许此版本并连接", "Allow this version & connect") : settings.text("允许此版本并测速", "Allow this version & test"), role: .destructive) {
                    Task { await tunnel.approveCertificates(request) }
                }
            } message: { request in
                Text(settings.text("此订阅包含 \(request.nodeCount) 个不校验服务器证书的节点，无法可靠验证服务器身份。允许后，本版本中的这些节点可用于连接、自动选择和测速；订阅内容更新后需重新确认。", "This subscription contains \(request.nodeCount) nodes that skip server certificate verification, so server identity cannot be reliably verified. Approval enables these nodes for connections, automatic selection and tests in this version. Changed subscription content requires approval again."))
            }
        .task(id: canOfferVPNSetup) {
            guard canOfferVPNSetup, !showVPNSetup else { return }
            if tunnel.profileReady { firstLaunch.dismissVPNSetupOffer() }
            else if !showVPNSetup {
                // Let the final home controls finish their introduction fade first.
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard canOfferVPNSetup, !Task.isCancelled else { return }
                showVPNSetup = true
            }
        }
        .sheet(isPresented: $showVPNSetup, onDismiss: {
            vpnSetupTask?.cancel()
            firstLaunch.dismissVPNSetupOffer()
        }) {
            VPNSetupView(preparing: preparingVPN, checkingNetwork: checkingNetwork,
                canPrepare: tunnel.permitsNetwork && TunnelController.supportsTunnel && !tunnel.isBusy && !tunnel.isTunnelActive,
                unavailableReason: vpnSetupUnavailableReason,
                errorMessage: vpnSetupError,
                onAdd: addVPNProfile,
                onLater: {
                    vpnSetupTask?.cancel()
                    showVPNSetup = false
                })
        }
        .task(id: tunnel.didFinishInitialRefresh) {
            guard tunnel.didFinishInitialRefresh else { return }
            firstLaunch.resolve(hasExistingConfiguration: tunnel.hasProfile || !tunnel.subscriptions.isEmpty,
                                horizon: settings.isHorizon)
        }
        .onChange(of: selected) { _, tab in
            // Explicit navigation away counts as skipping; returning must not replay it.
            if tab != 0, !firstLaunch.isShowingGuide, let id = firstLaunch.requestID { firstLaunch.complete(id) }
        }
        .task(id: scenePhase == .active) {
            // Sampling belongs to the foreground app, not the selected tab.
            // Offscreen drawing pauses independently without discarding the rate baseline.
            if scenePhase == .active { await telemetry.collect(from: tunnel) }
        }
        .onChange(of: tunnel.network.isOffline) { _, offline in
            if offline { tunnel.cancelForegroundProbes() }
        }
        .onChange(of: tunnel.status) { _, status in
            if status != .connected { telemetry.disconnect() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await tunnel.refresh() } }
            else { tunnel.cancelForegroundProbes() }
            // Permission dialogs make the scene inactive; only backgrounding
            // cancels the foreground check, never the system dialog itself.
            if phase == .background && checkingNetwork { vpnSetupTask?.cancel() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            tunnel.setSubscriptionCleanupActive(phase == .active)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            tunnel.requestSubscriptionCleanup()
        }
    }
    private func replayIntroduction() {
        selected = 0
        firstLaunch.replay()
    }
    private var homeContent: some View {
        Group {
            if !tunnel.didFinishInitialRefresh || !firstLaunch.resolved { StartupView() }
            else {
                Group {
                    if settings.isHorizon {
                        HorizonHomeView(tunnel: tunnel, telemetry: telemetry, visible: selected == 0,
                            introduction: firstLaunch, entranceVisible: homeEntered || firstLaunch.requestID != nil)
                    } else {
                        HomeView(tunnel: tunnel, telemetry: telemetry, visible: selected == 0,
                            entranceVisible: homeEntered || firstLaunch.requestID != nil)
                    }
                }
                .task(id: scenePhase) {
                    guard !homeEntered, scenePhase == .active else { return }
                    // Establish the initial presentation after real VPN/config state
                    // resolves. Introduction already has its own uninterrupted handoff.
                    if firstLaunch.requestID == nil {
                        do { try await Task.sleep(for: .milliseconds(30)) }
                        catch { return }
                    }
                    homeEntered = true
                }
            }
        }
    }
    private var phoneTabs: some View {
        TabView(selection: $selected) {
            Tab(settings.text("主页", "Home"), systemImage: settings.isHorizon ? "globe.europe.africa" : "circle.hexagongrid", value: 0) {
                NavigationStack { homeContent }
                    .background(HorizonIntroductionTabBar(hidden: firstLaunch.suppressesTabBar))
            }
            Tab(settings.text("节点", "Nodes"), systemImage: "point.3.connected.trianglepath.dotted", value: 1) {
                NavigationStack { NodesView(tunnel: tunnel) }
            }
            Tab(settings.text("设置", "Settings"), systemImage: "slider.horizontal.3", value: 2) {
                NavigationStack { SettingsView(tunnel: tunnel, replayIntroduction: replayIntroduction) }
            }
        }
    }
    private var canStartNetworkMonitoring: Bool {
        firstLaunch.allowsNetworkMonitoring && scenePhase == .active &&
        !showVPNSetup && !preparingVPN
    }
    private var canStartCloudSync: Bool {
        firstLaunch.resolved && !firstLaunch.suppressesTabBar && firstLaunch.requestID == nil &&
        scenePhase == .active && !showVPNSetup && !preparingVPN && tunnel.didFinishInitialRefresh && !tunnel.network.isOffline
    }
    private var canOfferVPNSetup: Bool {
        firstLaunch.needsVPNSetupOffer && firstLaunch.resolved && firstLaunch.requestID == nil &&
        scenePhase == .active && selected == 0 && tunnel.didFinishInitialRefresh && !tunnel.isBusy && !preparingVPN
    }
    private var vpnSetupUnavailableReason: String? {
        if !tunnel.permitsNetwork || !TunnelController.supportsTunnel {
            return settings.text("请在真机上添加 VPN 配置。", "VPN setup requires a physical device.")
        }
        if !tunnel.didLoadPreferences {
            return settings.text("系统状态暂不可用，可稍后在连接诊断中重试。", "System status is unavailable. Retry later in Connection diagnostics.")
        }
        if !tunnel.isIdle && !preparingVPN {
            return settings.text("请等待当前 VPN 操作完成。", "Wait for the current VPN operation to finish.")
        }
        return nil
    }
    private func addVPNProfile() {
        guard !preparingVPN, tunnel.permitsNetwork, TunnelController.supportsTunnel else { return }
        preparingVPN = true
        vpnSetupError = nil
        vpnSetupTask = Task {
            defer { checkingNetwork = false; preparingVPN = false; vpnSetupTask = nil }
            await tunnel.refresh()
            if !tunnel.profileReady { await tunnel.prepareProfile() }
            if tunnel.profileReady {
                guard !Task.isCancelled else { return }
                // Wait for the VPN permission dialog to yield the foreground
                // before allowing a separate Internet-access prompt.
                while scenePhase == .inactive {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                guard scenePhase == .active, firstLaunch.resolved,
                      firstLaunch.requestID == nil, !Task.isCancelled else { return }
                tunnel.network.startMonitoring()
                checkingNetwork = true
                let result = await NetworkAccessCheck.run()
                guard !Task.isCancelled else { return }
                if result == .reachable {
                    firstLaunch.dismissVPNSetupOffer()
                    showVPNSetup = false
                } else {
                    vpnSetupError = settings.text("VPN 配置已添加，但未能确认联网。请检查连接与系统设置中的网络访问权限，然后重试或稍后继续。",
                        "VPN profile added, but Internet access could not be confirmed. Check your connection and network access in Settings, then retry or continue later.")
                }
            } else {
                vpnSetupError = settings.text(tunnel.message, DiagnosticText.english(tunnel.message))
            }
        }
    }
}
