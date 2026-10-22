import Foundation
import CoreGraphics

/// Presentation-only math. Measured values and the numeric readout are never smoothed.
enum TrafficPlotGeometry {
    static let window: Double = 60
    // Keep the next segment available before revealing it at the right edge.
    static let presentationDelay: Double = 2.5
    static let logarithmicCeiling: Double = 10 * 1024 * 1024

    static func x(uptime: Double, end: Double, width: Double) -> Double {
        width * (1 + (uptime - end) / window)
    }

    static func normalizedHeight(rate: Double, ceiling: Double, logarithmicWeight: Double = 0) -> Double {
        guard rate.isFinite, ceiling.isFinite, ceiling > 0 else { return 0 }
        let value = max(0, rate)
        let linear = min(1, value / ceiling)
        let logarithmic = min(1, log1p(value) / log1p(logarithmicCeiling))
        let weight = min(1, max(0, logarithmicWeight))
        return linear + (logarithmic - linear) * weight
    }

    /// Only explicit user scale changes animate; traffic never changes these parameters.
    struct Axis {
        struct Value: Equatable {
            var ceiling: Double = 1_000_000
            var logarithmicWeight: Double = 0
        }
        private var from = Value()
        private var to = Value()
        private var changedAt: Double?

        func value(at now: Double) -> Value {
            guard let changedAt else { return to }
            let t = min(1, max(0, (now - changedAt) / 0.3))
            if t == 1 { return to }
            let p = t * t * (3 - 2 * t)
            return Value(ceiling: exp(log(from.ceiling) + (log(to.ceiling) - log(from.ceiling)) * p),
                         logarithmicWeight: from.logarithmicWeight + (to.logarithmicWeight - from.logarithmicWeight) * p)
        }

        mutating func select(ceiling: Double, logarithmic: Bool, at now: Double, animated: Bool) {
            let next = Value(ceiling: ceiling, logarithmicWeight: logarithmic ? 1 : 0)
            guard next != to else {
                if !animated { changedAt = nil }
                return
            }
            from = value(at: now)
            to = next
            changedAt = animated ? now : nil
        }
    }

    struct RoundedSegment: Equatable {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
    }

    /// Work in seconds, before projecting to pixels. Idle spans need nearby zero
    /// controls at BOTH ends: using the far end of a long idle interval as a
    /// neighbour stretches a rounded corner, and reconnecting reshapes that corner.
    static func plotVertices(_ samples: [CGPoint], baseline: Double, end: Double) -> [CGPoint] {
        guard let first = samples.first, let last = samples.last else {
            return [CGPoint(x: end - window - 2, y: baseline), CGPoint(x: end + 120, y: baseline)]
        }
        var anchors = samples
        // Only a display continuation. It is never used for numeric readings.
        if last.y != baseline { anchors.append(CGPoint(x: last.x + 3.5, y: baseline)) }
        anchors.append(CGPoint(x: max(last.x + 120, end + 120), y: baseline))
        var result = [CGPoint(x: min(first.x - 2, end - window - 2), y: baseline)]
        result.append(CGPoint(x: first.x - 1, y: baseline))
        for next in anchors {
            if let previous = result.last, previous.y == baseline, next.y == baseline,
               next.x - previous.x > 2 {
                result.append(CGPoint(x: previous.x + 1, y: baseline))
                result.append(CGPoint(x: next.x - 1, y: baseline))
            }
            if next.x > result.last!.x { result.append(next) }
        }
        return result
    }

    /// Midpoint quadratic smoothing rounds peaks without overshoot. Only the plot is
    /// softened; measured rates remain untouched. Each mature segment uses three
    /// adjacent samples, so new readings cannot reshape visible history.
    static func roundedSegments(_ points: [CGPoint]) -> [RoundedSegment] {
        guard points.count > 1 else { return [] }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) / 2, y: a.y + (b.y - a.y) / 2)
        }
        return points.indices.map { i in
            RoundedSegment(
                start: i == 0 ? points[i] : midpoint(points[i - 1], points[i]),
                control: points[i],
                end: i == points.count - 1 ? points[i] : midpoint(points[i], points[i + 1]))
        }
    }
}
