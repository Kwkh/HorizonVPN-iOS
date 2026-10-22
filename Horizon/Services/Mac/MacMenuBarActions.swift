#if os(macOS)
import Foundation
import Observation

/// Menu commands share the window's store, transaction queue and VPN controller.
@MainActor @Observable final class MacMenuBarActions {
    enum Result { case finished, confirmConnection, showAttention }
    struct PingTarget: Equatable {
        let scope: String
        let index: Int
        let name: String
    }
    let library: MacLibraryStore
    private(set) var working = false

    init(library: MacLibraryStore) { self.library = library }

    private var hasModal: Bool {
        library.preview != nil || library.revisionPreview != nil || library.error != nil
            || library.certificateDigest != nil || library.subscriptionSwitch != nil
    }
    var canSelect: Bool {
        library.ready && !working && !library.busy && !library.vpn.working
            && library.pendingRouting == nil && library.pendingSelection == nil
            && !hasModal
            && (library.vpn.isIdle || library.vpn.status == .connected)
    }
    var canActivate: Bool { canSelect && library.canActivateSubscription }
    var pingTarget: PingTarget? {
        guard let catalog = library.prepared?.catalog,
              let name = catalog.resolvedTarget(runtimeChoices: library.runtimeChoices),
              let index = catalog.nodes.firstIndex(where: { $0.name == name }) else { return nil }
        return PingTarget(scope: library.probeScope, index: index, name: name)
    }
    var canPing: Bool {
        canSelect && !library.offline && pingTarget.map { !library.probes.isTesting($0.index) } == true
    }
    var canToggle: Bool {
        library.ready && !library.offline && !working && !library.busy
            && !library.vpn.working && library.pendingRouting == nil
            && library.pendingSelection == nil && !hasModal
            && library.vpn.status != .disconnecting
            && (!library.vpn.isIdle || library.prepared != nil)
    }
    var statusTitle: String {
        if library.vpn.working && library.vpn.isIdle {
            return MacText.value("连接中", "Connecting")
        }
        return library.vpn.title
    }
    private var result: Result {
        library.error != nil || library.certificateDigest != nil || library.subscriptionSwitch != nil ? .showAttention : .finished
    }
    func toggleConnection(confirm: Bool) async -> Result {
        guard canToggle else { return .finished }
        if library.vpn.isIdle && confirm { return .confirmConnection }
        working = true
        defer { working = false }
        if library.vpn.isIdle { await library.connect() }
        else { library.vpn.disconnect() }
        return result
    }
    func ping(_ target: PingTarget) async -> Result {
        // An open menu must not test a different node after a selection/scope change.
        guard canPing, target == pingTarget else { return .finished }
        working = true
        defer { working = false }
        await library.test([target.index])
        return result
    }
    func activate(_ id: UUID) async -> Result {
        guard canActivate, library.index.activeID != id,
              library.index.entries.contains(where: { $0.id == id }) else { return .finished }
        working = true
        defer { working = false }
        await library.activate(id)
        return result
    }
    func select(group: Int, member: String, scope: String) async -> Result {
        // A menu can outlive the configuration it was built from.
        guard canSelect, scope == library.probeScope,
              let target = library.prepared?.catalog.groups.first(where: { $0.id == group }),
              target.allowsSelection, target.members.contains(member) else { return .finished }
        working = true
        defer { working = false }
        await library.select(group: group, member: member)
        return result
    }
}
#endif
