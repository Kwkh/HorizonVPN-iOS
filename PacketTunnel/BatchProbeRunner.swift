import Foundation
import Hako

/// Accessed only on the provider lifecycle queue. Raw names never cross IPC.
final class BatchProbeRunner {
    private let queue: DispatchQueue
    private let names: [String]
    private let native: HakoCancellableURLTests?
    private var admission = ProbeAdmissionQueue()
    private var lease: DispatchWorkItem?
    private(set) var status: BatchProbeStatus

    init(command: BatchProbeCommand, names: [String], queue: DispatchQueue) {
        self.queue = queue; self.names = names
        admission.enqueue(command.nodeIndices ?? command.nodeIndex.map { [$0] } ?? Array(names.indices))
        native = HakoNewCancellableURLTests(ProbeAdmissionQueue.limit)
        status = .init(version: command.version, batchID: command.batchID, sessionID: command.sessionID,
            configurationID: command.configurationID, phase: .running,
            results: names.indices.map { .init(id: $0, state: .waiting) })
    }
    func start() {
        guard native != nil else { status.phase = .unavailable; return }
        renewLease(); pump()
    }
    func enqueue(_ indices: [Int]) {
        guard status.phase == .running || status.phase == .complete else { return }
        admission.enqueue(indices)
        if !admission.isFinished { status.phase = .running }
        renewLease(); pump()
    }
    func renewLease() {
        guard status.phase == .running else { return }
        lease?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        lease = work
        queue.asyncAfter(deadline: .now() + 15, execute: work)
    }
    func cancel() {
        lease?.cancel(); lease = nil
        native?.cancel()
        guard status.phase == .running else { return }
        status.phase = .cancelled
        for i in status.results.indices where [.waiting, .testing].contains(status.results[i].state) {
            status.results[i].state = .cancelled
        }
    }
    private func pump() {
        guard status.phase == .running, let native else { return }
        for index in admission.takeAvailable() {
            status.results[index].state = .testing
            let name = names[index], native = native
            DispatchQueue.global(qos: .utility).async { [self] in
                let delay = native.test(name, url: PingReport.testURL, timeoutMillis: PingReport.timeoutMilliseconds)
                queue.async { [self] in
                    admission.finish(index)
                    guard status.phase == .running else { return }
                    let state: BatchProbeStatus.State = delay == -2 ? .cancelled :
                        (delay == -3 || delay >= PingReport.timeoutMilliseconds) ? .timedOut : delay > 0 ? .success : .failed
                    status.results[index] = .init(id: index, state: state,
                        milliseconds: state == .success ? delay : nil, testedAt: Date())
                    pump()
                }
            }
        }
        if admission.isFinished {
            status.phase = .complete; lease?.cancel(); lease = nil
        }
    }
    deinit { native?.cancel(); lease?.cancel() }
}
