import SwiftUI

struct TunnelStatisticsSection: View {
    let snapshot: TunnelSnapshot?
    let canRefresh: Bool
    let onRefresh: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section(settings.text("扩展统计", "Extension statistics")) {
            if let stats = snapshot {
                LabeledContent(settings.text("内核", "Core"), value: stats.coreRunning ? settings.text("运行中", "Running") : settings.text("未运行", "Stopped"))
                LabeledContent(settings.text("收到系统数据包", "Packets from system"), value: String(stats.packetsFromSystem))
                LabeledContent(settings.text("返回系统数据包", "Packets to system"), value: String(stats.packetsToSystem))
                LabeledContent(settings.text("桥接丢包", "Bridge packet drops"), value: String(stats.droppedPackets))
                if let up = stats.proxyUploadBytes, let down = stats.proxyDownloadBytes {
                    LabeledContent(settings.text("代理上行 / 下行", "Proxy upload / download"), value: "\(up) / \(down) B")
                }
                if let success = stats.bindingSuccesses, let failure = stats.bindingFailures {
                    LabeledContent(settings.text("出站绑定 成功 / 失败", "Outbound bindings: success / failure"), value: "\(success) / \(failure)")
                }
                if let transport = stats.physicalTransport {
                    LabeledContent(settings.text("物理链路", "Physical transport"), value: transport)
                }
                LabeledContent(settings.text("扩展内存", "Extension memory"), value: String(format: "%.1f MiB", Double(stats.memoryBytes) / 1_048_576))
            } else {
                Text(settings.text("连接后手动读取；统计不等于出口及 DNS 验收通过。", "Read manually after connecting. Counters alone do not verify the exit route or DNS."))
                    .foregroundStyle(.secondary)
            }
            Button(settings.text("读取扩展统计", "Read extension statistics"), action: onRefresh)
                .disabled(!canRefresh)
        }
    }
}
