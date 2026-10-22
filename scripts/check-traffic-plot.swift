import Foundation
import CoreGraphics

@main struct CheckTrafficPlot {
    static func main() {
        let width = 360.0, time = 1000.0, sampleTime = 990.0
        let expectedStep = width / 60 / 60
        var previous = TrafficPlotGeometry.x(uptime: sampleTime, end: time, width: width)
        for frame in 1...600 {
            let now = time + Double(frame) / 60
            let x = TrafficPlotGeometry.x(uptime: sampleTime, end: now, width: width)
            precondition(abs((previous - x) - expectedStep) < 0.000001, "scroll must never pause at sample boundaries")
            previous = x
        }
        for phase in [0.0, 0.017, 0.63, 1.0, 3.7] {
            let cached = TrafficPlotGeometry.x(uptime: sampleTime, end: time, width: width) - width * phase / 60
            let rebuilt = TrafficPlotGeometry.x(uptime: sampleTime, end: time + phase, width: width)
            precondition(abs(cached - rebuilt) < 0.000001, "rebuilding paths must preserve on-screen positions")
        }
        for ceiling in [100_000.0, 1_000_000, 10_000_000, 100_000_000] {
            precondition(TrafficPlotGeometry.normalizedHeight(rate: ceiling / 4, ceiling: ceiling) == 0.25)
            precondition(TrafficPlotGeometry.normalizedHeight(rate: ceiling * 2, ceiling: ceiling) == 1)
            precondition(TrafficPlotGeometry.normalizedHeight(rate: 0, ceiling: ceiling) == 0)
            // The same reading retains its height before and after an unrelated spike.
            let before = TrafficPlotGeometry.normalizedHeight(rate: 20_000, ceiling: ceiling)
            _ = TrafficPlotGeometry.normalizedHeight(rate: 90_000_000, ceiling: ceiling)
            precondition(TrafficPlotGeometry.normalizedHeight(rate: 20_000, ceiling: ceiling) == before)
        }
        precondition(TrafficPlotGeometry.presentationDelay < 66 - 60, "retain enough offscreen history for delayed presentation")
        func detail(_ rate: Double) -> Double {
            TrafficPlotGeometry.normalizedHeight(rate: rate, ceiling: 1_000_000, logarithmicWeight: 1)
        }
        precondition(detail(0) == 0 && detail(-1) == 0)
        precondition(detail(TrafficPlotGeometry.logarithmicCeiling) == 1)
        precondition(detail(100_000_000) == 1 && detail(.infinity) == 0)
        precondition(detail(5000) > 0.5 && detail(5000) < 0.55, "small traffic should be visible at a fixed scale")
        var previousHeight = 0.0
        for i in 0...10_000 {
            let height = detail(Double(i) * 1100)
            precondition(height >= previousHeight && height <= 1, "log mapping must remain bounded and monotonic")
            previousHeight = height
        }
        for boundary in [10.0, 100, 1024, 10240, 102400, 1048576] {
            precondition(abs(detail(boundary + 0.0001) - detail(boundary - 0.0001)) < 0.00001,
                         "no scale-band jumps")
        }
        var axis = TrafficPlotGeometry.Axis()
        axis.select(ceiling: 1_000_000, logarithmic: true, at: 0, animated: true)
        let middle = axis.value(at: 0.15)
        precondition(abs(middle.logarithmicWeight - 0.5) < 0.000001)
        axis.select(ceiling: 1_000_000, logarithmic: true, at: 0.15, animated: true)
        precondition(axis.value(at: 0.3).logarithmicWeight == 1, "ordinary updates cannot restart scale transition")
        axis.select(ceiling: 100_000, logarithmic: false, at: 0.15, animated: true)
        precondition(axis.value(at: 0.15) == middle, "rapid selection starts at the currently displayed scale")
        axis.select(ceiling: 100_000, logarithmic: false, at: 0.16, animated: false)
        precondition(axis.value(at: 0.16).logarithmicWeight == 0, "reduced motion settles immediately")
        let vertices = [CGPoint(x: 0, y: 0), CGPoint(x: 0.7, y: 20),
                        CGPoint(x: 2, y: 3), CGPoint(x: 3, y: 45),
                        CGPoint(x: 4.5, y: 45), CGPoint(x: 6, y: 0), CGPoint(x: 7, y: 0)]
        let segments = TrafficPlotGeometry.roundedSegments(vertices)
        for (index, segment) in segments.enumerated() {
            var lastX = segment.start.x
            for step in 0...100 {
                let t = Double(step) / 100, s = 1 - t
                let x = s*s*segment.start.x + 2*s*t*segment.control.x + t*t*segment.end.x
                let y = s*s*segment.start.y + 2*s*t*segment.control.y + t*t*segment.end.y
                let bounds = [segment.start.y, segment.control.y, segment.end.y]
                precondition(y >= bounds.min()! - 0.00001 && y <= bounds.max()! + 0.00001,
                             "rounded path must not invent negative rates or overshooting peaks")
                precondition(x >= lastX - 0.00001, "path must move forward in time")
                lastX = x
            }
            if index > 0 {
                let previous = segments[index - 1]
                precondition(previous.end == segment.start, "segments must join without gaps")
                let before = CGPoint(x: previous.end.x - previous.control.x, y: previous.end.y - previous.control.y)
                let after = CGPoint(x: segment.control.x - segment.start.x, y: segment.control.y - segment.start.y)
                precondition(abs(before.x - after.x) < 0.00001 && abs(before.y - after.y) < 0.00001,
                             "tangent must remain continuous even with irregular sample times")
            }
        }
        let appended = TrafficPlotGeometry.roundedSegments(vertices + [CGPoint(x: 8, y: 90)])
        precondition(Array(segments.dropLast()) == Array(appended.prefix(segments.count - 1)),
                     "new readings cannot reshape mature history")
        let trimmed = TrafficPlotGeometry.roundedSegments(Array(vertices.dropFirst()))
        precondition(Array(segments.dropFirst(2)) == Array(trimmed.dropFirst()),
                     "removing offscreen history cannot reshape mature segments")
        let peak = TrafficPlotGeometry.roundedSegments([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0)])[1]
        precondition(peak.start.y * 0.25 + peak.control.y * 0.5 + peak.end.y * 0.25 == 0.75,
                     "a one-sample spike is gently rounded, not flattened away")
        precondition(segments.last!.start.y == 0 && segments.last!.end.y == 0, "idle tail stays at zero")
        precondition(TrafficPlotGeometry.roundedSegments([]).isEmpty)
        precondition(TrafficPlotGeometry.roundedSegments([.zero]).isEmpty)
        print("PASS: continuous scrolling, fixed scales, rounded joins, bounded peaks, stable history and zero baseline")
    }
}
