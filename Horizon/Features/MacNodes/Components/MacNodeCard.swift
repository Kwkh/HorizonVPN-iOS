#if os(macOS)
import SwiftUI

struct MacNodeCard: View {
    let library: MacLibraryStore
    let index: Int
    @State private var hovered = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let catalog = library.prepared?.catalog, catalog.nodes.indices.contains(index) {
            let node = catalog.nodes[index]
            let selected = catalog.resolvedTarget(runtimeChoices: library.runtimeChoices) == node.name
            let switching = catalog.directSelection(for: node.name).map {
                library.isSelecting(group: $0.group, member: node.name)
            } ?? false
            Button {
                    guard !library.busy, library.pendingSelection == nil, library.vpn.isIdle || library.vpn.status == .connected else { return }
                    if let selection = catalog.directSelection(for: node.name),
                       let group = catalog.groups.first(where: { $0.id == selection.group }) {
                        Task { await library.select(group: group.id, member: group.members[selection.member]) }
                    }
                } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(settings.nodeLabel(catalog, name: node.name)).font(.body.weight(.medium))
                            .lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            Image(systemName: "checkmark.circle.fill").opacity(selected && !switching ? 1 : 0)
                                .accessibilityHidden(true)
                            ProgressView().controlSize(.small)
                                .opacity(switching ? 1 : 0).accessibilityHidden(!switching)
                                .accessibilityLabel(settings.text("切换节点中", "Switching node"))
                        }.frame(width: 18, height: 18)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: switching)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())

                HStack {
                    Text(node.kind.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    Spacer(minLength: 8)
                    Color.clear.frame(width: 88, height: 26)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!library.busy && library.pendingSelection == nil && (library.vpn.isIdle || library.vpn.status == .connected))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(settings.nodeLabel(catalog, name: node.name))
            // Independent sibling control: Ping never also selects the node.
            .overlay(alignment: .bottomTrailing) {
                    Button {
                        guard !library.probes.isTesting(index), !library.offline else { return }
                        Task { await library.test([index]) }
                    } label: {
                        Text(library.probes.label(index)).font(.callout.monospacedDigit())
                            .contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 88, height: 18, alignment: .trailing)
                            .padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.primary)
                        .accessibilityLabel(settings.text("测试节点延迟", "Test node latency"))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.probes.label(index))
                    .padding(16)
            }
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(selected ? 0.09 : hovered ? 0.065 : 0.035))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(selected ? 0.4 : hovered ? 0.2 : 0.1))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            }
            .onHover { hovered = $0 }
        }
    }
}
#endif
