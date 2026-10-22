import Foundation

/// Only configured group/member ordinals cross IPC; raw core JSON and names stay inside the extension.
enum RuntimeGroupChoices {
    static func sanitize(_ json: String, catalog: ConfigurationCatalog) -> [Int: Int]? {
        guard json.utf8.count <= 2 * 1024 * 1024,
              let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let proxies = value["proxies"] as? [String: [String: Any]] else { return nil }
        var result: [Int: Int] = [:]
        for group in catalog.groups {
            if let selected = proxies[group.name]?["now"] as? String,
               let member = group.members.firstIndex(of: selected) { result[group.id] = member }
        }
        return result
    }
    static func names(_ indices: [Int: Int], catalog: ConfigurationCatalog) -> [String: String] {
        var result: [String: String] = [:]
        for (group, member) in indices where catalog.groups.indices.contains(group) && catalog.groups[group].members.indices.contains(member) {
            result[catalog.groups[group].name] = catalog.groups[group].members[member]
        }
        return result
    }
}
