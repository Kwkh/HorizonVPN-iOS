import SwiftUI
import UniformTypeIdentifiers

struct SubscriptionListView: View {
    @Environment(AppSettings.self) private var settings
    let tunnel: TunnelController
    var tabletGrid = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detailID: UUID?
    @State private var switchTarget: SubscriptionSummary?
    @State private var confirmSwitch = false
    @State private var switching = false
    @State private var importing = false
    @State private var importSheet: ImportSheet?

    private enum ImportSheet: Identifiable {
        case link
        case file(SubscriptionImportPreview)
        var id: String {
            switch self {
            case .link: "link"
            case .file(let preview): "file-" + preview.id.uuidString
            }
        }
    }
    @State private var importError = false
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var deletion: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var deleteError = false
    @State private var compatibilityPresented = false
    @ScaledMetric(relativeTo: .body) private var selectionBarClearance = 68

    private var currentTitle: String {
        tunnel.hasConfiguration ? tunnel.currentSubscriptionTitle : settings.text("未选择订阅", "No subscription selected")
    }

    var body: some View {
        Group {
            if tabletGrid {
                TabletSubscriptionGridView(tunnel: tunnel, selecting: selecting, selected: selected,
                    pendingID: switching ? switchTarget?.id : nil, canChoose: tunnel.canManageSubscriptions && !switching,
                    choose: { subscription in
                        if selecting {
                            withAnimation(transition) {
                                if !selected.insert(subscription.id).inserted { selected.remove(subscription.id) }
                            }
                        } else { requestSwitch(subscription) }
                    }, details: { detailID = $0 }, delete: requestSwipeDelete,
                    importURL: { tunnel.cancelImport(); importSheet = .link }, importFile: { importing = true })
            } else {
        List {
            ClashListContent {
                Section {
                    LabeledContent(settings.text("当前订阅", "Current subscription")) {
                        ZStack(alignment: .trailing) {
                            Text(currentTitle)
                                .id(currentTitle)
                                .transition(.opacity)
                        }
                        .animation(transition, value: currentTitle)
                    }
                }
                // Keep ForEach in the same structural position, even with zero entries.
                // A tall ContentUnavailableView inserted during the final swipe would
                // change content height and scroll anchoring while the row is removed.
                // "Saved · 0" plus the import actions already express the empty state.
                Section {
                    ForEach(tunnel.subscriptions) { subscription in
                        HStack(spacing: 0) {
                            Button {
                                if selecting {
                                    withAnimation(transition) {
                                        if !selected.insert(subscription.id).inserted { selected.remove(subscription.id) }
                                    }
                                } else { requestSwitch(subscription) }
                            } label: {
                                HStack(spacing: 0) {
                                    // Exchange equal-width leading/trailing slots. The title
                                    // moves without gaining width and changing its line count.
                                    Image(systemName: selected.contains(subscription.id) ? "checkmark.circle.fill" : "circle")
                                        .frame(width: 24)
                                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                                        .frame(width: selecting ? 44 : 0, alignment: .leading)
                                        .opacity(selecting ? 1 : 0)
                                        .clipped()
                                        .accessibilityHidden(true)
                                    SubscriptionRowView(subscription: subscription,
                                        isCurrent: subscription.id == tunnel.activeSubscriptionID,
                                        isPending: switching && switchTarget?.id == subscription.id)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SubscriptionSelectionButtonStyle())
                            .disabled(!tunnel.canManageSubscriptions || switching)
                            .accessibilityIdentifier("subscription.choose.\(subscription.id)")
                            .accessibilityAddTraits((selecting ? selected.contains(subscription.id) : subscription.id == tunnel.activeSubscriptionID) ? .isSelected : [])
                            Button { detailID = subscription.id } label: {
                                Image(systemName: "chevron.right").font(.callout.weight(.semibold))
                                    .foregroundStyle(.secondary).frame(width: 44, height: 56)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .frame(width: selecting ? 0 : 44)
                            .opacity(selecting ? 0 : 1)
                            .clipped()
                            .allowsHitTesting(!selecting)
                            .accessibilityHidden(selecting)
                            .accessibilityLabel(settings.text("\(subscription.title) 详情", "Details for \(subscription.title)"))
                            .accessibilityIdentifier("subscription.details.\(subscription.id)")
                        }
                        .animation(transition, value: selecting)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !selecting {
                                // Remove only after the storage commit, avoiding the native
                                // destructive button's optimistic removal/reinsertion on failure.
                                // Keep action availability stable during native swipe dismissal;
                                // requestSwipeDelete still guards busy/switching states.
                                Button { requestSwipeDelete(subscription.id) } label: {
                                    Label(settings.text("删除", "Delete"), systemImage: "trash")
                                }
                                    .tint(Color(uiColor: .systemRed))
                                    .accessibilityIdentifier("subscription.delete.\(subscription.id)")
                            }
                        }
                    }
                } header: {
                    Text(settings.text("已保存 · \(tunnel.subscriptions.count)", "Saved · \(tunnel.subscriptions.count)"))
                        .contentTransition(.numericText())
                }
                Section {
                    Button { tunnel.cancelImport(); importSheet = .link } label: {
                        Label(settings.text("通过链接导入", "Import from URL"), systemImage: "link")
                    }
                    .disabled(!tunnel.canManageSubscriptions)
                    .buttonStyle(SubscriptionSelectionButtonStyle())
                    .accessibilityIdentifier("subscriptions.importURL")
                    Button { importing = true } label: { Label(settings.text("导入配置文件", "Import file"), systemImage: "plus.circle") }
                        .disabled(!tunnel.canManageSubscriptions)
                        .buttonStyle(SubscriptionSelectionButtonStyle())
                }
                .id("subscriptions.imports")
            }
        }
            }
        }
        // List owns row/section positions, including the import rows below them.
        // A ForEach-only transaction cannot animate those sibling layout changes.
        // Trigger exclusively on membership changes, never telemetry or busy state.
        .animation(transition, value: tunnel.subscriptions.map(\.id))
        // Leave scrolling clearance without changing the viewport or its safe area
        // when the floating selection action appears/disappears.
        .contentMargins(.bottom, selectionBarClearance, for: .scrollContent)
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("订阅", "Subscriptions"))
        .navigationDestination(item: $detailID) { SubscriptionDetailView(tunnel: tunnel, id: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CompatibilityInfoButton(report: tunnel.compatibilityReport,
                    onPresentationChange: { compatibilityPresented = $0 })
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    setSelecting(!selecting)
                } label: {
                    ZStack {
                        Text(settings.text("完成", "Done")).hidden()
                        Text(settings.text("选择", "Select")).hidden()
                        Text(selecting ? settings.text("完成", "Done") : settings.text("选择", "Select"))
                            .contentTransition(.opacity)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .animation(transition, value: selecting)
                }
                    .accessibilityIdentifier("subscriptions.select")
                    // Selection mode is local UI state, not a repository operation.
                    // Busy toggles during activation must not dim/restore this toolbar item.
                    // The row and delete actions retain their own busy guards.
                    .disabled(!selecting && (tunnel.subscriptions.isEmpty || !tunnel.libraryReady))
            }
        }
        .overlay(alignment: .bottom) {
            Button(role: .destructive) { deletion = selected; confirmDelete = true } label: {
                Label(settings.text("删除所选（\(selected.count)）", "Delete selected (\(selected.count))"), systemImage: "trash")
                    .contentTransition(.numericText())
                    .padding(.horizontal, 18).frame(minHeight: 44)
            }
            .buttonStyle(.glass).tint(.red)
            .disabled(selected.isEmpty || !tunnel.canManageSubscriptions || switching)
            .accessibilityIdentifier("subscriptions.deleteSelected")
            .padding(12)
            .frame(maxWidth: .infinity)
            .opacity(selecting ? 1 : 0)
            .offset(y: selecting || reduceMotion ? 0 : 12)
            .allowsHitTesting(selecting)
            .accessibilityHidden(!selecting)
            .animation(transition, value: selecting)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.yaml, .plainText, .data]) { result in
            switch result {
            case .success(let url):
                Task {
                    if await tunnel.prepareImport(url), let preview = tunnel.importPreview {
                        importSheet = .file(preview)
                    } else { importError = true }
                }
            case .failure: tunnel.importFailed(); importError = true
            }
        }
        // One owner for both entry points. An old URL preview must never become
        // a new file sheet when URL dismissal changes the presentation binding.
        .sheet(item: $importSheet, onDismiss: { tunnel.cancelImport() }) { destination in
            switch destination {
            case .link: SubscriptionLinkImportView(tunnel: tunnel)
            case .file(let preview): ImportConfirmationView(tunnel: tunnel, preview: preview)
            }
        }
        .importFailureAlert(isPresented: $importError, detail: tunnel.message)
        .alert(settings.text("删除未完成", "Could not delete"), isPresented: $deleteError) {
            Button(settings.text("完成", "Done"), role: .cancel) { }
        } message: { Text(settings.text(tunnel.message, DiagnosticText.importEnglish(tunnel.message))) }
        .alert(settings.text("切换订阅并重新连接？", "Switch and reconnect?"), isPresented: $confirmSwitch, presenting: switchTarget) { subscription in
            Button(settings.text("取消", "Cancel"), role: .cancel) { switchTarget = nil }
            Button(settings.text("切换并重连", "Switch & reconnect")) { activate(subscription, reconnect: true) }
        } message: { subscription in
            Text(settings.text("切换到“\(subscription.title)”并重新连接，网络会短暂中断。", "Switch to “\(subscription.title)” and reconnect. Network access will be interrupted briefly."))
        }
        .alert(settings.text("删除所选 \(deletion.count) 份订阅？", "Delete \(deletion.count) configurations?"), isPresented: $confirmDelete) {
            Button(settings.text("取消", "Cancel"), role: .cancel) { }
            Button(settings.text("删除", "Delete"), role: .destructive) {
                Task {
                    await tunnel.deleteSubscriptions(deletion)
                    setSelecting(false)
                }
            }
        } message: {
            Text(settings.text("将删除本机记录和凭据，原始 YAML 文件保留。", "Removes the local record and credentials. The original YAML file is preserved.") +
                 (tunnel.activeSubscriptionID.map { deletion.contains($0) } == true ? settings.text("包含当前订阅：会先断开 VPN，删除后不自动选择或连接其他订阅。", "The active configuration is included: VPN will disconnect, with no automatic selection or reconnection.") : ""))
        }
        .modifier(CloudReviewPromptModifier(tunnel: tunnel,
            blocked: selecting || switching || importing || importSheet != nil || detailID != nil ||
                confirmSwitch || confirmDelete || deleteError || importError || compatibilityPresented))
    }
    private var transition: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }

    private func setSelecting(_ enabled: Bool) {
        // Clear on entry so the outgoing action keeps its count/width while fading.
        // Animate individual controls, not the navigation bar or the entire List.
        if enabled { selected.removeAll() }
        selecting = enabled
    }

    private func requestSwipeDelete(_ id: UUID) {
        guard !selecting, !switching, tunnel.canManageSubscriptions else { return }
        if id == tunnel.activeSubscriptionID && tunnel.isTunnelActive {
            deletion = [id]
            confirmDelete = true
            return
        }
        Task {
            await tunnel.deleteSubscriptions([id], allowDisconnect: false)
            if tunnel.subscriptions.contains(where: { $0.id == id }) { deleteError = true }
            else { selected.remove(id) }
        }
    }

    private func requestSwitch(_ subscription: SubscriptionSummary) {
        guard !switching, tunnel.canManageSubscriptions, subscription.id != tunnel.activeSubscriptionID else { return }
        if tunnel.isTunnelActive { switchTarget = subscription; confirmSwitch = true }
        else { activate(subscription, reconnect: false) }
    }
    private func activate(_ subscription: SubscriptionSummary, reconnect: Bool) {
        switchTarget = subscription
        switching = true
        Task {
            await tunnel.activateSubscription(subscription.id, reconnect: reconnect)
            switching = false
            switchTarget = nil
        }
    }
}

/// Preserve disabled semantics without globally dimming the subscription text during a switch.
private struct SubscriptionSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
