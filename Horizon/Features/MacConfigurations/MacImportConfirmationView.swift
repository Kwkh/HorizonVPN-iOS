#if os(macOS)
import SwiftUI

struct MacImportConfirmationView: View {
    let library: MacLibraryStore
    let preview: MacSubscriptionWorker.Preview
    @State private var title: String
    @State private var makeCurrent: Bool
    @Environment(\.dismiss) private var dismiss
    init(library: MacLibraryStore, preview: MacSubscriptionWorker.Preview) {
        self.library = library; self.preview = preview
        _title = State(initialValue: preview.title)
        _makeCurrent = State(initialValue: library.vpn.isIdle)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(MacText.value("导入订阅", "Import configuration")).font(.title2)
            TextField(MacText.value("名称", "Name"), text: $title)
            Text(MacText.value("\(preview.prepared.catalog.nodes.count) 个节点 · \(preview.prepared.catalog.groups.count) 个策略组 · \(preview.prepared.ruleCount) 条规则", "\(preview.prepared.catalog.nodes.count) nodes · \(preview.prepared.catalog.groups.count) groups · \(preview.prepared.ruleCount) rules")).foregroundStyle(.secondary)
            Toggle(MacText.value("使用此订阅（不连接）", "Use configuration (without connecting)"), isOn: $makeCurrent).disabled(!library.vpn.isIdle)
            Label(MacText.value("结构已验证", "Structure validated"), systemImage: "checkmark.seal")
            // Desktop listeners/process rules are intentionally not enabled in this first Mac target.
            Text(MacText.value("当前沿用移动端兼容策略：不启用桌面监听与进程规则。", "Uses the existing compatibility policy. Desktop listeners and process rules remain inactive.")).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(MacText.value("取消", "Cancel"), role: .cancel) { dismiss() }.disabled(library.busy)
                Spacer()
                ProgressView().controlSize(.small).opacity(library.busy ? 1 : 0).frame(width: 18)
                Button(MacText.value("保存", "Save")) {
                    Task { if await library.save(preview, title: title, makeCurrent: makeCurrent) { dismiss() } }
                }
                .keyboardShortcut(.defaultAction).disabled(library.busy || SubscriptionSummary.cleanName(title).isEmpty)
            }
        }
        .padding(28).frame(width: 500).interactiveDismissDisabled(library.busy)
    }
}

#endif
