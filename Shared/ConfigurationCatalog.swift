import Foundation
import CryptoKit

/// Names remain in memory/Keychain. UI and diagnostics use ordinal labels.
nonisolated struct ConfigurationCatalog: Sendable {
    struct Node: Sendable {
        let name: String
        let kind: String
        let isFixture: Bool
        let label: String
    }
    struct Group: Identifiable, Sendable {
        let id: Int
        let name: String
        let members: [String]
        var kind: String = "select"
        var allowsSelection: Bool { kind == "select" }
    }
    let nodes: [Node]
    let groups: [Group]
    let choices: [String: String]
    let matchTarget: String

    func label(for name: String) -> String {
        if let node = nodes.first(where: { $0.name == name }) { return node.label }
        if let group = groups.first(where: { $0.name == name }) { return "策略组 \(group.id + 1)" }
        return name == "DIRECT" ? "直连" : "拒绝连接"
    }
    func resolvedTarget(_ name: String? = nil, runtimeChoices: [String: String] = [:]) -> String? {
        var current = name ?? matchTarget
        var visited = Set<String>()
        while let group = groups.first(where: { $0.name == current }) {
            guard visited.insert(current).inserted else { return nil }
            guard let next = runtimeChoices[group.name] ?? choices[group.name] ?? (group.allowsSelection ? group.members.first : nil) else { return nil }
            current = next
        }
        return nodes.contains(where: { $0.name == current }) ? current : nil
    }
    /// Only switch a group on the currently selected MATCH path. Prefer the deepest
    /// eligible group so unrelated rule groups and outer selections remain untouched.
    func directSelection(for node: String) -> (group: Int, member: Int)? {
        guard nodes.contains(where: { $0.name == node }), resolvedTarget() != node else { return nil }
        var current = matchTarget, visited = Set<String>()
        var result: (group: Int, member: Int)?
        while let group = groups.first(where: { $0.name == current }) {
            guard visited.insert(current).inserted else { return nil }
            if group.allowsSelection, let member = group.members.firstIndex(of: node) { result = (group.id, member) }
            guard let next = choices[group.name] ?? (group.allowsSelection ? group.members.first : nil) else { break }
            current = next
        }
        return result
    }

    var probeLabel: String {
        resolvedTarget().map { label(for: $0) } ?? (groups.contains(where: { $0.name == matchTarget }) ? "自动策略组" : "当前 MATCH 目标为直连或拒绝")
    }
}

nonisolated struct ConfigurationIssue: Error {
    let code: PrototypeError
    /// Constructed only from fixed labels and numeric positions, never source values.
    let detail: String
}

nonisolated struct StoredConfiguration: Codable, Sendable {
    let format: String
    let source: Data
    var choices: [String: String]
    var sourceURL: String?
    var revisionID: UUID?
    var revisionNumber: Int?
    var revisionDate: Date?
    var startupConfirmed: Bool?
    var verifiedAt: Date?
    var history: [SubscriptionRevision]?
    var lastUsable: SubscriptionRevision?
    var certificateConsentDigest: String?
    var contentDigest: String { SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined() }
    func requireCertificateConsent(for prepared: PrototypeConfiguration.Prepared) throws {
        if prepared.insecureNodeCount > 0 && certificateConsentDigest != contentDigest { throw PrototypeError.certificateConsent }
    }
    init(source: Data, choices: [String: String] = [:]) {
        self.format = "clash-vault-v2"
        self.source = source
        self.choices = choices
        self.revisionID = UUID()
        self.revisionNumber = 1
        self.revisionDate = Date()
    }
}
