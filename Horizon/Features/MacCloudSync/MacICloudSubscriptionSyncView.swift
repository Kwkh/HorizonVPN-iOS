#if os(macOS)
import SwiftUI

struct MacICloudSubscriptionSyncView: View {
    @Environment(\.macSubpageTokens) private var subpageTokens
    let library: MacLibraryStore
    @Environment(AppSettings.self) private var settings
    @Environment(MacICloudSubscriptionSyncStore.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingInfo = false
    @State private var confirmingEnable = false
    @State private var confirmingAccount = false
    @State private var awaitingSyncFeedback = false
    @State private var syncSucceeded = false
    var body: some View {
        Form {
            Group {
                Section {
                    Toggle(settings.text("同步个人订阅", "Sync personal subscriptions"), isOn: Binding(
                        get: { sync.enabled },
                        set: { if $0 { confirmingEnable = true } else { sync.disable() } }))
                        .tint(Color.green)
                        .accessibilityIdentifier("settings.icloud.enabled")
                        .disabled(library.offline)
                    if library.offline {
                        Text(settings.text("离线预览不会访问 iCloud。", "Offline preview does not access iCloud.")).foregroundStyle(.secondary)
                    }
                    if sync.enabled {
                        LabeledContent(settings.text("状态", "Status")) {
                            HStack(spacing: 8) {
                                if sync.working { ProgressView().controlSize(.small) }
                                Text(statusText).foregroundStyle(.secondary).contentTransition(.numericText())
                            }
                            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.working)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.status)
                        }
                        if let date = sync.lastSync {
                            LabeledContent(settings.text("最近同步", "Last synced")) {
                                TimelineView(.periodic(from: date, by: 60)) { context in
                                    let minutes = max(0, Int(context.date.timeIntervalSince(date) / 60))
                                    Text(lastSyncText(minutes: minutes))
                                        .foregroundStyle(.secondary)
                                        .contentTransition(.numericText())
                                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: minutes)
                                }
                            }
                        }
                        if sync.blockedCount > 0 {
                            Text(settings.text("\(sync.blockedCount) 份订阅暂无法同步，请检查依赖或更新 App 后重试。", "\(sync.blockedCount) subscriptions could not sync. Check dependencies or update the app and retry."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if case .accountChanged = sync.status {
                            Button(settings.text("与当前 iCloud 账户合并…", "Merge with current iCloud account…")) { confirmingAccount = true }
                        } else {
                            Button(action: requestSync) {
                                HStack {
                                    Text(settings.text("立即同步", "Sync now"))
                                    Spacer()
                                    syncSymbol
                                        .frame(width: 30)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(MacSyncNowButtonStyle())
                            .disabled(sync.working || awaitingSyncFeedback)
                            .accessibilityIdentifier("settings.icloud.syncNow")
                        }
                    }
                }.listRowBackground(Color.clear)
                if sync.enabled, !sync.reviews.isEmpty {
                    Section(settings.text("需要处理", "Needs review")) {
                        ForEach(sync.reviews) { item in
                            NavigationLink { MacCloudSubscriptionReviewView(item: item, library: library).modifier(MacSubpageTracking(tokens: subpageTokens)) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.deleted ? settings.text("已在其他设备删除", "Deleted on another device") : settings.text("有待处理的云端版本", "Cloud revision available"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.listRowBackground(Color.clear)
                }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(.black).tint(.white)
            .navigationTitle(settings.text("iCloud 同步", "iCloud sync"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel(settings.text("同步说明", "About synchronization"))
                }
            }
            .sheet(isPresented: $showingInfo) { MacICloudSyncInfoView().frame(width: 560, height: 480) }
            .alert(settings.text("开启 iCloud 同步？", "Enable iCloud sync?"), isPresented: $confirmingEnable) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("开启", "Enable")) { sync.enable() }
            } message: {
                Text(settings.text("这将在你的设备之间同步个人订阅", "This will sync your personal subscription across your devices"))
            }
            .alert(settings.text("合并到当前账户？", "Merge into this account?"), isPresented: $confirmingAccount) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("合并", "Merge")) { sync.retry(allowAccountChange: true) }
            } message: {
                Text(settings.text("本机保留的订阅（可能来自之前的账户）将上传到当前 iCloud 账户。原账户的云端内容不变。", "Subscriptions retained on this device, including those from a previous account, will upload to the current iCloud account. The previous account's cloud data stays unchanged."))
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.enabled)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.reviews)
            .onChange(of: sync.working) { wasWorking, isWorking in
                guard wasWorking, !isWorking, awaitingSyncFeedback else { return }
                awaitingSyncFeedback = false
                syncSucceeded = sync.status == .ready && sync.blockedCount == 0
            }
            .onChange(of: sync.enabled) { _, enabled in
                if !enabled { awaitingSyncFeedback = false; syncSucceeded = false }
            }
            .task(id: syncSucceeded) {
                guard syncSucceeded else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                syncSucceeded = false
            }
            .onDisappear { awaitingSyncFeedback = false; syncSucceeded = false }
    }
    private var syncSymbol: some View {
        Image(systemName: syncSucceeded ? "checkmark.icloud" : "arrow.trianglehead.2.clockwise.rotate.90.icloud")
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(
                .replace.byLayer.downUp.magic(fallback: .replace.byLayer.downUp)))
            .animation(reduceMotion ? nil : .default, value: syncSucceeded)
    }
    private func requestSync() {
        guard sync.enabled, !sync.working, !awaitingSyncFeedback else { return }
        if case .accountChanged = sync.status {
            confirmingAccount = true
            return
        }
        syncSucceeded = false
        switch sync.status {
        case .ready, .waiting: awaitingSyncFeedback = sync.syncNow()
        default: awaitingSyncFeedback = sync.retry()
        }
    }
    private func lastSyncText(minutes: Int) -> String {
        guard minutes > 0 else { return settings.text("刚刚", "Just now") }
        return settings.text("\(minutes) 分钟前", minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago")
    }
    private var statusText: String {
        switch sync.status {
        case .off: settings.text("已关闭", "Off")
        case .syncing: settings.text("同步中", "Syncing")
        case .ready: settings.text("已同步", "Up to date")
        case .noAccount: settings.text("请登录 iCloud", "Sign in to iCloud")
        case .accountChanged: settings.text("账户已改变", "Account changed")
        case .quota: settings.text("iCloud 空间不足", "iCloud storage full")
        case .configuration: settings.text("iCloud 配置需要检查", "Check iCloud configuration")
        case .waiting: settings.text("等待同步，可重试", "Waiting to sync · Retry available")
        case .failed: settings.text("同步未完成，可重试", "Sync incomplete · Retry available")
        }
    }
}

/// Keep the sync row's color stable while retaining disabled interaction semantics.
private struct MacSyncNowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

#Preview {
    let library = MacLibraryStore(offline: true)
    NavigationStack {
        MacICloudSubscriptionSyncView(library: library)
    }
    .environment(AppSettings(defaults: UserDefaults(suiteName: "Horizon.MacCloudPreview")!))
    .environment(MacICloudSubscriptionSyncStore(repository: library.cloudRepository, permitsNetwork: false))
    .preferredColorScheme(.dark)
    .frame(width: 700, height: 520)
}

#endif
