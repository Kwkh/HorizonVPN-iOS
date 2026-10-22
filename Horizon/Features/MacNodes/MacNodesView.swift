#if os(macOS)
import SwiftUI

struct MacNodesView: View {
    let library: MacLibraryStore
    @State private var search = ""
    @State private var sort = Sort.original
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Sort { case original, name, latency }
    private var indices: [Int] {
        guard let catalog = library.prepared?.catalog else { return [] }
        if search.isEmpty, sort == .original { return Array(catalog.nodes.indices) }
        // Resolve each display name once, rather than scanning the catalog on
        // every sorting comparison (especially while batch results arrive).
        let labels = sort == .name || !search.isEmpty
            ? catalog.nodes.map { settings.nodeLabel(catalog, name: $0.name) } : []
        let results = sort == .latency ? library.probes.results : [:]
        return catalog.nodes.indices.filter {
            search.isEmpty || catalog.nodes[$0].name.localizedCaseInsensitiveContains(search)
                || labels[$0].localizedCaseInsensitiveContains(search)
        }.sorted { a, b in
            switch sort {
            case .original: return a < b
            case .name:
                let result = labels[a].localizedStandardCompare(labels[b])
                return result == .orderedSame ? a < b : result == .orderedAscending
            case .latency:
                let lhs = results[a]?.milliseconds ?? .max
                let rhs = results[b]?.milliseconds ?? .max
                return lhs == rhs ? a < b : lhs < rhs
            }
        }
    }
    var body: some View {
        let visibleIndices = indices
        ScrollView {
            if let catalog = library.prepared?.catalog {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 20) {
                        Text(settings.text("\(catalog.nodes.count) 个节点", "\(catalog.nodes.count) nodes"))
                            .fixedSize()
                        Spacer(minLength: 16)
                        let target = catalog.resolvedTarget(runtimeChoices: library.runtimeChoices)
                        Text(target.map { settings.text("当前：", "Current: ") + settings.nodeLabel(catalog, name: $0) } ?? "")
                            .lineLimit(1).frame(height: 18)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: target)
                    }.font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Text(library.probes.targetCount > 0
                            ? settings.text("已完成 \(library.probes.completedCount) / \(library.probes.targetCount)",
                                "Tested \(library.probes.completedCount) / \(library.probes.targetCount)")
                            : settings.text("最多 5 个节点同时测试", "Up to 5 simultaneous tests"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.probes.completedCount)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.probes.targetCount)
                        Spacer(minLength: 8)
                        Button(settings.text("停止", "Stop")) { library.probes.cancel() }
                            .opacity(library.probes.running ? 1 : 0)
                            .disabled(!library.probes.running)
                            .accessibilityHidden(!library.probes.running)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: library.probes.running)
                    }
                    // Keep the test controls in place while progress changes.
                    .frame(height: 24)
                    if catalog.nodes.isEmpty {
                        ContentUnavailableView(settings.text("没有节点", "No nodes"), systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text(settings.text("此订阅没有可显示的节点。", "This configuration has no nodes to display.")))
                            .frame(maxWidth: .infinity)
                    } else if visibleIndices.isEmpty {
                        ContentUnavailableView.search(text: search).frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], spacing: 12) {
                            ForEach(visibleIndices, id: \.self) { index in MacNodeCard(library: library, index: index) }
                        }
                        // A new query gets fresh lazy cells; sorting within that
                        // query retains identities so positions can animate.
                        .id([library.probeScope, search])
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: visibleIndices)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            } else { ContentUnavailableView(MacText.value("尚未选择订阅", "No configuration selected"), systemImage: "point.3.connected.trianglepath.dotted").padding(.top, 100) }
        }
        .background(.black).navigationTitle(library.activeTitle)
        .searchable(text: $search, prompt: settings.text("搜索节点", "Search nodes"))
        .toolbar {
            Picker(settings.text("排序", "Sort"), selection: $sort) {
                Text(settings.text("原始顺序", "Original")).tag(Sort.original)
                Text(settings.text("名称", "Name")).tag(Sort.name)
                Text(settings.text("延迟", "Latency")).tag(Sort.latency)
            }.pickerStyle(.menu)
            Button(settings.text("测试所有节点", "Test all nodes")) { Task { await library.test(Array(library.prepared?.catalog.nodes.indices ?? 0..<0)) } }
                .disabled(library.prepared?.catalog.nodes.isEmpty != false || library.offline)
        }
    }
}
#endif
