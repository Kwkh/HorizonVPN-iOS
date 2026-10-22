import SwiftUI
import NetworkExtension

struct BatchProbeView: View {
    let tunnel: TunnelController
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sorted = false
    @State private var pendingNode: String?
    @State private var selectionError: String?
    @State private var showGroups = false
    private var store: BatchProbeStore { tunnel.batchProbes }
    private var rows: [BatchProbeStatus.Result] {
        guard sorted else { return store.results }
        return store.results.sorted {
            let a = $0.state == .success ? $0.milliseconds ?? .max : .max
            let b = $1.state == .success ? $1.milliseconds ?? .max : .max
            return a == b ? $0.id < $1.id : a < b
        }
    }
    var body: some View {
        let displayedRows = rows
        List {
            ClashListContent {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(phaseLabel).font(.title2.weight(.medium)).contentTransition(.opacity)
                            Text(progressLabel)
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary).contentTransition(.numericText())
                        }
                        Spacer()
                        Button {
                            if store.isRunning { store.cancel(using: tunnel) }
                            else {
                                guard tunnel.canTestBatch else { return }
                                store.start(using: tunnel)
                            }
                        } label: {
                            Image(systemName: store.isRunning ? "stop.fill" : "play.fill").frame(width: 42, height: 42)
                        }.buttonStyle(.glass).buttonBorderShape(.circle)
                            // Selection temporarily locks testing, but must not dim the glass.
                            // The action guard also protects accessibility activation during it.
                            .disabled(!store.isRunning && !tunnel.canTestBatch && !tunnel.isSwitchingNode)
                            .allowsHitTesting(store.isRunning || !tunnel.isSwitchingNode)
                            .accessibilityLabel(store.isRunning ? settings.text("取消测速", "Cancel tests") : settings.text("开始测速", "Start tests"))
                            .accessibilityIdentifier("batch.start-stop")
                    }.padding(.vertical, 12)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.phase)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.finishedCount)
                    if tunnel.network.isOffline { Label(settings.text("无网络连接", "No network connection"), systemImage: "wifi.slash") }
                }.listRowBackground(Color.clear)
                ForEach(displayedRows) { result in
                    if let catalog = tunnel.catalog, catalog.nodes.indices.contains(result.id) {
                        let name = catalog.nodes[result.id].name
                        HStack(spacing: 8) {
                            NodeSelectionRowView(number: result.id + 1, title: nodeLabel(result.id),
                                protocolName: catalog.nodes[result.id].kind.uppercased(),
                                isSelected: tunnel.selectedNode == name, isPending: pendingNode == name,
                                isEnabled: tunnel.canSelectMember && pendingNode == nil) { choose(name, in: catalog) }
                            NodePingButton(tunnel: tunnel, index: result.id)
                        }.listRowBackground(Color.clear)
                    }
                }
                if let date = store.date {
                    Section { Text(date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary) }
                        .listRowBackground(Color.clear)
                }
            }
        }
        // List owns row positions, including rows exposed by ClashListContent.
        // Animate its diff for both manual sorting and arriving results, using stable node IDs.
        // Unchanged order (including node selection) must not trigger a list animation.
        .animation(reduceMotion ? nil : .smooth(duration: 0.38), value: displayedRows.map(\.id))
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("批量测速", "Latency tests"))
        .navigationDestination(isPresented: $showGroups) { NodeSelectionView(tunnel: tunnel) }
        .alert(settings.text("节点切换", "Node selection"), isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button(settings.text("好", "OK"), role: .cancel) { selectionError = nil }
        } message: { Text(settings.text(selectionError ?? "", DiagnosticText.english(selectionError ?? ""))) }
        .onChange(of: tunnel.activeSubscriptionID) { _, _ in sorted = false }
        .toolbar {
            InformationButton(title: settings.text("测速说明", "About latency tests"), paragraphs: [
                settings.text("测试节点延迟，不代表下载速度。测试地址：", "Measures node latency, not download speed. Test URL: ") + PingReport.testURL,
                settings.text("无需连接 VPN，也不会自动切换节点。未连接时使用系统 DNS，连接时通过隧道测速。", "VPN is optional. Tests never switch nodes automatically. Disconnected tests use system DNS; connected tests use the tunnel."),
                settings.text("最多同时测试 \(ProbeAdmissionQueue.limit) 个节点，单次最多 10 秒。可随时取消，进入后台会停止。未连接时不计入隧道流量。", "Tests up to \(ProbeAdmissionQueue.limit) nodes at once, with a 10-second timeout. Cancel anytime; backgrounding stops tests. Disconnected tests are excluded from tunnel traffic."),
                settings.text("点击名称选择节点，点击 Ping 单独测速。测速时可切换节点，结果保留；需要时会进入策略组选择。切换或更新订阅后清除旧结果。", "Tap a name to select, or Ping to test one node. Selection keeps test progress and results; Groups opens when needed. Switching or updating subscriptions clears old results.")
            ])
            Button { sorted.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                .disabled(store.results.isEmpty)
                .accessibilityLabel(settings.text("切换延迟排序", "Toggle latency sorting"))
        }
    }
    private func choose(_ name: String, in catalog: ConfigurationCatalog) {
        guard pendingNode == nil, tunnel.canSelectMember, tunnel.selectedNode != name else { return }
        guard let selection = catalog.directSelection(for: name) else { showGroups = true; return }
        let identity = tunnel.configurationID
        pendingNode = name
        Task {
            let applied = await tunnel.selectMember(group: selection.group, member: selection.member, expectedConfigurationID: identity)
            pendingNode = nil
            if !applied { selectionError = tunnel.message }
        }
    }
    private func nodeLabel(_ index: Int) -> String {
        if settings.showOriginalNames, store.phase != .stale, let catalog = tunnel.catalog, catalog.nodes.indices.contains(index) {
            return catalog.nodes[index].name
        }
        return settings.text("节点 \(index + 1)", "Node \(index + 1)")
    }
    private var progressLabel: String {
        if store.isRunning { return "\(store.finishedCount) / \(store.targetCount)" }
        if case .node(let index) = store.runScope {
            return settings.text("节点 \(index + 1) · 10 秒超时", "Node \(index + 1) · 10s timeout")
        }
        if store.runScope == .selectedNodes {
            return settings.text("所选节点 · 10 秒超时", "Selected nodes · 10s timeout")
        }
        return settings.text("全部节点 · 10 秒超时", "All nodes · 10s timeout")
    }
    private var phaseLabel: String {
        switch store.phase {
        case .idle: settings.text("准备测速", "Ready to test")
        case .running: settings.text("正在测速", "Testing")
        case .complete: store.runScope == .allNodes
            ? settings.text("全部节点测试完成", "All node tests finished")
            : settings.text("节点测速完成", "Node test finished")
        case .cancelled: settings.text("已取消", "Cancelled")
        case .failed: settings.text("暂不可用，请重试", "Unavailable. Try again")
        case .stale: settings.text("结果已过期", "Results expired")
        }
    }
}
