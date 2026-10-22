import Foundation
import Observation
import NetworkExtension

@MainActor @Observable final class BatchProbeStore {
    enum Phase { case idle, running, complete, cancelled, failed, stale }
    enum RunScope: Equatable { case allNodes, node(Int), selectedNodes }
    private(set) var runScope: RunScope?
    private(set) var phase: Phase = .idle
    private(set) var results: [BatchProbeStatus.Result] = []
    private(set) var kinds: [String] = []
    private(set) var date: Date?
    @ObservationIgnored private var scope = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var command: BatchProbeCommand?
    @ObservationIgnored private var standalone: StandaloneProbeSession?
    @ObservationIgnored private var ticket = UUID()
    private var targets: [Int] = []
    @ObservationIgnored private var admission = ProbeAdmissionQueue()
    @ObservationIgnored private var standaloneTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var preparedNodes: [String] = []
    @ObservationIgnored private var standaloneUnified = true
    func canEnqueue(_ index: Int) -> Bool {
        !isRunning || (runScope != .allNodes && !targets.contains(index))
    }
    var isRunning: Bool { phase == .running }
    var isTestingAllNodes: Bool { isRunning && runScope == .allNodes }
    func isTesting(_ index: Int) -> Bool { isRunning && targets.contains(index) && results.indices.contains(index) && [.waiting, .testing].contains(results[index].state) }
    var targetCount: Int { targets.count }
    var finishedCount: Int {
        targets.filter { results.indices.contains($0) && ![.waiting, .testing].contains(results[$0].state) }.count
    }

