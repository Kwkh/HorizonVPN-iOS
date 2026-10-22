import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Horizon

@MainActor struct TrafficPlotContinuityTests {
    private func curves(_ samples: [CGPoint], end: Double = 20) -> [TrafficPlotGeometry.RoundedSegment] {
        TrafficPlotGeometry.roundedSegments(TrafficPlotGeometry.plotVertices(samples, baseline: 0, end: end))
    }

    // Compare actual drawn geometry at the same absolute time, not just source samples.
    private func height(_ time: Double, in segments: [TrafficPlotGeometry.RoundedSegment]) -> Double {
        guard let s = segments.first(where: { $0.start.x <= time && time <= $0.end.x }) else { return .nan }
        var low = 0.0, high = 1.0
        for _ in 0..<50 {
            let t = (low + high) / 2, u = 1 - t
            let x = u*u*s.start.x + 2*u*t*s.control.x + t*t*s.end.x
            if x < time { low = t } else { high = t }
        }
        let t = (low + high) / 2, u = 1 - t
        return u*u*s.start.y + 2*u*t*s.control.y + t*t*s.end.y
    }

    @Test func reconnectDoesNotRedrawTheCompletedDescent() {
        let stopped = [CGPoint(x: 9, y: 60), CGPoint(x: 10, y: 100), CGPoint(x: 10.2, y: 0)]
        let before = curves(stopped)
        for restart in [14.0, 20, 45] {
            let after = curves(stopped + [CGPoint(x: restart, y: 0), CGPoint(x: restart + 1, y: 80)])
            for step in 0...200 {
                let time = 9 + Double(step) / 100
                #expect(abs(height(time, in: before) - height(time, in: after)) < 0.000001)
            }
        }
    }

    @Test func idleReturnFinishesLocallyAndIdleSpanStaysFlat() {
        let samples = [CGPoint(x: 9, y: 60), CGPoint(x: 10, y: 100), CGPoint(x: 10.2, y: 0),
                       CGPoint(x: 40, y: 0), CGPoint(x: 41, y: 80)]
        let path = curves(samples, end: 41)
        // Both ends round within a local one-second neighbourhood, not across the gap.
        for time in stride(from: 10.7, through: 39.5, by: 0.1) {
            #expect(abs(height(time, in: path)) < 0.000001)
        }
        #expect(height(40.5, in: path) > 0)
        let old = curves(Array(samples.prefix(2)))
        let stale = curves(Array(samples.prefix(2)) + [CGPoint(x: 13.5, y: 0)])
        for time in stride(from: 9.0, through: 15, by: 0.05) {
            #expect(abs(height(time, in: old) - height(time, in: stale)) < 0.000001)
        }
    }

    @Test func everyJoinHasContinuousTangentAndNoOvershoot() {
        let path = curves([.init(x: 1, y: 0), .init(x: 2, y: 100), .init(x: 2.2, y: 0),
                           .init(x: 25, y: 0), .init(x: 26, y: 50), .init(x: 29, y: 5)])
        for (index, s) in path.enumerated() {
            if index > 0 {
                let p = path[index - 1]
                #expect(p.end == s.start)
                #expect(abs((p.end.x - p.control.x) - (s.control.x - s.start.x)) < 0.000001)
                #expect(abs((p.end.y - p.control.y) - (s.control.y - s.start.y)) < 0.000001)
            }
            for step in 0...30 {
                let t = Double(step) / 30, u = 1 - t
                let y = u*u*s.start.y + 2*u*t*s.control.y + t*t*s.end.y
                #expect(y >= -0.000001 && y <= 100.000001)
            }
        }
    }

