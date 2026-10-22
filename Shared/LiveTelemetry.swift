import Foundation
import CryptoKit

struct LiveTelemetry: Codable {
    let version: Int
    let sessionID: UUID
    let configurationID: String
    let sampledAt: Date
    let uptime: TimeInterval
    let connectedAt: Date
    let uploadBytes: Int64?
    let downloadBytes: Int64?
    let coreReady: Bool
    let transport: String
    var groupSelections: [Int: Int]? = nil
}

nonisolated enum RuntimeIdentity {
    static func fingerprint(source: Data, choices: [String: String]) -> String {
        var data = source
        data.append(0)
        data.append((try? JSONSerialization.data(withJSONObject: choices, options: .sortedKeys)) ?? Data())
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct TrafficPoint: Identifiable, Equatable {
    let id: TimeInterval
    let date: Date
    let upload: Double
    let download: Double
    let segment: Int
    var isMeasured = true
}

/// Only contiguous, increasing samples from one real extension session are differentiated.
struct TrafficWindow {
    private(set) var points: [TrafficPoint] = []
    private(set) var last: LiveTelemetry?
    private(set) var current: TrafficPoint?
    private var segment = 0
    private var historySession: UUID?
    private var historyUptime: TimeInterval?
    mutating func baseline(date: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                           forceAnchor: Bool = false) {
        invalidate()
        guard uptime.isFinite else { return }
        // A disconnected tail is already a flat zero. Repeated status changes and
        // failed polls must not keep inserting control points into the same tail.
        if let tail = points.last, uptime <= tail.id || (!tail.isMeasured && !forceAnchor) {
            trim(at: uptime)
            return
        }
        // A late failure notification must not draw the last rate across a long
        // period with no measurements. Match the renderer's bounded idle return.
        let anchor = forceAnchor ? uptime : min(uptime, (points.last?.id ?? uptime) + 3.5)
        points.append(.init(id: anchor, date: date.addingTimeInterval(anchor - uptime),
                            upload: 0, download: 0, segment: segment, isMeasured: false))
        trim(at: uptime)
    }

    /// A failed IPC read is not a disconnect. Retain a recent measurement and do
    /// not insert a zero control point which the next valid snapshot would erase.
    mutating func missedPoll(at uptime: TimeInterval) {
        guard let latest = last?.uptime ?? historyUptime else { return }
        guard uptime - latest > 3.5 else { return }
        baseline(uptime: latest + 3.5)
        trim(at: uptime)
    }
    private mutating func trim(at uptime: TimeInterval) {
        // Overscan keeps the left clipping edge stable during delayed presentation.
        points.removeAll { uptime - $0.id > 66 }
        if points.count > 72 { points.removeFirst(points.count - 72) }
    }
    mutating func invalidate(clear: Bool = false) {
        last = nil; current = nil; segment += 1
        if clear { points.removeAll(); historySession = nil; historyUptime = nil }
    }
    mutating func ingest(_ sample: LiveTelemetry) {
        guard sample.version == 2, sample.coreReady, sample.uptime.isFinite,
              let up = sample.uploadBytes, let down = sample.downloadBytes, up >= 0, down >= 0 else {
            baseline(date: sample.sampledAt, uptime: sample.uptime.isFinite ? sample.uptime : ProcessInfo.processInfo.systemUptime); return
        }
        if let previous = last {
            guard sample.uptime > previous.uptime else { return }
            // Selector changes keep the same core session and cumulative counters.
            if previous.sessionID != sample.sessionID {
                baseline(date: sample.sampledAt, uptime: sample.uptime, forceAnchor: true)
            } else if let oldUp = previous.uploadBytes, let oldDown = previous.downloadBytes {
                let dt = sample.uptime - previous.uptime
                guard dt > 0 else { return } // Ignore duplicate/out-of-order responses.
                if dt <= 3.5, up >= oldUp, down >= oldDown {
                    let point = TrafficPoint(id: sample.uptime, date: sample.sampledAt,
                        upload: Double(up - oldUp) / dt, download: Double(down - oldDown) / dt, segment: segment)
                    points.append(point); current = point
                } else {
                    if dt > 3.5 {
                        baseline(date: previous.sampledAt.addingTimeInterval(3.5), uptime: previous.uptime + 3.5)
                    }
                    baseline(date: sample.sampledAt, uptime: sample.uptime, forceAnchor: true)
                }
            }
        }
        last = sample
        trim(at: sample.uptime)
    }

    /// The extension owns counter history; the app owns the continuous display
    /// across sessions. Never differentiate counters from two different sessions.
    mutating func mergeHistory(_ rebuilt: TrafficWindow, first: LiveTelemetry, latest: LiveTelemetry,
                               now: TimeInterval) -> Bool {
        let highWater = max(historyUptime ?? -.infinity, last?.uptime ?? -.infinity)
        guard latest.uptime >= highWater else { return false }
        let previousSession = historySession ?? last?.sessionID
        if latest.uptime == highWater, let previousSession, previousSession != latest.sessionID { return false }
        var prefix = points.filter { $0.id <= first.uptime && now - $0.id <= 66 }
        let changedSession = previousSession.map { $0 != latest.sessionID } ?? false
        let uncoveredGap = prefix.last.map { first.uptime - $0.id > 3.5 } ?? false
        if changedSession || uncoveredGap {
            func zero(_ time: TimeInterval) -> TrafficPoint {
                .init(id: time, date: first.sampledAt.addingTimeInterval(time - first.uptime),
                      upload: 0, download: 0, segment: segment + 1, isMeasured: false)
            }
            if let tail = prefix.last, tail.isMeasured, tail.id < first.uptime {
                prefix.append(zero(min(tail.id + 3.5, first.uptime)))
            }
            if !prefix.isEmpty, prefix.last!.id < first.uptime { prefix.append(zero(first.uptime)) }
        }
        points = prefix + rebuilt.points.filter { $0.id > first.uptime }
        last = rebuilt.last
        current = rebuilt.current
        segment = max(segment, rebuilt.segment)
        historySession = latest.sessionID
        historyUptime = latest.uptime
        trim(at: now)
        return true
    }
}
