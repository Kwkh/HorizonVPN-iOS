import SwiftUI

struct NodeSelectionView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var pendingSelection: Selection?
    @State private var selectionError: String?
    private struct Selection: Equatable {
        let group: Int
        let member: Int
    }
    let tunnel: TunnelController
    var body: some View {
        List {
            ClashListContent {
                Section { Text(settings.text(tunnel.configurationSummary, DiagnosticText.importEnglish(tunnel.configurationSummary))) }
                if let catalog = tunnel.catalog {
                    Section(settings.text("默认流量 / Ping 目标", "Default route / Ping target")) {
                        Text(tunnel.selectedNode.map { settings.nodeLabel(catalog, name: $0) } ?? settings.probeLabel(catalog))
                            .lineLimit(1).truncationMode(.middle)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: tunnel.selectedNode)
                    }
                    ForEach(catalog.groups) { group in
                        let members = matchingMembers(group, catalog: catalog)
                        if !members.isEmpty {
                            NodeGroupSection(
                                title: settings.nodeLabel(catalog, name: group.name),
                                kind: group.kind,
                                selectedTitle: tunnel.selectedMember(group).map { settings.nodeLabel(catalog, name: $0) },
                                groupID: group.id,
                                members: members.map { index in
                                    .init(id: index, title: settings.nodeLabel(catalog, name: group.members[index]),
                                          isSelected: tunnel.selectedMember(group) == group.members[index],
                                          isPending: pendingSelection == Selection(group: group.id, member: index))
                                },
                                isExpanded: !search.isEmpty || !collapsedGroups.contains(group.name),
                                canCollapse: search.isEmpty,
                                canSelect: group.allowsSelection && tunnel.canSelectMember && pendingSelection == nil,
                                toggle: {
                                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                                        if !collapsedGroups.insert(group.name).inserted { collapsedGroups.remove(group.name) }
                                    }
                                },
                                select: { choose(group: group, member: $0) }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("节点与策略组", "Nodes & groups"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.showOriginalNames) { _, _ in search = "" }
        .searchable(text: $search, prompt: settings.text("搜索当前显示名称", "Search displayed names"))
        .onChange(of: tunnel.activeSubscriptionID) { _, _ in collapsedGroups = []; search = "" }
        .alert(settings.text("节点切换", "Node selection"), isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { selectionError = nil }
        } message: { Text(settings.text(selectionError ?? "", DiagnosticText.english(selectionError ?? ""))) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InformationButton(title: settings.text("选择说明", "About selection"), paragraphs: [
                    settings.text("手动策略组可在连接时切换，仅影响新连接；已有连接保持原路径。", "Manual groups can switch while connected. New connections use the new choice; existing connections keep their paths."),
                    settings.text("自动策略组由内核选择，勾号反映最近一次实际选择；未连接时不显示自动组的当前选择。", "Automatic groups are managed by the core. Checkmarks show the latest observed choice and remain unset while disconnected."),
                    settings.text("选择会保存。保存失败时尝试恢复；无法确认结果时会断开 VPN。名称显示跟随「显示节点原名」设置。", "Choices are saved. A failed save attempts recovery; an uncertain result disconnects VPN. Names follow the Original node names setting.")
                ])
            }
        }
    }
    private func matchingMembers(_ group: ConfigurationCatalog.Group, catalog: ConfigurationCatalog) -> [Int] {
        if search.isEmpty || settings.nodeLabel(catalog, name: group.name).localizedCaseInsensitiveContains(search) {
            return Array(group.members.indices)
        }
        return group.members.indices.filter {
            settings.nodeLabel(catalog, name: group.members[$0]).localizedCaseInsensitiveContains(search)
        }
    }
    private func choose(group: ConfigurationCatalog.Group, member: Int) {
        guard pendingSelection == nil, tunnel.canSelectMember, group.allowsSelection,
              tunnel.selectedMember(group) != group.members[member] else { return }
        let identity = tunnel.configurationID
        pendingSelection = Selection(group: group.id, member: member)
        Task {
            let applied = await tunnel.selectMember(group: group.id, member: member, expectedConfigurationID: identity)
            pendingSelection = nil
            if !applied { selectionError = tunnel.message }
        }
    }

}

#Preview { NavigationStack { NodeSelectionView(tunnel: TunnelController()) } }
