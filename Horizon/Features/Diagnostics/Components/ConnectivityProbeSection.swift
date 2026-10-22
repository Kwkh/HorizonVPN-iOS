import SwiftUI

struct ConnectivityProbeSection: View {
    let report: ConnectivityReport?
    let isRunning: Bool
    let canRun: Bool
    let onRun: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            if let report {
                LabeledContent(settings.text("节点引导解析", "Node bootstrap"), value: settings.text(report.bootstrapSummary, DiagnosticText.english(report.bootstrapSummary)))
                LabeledContent(settings.text("节点 HTTPS", "Node HTTPS"), value: settings.text(report.nodeSummary, DiagnosticText.english(report.nodeSummary)))
                LabeledContent("ping0.cc DNS", value: settings.text(report.dns.summary, DiagnosticText.english(report.dns.summary)))
            }
            Button(isRunning ? settings.text("正在检查…", "Checking…") : settings.text("检查节点与 DNS", "Check node & DNS"), action: onRun)
                .disabled(!canRun || isRunning)
        } header: {
            HStack {
                Text(settings.text("联网诊断", "Connectivity checks"))
                Spacer()
                InformationButton(title: settings.text("联网诊断说明", "About connectivity checks"), paragraphs: [settings.text("手动通过节点请求 https://1.1.1.1/cdn-cgi/trace，并经内核解析 ping0.cc。仅显示结果和耗时；不显示响应内容、IP 或节点信息。此检查不代替 Safari 的完整隧道验收。", "Manually requests https://1.1.1.1/cdn-cgi/trace through the node and resolves ping0.cc through the core. Only results and timing are shown; response contents, IPs and node details are hidden. This does not replace an end-to-end tunnel check in Safari.")])
            }

        }
    }
}