    @Test func newSamplesAndMovingTailCannotChangeVisibleHistory() {
        let base = (0...10).map { CGPoint(x: Double($0), y: 50 + sin(Double($0)) * 40) }
        let original = curves(base, end: 7.5)
        let extended = curves(base + [.init(x: 11, y: 85)], end: 8.5)
        let scrolled = curves(base, end: 90)
        for time in stride(from: 0.0, through: 7.5, by: 0.025) {
            #expect(abs(height(time, in: original) - height(time, in: extended)) < 0.000001)
            #expect(abs(height(time, in: original) - height(time, in: scrolled)) < 0.000001)
        }
    }

    @Test func longDisconnectedPeriodDoesNotStretchLastMeasurement() {
        var window = TrafficWindow()
        let session = UUID()
        func sample(_ t: Double) -> LiveTelemetry {
            .init(version: 2, sessionID: session, configurationID: "test", sampledAt: Date(), uptime: t,
                  connectedAt: Date(), uploadBytes: Int64(t * 100), downloadBytes: Int64(t * 200),
                  coreReady: true, transport: "test")
        }
        window.ingest(sample(9)); window.ingest(sample(10))
        window.baseline(uptime: 40)
        #expect(window.points.last?.id == 13.5)
        #expect(window.points.last?.isMeasured == false)
    }

    @Test func temporaryReadFailureDoesNotInsertThenEraseAZero() {
        var window = TrafficWindow()
        let session = UUID()
        func sample(_ t: Double) -> LiveTelemetry {
            .init(version: 2, sessionID: session, configurationID: "test", sampledAt: Date(), uptime: t,
                  connectedAt: Date(), uploadBytes: Int64(t * 100), downloadBytes: Int64(t * 200),
                  coreReady: true, transport: "test")
        }
        let restored = window.restore(.init(version: 1, samples: [sample(9), sample(10)]), now: 10)
        #expect(restored)
        let original = window.points
        window.missedPoll(at: 11)
        #expect(window.points == original)
        #expect(window.current?.upload == 100)
        window.missedPoll(at: 14)
        #expect(window.current == nil)
        #expect(window.points.last?.id == 13.5)
        let stale = window.points
        window.missedPoll(at: 15)
        #expect(window.points == stale)
    }

    @Test func surfaceUsesBezierForBothSeriesIncludingIdleConnections() throws {
        let view = TrafficPlotSurface(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        let now = ProcessInfo.processInfo.systemUptime
        let points = [TrafficPoint(id: now - 10, date: Date(), upload: 100, download: 200, segment: 0),
                      TrafficPoint(id: now - 9.8, date: Date(), upload: 0, download: 0, segment: 1, isMeasured: false),
                      TrafficPoint(id: now - 4, date: Date(), upload: 0, download: 0, segment: 1, isMeasured: false),
                      TrafficPoint(id: now - 3, date: Date(), upload: 80, download: 50, segment: 1)]
        view.configure(points: points, upload: .red, download: .white, running: false,
                       reduceMotion: true, ceiling: 1000, logarithmic: false)
        let layers = try #require(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer })
        #expect(layers.count == 2)
        for layer in layers {
            let path = try #require(layer.path)
            var moves = 0, curves = 0, other = 0
            path.applyWithBlock { element in
                switch element.pointee.type {
                case .moveToPoint: moves += 1
                case .addQuadCurveToPoint: curves += 1
                default: other += 1
                }
            }
            #expect(moves == 1 && curves > 5 && other == 0)
            #expect(layer.animationKeys()?.isEmpty ?? true)
        }
    }

    @Test func idleCacheContinuesToCoverTheScreenAfterSeveralMinutes() throws {
        let view = TrafficPlotSurface(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        let now = ProcessInfo.processInfo.systemUptime
        view.configure(points: [], upload: .red, download: .white, running: false,
                       reduceMotion: false, ceiling: 1000, logarithmic: false)
        for elapsed in [59.0, 61, 130, 600] {
            view.render(at: now + elapsed)
            for layer in try #require(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer }) {
                let box = try #require(layer.path).boundingBoxOfPath
                #expect(box.minX + layer.transform.m41 <= 0)
                #expect(box.maxX + layer.transform.m41 >= 360)
            }
        }
    }
}
