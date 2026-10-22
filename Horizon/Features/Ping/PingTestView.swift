import SwiftUI
import NetworkExtension

struct PingTestView: View {
    @Environment(AppSettings.self) private var settings
    let tunnel: TunnelController

    var body: some View {
        List {
            ClashListContent {
                Section(settings.text("当前节点", "Selected node")) {
                    LabeledContent(settings.text("VPN 状态", "VPN status"), value: settings.statusText(tunnel.status))
                    Text(tunnel.catalog.map { settings.probeLabel($0) } ?? settings.text("缺少配置", "No configuration")).font(.footnote)
                    LabeledContent(settings.text("测量方式", "Measurement"), value: tunnel.unifiedDelay ? settings.text("统一延迟", "Unified delay") : settings.text("首次请求耗时", "First request"))
                    LabeledContent(settings.text("超时", "Timeout"), value: settings.text("10 秒", "10 seconds"))
                    if tunnel.isTestingPing {
                        ProgressView(settings.text("正在测试…", "Testing…"))
                            .accessibilityIdentifier("ping.progress")
                    } else if let report = tunnel.pingReport {
                        LabeledContent(settings.text("测试结果", "Result"), value: report.summary)
                            .monospacedDigit()
                            .accessibilityIdentifier("ping.result")
                        if let date = tunnel.pingDate {
                            LabeledContent(settings.text("测试时间", "Tested")) {
                                Text(date, format: .dateTime.hour().minute().second())
                            }
                        }
                    } else {
                        Text(settings.text("尚未测试", "Not tested")).foregroundStyle(.secondary)
                    }
                    Button(tunnel.isTestingPing ? settings.text("正在测试…", "Testing…") : settings.text("测试 Ping", "Test Ping")) {
                        Task { await tunnel.testPing() }
                    }
                    .disabled(!tunnel.canTestPing)
                    .accessibilityIdentifier("ping.start")
                    if tunnel.network.isOffline {
                        Text(settings.text("请先恢复网络连接。", "Restore your network connection first."))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if tunnel.isProbing {
                        Text(settings.text("请等待当前联网诊断结束。", "Wait for the current diagnostic to finish."))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if tunnel.catalog?.resolvedTarget() == nil {
                        Text(settings.text("当前没有可测速的代理节点。", "No proxy node is available to test.")).font(.footnote)
                    }
                }

            }
        }
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("测试 Ping", "Test Ping"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InformationButton(title: settings.text("测试说明", "About this test"), paragraphs: [
                    PingReport.testURL,
                    settings.text("未连接时通过所选节点测速，使用系统 DNS；已连接时通过隧道测速，结果可能不同。测速不会切换节点。", "Disconnected tests use the selected node and system DNS; connected tests use the tunnel. Results may differ. Tests never switch nodes."),
                    tunnel.unifiedDelay
                    ? settings.text("优先测量复用连接的请求耗时；失败时可能计入首次连接耗时。", "Times a request on a reused connection when possible; fallback results may include initial connection setup.")
                    : settings.text("测量建立连接及首次响应的耗时。", "Measures connection setup and the first response."),
                    settings.text("这是 HTTP 延迟测试，不代表下载速度、ICMP Ping 或目标网站的 HTTPS 可用性。节点加密和证书设置不变。", "Measures HTTP latency, not download speed, ICMP Ping or destination HTTPS availability. Proxy encryption and certificate settings stay unchanged."),
                    settings.text("等待 10 秒后显示超时；超时后可能需稍候再测。返回不会取消测试；断开 VPN 或等待网络恢复时会清除结果。", "Shows a timeout after 10 seconds; the next test may need to wait. Going back does not cancel the test. Results clear on disconnect or while waiting for network recovery."),
                    settings.text("结果仅在本次 App 会话保留，不记录节点地址、凭据或响应内容。", "Results last for this app session. Node addresses, credentials and response contents are not logged.")
                ])
            }
        }
    }
}

#Preview { NavigationStack { PingTestView(tunnel: TunnelController()) } }
