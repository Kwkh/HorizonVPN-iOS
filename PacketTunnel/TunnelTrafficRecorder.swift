import Foundation

/// All methods and the sampling callback run on the provider lifecycle queue.
/// No persistence, requests, or UI activity is needed to retain the latest minute.
final class TunnelTrafficRecorder {
    private var timer: DispatchSourceTimer?
    private var buffer = TelemetryHistoryBuffer()
    private var generation = UUID()

    var samples: [LiveTelemetry] { buffer.samples }

    func start(on queue: DispatchQueue, sample: @escaping () -> LiveTelemetry?) {
        stop()
        let ticket = generation
        if let value = sample() { buffer.append(value) }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == ticket, let value = sample() else { return }
            self.buffer.append(value)
        }
        self.timer = timer
        timer.resume()
    }

    /// Handles a delayed timer without inventing intermediate samples.
    func catchUp(_ sample: () -> LiveTelemetry?) {
        guard let value = sample() else { return }
        if let last = buffer.samples.last,
           last.sessionID == value.sessionID,
           last.configurationID == value.configurationID,
           value.uptime - last.uptime < 3.5 { return }
        buffer.append(value)
    }

    func stop() {
        generation = UUID()
        timer?.cancel(); timer = nil
        buffer.reset()
    }
    deinit { timer?.cancel() }
}
