import Foundation
import Testing
@testable import Horizon

@MainActor struct TelemetryHistoryTests {
    private let session = UUID()
    private func sample(_ time: Double, sessionID: UUID? = nil, configuration: String = "A",
                        up: Int64? = nil, down: Int64? = nil) -> LiveTelemetry {
        .init(version: 2, sessionID: sessionID ?? session, configurationID: configuration,
              sampledAt: Date(timeIntervalSince1970: time), uptime: time,
              connectedAt: Date(timeIntervalSince1970: 0), uploadBytes: up ?? Int64(time * 1000),
              downloadBytes: down ?? Int64(time * 2000), coreReady: true, transport: "wifi")
    }

    @Test func backgroundAndColdAppRecoverActualLastMinute() throws {
        var buffer = TelemetryHistoryBuffer(), foreground = TrafficWindow()
        for time in 1...15 { let s = sample(Double(time)); buffer.append(s); foreground.ingest(s) }
        foreground.invalidate()
        for time in 16...120 { buffer.append(sample(Double(time))) }
        let history = TelemetryHistory(version: 1, samples: buffer.samples)
        #expect(buffer.samples.count == 67)
        #expect(history.isValid(configurationID: "A", now: 120))
        let restored1 = foreground.restore(history, now: 120)
        #expect(restored1)
        #expect(foreground.points.count == 66 && foreground.current?.download == 2000)
        #expect(foreground.points.allSatisfy { $0.isMeasured && $0.upload == 1000 })
        var coldApp = TrafficWindow()
        let restored2 = coldApp.restore(history, now: 120)
        #expect(restored2)
        #expect(coldApp.points == foreground.points)
        let wire = try JSONEncoder().encode(history)
        #expect(wire.count < TelemetryHistory.maximumBytes)
        #expect(try JSONDecoder().decode(TelemetryHistory.self, from: wire).samples.count == 67)
    }

    @Test func repeatedPollsAndLateRepliesDoNotDuplicateOrRewind() {
        var window = TrafficWindow()
        let first = TelemetryHistory(version: 1, samples: (1...10).map { sample(Double($0)) })
        let restored3 = window.restore(first, now: 10)
        #expect(restored3)
        let original = window.points
        let restored4 = window.restore(first, now: 10.5)
        #expect(restored4)
        #expect(window.points == original)
        let older = TelemetryHistory(version: 1, samples: (1...9).map { sample(Double($0)) })
        let restored5 = !window.restore(older, now: 10.5)
        #expect(restored5)
        #expect(window.points == original)
        window.invalidate()
        let restored6 = window.restore(first, now: 10.5)
        #expect(restored6)
        #expect(window.current?.upload == 1000)
    }

    @Test func sessionRestartKeepsVisibleHistoryButResetsCounterBaseline() {
        var buffer = TelemetryHistoryBuffer()
        buffer.append(sample(1)); buffer.append(sample(2, configuration: "B"))
        let hot = TelemetryHistory(version: 1, samples: buffer.samples)
        #expect(hot.isValid(configurationID: "B", now: 2))
        #expect(!hot.isValid(configurationID: "A", now: 2))
        var window = TrafficWindow()
        let restored7 = window.restore(hot, now: 2) && window.current?.upload == 1000
        #expect(restored7)
        buffer.append(sample(3, sessionID: UUID(), configuration: "B", up: 0, down: 0))
        #expect(buffer.samples.count == 1)
        let restored8 = window.restore(.init(version: 1, samples: buffer.samples), now: 3)
        #expect(restored8)
        #expect(window.current == nil)
        #expect(window.points.contains { $0.id == 2 && $0.isMeasured && $0.upload == 1000 })
        #expect(window.points.contains { $0.id == 3 && !$0.isMeasured && $0.upload == 0 })
        buffer.reset()
        #expect(buffer.samples.isEmpty)
    }

    @Test func repeatedDisconnectsDoNotReshapeTheZeroTail() {
        var window = TrafficWindow()
        let merged1 = window.restore(.init(version: 1, samples: (1...10).map { sample(Double($0)) }), now: 10)
        #expect(merged1)
        window.baseline(date: Date(timeIntervalSince1970: 10.2), uptime: 10.2)
        let stopped = window.points
        for time in [10.3, 10.5, 11, 12, 13] { window.baseline(uptime: time) }
        #expect(window.points == stopped)
        #expect(window.current == nil)
    }

