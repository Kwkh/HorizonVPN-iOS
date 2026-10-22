#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacConfigurationsView: View {
    let library: MacLibraryStore
    // Read the live selection at event time, including while this page fades out.
    var isCurrentPage: () -> Bool = { true }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var importing = false
    @State private var showURL = false
    @State private var link = ""
    @State private var search = ""
    @State private var management: [UUID: MacSubscriptionWorker.ManagementInfo] = [:]
    @State private var renameEntry: SubscriptionSummary?
    @State private var renameTitle = ""
    @State private var deleteIDs: Set<UUID> = []
    @State private var selection = MacConfigurationSelection()
    @State private var frames: [UUID: CGRect] = [:]
    private var entries: [SubscriptionSummary] {
        library.index.entries.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                if library.index.entries.isEmpty {
                    ContentUnavailableView(MacText.value("导入你的订阅", "Bring your configurations"), systemImage: "square.3.layers.3d",
                        description: Text(MacText.value("选择 Clash YAML 文件或 HTTPS 订阅链接。", "Choose a Clash YAML file or an HTTPS subscription link."))).padding(.top, 100)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(MacText.value("\(library.index.entries.count) 份订阅", "\(library.index.entries.count) configurations"))
                            Spacer()
                            Text(MacText.value("已选 \(selection.ids.count) 项", "\(selection.ids.count) selected"))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .opacity(selection.ids.isEmpty ? 0 : 1)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection.ids.count)
                        }.font(.subheadline).foregroundStyle(.secondary)
                        if entries.isEmpty {
                            ContentUnavailableView.search(text: search).frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], spacing: 12) {
                                ForEach(entries) { entry in
                                    MacConfigurationCard(entry: entry, isCurrent: entry.id == library.index.activeID, isSelected: selection.ids.contains(entry.id),
                                        canActivate: library.canActivateSubscription,
                                        canRefresh: management[entry.id]?.canRefresh == true,
                                        refreshEnabled: !library.offline && !library.busy && (library.vpn.isIdle || library.vpn.status == .connected || entry.id != library.index.activeID),
                                        refreshing: library.refreshingIDs.contains(entry.id),
                                        usage: library.usage[entry.id], activate: {
                                            select(entry.id, flags: NSEvent.modifierFlags)
                                        }, refresh: {
                                            Task { await library.refreshInBackground(entry.id) }
                                        })
                                        .background {
                                            GeometryReader { geometry in
                                                Color.clear.preference(key: MacConfigurationFrames.self,
                                                    value: [entry.id: geometry.frame(in: .named("configurationSelection"))])
                                            }
                                        }
                                        .contextMenu {
                                            if selection.ids.count > 1, selection.ids.contains(entry.id) { selectionMenu }
                                            else { managementMenu(entry) }
                                        }
                                        .task(id: entry.updatedAt) {
                                            // Read off the main actor without changing the page's busy state.
                                            if let info = try? await library.managementInfo(entry.id), !Task.isCancelled {
                                                management[entry.id] = info
                                            }
                                        }
                                }
                            }

                        }
                    }.padding(24)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "configurationSelection")
                    .onPreferenceChange(MacConfigurationFrames.self) { value in
                        frames = value
                        if let rectangle = selection.rectangle { selection.updateDrag(rectangle, frames: value) }
                    }
                    .overlay {
                        MacConfigurationSelectionSurface(frames: frames, enabled: !library.busy,
                            isCurrentPage: isCurrentPage,
                            click: { id, flags in
                                if let id { select(id, flags: flags) }
                                else if flags.intersection([.command, .shift]).isEmpty { selection.clear() }
                            }, drag: { event in
                                switch event {
                                case .began(let extending): selection.beginDrag(extending: extending)
                                case .changed(let rectangle): selection.updateDrag(rectangle, frames: frames)
                                case .ended: selection.endDrag()
                                case .cancelled: selection.endDrag(cancelled: true)
                                }
                            }, selectAll: { selection.selectAll(entries.map(\.id)) }, clear: { selection.clear() },
                            delete: { if canDeleteSelection { deleteIDs = selection.ids } })
                        if let rectangle = selection.rectangle {
                            Rectangle().fill(.white.opacity(0.07))
                                .overlay(Rectangle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                                .frame(width: rectangle.width, height: rectangle.height)
                                .position(x: rectangle.midX, y: rectangle.midY)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .onChange(of: entries.map(\.id)) { _, ids in selection.retain(Set(ids)) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL, !library.busy else { return false }
            Task { await library.importDroppedFile(url) }; return true
        }
        .background(.black).navigationTitle(MacText.value("订阅", "Configurations"))
        .searchable(text: $search, prompt: MacText.value("搜索订阅", "Search configurations"))
        .toolbar {
            ToolbarItemGroup {
                Button { guard !library.busy else { return }; showURL = true } label: { Label(MacText.value("导入链接", "Import URL"), systemImage: "link") }.disabled(library.offline).allowsHitTesting(!library.busy)
                Button { guard !library.busy else { return }; importing = true } label: { Label(MacText.value("导入文件", "Import file"), systemImage: "plus") }.keyboardShortcut("o").allowsHitTesting(!library.busy)
            }
        }
        .modifier(MacCloudReviewPromptModifier(library: library,
            blocked: importing || showURL || renameEntry != nil || !deleteIDs.isEmpty || selection.rectangle != nil ||
                library.preview != nil || library.revisionPreview != nil || library.error != nil || library.certificateDigest != nil || library.subscriptionSwitch != nil))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.yaml, .plainText, .json]) { result in
            switch result {
            case .success(let url): Task { await library.importFile(url) }
            case .failure: library.error = MacText.value("文件无法打开，请重试。", "Could not open the file. Try again.")
            }
        }
        .alert(MacText.value("改名", "Rename"), isPresented: Binding(
            get: { renameEntry != nil }, set: { if !$0 { renameEntry = nil } })) {
                TextField(MacText.value("名称", "Name"), text: $renameTitle)
                Button(MacText.value("取消", "Cancel"), role: .cancel) { renameEntry = nil }
                Button(MacText.value("保存", "Save")) {
                    guard let entry = renameEntry else { return }
                    let title = renameTitle; renameEntry = nil
                    Task { _ = await library.rename(entry.id, title: title) }
                }.disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        .confirmationDialog(deleteIDs.count > 1 ? MacText.value("删除 \(deleteIDs.count) 份订阅？", "Delete \(deleteIDs.count) configurations?") : MacText.value("删除订阅？", "Delete configuration?"), isPresented: Binding(
            get: { !deleteIDs.isEmpty }, set: { if !$0 { deleteIDs = [] } }), titleVisibility: .visible) {
                Button(MacText.value("删除", "Delete"), role: .destructive) {
                    let ids = deleteIDs; deleteIDs = []
                    Task { _ = await library.deleteConfigurations(ids) }
                }
                Button(MacText.value("取消", "Cancel"), role: .cancel) { deleteIDs = [] }
            }
        .alert(MacText.value("导入订阅链接", "Import subscription URL"), isPresented: $showURL) {
            TextField("HTTPS", text: $link)
            Button(MacText.value("取消", "Cancel"), role: .cancel) { link = "" }
            Button(MacText.value("导入", "Import")) { let value = link; link = ""; Task { await library.importLink(value) } }
        }
    }

    private func select(_ id: UUID, flags: NSEvent.ModifierFlags) {
        let activates = selection.click(id, order: entries.map(\.id), toggle: flags.contains(.command), range: flags.contains(.shift))
        if activates, library.canActivateSubscription, id != library.index.activeID {
            Task { await library.activate(id) }
        }
    }
    private var canDeleteSelection: Bool {
        !selection.ids.isEmpty && !library.busy && (library.vpn.isIdle || library.index.activeID.map { !selection.ids.contains($0) } != false)
    }
    private var refreshSelection: [UUID] {
        entries.filter { selection.ids.contains($0.id) && management[$0.id]?.canRefresh == true }.map(\.id)
    }
    @ViewBuilder private var selectionMenu: some View {
        Text(MacText.value("已选 \(selection.ids.count) 份订阅", "\(selection.ids.count) configurations selected"))
        Button(MacText.value("刷新所选订阅", "Refresh selected configurations")) {
            let ids = refreshSelection
            Task {
                for id in ids {
                    await library.refreshInBackground(id)
                    if library.error != nil { break }
                }
            }
        }.disabled(library.offline || library.busy || refreshSelection.isEmpty)
        Button(MacText.value("删除所选订阅…", "Delete selected configurations…"), role: .destructive) { deleteIDs = selection.ids }
            .disabled(!canDeleteSelection)
        Divider()
        Button(MacText.value("取消选择", "Clear selection")) { selection.clear() }
    }

    @ViewBuilder private func managementMenu(_ entry: SubscriptionSummary) -> some View {
        Button(MacText.value("使用订阅", "Use configuration")) { Task { await library.activate(entry.id) } }
            .disabled(entry.id == library.index.activeID || !library.canActivateSubscription)
        Menu(MacText.value("订阅信息", "Configuration info")) {
            Text(entry.title)
            Text(MacText.value("\(entry.nodeCount) 个节点 · \(entry.groupCount) 个策略组 · \(entry.ruleCount) 条规则",
                               "\(entry.nodeCount) nodes · \(entry.groupCount) groups · \(entry.ruleCount) rules"))
            if let fileName = entry.fileName { Text(fileName) }
            if let date = entry.importedAt { Text(MacText.value("导入：", "Imported: ") + date.formatted(date: .abbreviated, time: .shortened)) }
            if let info = management[entry.id] {
                Text(MacText.value("版本 \(info.revisionNumber)", "Revision \(info.revisionNumber)"))
            }
        }
        Divider()
        Button(MacText.value("检查更新…", "Check for updates…")) { Task { await library.stageRevision(entry.id) } }
            .disabled(library.offline || library.busy || management[entry.id]?.canRefresh != true)
        Menu(MacText.value("历史版本", "Revision history")) {
            if let info = management[entry.id] {
                if info.history.isEmpty { Text(MacText.value("暂无历史版本", "No previous revisions")) }
                ForEach(info.history) { revision in
                    Button(MacText.value("版本 \(revision.number)", "Revision \(revision.number)") + " · " + revision.date.formatted(date: .abbreviated, time: .shortened)) {
                        Task { await library.stageRevision(entry.id, revisionID: revision.id) }
                    }.disabled(library.busy)
                }
            } else { Text(MacText.value("正在读取…", "Loading…")) }
        }
        Button(MacText.value("改名…", "Rename…")) { renameTitle = entry.title; renameEntry = entry }
            .disabled(library.busy)
        Divider()
        Button(MacText.value("删除订阅…", "Delete configuration…"), role: .destructive) { deleteIDs = [entry.id] }
            .disabled(library.busy || (!library.vpn.isIdle && entry.id == library.index.activeID))
    }
}

#endif
