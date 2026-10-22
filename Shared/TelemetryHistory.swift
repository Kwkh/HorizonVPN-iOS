import Foundation

/// Bounded IPC snapshot of actual counter readings. Never contains node names or credentials.
struct TelemetryHistory: Codable {
    static let command = "telemetry.history.v1"
    static let maximumSamples = 72
    static let retention: TimeInterval = 66
    static let maximumBytes = 64 * 1024
    let version: Int
    var samples: [LiveTelemetry]

    var latest: LiveTelemetry? { samples.last }

    func isValid(configurationID: String, now: TimeInterval) -> Bool {
        guard version == 1, !samples.isEmpty, samples.count <= Self.maximumSamples,
              let latest, latest.configurationID == configurationID, latest.coreReady,
              now.isFinite, latest.uptime.isFinite,
              now - latest.uptime >= -0.25, now - latest.uptime <= 3.5 else { return false }
        var previous = -Double.infinity
        for sample in samples {
            guard sample.version == 2, sample.sessionID == latest.sessionID,
                  sample.uptime.isFinite, sample.uptime > previous,
                  latest.uptime - sample.uptime <= Self.retention,
                  sample.sampledAt.timeIntervalSince1970.isFinite,
                  sample.uploadBytes.map({ $0 >= 0 }) ?? true,
                  sample.downloadBytes.map({ $0 >= 0 }) ?? true else { return false }
            previous = sample.uptime
        }
        return true
    }
}

/// Owned by the extension's lifecycle queue, independent of the main App's lifetime.
struct TelemetryHistoryBuffer {
    private(set) var samples: [LiveTelemetry] = []

    mutating func append(_ value: LiveTelemetry) {
        guard value.version == 2, value.uptime.isFinite else { return }
        if let previous = samples.last {
            if previous.sessionID != value.sessionID { samples.removeAll(keepingCapacity: true) }
            else if value.uptime <= previous.uptime { return }
        }
        var sample = value
        sample.groupSelections = nil // Only the latest reply needs current selector metadata.
        samples.append(sample)
        samples.removeAll { value.uptime - $0.uptime > TelemetryHistory.retention }
        if samples.count > TelemetryHistory.maximumSamples {
            samples.removeFirst(samples.count - TelemetryHistory.maximumSamples)
        }
    }
    mutating func reset() { samples.removeAll(keepingCapacity: true) }
}

extension TrafficWindow {
    /// Merge one coherent snapshot with still-visible history from earlier sessions.
    /// Also restores a newly launched App without calculating a foreground/background average.
    mutating func restore(_ history: TelemetryHistory, now: TimeInterval) -> Bool {
        guard let first = history.samples.first, let latest = history.latest,
              history.isValid(configurationID: latest.configurationID, now: now) else { return false }
        if let last, last.sessionID == latest.sessionID, last.uptime > latest.uptime { return false }
        var restored = TrafficWindow()
        for sample in history.samples { restored.ingest(sample) }
        return mergeHistory(restored, first: first, latest: latest, now: now)
    }
}
