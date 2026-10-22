#if DEBUG
import Foundation

/// Opt-in lifecycle counters for tab-switch regression checks. No rates or identities.
struct TelemetryMetrics {
    private let enabled = ProcessInfo.processInfo.environment["CLASH_TELEMETRY_METRICS"] == "1"
    private var starts = 0
    private var stops = 0
    private var polls = 0
    private var measured = 0

    mutating func started() { starts += 1; write() }
    mutating func stopped() { stops += 1; write() }
    mutating func polled(hasRate: Bool) { polls += 1; if hasRate { measured += 1 }; write() }

    private func write() {
        guard enabled, polls <= 300 else { return }
        let counters = ["starts": starts, "stops": stops, "polls": polls, "measured": measured]
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("telemetry-lifecycle.json")
        if let data = try? JSONSerialization.data(withJSONObject: counters, options: .sortedKeys) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
#endif
