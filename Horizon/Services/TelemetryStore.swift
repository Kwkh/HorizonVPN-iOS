import Foundation
import Observation

@MainActor @Observable final class TelemetryStore {
    private(set) var window = TrafficWindow()
    private(set) var sample: LiveTelemetry?
    private(set) var stale = true
    private(set) var awaitingHistory = true
    @ObservationIgnored private var owner = UUID()
    #if DEBUG
    @ObservationIgnored private var metrics = TelemetryMetrics()
    #endif

    func collect(from tunnel: TunnelController) async {
        let ticket = UUID(); owner = ticket
        #if DEBUG
        metrics.started()
        #endif
        window.invalidate(); stale = true; awaitingHistory = true
        defer {
            #if DEBUG
            metrics.stopped()
            #endif
            if owner == ticket { stale = true; awaitingHistory = true; window.invalidate() }
        }
        while !Task.isCancelled, owner == ticket {
            if let history = await tunnel.liveHistory(), !Task.isCancelled, owner == ticket,
               window.restore(history, now: ProcessInfo.processInfo.systemUptime) {
                sample = history.latest; stale = window.current == nil; awaitingHistory = false
            } else if !Task.isCancelled, owner == ticket {
                awaitingHistory = false
                window.missedPoll(at: ProcessInfo.processInfo.systemUptime)
                stale = window.current == nil
            }
            #if DEBUG
            metrics.polled(hasRate: window.current != nil)
            #endif
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
    }
    func disconnect() {
        window.baseline(); sample = nil; stale = true; awaitingHistory = false
    }
}
