import Foundation

@main struct CheckNetworkInspection {
    static func main() throws {
        let secret = "SYNTHETIC_SECRET"
        let catalog = ConfigurationCatalog(nodes: [.init(name: secret, kind: "vless", isFixture: true, label: "Node 1")],
            groups: [.init(id: 0, name: "PRIVATE-GROUP", members: [secret])], choices: ["PRIVATE-GROUP": secret], matchTarget: "PRIVATE-GROUP")
        let id = UUID()
        let item: [String: Any] = ["id": id.uuidString, "rule": "Domain", "rulePayload": "private.example.invalid",
            "chains": [secret, "PRIVATE-GROUP"], "metadata": ["host": "private.example.invalid", "network": "tcp", "processPath": secret]]
        let bytes = try JSONSerialization.data(withJSONObject: ["connections": [item]])
        let json = String(decoding: bytes, as: UTF8.self)
        let rules = ["DOMAIN,private.example.invalid,PRIVATE-GROUP", "MATCH,PRIVATE-GROUP"]
        let rows = RuleObservation.sanitize(json, catalog: catalog, rules: rules)!
        precondition(rows.count == 1 && rows[0].ruleNumber == 1 && rows[0].chain == ["N1", "G1"] && rows[0].transport == "TCP")
        let encoded = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
        precondition(!encoded.contains(secret) && !encoded.contains("PRIVATE-GROUP") && !encoded.contains("example.invalid") && !encoded.contains("processPath"))
        precondition(RuleObservation.sanitize(json, catalog: catalog, rules: [rules[0], rules[0]])![0].ruleNumber == nil)
        precondition(RuleObservation.sanitize("not JSON", catalog: catalog, rules: []) == nil)
        let many = try JSONSerialization.data(withJSONObject: ["connections": (0..<80).map { _ -> [String: Any] in
            var row = item; row["id"] = UUID().uuidString; return row
        }])
        precondition(RuleObservation.sanitize(String(decoding: many, as: UTF8.self), catalog: catalog, rules: rules)?.count == 60)
        let answer = #"{"Status":0,"Answer":[{"type":28,"data":"2001:db8::1"},{"type":5,"data":"private.example.invalid"}]}"#
        precondition(DNSStage.query(answer, stage: .aaaa, milliseconds: 17).answers == 1)
        precondition(DNSStage.query(answer, stage: .a, milliseconds: 17).outcome == "no-answer")
        precondition(DNSStage.query(#"{"Status":3}"#, stage: .a, milliseconds: 1).responseCode == 3)
        let error = String(decoding: try JSONSerialization.data(withJSONObject: ["error": secret + " timeout"]), as: UTF8.self)
        let stage = DNSStage.query(error, stage: .a, milliseconds: 10)
        let safeStage = String(decoding: try JSONEncoder().encode(stage), as: UTF8.self)
        precondition(stage.outcome == "timeout" && !safeStage.contains(secret))
        for domain in ["ping0.cc", "example.invalid.", "xn--fiqs8s.example"] { precondition(DNSStage.validDomain(domain)) }
        for domain in ["", "https://example.invalid/secret", "user@example.invalid", "a..b", "a.-b", "a.b:53", String(repeating: "x", count: 64) + ".invalid"] { precondition(!DNSStage.validDomain(domain)) }
        let command = SelectionCommand(requestID: UUID(), sessionID: UUID(), configurationID: "hash", group: 0, member: 1)
        let payload = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(SelectionCommand.self, from: payload)
        precondition(decoded.member == 1)
        precondition((try? JSONDecoder().decode(InspectionCommand.self, from: payload)) == nil)
        var captureEntry = item
        captureEntry["metadata"] = ["host": "weixin.qq.com", "destinationIP": "223.5.5.5", "sourceIP": "192.168.1.10", "processPath": secret, "network": "tcp"]
        captureEntry["upload"] = 4096; captureEntry["download"] = 512
        func captured(_ entry: [String: Any]) throws -> [CapturedConnection] {
            let data = try JSONSerialization.data(withJSONObject: ["connections": [entry]])
            return CapturedConnection.sanitize(String(decoding: data, as: UTF8.self), catalog: catalog, rules: rules, now: Date(timeIntervalSince1970: 100))!
        }
        let capturedRows = try captured(captureEntry)
        precondition(capturedRows[0].destination == "weixin.qq.com" && capturedRows[0].family == "IPv4" && capturedRows[0].upload == 4096)
        let captureJSON = String(decoding: try JSONEncoder().encode(capturedRows), as: UTF8.self)
        precondition(!captureJSON.contains(secret) && !captureJSON.contains("192.168.1.10") && !captureJSON.contains("processPath"))
        captureEntry["metadata"] = ["host": "https://private.invalid/path?token=SECRET", "destinationIP": "2001:db8::1", "network": "udp"]
        let safe = try captured(captureEntry)
        precondition(safe[0].destination == "2001:db8::1" && safe[0].family == "IPv6")
        var buffer = ConnectionCapture()
        buffer.ingest(capturedRows, now: 0); precondition(buffer.rows.isEmpty)
        buffer.start(now: 10); buffer.ingest(capturedRows, now: 11)
        precondition(buffer.rows.count == 1 && buffer.running(now: 69))
        captureEntry["upload"] = 8192
        buffer.ingest(try captured(captureEntry), now: 12)
        precondition(buffer.rows.count == 1 && buffer.rows[0].upload == 8192)
        for _ in 0..<45 {
            captureEntry["id"] = UUID().uuidString
            buffer.ingest(try captured(captureEntry), now: 13)
        }
        precondition(buffer.rows.count == 30)
        let saved = buffer.rows.map(\.id)
        buffer.ingest(capturedRows, now: 70)
        precondition(!buffer.running(now: 70) && buffer.rows.map(\.id) == saved)
        buffer.expire(now: 310); precondition(buffer.rows.isEmpty && buffer.expiresAt == nil)
        buffer.start(now: 400); buffer.ingest(capturedRows, now: 401); buffer.clear()
        precondition(buffer.rows.isEmpty && !buffer.running(now: 402))
        let captureReply = InspectionReply(requestID: UUID(), sessionID: UUID(), configurationID: "hash", capture: capturedRows, captureSecondsRemaining: 60)
        let replySize = try JSONEncoder().encode(captureReply).count
        precondition(replySize < 32768)
        print("PASS: rule provenance, ambiguous indices, 60-row bound, endpoint redaction, A/AAAA separation, RCODE, sanitized errors, domain validation command isolation, opt-in destination sanitization, byte updates, 30-row cap, capture deadline and automatic expiry; no network or Keychain")
    }
}