    @Test func partialSameSessionHistoryDoesNotBridgeAnUnmeasuredGap() {
        var window = TrafficWindow()
        let initial = window.restore(.init(version: 1, samples: [sample(9), sample(10)]), now: 10)
        #expect(initial)
        let resumed = window.restore(.init(version: 1, samples: [sample(50), sample(51)]), now: 51)
        #expect(resumed)
        #expect(window.points.contains { $0.id == 13.5 && !$0.isMeasured })
        #expect(window.points.contains { $0.id == 50 && !$0.isMeasured })
        #expect(window.current?.upload == 1000)
    }

    @Test func reconnectAndRepeatedSnapshotsPreserveOldWaveform() {
        var window = TrafficWindow()
        let merged2 = window.restore(.init(version: 1, samples: (1...10).map { sample(Double($0)) }), now: 10)
        #expect(merged2)
        let oldWave = window.points
        window.baseline(uptime: 10.2)
        let newSession = UUID()
        let start = sample(14, sessionID: newSession, up: 0, down: 0)
        let merged3 = window.restore(.init(version: 1, samples: [start]), now: 14)
        #expect(merged3)
        #expect(Array(window.points.prefix(oldWave.count)) == oldWave)
        #expect(window.current == nil)
        let resumed = TelemetryHistory(version: 1, samples: [start, sample(15, sessionID: newSession, up: 100, down: 200)])
        let merged4 = window.restore(resumed, now: 15)
        #expect(merged4)
        let points = window.points
        #expect(window.current?.upload == 100 && window.current?.download == 200)
        #expect(Array(points.prefix(oldWave.count)) == oldWave)
        #expect(points.contains { $0.id == 14 && !$0.isMeasured })
        let merged5 = window.restore(resumed, now: 15.5)
        #expect(merged5)
        #expect(window.points == points)
        window.invalidate()
        let merged6 = !window.restore(.init(version: 1, samples: [sample(13), sample(14)]), now: 15.5)
        #expect(merged6)
        #expect(window.points == points)
        window.baseline(uptime: 90)
        #expect(window.points.allSatisfy { 90 - $0.id <= 66 })
    }

    @Test func missedTimerAndCounterResetNeverBecomeRateSpikes() {
        let history = TelemetryHistory(version: 1, samples: [sample(1), sample(2), sample(20), sample(21),
            sample(22, up: 1, down: 1), sample(23, up: 1001, down: 2001)])
        var window = TrafficWindow()
        let restored9 = window.restore(history, now: 23)
        #expect(restored9)
        #expect(window.points.filter(\.isMeasured).allSatisfy { $0.upload == 1000 && $0.download == 2000 })
        #expect(window.points.contains { $0.id == 5.5 && !$0.isMeasured && $0.upload == 0 })
        #expect(window.points.contains { $0.id == 20 && !$0.isMeasured })
        #expect(window.current?.download == 2000)
    }

    @Test func missingCountersUseHistoricalTimestampNotReceiptTime() {
        var missing = sample(3)
        missing = .init(version: 2, sessionID: session, configurationID: "A", sampledAt: missing.sampledAt,
                        uptime: 3, connectedAt: missing.connectedAt, uploadBytes: nil, downloadBytes: nil,
                        coreReady: true, transport: "wifi")
        var window = TrafficWindow()
        let restored10 = window.restore(.init(version: 1, samples: [sample(1), sample(2), missing, sample(4), sample(5)]), now: 5)
        #expect(restored10)
        #expect(window.points.contains { $0.id == 3 && !$0.isMeasured })
        #expect(window.current?.download == 2000)
    }

    @Test func malformedOrStaleSnapshotsAreRejectedAndBufferIsBounded() {
        let valid = [sample(1), sample(2)]
        #expect(!TelemetryHistory(version: 2, samples: valid).isValid(configurationID: "A", now: 2))
        #expect(!TelemetryHistory(version: 1, samples: valid).isValid(configurationID: "A", now: 6))
        #expect(!TelemetryHistory(version: 1, samples: valid).isValid(configurationID: "A", now: 1))
        for values in [[sample(2), sample(1)], [sample(1), sample(1)],
                       [sample(1), sample(2, sessionID: UUID())], [sample(1), sample(100)],
                       [sample(1, up: -1)], []] {
            #expect(!TelemetryHistory(version: 1, samples: values).isValid(configurationID: "A", now: 2))
        }
        var buffer = TelemetryHistoryBuffer()
        for i in 1...1000 { buffer.append(sample(Double(i) / 10)) }
        #expect(buffer.samples.count == TelemetryHistory.maximumSamples)
        buffer.append(sample(99)); buffer.append(sample(100))
        #expect(buffer.samples.count == TelemetryHistory.maximumSamples)
    }
}
