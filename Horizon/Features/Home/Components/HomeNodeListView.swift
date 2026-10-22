import SwiftUI

/// Inline rows participate in the home's ScrollView; there is no nested List.
struct HomeNodeListView: View {
    let tunnel: TunnelController
    let visible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingNode: String?
    @State private var selectionError: String?
    @State private var showGroups = false
    @State private var presentedInventory: Inventory?
    @State private var presentedSelection: String?
    @State private var inventoryOpacity = 1.0
    @State private var replacingInventory = false

    private struct Node: Equatable {
        let name: String
        let kind: String
    }
    private struct Inventory: Equatable {
        let subscription: UUID?
        let nodes: [Node]
    }
    private struct PresentationKey: Equatable {
        let inventory: Inventory
        let visible: Bool
        let reduceMotion: Bool
    }
    private struct RowID: Hashable {
        let subscription: UUID?
        let name: String
    }

    private var currentInventory: Inventory {
        Inventory(subscription: tunnel.activeSubscriptionID,
            nodes: tunnel.catalog?.nodes.map { Node(name: $0.name, kind: $0.kind) } ?? [])
    }

    var body: some View {
        let incoming = currentInventory
        let displayed = presentedInventory ?? incoming
        let isCurrent = displayed == incoming
        let selectedNode = isCurrent ? tunnel.selectedNode : presentedSelection
        LazyVStack(alignment: .leading, spacing: 0) {
            if !displayed.nodes.isEmpty {
                ForEach(Array(displayed.nodes.enumerated()), id: \.element.name) { index, node in
                    // One lazy child per node: a sibling separator would otherwise
                    // change the lazy stack's child estimates at the end of a library.
                    VStack(spacing: 0) {
                        NodeSelectionRowView(number: index + 1,
                            title: settings.showOriginalNames ? node.name : settings.text("节点 \(index + 1)", "Node \(index + 1)"),
                            protocolName: node.kind.uppercased(),
                            isSelected: selectedNode == node.name,
                            isPending: isCurrent && pendingNode == node.name,
                            isEnabled: visible && isCurrent && !replacingInventory && tunnel.canSelectMember && pendingNode == nil) {
                                choose(node.name, in: displayed)
                            }
                        if index < displayed.nodes.count - 1 {
                            Rectangle().fill(.primary.opacity(0.14)).frame(height: 0.5)
                                .padding(.horizontal, 4).padding(.vertical, 6)
                                .accessibilityHidden(true)
                        }
                    }
                    .id(RowID(subscription: displayed.subscription, name: node.name))
                }
            } else {
                Text(settings.text("还没有节点", "No nodes yet"))
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .accessibilityIdentifier("home.nodes")
        // Change lazy layout only while hidden. Animate opacity outside this
        // boundary so neither row heights nor the surrounding chart interpolate.
        .transaction { $0.animation = nil }
        .opacity(inventoryOpacity)
        .allowsHitTesting(isCurrent && !replacingInventory)
        .accessibilityHidden(!isCurrent || replacingInventory)
        .task(id: PresentationKey(inventory: incoming, visible: visible, reduceMotion: reduceMotion)) {
            await present(incoming)
        }
        .onChange(of: tunnel.selectedNode, initial: true) { _, selected in
            if presentedInventory == nil || presentedInventory == currentInventory {
                presentedSelection = selected
            }
        }
        .sheet(isPresented: $showGroups) {
            NavigationStack {
                NodeSelectionView(tunnel: tunnel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(settings.text("完成", "Done")) { showGroups = false }
                        }
                    }
            }
        }
        .alert(settings.text("节点切换", "Node selection"), isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { selectionError = nil }
        } message: {
            Text(settings.text(selectionError ?? "", DiagnosticText.english(selectionError ?? "")))
        }
        .animation(reduceMotion || !visible ? nil : .smooth(duration: 0.25), value: settings.showOriginalNames)
    }

    @MainActor private func present(_ inventory: Inventory) async {
        if presentedInventory == nil || !visible || reduceMotion {
            replaceInventory(inventory)
            return
        }
        guard presentedInventory != inventory else {
            // A rapid reversal may return to the still-displayed subscription.
            replacingInventory = false
            withAnimation(.easeInOut(duration: 0.18)) { inventoryOpacity = 1 }
            return
        }
        replacingInventory = true
        withAnimation(.easeInOut(duration: 0.12)) { inventoryOpacity = 0 }
        do {
            try await Task.sleep(for: .milliseconds(120))
            try Task.checkCancellation()
            guard inventory == currentInventory else { return }
            replaceInventory(inventory, opacity: 0)
            replacingInventory = true
            withAnimation(.easeInOut(duration: 0.18)) { inventoryOpacity = 1 }
            try await Task.sleep(for: .milliseconds(180))
            try Task.checkCancellation()
            if inventory == currentInventory { replacingInventory = false }
        } catch {
            // The new keyed task owns the next transition; never commit stale rows.
        }
    }

    private func replaceInventory(_ inventory: Inventory, opacity: Double = 1) {
        withTransaction(Transaction(animation: nil)) {
            presentedInventory = inventory
            presentedSelection = tunnel.selectedNode
            inventoryOpacity = opacity
            replacingInventory = false
        }
    }

    private func choose(_ name: String, in inventory: Inventory) {
        guard visible, !replacingInventory, inventory == currentInventory,
              let catalog = tunnel.catalog,
              pendingNode == nil, tunnel.canSelectMember, tunnel.selectedNode != name else { return }
        guard let selection = catalog.directSelection(for: name) else {
            showGroups = true
            return
        }
        let identity = tunnel.configurationID
        pendingNode = name
        Task { @MainActor in
            let applied = await tunnel.selectMember(group: selection.group, member: selection.member,
                expectedConfigurationID: identity)
            pendingNode = nil
            if !applied { selectionError = tunnel.message }
        }
    }
}
