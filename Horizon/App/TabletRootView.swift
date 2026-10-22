import SwiftUI

/// Native iPad navigation; content styling must not replace the sidebar material.
struct TabletRootView<Home: View>: View {
    private enum Page: String, CaseIterable, Identifiable {
        case home, nodes, subscriptions, groups, tests, settings
        var id: Self { self }
        var symbol: String {
            switch self {
            case .home: "globe.europe.africa"
            case .settings: "slider.horizontal.3"
            case .nodes: "point.3.connected.trianglepath.dotted"
            case .subscriptions: "square.stack.3d.up"
            case .groups: "arrow.triangle.branch"
            case .tests: "gauge.with.dots.needle.50percent"
            }
        }
        func title(_ settings: AppSettings) -> String {
            switch self {
            case .home: settings.text("主页", "Home")
            case .settings: settings.text("设置", "Settings")
            case .nodes: settings.text("节点", "Nodes")
            case .subscriptions: settings.text("订阅", "Subscriptions")
            case .groups: settings.text("策略组", "Groups")
            case .tests: settings.text("批量测速", "Test all nodes")
            }
        }
    }
    let tunnel: TunnelController
    let telemetry: TelemetryStore
    @Environment(AppSettings.self) private var settings
    @Binding var selected: Int
    let hidesNavigation: Bool
    let replayIntroduction: () -> Void
    @ViewBuilder let home: () -> Home
    @State private var columns: NavigationSplitViewVisibility = .automatic
    private var selection: Binding<Page?> {
        Binding(get: { Page.allCases.first { value($0) == selected } ?? .home },
                set: { if let page = $0 { selected = value(page) } })
    }
    private func value(_ page: Page) -> Int {
        switch page {
        case .home: 0
        case .nodes: 1
        case .settings: 2
        case .subscriptions: 3
        case .groups: 4
        case .tests: 5
        }
    }
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { hidesNavigation ? .detailOnly : columns },
            set: { if !hidesNavigation { columns = $0 } })) {
            List(selection: selection) {
                ForEach(Page.allCases) { page in
                    NavigationLink(value: page) { Label(page.title(settings), systemImage: page.symbol) }
                        .accessibilityIdentifier("tablet.navigation.\(page.rawValue)")
                }
            }
            .listStyle(.sidebar)
            .modifier(MacSidebarSelectionTint())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TabletSidebarTrafficView(telemetry: telemetry,
                    visible: !hidesNavigation && columns != .detailOnly)
            }
            .navigationTitle("HORIZON")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)

        } detail: {
            NavigationStack(path: $path) {
                switch selection.wrappedValue ?? .home {
                case .home: home()
                case .settings: SettingsView(tunnel: tunnel, replayIntroduction: replayIntroduction)
                case .nodes: NodesView(tunnel: tunnel, tabletGrid: true)
                case .subscriptions: SubscriptionListView(tunnel: tunnel, tabletGrid: true)
                case .groups: NodeSelectionView(tunnel: tunnel)
                case .tests: BatchProbeView(tunnel: tunnel)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: hidesNavigation) { _, hidden in
            if !hidden { columns = .all }
        }
        .clashTint()
        .modifier(TabletFileImportModifier(tunnel: tunnel, enabled: !hidesNavigation))
        .onChange(of: selected) { _, _ in path = NavigationPath() }
    }
}

/// The iPad-on-Mac sidebar uses the app tint as its selected row background.
/// Horizon's white tint would hide the white label; leave the iPad path untouched.
private struct MacSidebarSelectionTint: ViewModifier {
    @Environment(AppSettings.self) private var settings
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac && settings.isHorizon {
            content.tint(Color(white: 0.22))
        } else {
            content
        }
    }
}
