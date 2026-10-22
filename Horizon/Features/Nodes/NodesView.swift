import SwiftUI

struct NodesView: View {
    let tunnel: TunnelController
    var tabletGrid = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var pendingNode: String?
    @State private var selectionError: String?
    @State private var showGroups = false
    var body: some View {
        @Bindable var preferences = settings
        Group {
            if tabletGrid {
                TabletNodeGridView(tunnel: tunnel, search: search, pendingNode: pendingNode,
                    matches: { matches($0, index: $1) }, choose: { choose($0, in: $1) },
                    toggleBatch: {
                        if tunnel.batchProbes.isTestingAllNodes { tunnel.batchProbes.cancel(using: tunnel) }
                        else { tunnel.batchProbes.start(using: tunnel) }
                    })
            } else {
        List {
            ClashListContent {
                Section {
                    NavigationLink { SubscriptionListView(tunnel: tunnel) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Label(settings.text("订阅", "Subscriptions"), systemImage: "square.stack.3d.up")
                                .font(.callout).foregroundStyle(.secondary)
                            Text(tunnel.hasConfiguration ? tunnel.currentSubscriptionTitle : settings.text("导入 YAML", "Import YAML"))
                                .font(.title2.weight(.medium)).lineLimit(2)
                                .contentTransition(.opacity)
                                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: tunnel.currentSubscriptionTitle)
                        }.padding(.vertical, 12)
                    }
                    NavigationLink { NodeSelectionView(tunnel: tunnel) } label: {
                        Label(settings.text("策略组", "Groups"), systemImage: "arrow.triangle.branch")
                    }.disabled(!tunnel.hasConfiguration)
                    NavigationLink { BatchProbeView(tunnel: tunnel) } label: {
                        HStack {
                            Label(settings.text("批量测速", "Test all nodes"), systemImage: "gauge.with.dots.needle.50percent")
                            Spacer()
                            if tunnel.batchProbes.isTestingAllNodes { ProgressView() }
                        }
                    }.disabled(!tunnel.hasConfiguration)
                }.listRowBackground(Color.clear)
                Section(settings.text("节点", "Nodes")) {
                    if let catalog = tunnel.catalog {
                        ForEach(catalog.nodes.indices.filter { index in
                            matches(catalog, index: index)
                        }, id: \.self) { index in
                            let name = catalog.nodes[index].name
                            HStack(spacing: 8) {
                            NodeSelectionRowView(
                                number: index + 1,
                                title: settings.showOriginalNames ? name : settings.text("节点 \(index + 1)", "Node \(index + 1)"),
                                protocolName: catalog.nodes[index].kind.uppercased(),
                                isSelected: tunnel.selectedNode == name,
                                isPending: pendingNode == name,
                                isEnabled: tunnel.canSelectMember && pendingNode == nil
                            ) { choose(name, in: catalog) }
                            NodePingButton(tunnel: tunnel, index: index)
                            }
                        }.listRowBackground(Color.clear)
                        if !search.isEmpty, !catalog.nodes.indices.contains(where: { matches(catalog, index: $0) }) {
                            ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                        }
                    } else {
                        ContentUnavailableView(settings.text("还没有节点", "No nodes yet"), systemImage: "network")
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
            }
        }
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("节点", "Nodes"))
        .searchable(text: $search, prompt: settings.showOriginalNames ? settings.text("名称、编号或协议", "Name, number or protocol") : settings.text("编号或协议", "Number or protocol"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $preferences.showOriginalNames) {
                    Label(settings.text("显示原名", "Original names"), systemImage: settings.showOriginalNames ? "eye" : "eye.slash")
                }.toggleStyle(.button)
            }
        }
        .navigationDestination(isPresented: $showGroups) { NodeSelectionView(tunnel: tunnel) }
        .alert(settings.text("节点切换", "Node selection"), isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { selectionError = nil }
        } message: { Text(settings.text(selectionError ?? "", DiagnosticText.english(selectionError ?? ""))) }
        .onChange(of: settings.showOriginalNames) { _, _ in search = "" }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: settings.showOriginalNames)
    }
    private func choose(_ name: String, in catalog: ConfigurationCatalog) {
        guard pendingNode == nil, tunnel.canSelectMember, tunnel.selectedNode != name else { return }
        guard let selection = catalog.directSelection(for: name) else {
            showGroups = true
            return
        }
        let identity = tunnel.configurationID
        pendingNode = name
        Task { @MainActor in
            let applied = await tunnel.selectMember(group: selection.group, member: selection.member, expectedConfigurationID: identity)
            pendingNode = nil
            if !applied { selectionError = tunnel.message }
        }
    }
    private func matches(_ catalog: ConfigurationCatalog, index: Int) -> Bool {
        let node = catalog.nodes[index]
        let text = "\(index + 1) \(node.kind)" + (settings.showOriginalNames ? " " + node.name : "")
        return search.isEmpty || text.localizedCaseInsensitiveContains(search)
    }
}
