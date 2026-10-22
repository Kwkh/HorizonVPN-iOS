import Foundation

nonisolated struct SubscriptionSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var fileName: String?
    let importedAt: Date?
    var updatedAt: Date
    var sourceDigest: String
    var storageID: UUID? = nil
    var nodeCount: Int
    var groupCount: Int
    var ruleCount: Int

    var countSummary: String {
        nodeCount == 0 ? "旧版配置 · 选择时重新校验" : "\(nodeCount) 个节点 · \(groupCount) 个策略组 · \(ruleCount) 条规则"
    }
    static func cleanName(_ value: String) -> String {
        let excluded = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"))
        return String(String.UnicodeScalarView(value.unicodeScalars.filter { !excluded.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(100).description
    }
    static func title(from fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let base = ["yaml", "yml", "txt"].contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        let title = cleanName(base)
        return title.isEmpty ? "未命名订阅" : title
    }
}

nonisolated struct SubscriptionIndex: Codable, Sendable {
    var format: String
    var entries: [SubscriptionSummary]
    var activeID: UUID?
    // Committed tombstones keep failed credential cleanup durable and retryable.
    var pendingDeletion: [UUID]
    var needsLegacyCleanup: Bool
    // Durable mutation ledger; committed with the index, independent of cloud availability.
    // UUID generations avoid relying on wall clocks. Deletion is not credential GC.
    var syncMutations: [String: UUID]? = nil
    var syncDeletedIDs: Set<UUID>? = nil

    mutating func noteMutation(_ id: UUID, deleted: Bool = false) {
        if syncMutations == nil { syncMutations = [:] }
        syncMutations?[id.uuidString] = UUID()
        if syncDeletedIDs == nil { syncDeletedIDs = [] }
        if deleted { syncDeletedIDs?.insert(id) } else { syncDeletedIDs?.remove(id) }
    }

    init(entries: [SubscriptionSummary] = [], activeID: UUID? = nil, needsLegacyCleanup: Bool = false) {
        format = "clash-subscriptions-v1"
        self.entries = entries
        self.activeID = activeID
        pendingDeletion = []
        self.needsLegacyCleanup = needsLegacyCleanup
    }
    var cleanupCount: Int { pendingDeletion.count + (needsLegacyCleanup ? 1 : 0) }
    func validate() throws {
        let ids = Set(entries.map(\.id))
        guard ["clash-subscriptions-v1", "clash-subscriptions-v2"].contains(format), entries.count <= 128, ids.count == entries.count,
              activeID == nil || ids.contains(activeID!), Set(pendingDeletion).count == pendingDeletion.count,
              Set(entries.map { $0.storageID ?? $0.id }).count == entries.count,
              Set(entries.map { $0.storageID ?? $0.id }).isDisjoint(with: pendingDeletion),
              entries.allSatisfy({ !$0.title.isEmpty && $0.title == SubscriptionSummary.cleanName($0.title) }) else {
            throw SubscriptionError.invalidLibrary
        }
    }
}

enum SubscriptionError: Error {
    case invalidLibrary, missingEntry, tooMany, invalidTitle, stopTimeout, staleRevision
    var summary: String {
        switch self {
        case .staleRevision: "订阅已改变，请重新刷新或打开预览。"
        case .invalidLibrary: "订阅记录无法读取，已停止操作以保留现有数据。"
        case .missingEntry: "订阅已不存在，请刷新列表。"
        case .tooMany: "当前最多保存 128 份订阅，请先删除不再使用的记录。"
        case .invalidTitle: "请输入有效的订阅名称。"
        case .stopTimeout: "等待隧道断开超时，未切换或删除当前订阅；请确认系统状态后重试。"
        }
    }
}

nonisolated protocol SubscriptionStorage: Sendable {
    func keys() throws -> [String]
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}
