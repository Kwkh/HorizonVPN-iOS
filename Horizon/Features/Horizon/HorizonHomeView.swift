import SwiftUI
import NetworkExtension

struct HorizonHomeView: View {
    let tunnel: TunnelController
    let telemetry: TelemetryStore
    let visible: Bool
    let introduction: FirstLaunchExperience
    let entranceVisible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirming = false
    @State private var preparing = false
    @State private var showNetworkAlert = false
    @State private var pendingNetworkAlert = false
    @State private var sceneOnscreen = true
    @State private var pull = HorizonPullState()
    @State private var scrollOffset: CGFloat = 0
    @State private var introCamera = HorizonIntroCamera()

    @State private var sceneProgress: HorizonSceneProgress

    init(tunnel: TunnelController, telemetry: TelemetryStore, visible: Bool, introduction: FirstLaunchExperience, entranceVisible: Bool) {
        self.tunnel = tunnel
        self.telemetry = telemetry
        self.visible = visible
        self.introduction = introduction
        self.entranceVisible = entranceVisible
        // Match the renderer's initial pose before the title's very first layout.
        _sceneProgress = State(initialValue: HorizonSceneProgress(formation: tunnel.status == .connected ? 1 : 0))
    }

    var body: some View {
        GeometryReader { geometry in
            let heroHeight = max(540, min(880, geometry.size.height * 0.96))
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            HorizonSceneView(progress: sceneProgress, phase: visualPhase,
                                active: visible && sceneOnscreen && scenePhase == .active && (!introduction.isShowingGuide || introduction.isPreparingScene),
                                animate: settings.particles && !reduceMotion,
                                interactiveJourney: pull.journey,
                                introductionID: introduction.isShowingGuide && !introduction.isPreparingScene ? nil : introduction.requestID,
                                skipIntroduction: introduction.skipRequested,
                                holdIntroduction: introduction.isPreparingScene,
                                guideRotation: introduction.guideRotation,
                                guideTime: introduction.guideTime, guideClock:introduction.guideClock,
                                introCamera:introCamera)
                                .accessibilityHidden(true)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in:.global) } action: { introduction.sceneFrame = $0 }
                                .modifier(HomeEntrance(presented: entranceVisible, rise: 0))
                            HorizonCameraDragSurface(camera:introCamera,
                                enabled:introducing && !introduction.isShowingGuide,animated:settings.particles)
                            VStack(spacing: 0) {
                                LinearGradient(colors: [.black.opacity(0.94),.clear], startPoint: .top, endPoint: .bottom).frame(height: 150)
                                Spacer()
                                LinearGradient(colors: [.clear,.black], startPoint: .top, endPoint: .bottom).frame(height: 150)
                            }.allowsHitTesting(false)
                                .opacity(introducing ? 0 : 1)
                                .animation(entranceAnimation,value:introducing)
                            HorizonTitleView(status: statusTitle, progress: sceneProgress,
                                viewport: CGSize(width: geometry.size.width, height: heroHeight))
                                .opacity(introducing ? 0 : 1)
                                .accessibilityHidden(introducing)
                                .animation(entranceAnimation, value: introducing)
                                .modifier(HomeEntrance(presented: entranceVisible, delay: 0.04, rise: 6))
                            VStack {
                                Spacer()
                                GlassEffectContainer {
                                    HorizonConnectionButton(action: buttonAction, disabled: buttonVisuallyDisabled && !networkBlocked,
                                        unavailable: !tunnel.didLoadPreferences || !tunnel.hasConfiguration || networkBlocked,
                                        networkUnavailable: networkBlocked,
                                        onTap: connectionAction)
                                        .allowsHitTesting(!tunnel.isApplyingRouting)
                                }
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) {
                                        reader.scrollTo("information", anchor: .top)
                                    }
                                } label: {
                                    Image(systemName: "chevron.compact.down").font(.title3)
                                        .frame(width: 60, height: 44)
                                }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .accessibilityLabel(settings.text("查看流量信息", "Show traffic information"))
                            }.padding(.bottom, 22)
                                .opacity(introducing ? 0 : 1)
                                .allowsHitTesting(!introducing)
                                .accessibilityHidden(introducing)
                                .animation(entranceAnimation, value: introducing)
                                .modifier(HomeEntrance(presented: entranceVisible, delay: 0.10))
                        }
                        .frame(height: heroHeight).contentShape(Rectangle()).id("hero")
                        // Keep the wall in place while the ScrollView supplies the pull distance.
                        .offset(y: min(0, scrollOffset))
                        HorizonInformationView(tunnel: tunnel, telemetry: telemetry, visible: visible)
                            .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 36)
                            // Small subscriptions still have a full information viewport,
                            // so switching near its top does not pull the hero back down.
                            .frame(minHeight: geometry.size.height, alignment: .top)
                            .id("information")
                            .modifier(HorizonInformationFocus(
                                enabled: UIDevice.current.userInterfaceIdiom == .phone,
                                scrollOffset: scrollOffset, heroHeight: heroHeight,
                                viewportHeight: geometry.size.height))
                            .opacity(introducing ? 0 : 1)
                            .allowsHitTesting(!introducing)
                            .accessibilityHidden(introducing)
                            .animation(entranceAnimation, value: introducing)
                            .modifier(HomeEntrance(presented: entranceVisible, delay: 0.16))
                    }
                }
                .defaultScrollAnchor(.top, for: .sizeChanges)
                .scrollIndicators(.hidden)
                .scrollDisabled(introducing)
                .onChange(of: introduction.requestID) { _, id in
                    if id != nil { reader.scrollTo("hero", anchor: .top); pull.reset(); introCamera.reset() }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                    scrollOffset = offset
                    sceneOnscreen = offset < heroHeight - 100
                    if pull.update(distance: max(0, -Double(offset)), threshold: Double(heroHeight) * 0.18) {
                        requestConnection()
                    }
                }
                .onScrollPhaseChange { old, new in
                    if new == .interacting {
                        pull.begin(eligible: scrollOffset <= 2 && !tunnel.isTunnelActive && !actionDisabled && !networkBlocked && !confirming,
                                   currentJourney: sceneProgress.journey)
                    }
                    if old == .interacting && new != .interacting { pull.end() }
                }
            }
            // Anchor to the page's safe-area top, not the scrolling hero scene.
            .overlay(alignment:.topTrailing) {
                HorizonIntroductionControls(skip:introduction.skip,
                    visible:introducing && !introduction.isShowingGuide)
            }
        }
        .background(.black).foregroundStyle(.white).tint(.white)
        .onChange(of:sceneProgress.preparedIntroduction) { _, id in
            if let id { introduction.scenePresented(id) }
        }
        .toolbar(UIDevice.current.userInterfaceIdiom == .pad && !introduction.suppressesTabBar ? .automatic : .hidden, for: .navigationBar)
        .sheet(isPresented: $confirming, onDismiss: {
            if !preparing { pull.reset() }
            if pendingNetworkAlert { pendingNetworkAlert = false; showNetworkAlert = true }
        }) {
            ConnectionConfirmationView { skipNextTime in
                if skipNextTime { settings.confirmVPNConnection = false }
                beginConnection()
            }
        }
        .modifier(NetworkUnavailableAlert(isPresented: $showNetworkAlert))
        .onChange(of: tunnel.network.isOffline) { _, offline in
            if offline && !preparing { pull.reset() }
        }
        .onChange(of: visible) { _, visible in
            if !visible && !preparing { pull.reset() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && !pull.committed { pull.reset() }
        }
        .onChange(of: sceneProgress.completedIntroduction) { _, id in
            if let id { introduction.complete(id) }
        }
    }
    private var introducing: Bool { introduction.requestID != nil }
    private var entranceAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.2 : 0.45) }
    private func connectionAction() {
        guard !tunnel.isApplyingRouting else { return }
        if tunnel.canStop { tunnel.stop() } else { requestConnection() }
    }
    private func requestConnection() {
        guard !tunnel.network.isOffline else { showNetworkAlert = true; pull.reset(); return }
        guard !actionDisabled, !confirming, !tunnel.isTunnelActive else { pull.reset(); return }
        if settings.confirmVPNConnection { confirming = true }
        else { beginConnection() }
    }
    private func beginConnection() {
        guard !tunnel.network.isOffline else {
            if confirming { pendingNetworkAlert = true } else { showNetworkAlert = true }
            pull.reset()
            return
        }
        preparing = true
        Task {
            await tunnel.connectCurrentProfile()
            if tunnel.network.isOffline && !tunnel.isTunnelActive { showNetworkAlert = true }
            pull.reset()
            preparing = false
        }
    }
    private var networkBlocked: Bool { tunnel.network.isOffline && !tunnel.isTunnelActive }
    private var actionDisabled: Bool { buttonVisuallyDisabled || tunnel.isApplyingRouting }
    private var buttonVisuallyDisabled: Bool {
        introducing || preparing || tunnel.isAwaitingConnectionStatus || (tunnel.isBusy && !tunnel.isApplyingRouting) || !tunnel.didLoadPreferences ||
        (!tunnel.canStop && (!tunnel.hasConfiguration || tunnel.status == .disconnecting))
    }
    private var buttonAction: HorizonConnectionButton.Action {
        if tunnel.status == .disconnecting { return .stopping }
        if tunnel.status == .connecting { return .cancel }
        return tunnel.canStop ? .disconnect : .connect
    }
    private var statusTitle: String {
        if preparing || tunnel.isAwaitingConnectionStatus {
            return settings.statusText(tunnel.connectionTitleStatus(preparing: preparing))
        }
        if !tunnel.didLoadPreferences {
            return tunnel.didFinishInitialRefresh ? settings.text("无法读取状态", "Status unavailable") : settings.text("正在同步", "Syncing")
        }
        if !tunnel.hasConfiguration { return settings.text("等待导入", "Import a subscription") }
        return settings.statusText(tunnel.status)
    }
    private var visualPhase: HorizonMotion.Phase {
        switch tunnel.status {
        case .connecting: .connecting
        case .connected: .connected
        case .reasserting: .recovering
        case .disconnecting: .disconnecting
        default: .idle
        }
    }
}
