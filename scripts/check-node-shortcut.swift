import Foundation

@main struct CheckNodeShortcut {
    static func main() {
        let nodes = ["A", "B", "C"].map { ConfigurationCatalog.Node(name: $0, kind: "vless", isFixture: true, label: $0) }
        func catalog(_ groups: [ConfigurationCatalog.Group], _ choices: [String: String], match: String = "Root") -> ConfigurationCatalog {
            .init(nodes: nodes, groups: groups, choices: choices, matchTarget: match)
        }
        let single = catalog([.init(id: 0, name: "Root", members: ["A", "B"])], ["Root": "A"])
        precondition(single.directSelection(for: "B")?.group == 0 && single.directSelection(for: "B")?.member == 1)
        precondition(single.directSelection(for: "A") == nil)
        precondition(single.directSelection(for: "C") == nil)
        let groups: [ConfigurationCatalog.Group] = [
            .init(id: 0, name: "Root", members: ["Child", "B"]),
            .init(id: 1, name: "Child", members: ["A", "B"]),
            .init(id: 2, name: "Unrelated", members: ["C", "B"])]
        let nested = catalog(groups, ["Root": "Child", "Child": "A", "Unrelated": "C"])
        precondition(nested.directSelection(for: "B")?.group == 1)
        precondition(nested.directSelection(for: "C") == nil)
        var choices = nested.choices; choices["Child"] = "B"
        let changed = catalog(groups, choices)
        precondition(changed.resolvedTarget() == "B" && changed.choices["Root"] == "Child" && changed.choices["Unrelated"] == "C")
        let outer = catalog([.init(id: 0, name: "Root", members: ["Child", "B"]), .init(id: 1, name: "Child", members: ["A"])], ["Root": "Child", "Child": "A"])
        precondition(outer.directSelection(for: "B")?.group == 0)
        precondition(catalog(groups, [:], match: "A").directSelection(for: "B") == nil)
        let cycle = catalog([.init(id: 0, name: "Root", members: ["Root", "B"])], [:])
        precondition(cycle.directSelection(for: "B") == nil)
        print("PASS: direct node selection, current-node no-op, deepest active group, unrelated groups unchanged, explicit route and cycle fallback")
    }
}
