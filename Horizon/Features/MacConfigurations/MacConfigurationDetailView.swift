#if os(macOS)
import SwiftUI

struct MacConfigurationDetailView: View {
    let library: MacLibraryStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var record: StoredConfiguration?
    @State private var title = ""
    @State private var renaming = false
    @State private var deleting = false
    private var entry: SubscriptionSummary? { library.index.entries.first { $0.id == id } }
    var body: some View {
        List {
            if let entry {
                Section {
                    LabeledContent(MacText.value("名称", "Name"), value: entry.title)
                    LabeledContent(MacText.value("状态", "Status"), value: library.index.activeID == id ? MacText.value("当前订阅", "Current") : MacText.value("已保存", "Saved"))
                    Text(MacText.value("\(entry.nodeCount) 个节点 · \(entry.groupCount) 个策略组 · \(entry.ruleCount) 条规则", "\(entry.nodeCount) nodes · \(entry.groupCount) groups · \(entry.ruleCount) rules")).foregroundStyle(.secondary)
                    if let file = entry.fileName { LabeledContent(MacText.value("来源文件", "Source file"), value: file) }
                    if let date = entry.importedAt { LabeledContent(MacText.value("导入时间", "Imported")) { Text(date, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary) } }
                }
                Section {
                    Button(MacText.value("使用订阅", "Use configuration")) { Task { await library.activate(id) } }
                        .disabled(library.index.activeID == id || !library.canActivateSubscription)
                    NavigationLink(MacText.value("更新与版本", "Refresh & revisions")) { MacConfigurationMaintenanceView(library: library, id: id) }
                    Button(MacText.value("重命名", "Rename")) { title = entry.title; renaming = true }
                }
                Section {
                    Button(MacText.value("删除订阅", "Delete configuration"), role: .destructive) { deleting = true }
                        .disabled(library.busy || (!library.vpn.isIdle && library.index.activeID == id))
                }
                if let record {
                    Text(library.offline
                        ? MacText.value("版本 \(record.revisionNumber ?? 1) · 仅保存在内存中的虚构订阅", "Revision \(record.revisionNumber ?? 1) · Demo stored in memory only")
                        : MacText.value("版本 \(record.revisionNumber ?? 1) · 凭据保存在本机钥匙串", "Revision \(record.revisionNumber ?? 1) · Credentials stored in this Mac’s Keychain")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 24)
        .background(.black)
        .navigationTitle(entry?.title ?? MacText.value("订阅", "Configuration"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProgressView().controlSize(.small).opacity(library.busy ? 1 : 0).frame(width: 18)
                    .accessibilityHidden(!library.busy)
            }.sharedBackgroundVisibility(.hidden)
        }
        .task(id: id) { do { record = try await library.record(id) } catch { library.error = MacText.error(error) } }
        .alert(MacText.value("重命名订阅", "Rename configuration"), isPresented: $renaming) {
            TextField(MacText.value("名称", "Name"), text: $title)
            Button(MacText.value("取消", "Cancel"), role: .cancel) {}
            Button(MacText.value("保存", "Save")) { Task { _ = await library.rename(id, title: title) } }
        }
        .confirmationDialog(MacText.value("删除此订阅？", "Delete this configuration?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(MacText.value("删除", "Delete"), role: .destructive) { Task { if await library.delete(id) { dismiss() } } }
        }
    }
}
#endif
