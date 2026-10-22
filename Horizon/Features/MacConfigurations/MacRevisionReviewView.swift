#if os(macOS)
import SwiftUI

struct MacRevisionReviewView: View {
    let library: MacLibraryStore
    let preview: MacSubscriptionWorker.RevisionPreview
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(MacText.value("更新预览", "Update preview")).font(.title2)
            LabeledContent(MacText.value("节点", "Nodes"), value: "\(library.index.entries.first { $0.id == preview.subscriptionID }?.nodeCount ?? 0) → \(preview.prepared.catalog.nodes.count)")
            LabeledContent(MacText.value("策略组", "Groups"), value: "\(library.index.entries.first { $0.id == preview.subscriptionID }?.groupCount ?? 0) → \(preview.prepared.catalog.groups.count)")
            LabeledContent(MacText.value("规则", "Rules"), value: "\(library.index.entries.first { $0.id == preview.subscriptionID }?.ruleCount ?? 0) → \(preview.prepared.ruleCount)")
            Text(library.offline ? MacText.value("离线结构预览。", "Offline structure preview.") : preview.expected.source == preview.prepared.source ? MacText.value("内容没有变化。", "Content is unchanged.") : MacText.value("候选版本已通过结构与内核校验。原版本将保留用于回滚。", "The candidate passed structure and core validation. The current version will remain available for rollback."))
                .foregroundStyle(.secondary)
            if !library.vpn.isIdle && library.index.activeID == preview.subscriptionID {
                Text(MacText.value("本次连接保持不变，新配置将在下次连接时生效。", "Your connection stays unchanged. The update takes effect next time you connect.")).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button(MacText.value("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                ProgressView().controlSize(.small).opacity(library.busy ? 1 : 0).frame(width: 18)
                Button(MacText.value("应用", "Apply")) { Task { if await library.applyRevision(preview) { dismiss() } } }
                    .buttonStyle(.glass).disabled(library.busy || (!library.vpn.isIdle && library.vpn.status != .connected && library.index.activeID == preview.subscriptionID))
            }
        }.padding(28).frame(width: 480).background(.black)
    }
}
#endif
