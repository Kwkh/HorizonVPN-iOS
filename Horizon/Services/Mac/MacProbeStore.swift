#if os(macOS)
import Foundation
import Observation

/// One five-slot queue shared by single-node and batch requests. Scope changes
/// cancel the native context and invalidate every outstanding completion.
@MainActor @Observable final class MacProbeStore {
    private(set) var results: [Int: BatchProbeStatus.Result] = [:]
    private(set) var running = false
    private(set) var completedCount = 0
    private(set) var targetCount = 0
    @ObservationIgnored private let testNode: (@Sendable (String) async -> Int32)?
    init(testNode: (@Sendable (String) async -> Int32)? = nil) { self.testNode = testNode }
    @ObservationIgnored private var scope = ""
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var queue = ProbeAdmissionQueue()
    @ObservationIgnored private var session: StandaloneProbeSession?
    @ObservationIgnored private var submitted: Set<Int> = []
    @ObservationIgnored private var nodes: [String] = []
    func bind(_ identity: String) {
        guard scope != identity else { return }
        cancel(); scope = identity; results = [:]; completedCount = 0; targetCount = 0
    }
    func isTesting(_ index: Int) -> Bool { results[index].map { $0.state == .testing || $0.state == .waiting } ?? false }
    func start(indices: [Int], nodes: [String]) {
        let valid = indices.filter { nodes.indices.contains($0) && !isTesting($0) }
        guard !valid.isEmpty else { return }
        if !running {
            generation = UUID(); queue = ProbeAdmissionQueue(); self.nodes = nodes
            session = testNode == nil ? StandaloneProbeSession() : nil; completedCount = 0; targetCount = 0
            running = true; submitted = []
        }
        let accepted = valid.filter { submitted.insert($0).inserted }
        guard !accepted.isEmpty else { return }
        for index in accepted { results[index] = .init(id: index, state: .waiting) }
        targetCount += accepted.count; queue.enqueue(accepted)
        pump(generation)
    }
    private func pump(_ ticket: UUID) {
        guard ticket == generation, session != nil || testNode != nil else { return }
        let session = session, testNode = testNode
        for index in queue.takeAvailable() {
            results[index] = .init(id: index, state: .testing)
            let node = nodes[index]
            Task { [weak self] in
                let delay: Int32
                if let testNode { delay = await testNode(node) }
                else { delay = await session?.test(node: node, unified: true) ?? -1 }
                guard let self, ticket == self.generation else { return }
                self.results[index] = .init(id: index, state: delay > 0 ? .success : .failed,
                    milliseconds: delay > 0 ? delay : nil, testedAt: Date())
                self.completedCount += 1; self.queue.finish(index); self.pump(ticket)
            }
        }
        if queue.isFinished { running = false; self.session = nil }
    }
    func cancel() {
        generation = UUID(); session?.cancel(); session = nil; running = false
        for index in results.keys where isTesting(index) { results[index]?.state = .cancelled }
        queue = ProbeAdmissionQueue()
    }
    func label(_ index: Int) -> String {
        guard let result = results[index] else { return "Ping" }
        switch result.state {
        case .waiting: return MacText.value("等待中", "Queued")
        case .testing: return MacText.value("测试中", "Testing")
        case .success: return "\(result.milliseconds ?? 0) ms"
        case .cancelled: return "Ping"
        default: return MacText.value("失败", "Failed")
        }
    }
}
#endif
