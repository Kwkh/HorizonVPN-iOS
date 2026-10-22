import Testing
import Foundation
@testable import Horizon

struct ProbeAdmissionQueueTests {
    @Test func batchSnapshotSurvivesSelectionButRejectsStaleSessionsAndNewStarts() {
        let session = UUID(), batchID = UUID()
        let status = BatchProbeStatus(version: 3, batchID: batchID, sessionID: session,
            configurationID: "before-selection", phase: .running,
            results: [.init(id: 0, state: .success, milliseconds: 15), .init(id: 1, state: .testing)])
        func command(_ action: BatchProbeCommand.Action, id: UUID = batchID,
                     sessionID: UUID = session, configuration: String = "before-selection", version: Int = 3) -> BatchProbeCommand {
            .init(version: version, action: action, batchID: id, sessionID: sessionID,
                configurationID: configuration, nodeIndices: [0, 1])
        }
        func valid(_ command: BatchProbeCommand, currentSession: UUID = session) -> Bool {
            command.isValid(nodeCount: 2, sessionID: currentSession,
                configurationID: "after-selection", batch: status)
        }
        // Includes an idempotent retry of the initial start, plus cancelling after selection.
        for action in [BatchProbeCommand.Action.start, .poll, .enqueue, .cancel] {
            #expect(valid(command(action)))
            #expect(!valid(command(action, configuration: "after-selection")))
            #expect(!valid(command(action, sessionID: UUID())))
            #expect(!valid(command(action), currentSession: UUID()))
            #expect(!valid(command(action, version: 2)))
        }
        #expect(!valid(command(.start, id: UUID())))
        #expect(valid(command(.start, id: UUID(), configuration: "after-selection")))
        #expect(!valid(command(.enqueue, id: UUID(), configuration: "after-selection")))
        #expect(!command(.poll).isValid(nodeCount: 2, sessionID: session,
            configurationID: "after-selection", batch: nil))
        #expect(!command(.start).isValid(nodeCount: 2, sessionID: session,
            configurationID: "after-selection", batch: nil))
    }
    @Test func sixthNodeWaitsAndNewClicksUseFreeSlots() {
        var queue = ProbeAdmissionQueue()
        queue.enqueue([0])
        #expect(queue.takeAvailable() == [0])
        queue.enqueue([1, 2, 3, 4, 5, 6])
        #expect(queue.takeAvailable() == [1, 2, 3, 4])
        #expect(queue.active.count == 5)
        #expect(queue.takeAvailable().isEmpty)
        queue.finish(2)
        #expect(queue.takeAvailable() == [5])
        queue.finish(3)
        #expect(queue.takeAvailable() == [6])
        #expect(queue.active.count == 5)
    }
    @Test func repeatedRequestsNeverRestartFinishedNodes() {
        var queue = ProbeAdmissionQueue()
        queue.enqueue([0, 0, 1])
        #expect(queue.takeAvailable() == [0, 1])
        queue.finish(0); queue.finish(1)
        #expect(queue.isFinished)
        queue.enqueue([0, 1, 2]) // cumulative IPC snapshot after completion
        #expect(queue.takeAvailable() == [2])
        #expect(!queue.isFinished)
    }
    @Test func commandsValidateDynamicQueueAndLegacyVersions() throws {
        let id = UUID()
        func command(_ indices: [Int]) -> BatchProbeCommand {
            .init(version: 3, action: .enqueue, batchID: id, sessionID: id,
                  configurationID: "fixture", nodeIndices: indices)
        }
        #expect(command([0, 1, 5]).isSupported(nodeCount: 6))
        for indices in [[], [0, 0], [-1], [6]] {
            #expect(!command(indices).isSupported(nodeCount: 6))
        }
        let original = command([0, 2])
        let decoded = try JSONDecoder().decode(BatchProbeCommand.self, from: JSONEncoder().encode(original))
        #expect(decoded.nodeIndices == [0, 2] && decoded.isSupported(nodeCount: 6))
        var legacy = BatchProbeCommand(version: 2, action: .start, batchID: id, sessionID: id,
                                       configurationID: "fixture", nodeIndex: 0)
        #expect(legacy.isSupported(nodeCount: 1))
        legacy.nodeIndices = [0]
        #expect(!legacy.isSupported(nodeCount: 1))
    }
}
