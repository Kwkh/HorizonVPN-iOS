#if os(macOS)
import SwiftUI

@main struct HorizonMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var page: MacRootView.Page? = .home
    @State private var confirmMenuConnection = false
    @State private var menuActions: MacMenuBarActions
    @State private var library: MacLibraryStore
    @State private var sync: MacICloudSubscriptionSyncStore
    @State private var settings = AppSettings()
    init() {
        #if DEBUG
        let offline = Bundle.main.object(forInfoDictionaryKey: "HorizonOfflinePreview") as? String == "YES"
            || ProcessInfo.processInfo.arguments.contains("--offline")
            || ProcessInfo.processInfo.environment["HORIZON_MAC_OFFLINE"] == "1"
        #else
        let offline = false
        #endif
        let library = MacLibraryStore(offline: offline)
        _library = State(initialValue: library)
        _menuActions = State(initialValue: MacMenuBarActions(library: library))
        _sync = State(initialValue: MacICloudSubscriptionSyncStore(repository: library.cloudRepository, permitsNetwork: !offline))
    }
    var body: some Scene {
        Window("Horizon", id: "main") {
            MacRootView(library: library, page: $page, confirmMenuConnection: $confirmMenuConnection, menuActions: menuActions)
                .frame(minWidth: 850, minHeight: 580)
                .preferredColorScheme(.dark)
                .environment(settings)
                .environment(sync)
        }
        .defaultSize(width: 1100, height: 740)

        MenuBarExtra {
            MacMenuBarView(actions: menuActions, page: $page, confirmConnection: $confirmMenuConnection)
                .environment(settings)
        } label: {
            MacMenuBarLabel(actions: menuActions).environment(settings)
        }
        .menuBarExtraStyle(.menu)
        // Scene lifetime survives closing the main window. Reconcile the same
        // library after external or menu-initiated VPN status changes.
        .onChange(of: library.vpn.status) { _, _ in
            Task { await library.connectionChanged() }
        }
    }
}

#endif
