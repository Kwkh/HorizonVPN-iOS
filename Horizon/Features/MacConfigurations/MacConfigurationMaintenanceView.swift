#if os(macOS)
import SwiftUI

struct MacConfigurationMaintenanceView: View {
    let library: MacLibraryStore
    let id: UUID
    @State private var record: StoredConfiguration?
    var body: some View {
        List {
            Section {
                Button { Task { await library.stageRevision(id) } } label: {
                    HStack { Label(MacText.value("检查更新", "Check for updates"), systemImage: "arrow.clockwise"); Spacer(); ProgressView().controlSize(.small).opacity(library.busy ? 1 : 0) }
                }.disabled(record?.sourceURL == nil || library.offline || library.busy)
                if record?.sourceURL == nil { Text(MacText.value("文件导入的订阅没有在线更新来源。", "File imports do not have an online update source.")).foregroundStyle(.secondary) }
            }
            Section(MacText.value("历史版本", "Previous versions")) {
                if let history = record?.history, !history.isEmpty {
                    ForEach(history) { revision in
                        Button { Task { await library.stageRevision(id, revision: revision) } } label: {
                            HStack {
                                Text(MacText.value("版本 \(revision.number)", "Revision \(revision.number)"))
                                Spacer()
                                Text(revision.date, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }.disabled(library.busy)
                    }
                } else { Text(MacText.value("暂无历史版本", "No previous versions")).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 24)
        .background(.black)
        .navigationTitle(MacText.value("更新与版本", "Refresh & revisions"))
        .task(id: library.index.entries.first { $0.id == id }?.updatedAt) {
            do { record = try await library.record(id) } catch { library.error = MacText.error(error) }
        }
    }
}
#endif
