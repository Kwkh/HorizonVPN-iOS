import NetworkExtension
import SwiftUI

struct RuleDiagnosticsView: View {
    let tunnel: TunnelController
    @State private var store = NetworkInspectionStore()
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        List {
            ClashListContent {
                Section {
                    NavigationLink { ConnectionCaptureView(tunnel: tunnel) } label: {
                        Label(settings.text("短时后台诊断", "Capture across apps"), systemImage: "timer")
                    }
                    if tunnel.status != .connected {
                        Label(settings.text("请先连接 VPN", "Connect VPN first"), systemImage: "wifi.slash")
                    }
                    Toggle(settings.text("观测规则命中", "Observe rule matches"), isOn: Binding(get: { store.observing }, set: {
                        if $0 { store.startRules(tunnel) } else { store.stopRules() }
                    }))
                    .tint(Color(uiColor: .systemGreen))
                    .disabled(!tunnel.permitsNetwork || tunnel.status != .connected)
                    Button(settings.text("清空记录", "Clear records")) { store.clearRules() }.disabled(store.rules.isEmpty)
                    if let message = store.message { Text(settings.text(message, DiagnosticText.english(message))).foregroundStyle(.secondary) }
                }.listRowBackground(Color.clear)
                Section(settings.text("最近观测 · \(store.rules.count)", "Observed · \(store.rules.count)")) {
                    ForEach(store.rules) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.type).font(.headline)
                                Spacer()
                                Text(row.transport).foregroundStyle(.secondary)
                            }
                            Text(row.ruleNumber.map { settings.text("运行规则 #\($0)", "Runtime rule #\($0)") } ?? settings.text("规则序号无法唯一确定", "Rule index unavailable or ambiguous"))
                                .font(.callout).foregroundStyle(.secondary)
                            Text(row.chain.reversed().map(chainLabel).joined(separator: " → ")).font(.callout)
                        }.padding(.vertical, 5)
                    }.listRowBackground(Color.clear)
                    if store.rules.isEmpty {
                        ContentUnavailableView(settings.text("暂无命中记录", "No matches observed"), systemImage: "arrow.triangle.branch")
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }.listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("规则命中", "Rule matches"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InformationButton(title: settings.text("观测说明", "About observation"), paragraphs: [settings.text(
                    "手动开启后，每两秒读取内核当前连接快照，最多保留 60 条内存记录。短连接可能在两次采样间结束而未被捕获，不是完整访问历史。保留的是实际命中类型和经过的策略组／节点，不是静态规则推测。内核未暴露唯一规则 ID，重复规则或 iOS 插入规则可能没有原文件序号。",
                    "Opt-in snapshots every two seconds retain up to 60 observations in memory. Short-lived connections may be missed. Matches and chains come from actual core connections. Duplicate or iOS-inserted rules may have no unique source index."), settings.text(
                    "目的域名、IP、端口、进程与规则内容不会传给主 App 或写入日志。原名开关仅影响已知节点和策略组的显示。离开页面或进入后台会停止并清空。",
                    "Destination domains, IPs, ports, processes and rule payloads are never sent to the app or logged. Original names only affect known nodes and groups. Leaving this page or backgrounding stops and clears observation.")])
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: store.rules.map(\.id))
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: store.message)
        .onChange(of: tunnel.configurationID) { _, _ in store.stopRules(clear: true) }
        .onDisappear { store.stopRules(clear: true) }
        .onChange(of: phase) { _, phase in if phase != .active { store.stopRules(clear: true) } }
    }
    private func chainLabel(_ code: String) -> String {
        guard let catalog = tunnel.catalog else { return code }
        if code.first == "N", let i = Int(code.dropFirst()), catalog.nodes.indices.contains(i - 1) {
            return settings.nodeLabel(catalog, name: catalog.nodes[i - 1].name)
        }
        if code.first == "G", let i = Int(code.dropFirst()), catalog.groups.indices.contains(i - 1) {
            return settings.nodeLabel(catalog, name: catalog.groups[i - 1].name)
        }
        return code
    }
}
