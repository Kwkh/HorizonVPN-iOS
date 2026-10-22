import Foundation

/// One admission policy for connected and standalone probes. A node is submitted
/// once per run; queued additions never restart work already in flight.
struct ProbeAdmissionQueue {
    static let limit = 5
    private var pending: [Int] = []
    private var submitted: Set<Int> = []
    private(set) var active: Set<Int> = []
    var isFinished: Bool { pending.isEmpty && active.isEmpty }
    mutating func enqueue(_ indices: [Int]) {
        for index in indices where submitted.insert(index).inserted { pending.append(index) }
    }
    mutating func takeAvailable() -> [Int] {
        let count = min(Self.limit-active.count, pending.count)
        let next = Array(pending.prefix(count))
        pending.removeFirst(count)
        active.formUnion(next)
        return next
    }
    mutating func finish(_ index: Int) { active.remove(index) }
}