    /// Node choice is excluded from the scope; a different subscription/version is not.
    func bind(scope: String, catalog: ConfigurationCatalog?, using tunnel: TunnelController) {
        guard self.scope != scope || kinds != (catalog?.nodes.map(\.kind) ?? []) else { return }
        cancel(using: tunnel)
        self.scope = scope; phase = .idle; date = nil
        runScope = nil; targets = []
        kinds = catalog?.nodes.map(\.kind) ?? []
        results = kinds.indices.map { .init(id: $0, state: .waiting) }
    }
    func start(using tunnel: TunnelController, node: Int? = nil) {
        guard (node == nil ? tunnel.canTestBatch : tunnel.canEnqueueNodeProbe), let catalog = tunnel.catalog,
              node.map({ catalog.nodes.indices.contains($0) }) ?? true,
              tunnel.authorizeProbe(node.map { .node($0) } ?? .batch) else { return }
        if isRunning {
            guard let node, canEnqueue(node) else { return }
            targets.append(node); runScope = .selectedNodes
            results[node] = .init(id: node, state: .waiting)
            admission.enqueue([node])
            pumpStandalone(id: ticket)
            return
        }
        admission = ProbeAdmissionQueue(); preparedNodes = []
        runScope = node.map { .node($0) } ?? .allNodes
        let id = UUID(); ticket = id; phase = .running; date = Date()
        targets = node.map { [$0] } ?? Array(catalog.nodes.indices)
        admission.enqueue(targets)
        for i in targets { results[i] = .init(id: i, state: .waiting) }
        task = Task { [weak self, weak tunnel] in
            guard let self, let tunnel else { return }
            if tunnel.status != .connected {
                await runStandalone(tunnel, id: id)
                return
            }
            var start: BatchProbeCommand?
            var action = BatchProbeCommand.Action.start
            while ticket == id, !Task.isCancelled {
                if start == nil {
                    // Selection commits runtime and storage separately. Wait asynchronously for
                    // that transaction before binding a new batch to its initial identity.
                    if tunnel.isSwitchingNode {
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                        continue
                    }
                    guard let sample = await tunnel.liveSample() else {
                        if tunnel.isSwitchingNode { continue }
                        fail(id); return
                    }
                    guard ticket == id, !Task.isCancelled else { return }
                    start = BatchProbeCommand(version: 3, action: .start, batchID: id,
                        sessionID: sample.sessionID, configurationID: sample.configurationID, nodeIndices: targets)
                }
                guard let snapshot = start else { return }
                let submitted = targets
                let request = BatchProbeCommand(version: snapshot.version, action: action, batchID: id,
                    sessionID: snapshot.sessionID, configurationID: snapshot.configurationID, nodeIndices: submitted)
                command = request
                let payload = try? JSONEncoder().encode(request)
                let data = await payload.asyncFlatMap { await tunnel.engineMessage($0, limit: 32768) }
                guard ticket == id, !Task.isCancelled else { return }
                guard let data, let reply = try? JSONDecoder().decode(BatchProbeStatus.self, from: data) else {
                    cancel(using: tunnel); phase = .failed; return
                }
                // A selector can change after telemetry but before the first start reaches the
                // provider. No batch exists yet; retry against the committed selection. Once
                // accepted, keep the original identity for enqueue/poll/cancel throughout.
                if action == .start, reply.phase == .unavailable, reply.results.isEmpty,
                   reply.version == snapshot.version, reply.batchID == id, reply.sessionID == snapshot.sessionID,
                   reply.configurationID != snapshot.configurationID,
                   tunnel.isSwitchingNode || tunnel.configurationID != snapshot.configurationID {
                    command = nil; start = nil
                    continue
                }
                guard request.matches(reply),
                      reply.results.count == kinds.count,
                      reply.results.enumerated().allSatisfy({ $0.offset == $0.element.id &&
                          ($0.element.state != .success || (1..<PingReport.timeoutMilliseconds).contains($0.element.milliseconds ?? -1)) }) else {
                    cancel(using: tunnel); phase = .failed; return
                }
                for i in submitted { results[i] = reply.results[i] }
                switch reply.phase {
                case .complete:
                    if submitted == targets { phase = .complete; command = nil; return }
                case .cancelled: phase = .cancelled; command = nil; return
                case .busy, .unavailable: fail(id); command = nil; return
                case .running: break
                }
                action = .enqueue
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
    private func runStandalone(_ tunnel: TunnelController, id: UUID) async {
        do {
            let nodes = try await tunnel.standaloneNodes()
            guard ticket == id, !Task.isCancelled else { return }
            preparedNodes = nodes
            standalone = StandaloneProbeSession()
            standaloneUnified = tunnel.unifiedDelay
            pumpStandalone(id: id)
        } catch { fail(id) }
    }
    private func pumpStandalone(id: UUID) {
        guard ticket == id, isRunning, let session = standalone else { return }
        for index in admission.takeAvailable() {
            guard preparedNodes.indices.contains(index) else { fail(id); return }
            results[index].state = .testing
            let raw = preparedNodes[index], unified = standaloneUnified
            standaloneTasks[index] = Task { [weak self] in
                let delay = await session.test(node: raw, unified: unified)
                guard let self, ticket == id, !Task.isCancelled else { return }
                standaloneTasks[index] = nil
                admission.finish(index)
                results[index] = Self.result(index: index, delay: delay)
                pumpStandalone(id: id)
            }
        }
        if admission.isFinished {
            standalone = nil; preparedNodes = []; phase = .complete
        }
    }
    static func result(index: Int, delay: Int32) -> BatchProbeStatus.Result {
        let state: BatchProbeStatus.State = delay == -2 ? .cancelled :
            (delay == -3 || delay >= PingReport.timeoutMilliseconds) ? .timedOut : delay > 0 ? .success : .failed
        return .init(id: index, state: state, milliseconds: state == .success ? delay : nil, testedAt: Date())
    }
    private func fail(_ id: UUID) {
        guard ticket == id, !Task.isCancelled else { return }
        phase = .failed
        standalone?.cancel(); standalone = nil
        for task in standaloneTasks.values { task.cancel() }
        standaloneTasks = [:]; preparedNodes = []
        for i in targets where results.indices.contains(i) && [.waiting, .testing].contains(results[i].state) { results[i].state = .failed }
    }
    func cancel(using tunnel: TunnelController) {
        let old = command
        ticket = UUID(); task?.cancel(); task = nil; command = nil
        standalone?.cancel(); standalone = nil
        for task in standaloneTasks.values { task.cancel() }
        standaloneTasks = [:]; preparedNodes = []; admission = ProbeAdmissionQueue()
        if isRunning {
            phase = .cancelled
            for i in targets where results.indices.contains(i) && [.waiting, .testing].contains(results[i].state) { results[i].state = .cancelled }
        }
        if let old {
            let request = BatchProbeCommand(version: old.version, action: .cancel, batchID: old.batchID,
                sessionID: old.sessionID, configurationID: old.configurationID, nodeIndex: old.nodeIndex, nodeIndices: old.nodeIndices)
            Task { if let data = try? JSONEncoder().encode(request) { _ = await tunnel.engineMessage(data, limit: 32768) } }
        }
    }
    func invalidate(using tunnel: TunnelController) { cancel(using: tunnel) }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
