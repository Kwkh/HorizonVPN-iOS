#if os(macOS)
import AppKit
import SwiftUI

struct MacMenuBarView: View {
    let actions: MacMenuBarActions
    @Binding var page: MacRootView.Page?
    @Binding var confirmConnection: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    private var library: MacLibraryStore { actions.library }

    var body: some View {
        let _ = settings.language
        Text("Horizon · " + actions.statusTitle)
        Button(settings.text(library.vpn.isIdle ? "连接" : "断开连接",
                             library.vpn.isIdle ? "Connect" : "Disconnect")) {
            Task { handle(await actions.toggleConnection(confirm: settings.confirmVPNConnection)) }
        }
        .disabled(!actions.canToggle)
        .accessibilityIdentifier("mac.menu.connection")
        Divider()
        Menu(settings.text("订阅", "Configuration")) {
            if library.index.entries.isEmpty {
                Text(settings.text("尚未导入订阅", "No configurations"))
            }
            ForEach(library.index.entries) { entry in
                Toggle(entry.title, isOn: Binding(get: { library.index.activeID == entry.id }, set: { selected in
                    guard selected else { return }
                    Task { handle(await actions.activate(entry.id)) }
                }))
                .disabled(!actions.canActivate)
            }
            Divider()
            Button(settings.text("管理订阅…", "Manage configurations…")) { showMain(.configurations) }
        }
        Text(library.activeTitle)
        if let catalog = library.prepared?.catalog {
            let scope = library.probeScope
            let target = catalog.resolvedTarget(runtimeChoices: library.runtimeChoices)
            Text(settings.text("节点：", "Node: ") + (target.map { settings.nodeLabel(catalog, name: $0) }
                 ?? settings.text("由策略组决定", "Determined by routing groups")))
            let pingTarget = actions.pingTarget
            let pingResult = pingTarget.map { library.probes.label($0.index) } ?? "Ping"
            Button {
                guard let pingTarget else { return }
                Task { handle(await actions.ping(pingTarget)) }
            } label: {
                Label(settings.text("测试当前节点", "Ping current node")
                    + (pingResult == "Ping" ? "" : " · " + pingResult), systemImage: "speedometer")
            }
            .disabled(!actions.canPing)
            .accessibilityIdentifier("mac.menu.ping")
            Menu(settings.text("切换节点", "Switch node")) {
                ForEach(catalog.groups.filter(\.allowsSelection)) { group in
                    Menu(settings.nodeLabel(catalog, name: group.name)) {
                        ForEach(group.members, id: \.self) { member in
                            Toggle(settings.nodeLabel(catalog, name: member), isOn: Binding(
                                get: { (library.runtimeChoices[group.name] ?? catalog.choices[group.name]) == member },
                                set: { selected in
                                    guard selected else { return }
                                    Task { handle(await actions.select(group: group.id, member: member, scope: scope)) }
                                }))
                                .disabled(!actions.canSelect)
                        }
                    }
                }
                if !catalog.groups.contains(where: \.allowsSelection) {
                    Text(settings.text("此订阅没有手动策略组", "No manual selection groups"))
                }
                Divider()
                Button(settings.text("查看所有节点…", "Show all nodes…")) { showMain(.nodes) }
            }
        }
        if actions.working || library.pendingSelection != nil {
            Text(settings.text("正在处理…", "Working…"))
        }
        Divider()
        Button(settings.text("打开 Horizon", "Open Horizon")) { showMain() }
            .accessibilityIdentifier("mac.menu.open")
        Button(settings.text("设置…", "Settings…")) { showMain(.settings) }
            .accessibilityIdentifier("mac.menu.settings")
        Divider()
        Button(settings.text("退出 Horizon", "Quit Horizon")) { NSApp.terminate(nil) }
            .accessibilityIdentifier("mac.menu.quit")
    }

    private func showMain(_ destination: MacRootView.Page? = nil) {
        if let destination { page = destination }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
    private func handle(_ result: MacMenuBarActions.Result) {
        switch result {
        case .finished: break
        case .confirmConnection:
            showMain(.home)
            confirmConnection = true
        case .showAttention: showMain()
        }
    }
}

#Preview("Offline menu contents") {
    let library = MacLibraryStore(offline: true)
    MacMenuBarView(actions: MacMenuBarActions(library: library), page: .constant(.home),
                   confirmConnection: .constant(false))
        .environment(AppSettings())
        .task { await library.start() }
}
#endif
