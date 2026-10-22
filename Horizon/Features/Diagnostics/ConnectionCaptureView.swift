import NetworkExtension
import SwiftUI

struct ConnectionCaptureView: View {
    let tunnel: TunnelController
    @State private var store = ConnectionCaptureStore()
    @State private var confirm = false
    @State private var showDestinations = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            ClashListContent {
                Section {
                    Button { confirm = true } label: {
                        HStack {
                            Text(settings.text("记录 60 秒", "Capture 60 seconds"))
                            Spacer()
                            if store.remaining > 0 { Text("\(store.remaining) s").monospacedDigit().contentTransition(.numericText()) }
                        }
                    }.disabled(tunnel.status != .connected || store.busy || store.remaining > 0)
                    Button(settings.text("停止并清空", "Stop & clear"), role: .destructive) {
                        Task { await store.exchange(.captureClear, tunnel: tunnel) }
                    }.disabled(store.busy || tunnel.status != .connected)
                    Toggle(settings.text("显示目标域名 / IP", "Show destination domain / IP"), isOn: $showDestinations)
                        .tint(Color(uiColor: .systemGreen))
                    if tunnel.status != .connected { Text(settings.text("请先连接 VPN", "Connect VPN first")).foregroundStyle(.secondary) }
                    if store.unavailable { Text(settings.text("诊断暂不可用，请确认扩展已更新并重新连接。", "Capture unavailable. Update the extension and reconnect.")).foregroundStyle(.secondary) }
                }.listRowBackground(Color.clear)
                Section(settings.text("连接采样 · \(store.rows.count)", "Sampled connections · \(store.rows.count)")) {
                    ForEach(store.rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.match.type).font(.headline)
                                Spacer()
                                Text(row.match.transport + " · " + row.family).foregroundStyle(.secondary)
                            }
                            if showDestinations { Text(row.destination ?? "—").font(.callout).textSelection(.enabled) }
                            Text(row.match.chain.reversed().map(chainLabel).joined(separator: " → ")).font(.callout)
                            HStack {
                                Text("↑ " + bytes(row.upload)); Spacer(); Text("↓ " + bytes(row.download))
                            }.monospacedDigit().contentTransition(.numericText()).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: row.upload)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: row.download)
                    }.listRowBackground(Color.clear)
                }
            }
        }.listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("短时连接诊断", "Connection capture"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InformationButton(title: settings.text("诊断说明", "About capture"), paragraphs: [
                    settings.text("开启后可切到微信等 App，由 VPN 扩展每秒采样一次，60 秒后停止。最多 30 条连接在内存保留，开启 5 分钟后自动清空；断开或切换节点也会清空。", "The VPN extension samples once per second for 60 seconds, including while you use another app. Up to 30 connections are kept in memory and cleared five minutes after starting, on disconnect, or on node change."),
                    settings.text("记录目标域名或 IP、规则、出口与连接累计字节，不记录聊天、视频、完整 URL 或内容，不写入文件。短连接与建立失败的连接可能采不到；字节是最后一次采样值，不代表送达。无法据此识别连接属于哪个 App。", "Records destination domain or IP, rule, outbound and connection byte counters. No chats, videos, full URLs or content; nothing is written to disk. Short-lived or failed connections may be missed. Last-sampled bytes do not prove delivery or identify the originating app.")])
            }
        }
        .alert(settings.text("开始短时诊断？", "Start connection capture?"), isPresented: $confirm) {
            Button(settings.text("取消", "Cancel"), role: .cancel) { }
            Button(settings.text("开始", "Start")) { Task { await store.exchange(.captureStart, tunnel: tunnel) } }
        } message: {
            Text(settings.text("接下来 60 秒会在本机内存记录连接目标域名 / IP、规则、出口与传输量。可以切换到其他 App 复现问题，5 分钟后自动清空。", "For 60 seconds, destination domains/IPs, rules, outbounds and byte counts are held in local memory. Switch to another app to reproduce the problem. Data clears automatically after five minutes."))
        }
        .task(id: phase) { if phase == .active { await store.poll(tunnel) } }
        .onChange(of: phase) { _, next in if next != .active { store.clearLocal(); showDestinations = false } }
        .onChange(of: tunnel.configurationID) { _, _ in store.clearLocal() }
        .onChange(of: tunnel.status) { _, next in if next != .connected { store.clearLocal() } }
        .onDisappear { store.clearLocal() }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.remaining)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showDestinations)
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }
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
