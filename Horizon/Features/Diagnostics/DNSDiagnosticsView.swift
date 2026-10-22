import NetworkExtension
import SwiftUI

struct DNSDiagnosticsView: View {
    let tunnel: TunnelController
    @State private var store = NetworkInspectionStore()
    @State private var domain = "ping0.cc"
    @State private var configuration: [String] = []
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        List {
            ClashListContent {
                Section {
                    if tunnel.status != .connected {
                        Label(settings.text("请先连接 VPN", "Connect VPN first"), systemImage: "wifi.slash")
                    }
                    TextField(settings.text("测试域名", "Test domain"), text: $domain)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .disabled(store.querying)
                    Button { store.runDNS(domain, tunnel: tunnel) } label: {
                        HStack {
                            Label(settings.text("开始检查", "Run checks"), systemImage: "network")
                            Spacer()
                            if store.querying { ProgressView() }
                        }
                    }.disabled(store.querying || !tunnel.canDiagnoseDNS)
                    if store.querying {
                        Button(settings.text("停止等待", "Stop waiting")) { store.cancelDNS(tunnel) }
                    }
                    if let message = store.message { Text(settings.text(message, DiagnosticText.english(message))).foregroundStyle(.secondary) }
                }.listRowBackground(Color.clear)
                Section(settings.text("实际测试", "Observed results")) {
                    ForEach(store.dns) { result in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(label(result.stage)).font(.headline)
                                Spacer()
                                if result.milliseconds >= 0 { Text("\(result.milliseconds) ms").monospacedDigit().contentTransition(.numericText()) }
                            }
                            Text(outcome(result.outcome)).foregroundStyle(.secondary)
                            if let count = result.answers, let code = result.responseCode {
                                Text(settings.text("记录数 \(count) · RCODE \(code)", "Answers \(count) · RCODE \(code)")).font(.callout)
                            }
                        }.padding(.vertical, 5)
                    }.listRowBackground(Color.clear)
                    if store.dns.isEmpty { Text(settings.text("尚无结果", "No results yet")).foregroundStyle(.secondary).listRowBackground(Color.clear) }
                }
                Section(settings.text("配置摘要 · 非实测路径", "Configured · Not observed routing")) {
                    ForEach(configuration, id: \.self) { Text($0) }.listRowBackground(Color.clear)
                }
            }
        }.listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("DNS 分项诊断", "DNS diagnostics"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InformationButton(title: settings.text("测试范围", "Test scope"), paragraphs: [settings.text(
                    "手动开始后，通过内核解析器查询输入域名的 A 和 AAAA；还会检查当前 MATCH 节点的引导解析和固定 Cloudflare HTTPS 测试。HTTPS 测试不访问输入域名，不等同该网站连通性。DIRECT／拒绝模式无节点测试。查询可能命中缓存，耗时不是纯上游延迟。",
                    "Queries A and AAAA through the core resolver, plus bootstrap and a fixed Cloudflare HTTPS probe through the selected MATCH node. HTTPS does not test the entered website. Direct/reject routes have no node probe. Cached answers may be used; timing is not pure upstream latency."), settings.text(
                    "当前桥接没有暴露实际命中的 DNS 策略、上游与缓存来源。因此配置模式及数量只作参考，不宣称已验证具体上游或无 DNS 泄漏。停止等待、离开或后台会丢弃结果；已发出的查询等待内核超时结束，期间内核可能提示忙。域名不保存、不写日志；按正常 DNS 流程发送给配置的解析器。",
                    "The bridge does not expose the chosen DNS policy, upstream or cache source. Configuration summaries do not prove routing or absence of leaks. Stopping or leaving discards results; in-flight queries finish under core timeouts. The domain is sent through configured DNS, never saved or logged.")])
            }
        }
        .task { configuration = tunnel.dnsConfigurationSummary(english: !settings.isChinese) }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.querying)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.dns.map { $0.outcome })
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.message)
        .onChange(of: tunnel.configurationID) { _, _ in store.cancelDNS(tunnel); configuration = tunnel.dnsConfigurationSummary(english: !settings.isChinese) }
        .onChange(of: settings.isChinese) { _, _ in configuration = tunnel.dnsConfigurationSummary(english: !settings.isChinese) }
        .onDisappear { store.cancelDNS(tunnel); domain = "ping0.cc" }
        .onChange(of: phase) { _, phase in if phase != .active { store.cancelDNS(tunnel); domain = "ping0.cc" } }
    }
    private func label(_ stage: DNSStage.Stage) -> String {
        switch stage {
        case .a: "A · IPv4"
        case .aaaa: "AAAA · IPv6"
        case .bootstrap: settings.text("节点引导解析", "Node bootstrap")
        case .https: settings.text("节点 HTTPS", "Node HTTPS")
        }
    }
    private func outcome(_ value: String) -> String {
        switch value {
        case "resolved", "success": settings.text("成功", "Succeeded")
        case "no-answer", "noAnswer": settings.text("未返回所请求类型的记录", "No answer of requested type")
        case "timeout": settings.text("超时", "Timed out")
        case "not-run": settings.text("未执行／无需解析", "Not run / not required")
        case "http-status": settings.text("收到非 2xx 响应", "Non-2xx response")
        case "tls": settings.text("TLS 或证书错误", "TLS / certificate error")
        case "network": settings.text("网络错误", "Network error")
        case "authentication": settings.text("认证失败", "Authentication failed")
        case "dns-response-error": settings.text("DNS 返回错误码", "DNS returned an error code")
        default: settings.text("未完成（原始错误已隐藏）", "Incomplete (raw error hidden)")
        }
    }
}
