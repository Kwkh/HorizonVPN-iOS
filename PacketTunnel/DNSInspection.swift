import Foundation
import Hako

/// Explicit, bounded diagnostic probes; raw bridge output never leaves this scope.
enum DNSInspection {
    static func run(domain: String, node: String?) -> [DNSStage] {
        var stages: [DNSStage] = []
        for (stage, type) in [(DNSStage.Stage.a, "A"), (.aaaa, "AAAA")] {
            let start = ProcessInfo.processInfo.systemUptime
            let raw = HakoDNSQueryJSON(domain, type)
            stages.append(.query(raw, stage: stage, milliseconds: Int((ProcessInfo.processInfo.systemUptime - start) * 1000)))
        }
        if let node {
            let raw = HakoPrivateNodeProbeJSON(node)
            let root = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
            stages.append(.init(stage: .bootstrap, outcome: ConnectivityReport.safeProbeStatus(root?["bootstrap"] as? String), milliseconds: -1))
            stages.append(.init(stage: .https, outcome: ConnectivityReport.safeProbeStatus(root?["https"] as? String),
                                milliseconds: (root?["delay"] as? Int) ?? -1))
        }
        return stages
    }
}
