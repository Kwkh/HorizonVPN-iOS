#if DEBUG
import Foundation

/// Opt-in timing evidence only; never stores samples, configuration names or credentials.
struct TrafficPlotMetrics {
    private let enabled = ProcessInfo.processInfo.environment["CLASH_CHART_METRICS"] == "1"
    private var costs: [Double] = []
    private var intervals: [Double] = []
    private var previous: Double?
    private var reported = false
    private var delayedCallbacks = 0
    mutating func pause() { previous = nil }
    mutating func record(renderSeconds: Double, timestamp: Double, interval: Double) {
        guard enabled, !reported else { return }
        costs.append(renderSeconds * 1000)
        if let previous, timestamp > previous {
            intervals.append((timestamp - previous) * 1000)
            if timestamp - previous > interval * 1.5 { delayedCallbacks += 1 }
        }
        previous = timestamp
        guard costs.count >= 1800 else { return }
        reported = true
        let sorted = costs.sorted(), frames = intervals.sorted()
        let report: [String: Any] = ["frames": costs.count,
            "renderMedianMilliseconds": sorted[sorted.count / 2],
            "renderP95Milliseconds": sorted[Int(Double(sorted.count - 1) * 0.95)],
            "renderMaximumMilliseconds": sorted.last ?? 0,
            "callbackMedianMilliseconds": frames.isEmpty ? 0 : frames[frames.count / 2],
            "callbackP95Milliseconds": frames.isEmpty ? 0 : frames[Int(Double(frames.count - 1) * 0.95)],
            "callbackMaximumMilliseconds": frames.last ?? 0,
            "callbacksOverOneAndHalfIntervals": delayedCallbacks,
            "note": "Display-link callback timing; not a compositor FPS or Instruments trace."]
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("traffic-plot-metrics.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys) {
            try? data.write(to: file, options: .atomic)
        }
        costs.removeAll(); intervals.removeAll()
    }
}
#endif
