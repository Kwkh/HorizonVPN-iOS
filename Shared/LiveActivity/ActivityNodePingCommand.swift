import Foundation
import CryptoKit

nonisolated struct ActivityNodePingCommand: Codable {
    var kind = "activity-node-ping.v1"
    let sessionID: UUID
    let targetID: String

    static func targetID(configurationID: String, selections: [Int: Int]?) -> String {
        // Stable digest, never export names, configuration contents or credentials.
        let selection = selections?.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",") ?? "unknown"
        return SHA256.hash(data: Data((configurationID + "|" + selection).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
