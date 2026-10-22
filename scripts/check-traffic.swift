import Foundation

@main struct CheckTraffic {
    static func main() {
        let session = UUID(), other = UUID()
        func sample(_ uptime: Double, _ up: Int64?, _ down: Int64?, sessionID: UUID? = nil, config: String = "A") -> LiveTelemetry {
            .init(version: 2, sessionID: sessionID ?? session, configurationID: config,
                  sampledAt: Date(timeIntervalSince1970: uptime), uptime: uptime,
                  connectedAt: Date(timeIntervalSince1970: 0), uploadBytes: up, downloadBytes: down,
                  coreReady: true, transport: "wifi")
        }
        var window = TrafficWindow()
        window.ingest(sample(1, 500, 800)); precondition(window.current == nil)
        window.ingest(sample(3, 2500, 4800))
        precondition(window.current?.upload == 1000 && window.current?.download == 2000)
        window.ingest(sample(2, 999999, 999999))
        precondition(window.points.count == 1 && window.last?.uptime == 3)
        window.ingest(sample(4, 2500, 4800)); precondition(window.current?.download == 0)
        window.ingest(sample(10, 500000, 800000))
        precondition(window.current == nil && window.points.last?.isMeasured == false && window.points.last?.download == 0)
        window.ingest(sample(11, 501000, 802000)); precondition(window.current?.download == 2000)
        window.ingest(sample(12, 1, 1)); precondition(window.current == nil)
        window.ingest(sample(13, 1001, 2001)); precondition(window.current?.upload == 1000)
        window.ingest(sample(14, nil, 3000)); precondition(window.current == nil && window.last == nil)
        window.ingest(sample(15, 9000, 10000)); precondition(window.current == nil)
        window.ingest(sample(16, 10000, 11000)); precondition(window.current?.download == 1000)
        window.ingest(sample(17, 900000, 900000, sessionID: other)); precondition(window.current == nil && window.points.isEmpty)
        window.ingest(sample(18, 901000, 901000, sessionID: other)); precondition(window.current?.upload == 1000)
        let beforeSwitch = window.points.count
        window.ingest(sample(19, 902000, 902000, sessionID: other, config: "B"))
        precondition(window.current?.upload == 1000 && window.points.count == beforeSwitch + 1)
        window.baseline(date: Date(timeIntervalSince1970: 20), uptime: 20)
        precondition(window.current == nil && window.points.last?.upload == 0 && window.points.last?.isMeasured == false)
        for i in 21...180 { window.baseline(date: Date(timeIntervalSince1970: Double(i)), uptime: Double(i)) }
        precondition(window.points.count == 67 && window.points.first?.id == 114)
        let data = Data("fictional-source".utf8)
        precondition(RuntimeIdentity.fingerprint(source: data, choices: ["a":"x", "b":"y"]) == RuntimeIdentity.fingerprint(source: data, choices: ["b":"y", "a":"x"]))
        precondition(RuntimeIdentity.fingerprint(source: data, choices: ["a":"x"]) != RuntimeIdentity.fingerprint(source: data, choices: ["a":"y"]))
        print("PASS: real deltas, stale/zero distinction, reset, out-of-order, session isolation and hot-selection continuity and 66-second overscan bounds")
    }
}
