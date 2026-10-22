import Foundation

/// Secret-bearing snapshots stay inside the same protected Keychain namespace as YAML.
nonisolated struct SubscriptionRevision: Codable, Identifiable, Sendable {
    let id: UUID
    let number: Int
    let date: Date
    let source: Data
    var choices: [String: String]
    var verifiedAt: Date?
}

extension StoredConfiguration {
    nonisolated var snapshotRevision: SubscriptionRevision {
        .init(id: revisionID ?? UUID(), number: revisionNumber ?? 1, date: revisionDate ?? Date(),
              source: source, choices: choices, verifiedAt: verifiedAt)
    }
}
