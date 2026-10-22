import Foundation

/// Messages contain indices, fixed outcomes and counts, never subscription names or endpoints.
struct SelectionCommand: Codable {
    var kind = "selection.v1"
    let requestID: UUID
    let sessionID: UUID
    let configurationID: String
    let group: Int
    let member: Int
}
struct SelectionReply: Codable {
    let requestID: UUID
    let sessionID: UUID
    let configurationID: String
    let accepted: Bool
}
struct InspectionCommand: Codable {
    enum Action: String, Codable { case rules, dnsStart, dnsPoll, captureStart, capturePoll, captureClear }
    var kind = "inspection.v1"
    let action: Action
    let requestID: UUID
    let sessionID: UUID
    let configurationID: String
    var domain: String? = nil
}
nonisolated struct RuleObservation: Codable, Identifiable {
    let id: UUID
    let type: String
    let ruleNumber: Int?
    let chain: [String]
    let transport: String
    /// No destination host, IP, port, process or rule payload crosses the boundary.
    static func sanitize(_ json: String, catalog: ConfigurationCatalog, rules: [String]) -> [Self]? {
        guard json.utf8.count <= 2 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let entries = root["connections"] as? [[String: Any]] else { return nil }
        let types = ["Domain": "DOMAIN", "DomainSuffix": "DOMAIN-SUFFIX", "DomainKeyword": "DOMAIN-KEYWORD", "IPCIDR": "IP-CIDR", "IPCIDR6": "IP-CIDR6", "Match": "MATCH", "SrcIPCIDR": "SRC-IP-CIDR", "SrcPort": "SRC-PORT", "DstPort": "DST-PORT", "Network": "NETWORK", "RuleSet": "RULE-SET", "GeoIP": "GEOIP", "GeoSite": "GEOSITE"]
        return entries.suffix(60).compactMap { entry in
            guard let id = (entry["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            var type = types[entry["rule"] as? String ?? ""] ?? "OTHER"
            let payload = entry["rulePayload"] as? String ?? ""
            if type == "IP-CIDR", payload.contains(":") { type = "IP-CIDR6" }
            let matches = rules.indices.filter { index in
                let fields = rules[index].split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                return !(type == "IP-CIDR6" && payload == "::/0") && fields.first == type && (type == "MATCH" || fields.dropFirst().first == payload)
            }
            let chain = (entry["chains"] as? [String] ?? []).prefix(32).map { name -> String in
                if let i = catalog.nodes.firstIndex(where: { $0.name == name }) { return "N\(i + 1)" }
                if let i = catalog.groups.firstIndex(where: { $0.name == name }) { return "G\(i + 1)" }
                return ["DIRECT", "REJECT", "REJECT-DROP"].contains(name) ? name : "OTHER"
            }
            let network = (entry["metadata"] as? [String: Any])?["network"] as? String
            return Self(id: id, type: type, ruleNumber: matches.count == 1 ? matches[0] + 1 : nil,
                        chain: chain, transport: network == "tcp" ? "TCP" : network == "udp" ? "UDP" : "OTHER")
        }
    }
}
nonisolated struct DNSStage: Codable, Identifiable {
    enum Stage: String, Codable { case bootstrap, a, aaaa, https }
    var id: Stage { stage }
    let stage: Stage
    let outcome: String
    let milliseconds: Int
    var answers: Int? = nil
    var responseCode: Int? = nil
    static func query(_ json: String, stage: Stage, milliseconds: Int) -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return .init(stage: stage, outcome: "malformed", milliseconds: milliseconds)
        }
        if root["error"] != nil {
            return .init(stage: stage, outcome: ConnectivityReport.DNSOutcome.decode(json).rawValue, milliseconds: milliseconds)
        }
        guard let code = root["Status"] as? Int else { return .init(stage: stage, outcome: "malformed", milliseconds: milliseconds) }
        let expected = stage == .aaaa ? 28 : 1
        let count = (root["Answer"] as? [[String: Any]] ?? []).filter { $0["type"] as? Int == expected }.count
        return .init(stage: stage, outcome: code == 0 ? (count > 0 ? "resolved" : "no-answer") : "dns-response-error",
                     milliseconds: milliseconds, answers: count, responseCode: code)
    }
    static func validDomain(_ input: String) -> Bool {
        let value = input.hasSuffix(".") ? String(input.dropLast()) : input
        return value.utf8.count <= 253 && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 63 && $0.first != "-" && $0.last != "-" &&
            $0.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil
        } && value.contains(".")
    }
}
struct InspectionReply: Codable {
    let requestID: UUID
    let sessionID: UUID
    let configurationID: String
    var state: String = "complete"
    var rules: [RuleObservation] = []
    var dns: [DNSStage] = []
    var capture: [CapturedConnection]? = nil
    var captureSecondsRemaining: Int? = nil
}
