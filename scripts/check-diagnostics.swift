import Foundation

@main
struct CheckDiagnostics {
    static func main() {
        let failure = TunnelDiagnostics.startupError()
        precondition(failure.domain == "Clash.PacketTunnel" && failure.code == 1001)
        precondition(TunnelDiagnostics.safeErrorSummary(failure).contains("内核未接入"))
        let secret = "SYNTHETIC_TOKEN_NEVER_LOG"
        for domain in ["https://example.invalid/\(secret)", "NEVPNErrorDomain"] {
            let error = NSError(domain: domain, code: 42, userInfo: [
                NSLocalizedDescriptionKey: secret,
                NSUnderlyingErrorKey: NSError(domain: secret, code: 1)
            ])
            let summary = TunnelDiagnostics.safeErrorSummary(error)
            precondition(!summary.contains(secret) && !summary.contains("example.invalid"))
            precondition(summary.contains("42"))
        }
        for (error, expected) in [
            ("\(secret) timeout", ConnectivityReport.DNSOutcome.timeout),
            ("\(secret) certificate invalid", .tls),
            ("\(secret) authentication failed", .authentication),
            ("\(secret) network is unreachable", .network),
            (secret, .failed)
        ] {
            let data = try! JSONSerialization.data(withJSONObject: ["error": error])
            let result = ConnectivityReport.DNSOutcome.decode(String(decoding: data, as: UTF8.self))
            precondition(result == expected)
            let report = ConnectivityReport(nodeHTTPSMilliseconds: -1, dns: result, bootstrap: "timeout", nodeFailure: "not-run")
            let exported = String(decoding: try! JSONEncoder().encode(report), as: UTF8.self)
            precondition(!exported.contains(secret) && !result.summary.contains(secret))
        }
        precondition(ConnectivityReport.DNSOutcome.decode(#"{"Status":0,"Answer":[{"type":1,"data":"192.0.2.1"}]}"#) == .resolved)
        precondition(ConnectivityReport.DNSOutcome.decode(#"{"Status":0,"Answer":[{"type":5}]}"#) == .noAnswer)
        precondition(ConnectivityReport.DNSOutcome.decode(#"{"Status":2}"#) == .failed)
        precondition(ConnectivityReport.DNSOutcome.decode("invalid") == .malformed)
        precondition(ConnectivityReport.safeProbeStatus(secret) == "failed")
        let httpResponse = ConnectivityReport(nodeHTTPSMilliseconds: -1, dns: .resolved, bootstrap: "resolved", nodeFailure: "http-status")
        precondition(httpResponse.nodeResponded && httpResponse.nodeSummary.contains("非 2xx"))
        // Numeric-only IPC must not turn a failed or malformed probe into 0 ms success.
        for delay: Int32 in [-1, 0, 65536, .max] {
            precondition(PingReport(coreDelay: delay).outcome == .failed)
            precondition(PingReport(coreDelay: delay).milliseconds == nil)
        }
        for delay: Int32 in [1, 125, 9999] {
            let report = PingReport(coreDelay: delay)
            let data = try! JSONEncoder().encode(report)
            precondition(try! JSONDecoder().decode(PingReport.self, from: data) == report)
            precondition(report.summary == "\(delay) ms")
        }
        for delay: Int32 in [10_000, 65_535] {
            precondition(PingReport(coreDelay: delay).outcome == .timedOut)
            precondition(PingReport(coreDelay: delay).milliseconds == nil)
        }
        let invalidSuccess = try! JSONDecoder().decode(PingReport.self, from: Data(#"{"outcome":"success","milliseconds":-1}"#.utf8))
        precondition(invalidSuccess.outcome == .failed)
        let failedWithDelay = try! JSONDecoder().decode(PingReport.self, from: Data(#"{"outcome":"failed","milliseconds":123}"#.utf8))
        precondition(failedWithDelay.milliseconds == nil)
        let sensitivePayload = try! JSONSerialization.data(withJSONObject: ["outcome": secret, "milliseconds":123])
        precondition((try? JSONDecoder().decode(PingReport.self, from: sensitivePayload)) == nil)
        precondition(PingReport(outcome: .timedOut).summary.contains("超时"))
        print("PASS: startup error contract and credential-safe error summaries (host-only)")
    }
}
