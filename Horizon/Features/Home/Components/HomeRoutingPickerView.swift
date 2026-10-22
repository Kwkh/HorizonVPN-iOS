import SwiftUI

/// A shortcut into the same validated, versioned routing flow used by Settings.
struct HomeRoutingPickerView: View {
    let tunnel: TunnelController
    let id: UUID
    let visible: Bool
    @State private var store: SubscriptionMaintenanceStore
    @State private var displayedRouting: ConfigurationRouting?
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingError = false

    init(tunnel: TunnelController, id: UUID, visible: Bool) {
        self.tunnel = tunnel
        self.id = id
        self.visible = visible
        _store = State(initialValue: .init(id: id, tunnel: tunnel))
    }

    private struct LoadKey: Equatable {
        let id: UUID
        let visible: Bool
        let digest: String?
    }
    private var loadKey: LoadKey {
        .init(id: id, visible: visible, digest: tunnel.subscriptions.first { $0.id == id }?.sourceDigest)
    }
    private var canChoose: Bool {
        visible && store.id == id && tunnel.activeSubscriptionID == id && store.record != nil &&
        !store.loading && !store.working && store.review == nil && tunnel.canManageSubscriptions
    }
    private var selection: Binding<ConfigurationRouting?> {
        Binding(get: {
            guard store.id == id else { return displayedRouting }
            return store.pendingRouting ?? (store.record == nil ? displayedRouting : store.routing)
        }, set: { mode in
            guard canChoose, let mode, mode != store.routing else { return }
            store.changeRouting(mode, applyImmediately: true)
        })
    }

    var body: some View {
        Picker(settings.text("分流方案", "Routing"), selection: selection) {
            Text(settings.text("遵循订阅", "Follow configuration"))
                .tag(ConfigurationRouting.subscription as ConfigurationRouting?)
            Text(settings.text("智能分流", "Smart routing"))
                .tag(ConfigurationRouting.smart as ConfigurationRouting?)
        }
        .pickerStyle(.segmented)
        // Connection preparation and routing commits are temporary interaction
        // locks, not missing data. Keep the native segmented palette stable.
        // The binding guard also rejects accessibility changes during these locks.
        .disabled(!tunnel.libraryReady)
        .allowsHitTesting(canChoose)
        .accessibilityIdentifier("home.routing")
        .accessibilityValue(store.id != id || store.loading ? settings.text("正在加载", "Loading") :
            store.record == nil ? settings.text("暂不可用", "Unavailable") :
            store.working ? settings.text("正在切换", "Switching") : settings.text("已应用", "Applied"))
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection.wrappedValue)
        .alert(settings.text("操作未完成", "Couldn't complete operation"), isPresented: $showingError) {
            Button(settings.text("好", "OK"), role: .cancel) { }
        } message: {
            Text(settings.text(store.message ?? "", DiagnosticText.importEnglish(store.message ?? "")))
        }
        .onChange(of: visible && store.id == id && !store.loading && !store.working && store.message != nil) { _, failed in
            if failed { showingError = true }
        }
        .task(id: loadKey) {
            guard visible else { return }
            if store.id != id {
                // Keep the native Picker itself alive. Retain only its last visual
                // selection while loading; canChoose blocks writes to the old record.
                if store.record != nil { displayedRouting = store.pendingRouting ?? store.routing }
                store = SubscriptionMaintenanceStore(id: id, tunnel: tunnel)
            }
            let loadingStore = store
            guard !loadingStore.working else { return }
            await loadingStore.loadRouting()
            guard !Task.isCancelled, store === loadingStore, loadingStore.id == id else { return }
            displayedRouting = loadingStore.record == nil ? nil : loadingStore.routing
        }
        // The service owns an accepted operation; leaving Home must not interrupt
        // an in-flight commit or the recovery of an existing VPN connection.
    }
}
