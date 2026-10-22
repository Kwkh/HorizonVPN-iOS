#if os(macOS)
import SwiftUI

struct MacICloudSyncInfoView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section(settings.text("同步内容", "What syncs")) {
                        Text(settings.text("订阅名称、来源链接、原始配置与必要依赖。来源链接和配置可能包含凭据，使用 CloudKit 私有数据库及加密字段／资源保存。", "Names, source URLs, original configurations and required dependencies. Links and configurations may contain credentials; CloudKit private storage and encrypted fields/assets protect them."))
                    }.listRowBackground(Color.clear)
                    Section(settings.text("各设备独立", "Device-specific")) {
                        Text(settings.text("当前订阅、节点选择、智能分流、VPN 权限、证书风险确认、历史版本与测速结果不会同步。收到当前订阅的变更后，需要手动应用；不会自动断开或连接 VPN。", "Selected configuration, node choices, smart routing, VPN permissions, certificate approvals, revision history and test results stay local. Changes to the selected subscription require review and never automatically disconnect or connect VPN."))
                    }.listRowBackground(Color.clear)
                    Section(settings.text("离线与账户", "Offline and accounts")) {
                        Text(settings.text("关闭同步或退出 iCloud 会保留本地副本，不会清空云端。删除订阅会同步到其他已开启同步的设备，正在使用的订阅会等待处理。同步时机由系统与网络条件决定；切换账户后需重新确认合并。", "Disabling sync or signing out keeps local copies and does not erase iCloud. Deletions propagate to other devices with sync enabled; the selected configuration waits for review. Timing depends on system and network conditions. Switching accounts requires confirming a merge."))
                    }.listRowBackground(Color.clear)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).background(.black)
                .navigationTitle(settings.text("同步说明", "About sync"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(settings.text("完成", "Done")) { dismiss() } } }
        }.tint(.white)
    }
}

#Preview {
    MacICloudSyncInfoView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "Horizon.MacCloudPreview")!))
        .preferredColorScheme(.dark)
        .frame(width: 560, height: 480)
}

#endif
