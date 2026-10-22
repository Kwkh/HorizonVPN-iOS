import SwiftUI

struct TabletNodeGridView: View {
    let tunnel: TunnelController
    let search: String
    let pendingNode: String?
    let matches: (ConfigurationCatalog, Int) -> Bool
    let choose: (String, ConfigurationCatalog) -> Void
    let toggleBatch: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabletCardGrid {
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.text("当前订阅", "Current configuration")).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 16) {
                    Text(tunnel.currentSubscriptionTitle)
                        .font(.title3.weight(.medium)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: toggleBatch) {
                        HStack(spacing: 8) {
                            if tunnel.batchProbes.isTestingAllNodes {
                                ProgressView().controlSize(.small)
                                Text("\(tunnel.batchProbes.finishedCount)/\(tunnel.batchProbes.targetCount)")
                                    .monospacedDigit().contentTransition(.numericText())
                                Text(settings.text("取消", "Cancel"))
                            } else {
                                Text(settings.text("测试全部节点", "Test all nodes"))
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 4).frame(minHeight: 32)
                    }
                    .buttonStyle(.glass)
                    .disabled(!tunnel.batchProbes.isTestingAllNodes &&
                        (!tunnel.canTestBatch || tunnel.catalog?.nodes.isEmpty != false))
                    .accessibilityLabel(tunnel.batchProbes.isTestingAllNodes
                        ? settings.text("取消全部节点测速", "Cancel all node tests")
                        : settings.text("测试全部节点", "Test all nodes"))
                    .accessibilityIdentifier("nodes.tablet.test-all")
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: tunnel.batchProbes.isTestingAllNodes)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: tunnel.batchProbes.finishedCount)
                }
            }
            if tunnel.catalog == nil {
                ContentUnavailableView(settings.text("还没有节点", "No nodes yet"), systemImage: "network")
            } else if let catalog = tunnel.catalog, !catalog.nodes.indices.contains(where: { matches(catalog, $0) }) {
                ContentUnavailableView.search(text: search)
            }
        } content: {
            if let catalog = tunnel.catalog {
                ForEach(catalog.nodes.indices.filter { matches(catalog, $0) }, id: \.self) { index in
                    let node = catalog.nodes[index]
                    VStack(alignment: .leading, spacing: 8) {
                        NodeSelectionRowView(number: index + 1,
                            title: settings.nodeLabel(catalog, name: node.name), protocolName: node.kind.uppercased(),
                            isSelected: tunnel.selectedNode == node.name, isPending: pendingNode == node.name,
                            isEnabled: tunnel.canSelectMember && pendingNode == nil) { choose(node.name, catalog) }
                            .frame(minHeight: 76, alignment: .top)
                        HStack { Spacer(); NodePingButton(tunnel: tunnel, index: index) }
                    }
                    .modifier(TabletCardStyle(selected: tunnel.selectedNode == node.name))
                }
            }
        }
    }
}
