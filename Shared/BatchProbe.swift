import Foundation

struct BatchProbeCommand: Codable {
    enum Action: String, Codable { case start, poll, cancel, enqueue }
    let version: Int
    let action: Action
    let batchID: UUID
    let sessionID: UUID
    let configurationID: String
    var nodeIndex: Int? = nil
    var nodeIndices: [Int]? = nil
    func matches(_ status: BatchProbeStatus) -> Bool {
        version == status.version && batchID == status.batchID &&
        sessionID == status.sessionID && configurationID == status.configurationID
    }
    /// A running batch tests its immutable node snapshot, independent of selector choices.
    /// Only a new start must use the current selection's configuration identity.
    func isValid(nodeCount: Int, sessionID currentSession: UUID,
                 configurationID currentConfiguration: String, batch: BatchProbeStatus?) -> Bool {
        guard isSupported(nodeCount: nodeCount), sessionID == currentSession else { return false }
        if let batch, batchID == batch.batchID { return matches(batch) }
        return action == .start && configurationID == currentConfiguration
    }
    func isSupported(nodeCount: Int) -> Bool {
        if version == 3 {
            guard nodeIndex == nil, let indices = nodeIndices, !indices.isEmpty,
                  indices.count <= nodeCount, Set(indices).count == indices.count else { return false }
            return indices.allSatisfy { (0..<nodeCount).contains($0) }
        }
        guard action != .enqueue, nodeIndices == nil else { return false }
        guard (version == 1 && nodeIndex == nil) || (version == 2 && nodeIndex != nil) else { return false }
        return nodeIndex.map { (0..<nodeCount).contains($0) } ?? true
    }
}

struct BatchProbeStatus: Codable {
    enum Phase: String, Codable { case running, complete, cancelled, unavailable, busy }
    enum State: String, Codable { case waiting, testing, success, failed, timedOut, cancelled }
    struct Result: Codable, Identifiable {
        let id: Int
        var state: State
        var milliseconds: Int32?
        var testedAt: Date?
    }
    let version: Int
    let batchID: UUID
    let sessionID: UUID
    let configurationID: String
    var phase: Phase
    var results: [Result]
}
