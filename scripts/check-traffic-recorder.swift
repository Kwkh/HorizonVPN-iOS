import Foundation

@main struct CheckTrafficRecorder {
    static func main() {
        let queue = DispatchQueue(label: "synthetic.traffic-recorder")
        let recorder = TunnelTrafficRecorder()
        let session = UUID()
        var sequence: Double = 100
        func reading() -> LiveTelemetry {
            defer { sequence += 1 }
            return LiveTelemetry(version: 2, sessionID: session, configurationID: "SYNTHETIC",
                sampledAt: Date(timeIntervalSince1970: sequence), uptime: sequence,
                connectedAt: Date(timeIntervalSince1970: 0), uploadBytes: Int64(sequence * 1000),
                downloadBytes: Int64(sequence * 2000), coreReady: true, transport: "wifi")
        }
        func waitForQueue(_ seconds: Double, _ check: @escaping () -> Void) {
            let done = DispatchSemaphore(value: 0)
            queue.asyncAfter(deadline: .now() + seconds) { check(); done.signal() }
            precondition(done.wait(timeout: .now() + seconds + 3) == .success)
        }
        queue.sync { recorder.start(on: queue, sample: { reading() }) }
        waitForQueue(2.3) {
            precondition(recorder.samples.count >= 3, "samples continue without any App polling")
            recorder.stop()
            precondition(recorder.samples.isEmpty)
        }
        waitForQueue(1.2) { precondition(recorder.samples.isEmpty, "stop cancels future callbacks") }
        queue.sync {
            recorder.start(on: queue, sample: { reading() })
            precondition(recorder.samples.count == 1, "new session starts a fresh buffer")
            recorder.catchUp { reading() }
            precondition(recorder.samples.count == 1, "normal IPC polling does not double sample cadence")
            sequence += 10
            recorder.catchUp { reading() }
            precondition(recorder.samples.count == 2, "timer delay stores only an actual reading")
            recorder.stop()
        }
        print("PASS: recorder samples without App polling, stops and resets, avoids duplicate polling samples, and catches up without fabricated readings; synthetic counters only")
    }
}
