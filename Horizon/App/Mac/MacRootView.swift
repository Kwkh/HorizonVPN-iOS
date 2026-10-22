#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @Bindable var library: MacLibraryStore
    @Environment(MacICloudSubscriptionSyncStore.self) private var sync
    @Binding var page: Page?
    @Binding var confirmMenuConnection: Bool
    let menuActions: MacMenuBarActions
    @State private var introduction = false
    // Sidebar selection is updated by the native navigation container. Present
    // content in a separate transaction so its follow-up updates cannot coalesce
    // away the page fade before the first animation frame.
    @State private var presentedPage: Page = .home
    @State private var subpageTokens: Set<UUID> = []
    @State private var usesPageFade = true
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Page: String, CaseIterable, Identifiable {
        case home, nodes, configurations, groups, settings
        var id: Self { self }
        var title: String {
            switch self {
            case .home: MacText.value("主页", "Home")
            case .nodes: MacText.value("节点", "Nodes")
            case .configurations: MacText.value("订阅", "Configurations")
            case .groups: MacText.value("策略组", "Groups")
            case .settings: MacText.value("设置", "Settings")
            }
        }
        var symbol: String { switch self { case .home: "globe.europe.africa"; case .nodes: "point.3.connected.trianglepath.dotted"; case .configurations: "square.stack.3d.up"; case .groups: "arrow.triangle.branch"; case .settings: "slider.horizontal.3" } }
    }
    private var introductionDestination: HorizonMotion.Phase {
        switch library.vpn.status { case .connected: .connected; case .connecting: .connecting; case .disconnecting: .disconnecting; case .reasserting: .recovering; default: .idle }
    }
    // macOS becomes inactive whenever another app takes focus. Keep subscription
    // synchronization alive; only its fallback fetch cadence depends on focus.
    private var canSync: Bool { library.ready && !library.offline && !introduction }
    private var configurationPageVisible: Bool { canSync && sync.enabled && page == .configurations }
    private var homeSelected: Bool { presentedPage == .home }
    var body: some View {
        let _ = settings.language
        NavigationSplitView {
            List(Page.allCases, selection: sidebarSelection) { page in Label(page.title, systemImage: page.symbol).tag(page) }
                .tint(Color(white: 0.25))
                .navigationTitle("HORIZON")
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
                .safeAreaInset(edge: .bottom) {
                    MacSidebarTrafficView(telemetry: library.telemetry,
                        active: scenePhase == .active && !introduction,
                        visible: (page ?? .home) != .home && !introduction, offline: library.offline)
                }
        } detail: {
            ZStack {
                NavigationStack {
                    switch presentedPage {
                    // Home content has a stable lifetime in the overlay below.
                    // This stack supplies its title and the other pages' navigation.
                    case .home: Color.clear.navigationTitle(Page.home.title)
                    case .configurations:
                        MacConfigurationsView(library: library, isCurrentPage: {
                            page == .configurations && !introduction
                        })
                    case .nodes: MacNodesView(library: library)
                    case .groups: MacGroupsView(library: library)
                    case .settings: MacSettingsView(library: library) { introduction = true }
                    }
                }
                .environment(\.macSubpageTokens, $subpageTokens)
                // Reset section navigation without recreating the Metal surface.
                .id(presentedPage)
                .transition(reduceMotion ? .identity : .opacity)
                .allowsHitTesting(presentedPage == (page ?? .home) && !introduction)
                .zIndex(1)

                // Retain Home's surface and compiled pipelines across sidebar
                // changes. Hidden Home pauses both rendering clocks and input.
                MacHomeView(library: library, visible: homeSelected && !introduction)
                    .opacity(homeSelected ? 1 : 0)
                    .allowsHitTesting(homeSelected && (page ?? .home) == .home && !introduction)
                    .accessibilityHidden(!homeSelected || introduction)
                    .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .animation(reduceMotion || !usesPageFade ? nil : .easeInOut(duration: 0.2), value: presentedPage)
        }
        .task(id: page) {
            let target = page ?? .home
            guard presentedPage != target else { return }
            // External menu navigation follows the same policy as sidebar clicks.
            guard subpageTokens.isEmpty else {
                presentWithoutPageFade(target)
                return
            }
            usesPageFade = true
            // Leave the native List/NavigationSplitView selection transaction.
            // The task is cancelled when another destination supersedes this one.
            await Task.yield()
            guard !Task.isCancelled, target == (page ?? .home) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                presentedPage = target
            }
        }
        .toolbar(introduction ? .hidden : .automatic, for: .windowToolbar)
        .onChange(of: scenePhase) { _, phase in if phase != .active { library.probes.cancel() } }
        .onChange(of: scenePhase) { _, phase in sync.setForeground(phase == .active) }
        .environment(\.locale, settings.locale)
        .disabled(introduction)
        .overlay {
            if introduction {
                MacIntroductionView(destination: introductionDestination) {
                    if !library.offline { UserDefaults.standard.set(true, forKey: "mac.introduction.completed.v1") }
                    introduction = false
                }.transition(.opacity)
            }
        }
        .task(id: "\(canSync)-\(sync.enabled)") {
            sync.setForeground(scenePhase == .active)
            sync.setAllowed(canSync)
            await sync.observe(library: library, allowed: canSync)
        }
        .task(id: configurationPageVisible) {
            guard configurationPageVisible else { return }
            await sync.observeConfigurationPage()
        }
        .task {
            await library.start()
            if !library.offline, library.index.entries.isEmpty, !UserDefaults.standard.bool(forKey: "mac.introduction.completed.v1") { introduction = true }
        }
        .task(id: scenePhase == .active ? library.identity : "inactive") {
            guard scenePhase == .active, !library.offline else { return }
            await library.telemetry.collect(vpn: library.vpn, identity: library.identity)
        }
        .sheet(item: $library.revisionPreview, onDismiss: { Task { await library.cancelPreview() } }) { preview in
            MacRevisionReviewView(library: library, preview: preview)
        }
        .sheet(item: $library.preview, onDismiss: { Task { await library.cancelPreview() } }) { preview in
            MacImportConfirmationView(library: library, preview: preview)
        }
        .alert(settings.text("连接 Horizon？", "Connect Horizon?"), isPresented: $confirmMenuConnection) {
            Button(settings.text("取消", "Cancel"), role: .cancel) {}
            Button(settings.text("连接", "Connect")) {
                Task {
                    guard library.vpn.isIdle else { return }
                    _ = await menuActions.toggleConnection(confirm: false)
                }
            }
        } message: {
            Text(settings.text("Horizon 将使用当前订阅建立 VPN 连接。", "Horizon will establish a VPN connection using your selected configuration."))
        }
        .alert(MacText.value("切换订阅并重新连接？", "Switch configuration and reconnect?"),
               isPresented: Binding(get: { library.subscriptionSwitch != nil },
                                    set: { if !$0 { library.subscriptionSwitch = nil } }),
               presenting: library.subscriptionSwitch) { target in
            Button(MacText.value("取消", "Cancel"), role: .cancel) { library.subscriptionSwitch = nil }
            Button(MacText.value("切换并重连", "Switch & reconnect")) {
                library.subscriptionSwitch = nil
                Task { await library.activate(target.id, reconnect: true) }
            }
        } message: { target in
            Text(MacText.value("切换到「\(target.title)」将短暂中断网络连接。", "Switching to “\(target.title)” will briefly interrupt your connection."))
        }
        .alert(MacText.value("未完成", "Could not complete"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button(MacText.value("好", "OK")) { library.error = nil }
        } message: { Text(library.error ?? "") }
        .alert(MacText.value("跳过证书校验？", "Skip certificate verification?"), isPresented: Binding(get: { library.certificateDigest != nil }, set: { if !$0 { library.certificateDigest = nil } })) {
            Button(MacText.value("取消", "Cancel"), role: .cancel) { library.certificateDigest = nil }
            Button(MacText.value("允许并继续", "Allow and continue"), role: .destructive) {
                guard let digest = library.certificateDigest else { return }
                library.certificateDigest = nil
                Task { await library.approveAndConnect(digest) }
            }
        } message: { Text(MacText.value("此订阅包含不校验服务器证书的节点，可能无法确认服务器身份。只授权当前配置版本。", "This configuration includes nodes that do not verify server certificates. Their identity may not be authenticated. Approval applies to this version only.")) }
    }
    private var sidebarSelection: Binding<Page?> {
        Binding(get: { page }, set: { target in
            guard target != page else { return }
            // Read depth before native List selection dismisses its subpage.
            let leavingSubpage = !subpageTokens.isEmpty
            page = target
            if leavingSubpage { presentWithoutPageFade(target ?? .home) }
        })
    }
    private func presentWithoutPageFade(_ target: Page) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            usesPageFade = false
            presentedPage = target
        }
    }
}

#endif
