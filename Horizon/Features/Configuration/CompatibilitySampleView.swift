import SwiftUI

struct CompatibilitySampleView: View {
    let sample: CompatibilitySamples.Sample
    @Environment(AppSettings.self) private var settings
    @State private var report: ConfigurationCompatibility?
    var body: some View {
        List {
            ClashListContent {
                Section { Text(settings.text("完全虚构的固定用例，仅用于说明和离线测试，不连接服务器。", "Entirely fictional fixture for documentation and offline tests. No server connection.")) }
                if let report {
                    ForEach(report.findings) { finding in
                        VStack(alignment: .leading) {
                            Label(settings.text(finding.location, ConfigurationDiagnosticText.location(finding.location) ?? "Configuration"), systemImage: finding.level == .blocked ? "xmark.circle" : finding.level == .adapted ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                            Text(settings.text(finding.detail, DiagnosticText.importEnglish(finding.detail))).foregroundStyle(.secondary)
                        }
                    }
                } else { ProgressView() }
            }
        }
        .listStyle(.plain).clashScreen().navigationTitle(settings.text(sample.title, sample.englishTitle))
        .task { report = ConfigurationCompatibility.inspect(Data(sample.yaml.utf8)) }
    }
}
