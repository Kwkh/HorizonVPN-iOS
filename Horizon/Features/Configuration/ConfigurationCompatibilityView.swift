import SwiftUI

struct ConfigurationCompatibilityView: View {
    let report: ConfigurationCompatibility?
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ClashListContent {
                    if let report {
                        ForEach(ConfigurationCompatibility.Level.allCases, id: \.self) { level in
                            let findings = report.findings.filter { $0.level == level }
                            if !findings.isEmpty {
                                Section(title(level)) {
                                    ForEach(findings) { finding in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(settings.text(finding.location, ConfigurationDiagnosticText.location(finding.location) ?? "Configuration")).font(.headline)
                                            Text(settings.text(finding.detail, DiagnosticText.importEnglish(finding.detail))).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Section { Text(settings.text("导入后可查看当前候选配置的完整诊断；未支持项不会被静默删除。", "Import a configuration to inspect its diagnostics. Unsupported fields are never silently removed.")) }
                    }
                    Section(settings.text("说明", "Information")) {
                        Text(settings.text("直接支持表示当前结构校验通过，不保证节点可达。需要适配项会明确显示；无法使用项必须修复后重新导入。语法无效时无法枚举内部字段。", "Supported means structural validation passed, not that nodes are reachable. Adaptations are disclosed; blocked items must be fixed. Invalid YAML must be repaired before fields can be inspected."))
                        Text(settings.text("来源 URL、原文和历史版本保存在本机钥匙串。订阅仅手动刷新；可在设置中开启跨设备 iCloud 同步，历史版本仍各设备独立。新版本首次启动失败时最多恢复一个保留版本；主动断开会取消恢复。更新预览隐藏凭据和服务器地址。", "Source URLs, original input and revision history stay in device Keychain. Refresh is manual. Optional iCloud sync shares subscriptions across devices; history stays local. Failed first startup restores at most one retained revision; an explicit stop cancels recovery. Reviews hide credentials and endpoints."))
                        Text(settings.text("点击订阅切换，右侧箭头打开详情。设置来源、更新及回滚均需确认；当前连接需要重启时会单独提示。旧版一次性导入未保存的链接不能自动找回。", "Tap a configuration to switch, or its arrow for details. Source changes, updates and rollbacks require review; reconnection is confirmed separately. URLs missing from older imports cannot be recovered."))
                    }
                    Section(settings.text("脱敏样例库", "Synthetic examples")) {
                        ForEach(CompatibilitySamples.all) { sample in
                            NavigationLink(settings.text(sample.title, sample.englishTitle)) { CompatibilitySampleView(sample: sample) }
                        }
                    }
                }
            }
            .listStyle(.plain).clashScreen().navigationTitle(settings.text("兼容性诊断", "Compatibility"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(settings.text("完成", "Done")) { dismiss() } } }
        }
    }
    private func title(_ level: ConfigurationCompatibility.Level) -> String {
        switch level {
        case .supported: settings.text("直接支持", "Supported")
        case .adapted: settings.text("需要适配", "Adapted")
        case .blocked: settings.text("无法使用", "Blocked")
        }
    }
}
