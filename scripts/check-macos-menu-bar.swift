import Foundation

extension CheckMacLibrary {
    @MainActor static func checkMenuBarActions() async throws {
        let library = MacLibraryStore(offline: true, offlineStorage: MacMemoryStorage())
        let menu = MacMenuBarActions(library: library)
        precondition(!menu.canToggle && !menu.canSelect && !menu.canActivate && !menu.canPing)
        await library.start()
        precondition(library.ready && menu.canActivate && menu.canSelect && !menu.canToggle)
        _ = await menu.toggleConnection(confirm: false)
        precondition(library.vpn.isIdle && !library.vpn.working && library.error == nil)
        print("PASS menu shares ready state and cannot start VPN in offline mode")

        let entry = library.index.entries[0]
        _ = await menu.activate(entry.id)
        precondition(library.index.activeID == entry.id && library.vpn.isIdle)
        let catalog = library.prepared!.catalog
        let group = catalog.groups.first(where: \.allowsSelection)!
        let member = group.members.first { $0 != catalog.choices[group.name] }!
        let scope = library.probeScope
        let firstPing = menu.pingTarget
        precondition(firstPing?.scope == scope && firstPing?.name == catalog.resolvedTarget())
        precondition(!menu.canPing, "Offline menu must never start a real latency test")
        if let firstPing { _ = await menu.ping(firstPing) }
        precondition(!library.probes.running && library.probes.results.isEmpty && library.error == nil)
        _ = await menu.select(group: group.id, member: member, scope: scope)
        precondition(library.prepared?.catalog.choices[group.name] == member)
        precondition(library.probeScope == scope && !menu.working)
        precondition(menu.pingTarget == nil, "DIRECT is not a testable proxy node")
        _ = await menu.select(group: group.id, member: catalog.nodes[0].name, scope: scope)
        precondition(menu.pingTarget?.index == 0 && menu.pingTarget?.name == catalog.nodes[0].name)
        precondition(!menu.canPing && !library.probes.running && library.vpn.isIdle)
        print("PASS menu resolves the selected proxy for Ping, excludes DIRECT, and cannot probe in offline mode")
        print("PASS menu uses existing activation and node selection without starting VPN")

        let identity = library.identity
        _ = await menu.select(group: group.id, member: group.members[0], scope: "stale-scope")
        _ = await menu.select(group: group.id, member: "missing-member", scope: scope)
        _ = await menu.select(group: -1, member: member, scope: scope)
        _ = await menu.activate(UUID())
        precondition(library.identity == identity && library.error == nil)
        print("PASS stale menu scope, missing group/member and deleted configuration rejected")

        library.preview = .init(prepared: library.prepared!, fileName: "fixture.yaml", sourceURL: nil, title: "Fixture")
        precondition(!menu.canSelect && !menu.canActivate && !menu.canToggle && !menu.canPing)
        library.preview = nil
        library.error = "Fixture error"
        precondition(!menu.canSelect && !menu.canActivate && !menu.canToggle && !menu.canPing)
        library.error = nil
        print("PASS menu cannot act through pending import or error presentation")

        library.certificateDigest = "pending-consent"
        precondition(!menu.canSelect && !menu.canActivate && !menu.canToggle && !menu.canPing)
        _ = await menu.activate(library.index.entries[1].id)
        precondition(library.index.activeID == entry.id)
        library.certificateDigest = nil
        _ = await menu.activate(library.index.entries[1].id)
        let newIdentity = library.identity
        _ = await menu.select(group: group.id, member: member, scope: scope)
        precondition(library.identity == newIdentity && menu.canActivate && !menu.working)
        print("PASS pending certificate consent blocks menu actions; old menu cannot affect new subscription")
    }
}
