#if os(macOS)
import SwiftUI

struct MacGroupsView: View {
    let library: MacLibraryStore
    @State private var collapsed: Set<String> = []
    @State private var search = ""
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            if let catalog = library.prepared?.catalog {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(catalog.groups) { group in
                        VStack(alignment: .leading, spacing: 16) {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                    if !collapsed.insert(group.name).inserted { collapsed.remove(group.name) }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(settings.nodeLabel(catalog, name: group.name)).font(.headline).foregroundStyle(.primary)
                                        Text(group.kind.uppercased() + " · \(group.members.count)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: collapsed.contains(group.name) ? "chevron.down" : "chevron.up")
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if !collapsed.contains(group.name) || !search.isEmpty {
                                ForEach(group.members.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || settings.nodeLabel(catalog, name: $0).localizedCaseInsensitiveContains(search) }, id: \.self) { member in
                                    let switching = library.isSelecting(group: group.id, member: member)
                                    let selected = (library.runtimeChoices[group.name] ?? catalog.choices[group.name]) == member
                                    HStack(spacing: 14) {
                                        Button { Task { await library.select(group: group.id, member: member) } } label: {
                                            HStack(spacing: 10) {
                                                // Keep the status beside its node name. Reserve the
                                                // same slot for idle, switching and selected states.
                                                ZStack {
                                                    Image(systemName: "checkmark").opacity(selected && !switching ? 1 : 0)
                                                        .accessibilityHidden(true)
                                                    ProgressView().controlSize(.small)
                                                        .opacity(switching ? 1 : 0).accessibilityHidden(!switching)
                                                        .accessibilityLabel(settings.text("切换节点中", "Switching node"))
                                                }.frame(width: 18, height: 18)
                                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: switching)
                                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                                                Text(settings.nodeLabel(catalog, name: member)).font(.body).foregroundStyle(.primary).lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                Spacer(minLength: 8)
                                            }.contentShape(Rectangle())
                                        }.buttonStyle(.plain).allowsHitTesting(group.allowsSelection && (library.vpn.isIdle || library.vpn.status == .connected) && !library.busy && library.pendingSelection == nil)
                                        if let index = catalog.nodes.firstIndex(where: { $0.name == member }) {
                                            Button { Task { await library.test([index]) } } label: {
                                                Text(library.probes.label(index))
                                                    .contentTransition(.numericText())
                                                    .lineLimit(1).minimumScaleFactor(0.8)
                                                    .frame(width: 88, height: 18, alignment: .trailing)
                                            }
                                                .buttonStyle(.plain).font(.callout.monospacedDigit())
                                                .allowsHitTesting(!library.probes.isTesting(index) && !library.offline)
                                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.probes.label(index))
                                        }
                                    }.padding(.leading, 14).padding(.vertical, 5)
                                }
                            }
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
                    }
                }.padding(28)
            } else { ContentUnavailableView(settings.text("尚未选择订阅", "No configuration selected"), systemImage: "arrow.triangle.branch").padding(.top, 100) }
        }
        .background(.black).navigationTitle(settings.text("策略组", "Groups"))
        .searchable(text: $search, prompt: settings.text("搜索节点与策略组", "Search nodes & groups"))
        .onChange(of: library.probeScope) { collapsed = [] }
    }
}
#endif
