import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct CloudSyncTriggerTests {
    @Test func burstEditsAreCoalesced() async throws {
        var sends = 0
        let trigger = CloudSyncTrigger { sends += 1 }
        defer { trigger.cancel() }
        for _ in 0..<10 { trigger.request(after: .milliseconds(20)) }
        try await waitUntil { sends == 1 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(sends == 1)
    }

    @Test func editDuringSendRunsOneFollowUpWithoutCancellingSend() async throws {
        var sends = 0
        var release: CheckedContinuation<Void, Never>?
        let trigger = CloudSyncTrigger {
            sends += 1
            if sends == 1 { await withCheckedContinuation { release = $0 } }
            #expect(!Task.isCancelled)
        }
        defer { trigger.cancel(); release?.resume() }
        trigger.request(after: .zero)
        try await waitUntil { release != nil }
        for _ in 0..<10 { trigger.request(after: .milliseconds(10)) }
        #expect(sends == 1)
        release?.resume(); release = nil
        try await waitUntil { sends == 2 }
        try await Task.sleep(for: .milliseconds(40))
        #expect(sends == 2)
    }

    @Test func leavingForegroundCancelsDebounceAndIgnoresLateNotification() async throws {
        var sends = 0
        let trigger = CloudSyncTrigger { sends += 1 }
        trigger.request(after: .milliseconds(30))
        trigger.cancel()
        trigger.request(after: .zero)
        try await Task.sleep(for: .milliseconds(70))
        #expect(sends == 0)
    }

    @Test func foregroundRequestDoesNotWaitForEditDebounce() async throws {
        var sends = 0
        let trigger = CloudSyncTrigger { sends += 1 }
        defer { trigger.cancel() }
        trigger.request(after: .seconds(10))
        trigger.request(after: .zero)
        try await waitUntil { sends == 1 }
    }

    @Test func onlySuccessfulLocalCommitsNotify() throws {
        try SubscriptionRepository.transaction {
            let storage = MemorySubscriptionStorage()
            let repository = SubscriptionRepository(storage: storage)
            let counter = CommitCounter()
            let observer = NotificationCenter.default.addObserver(
                forName: SubscriptionRepository.didCommitLocalChange, object: nil, queue: nil
            ) { notification in
                #expect(notification.object == nil && notification.userInfo == nil)
                counter.increment()
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            let source = Data(PrototypeSelfCheck.fixture.utf8)
            let id = try repository.add(.init(source: source), fileName: "Example.yaml",
                nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
            #expect(counter.count == 1)
            storage.failingWriteKey = SubscriptionRepository.indexKey
            #expect(throws: (any Error).self) { try repository.rename(id, title: "Failed") }
            #expect(counter.count == 1)
            storage.failingWriteKey = nil
            try repository.rename(id, title: "Renamed")
            #expect(counter.count == 2)
            let original = try repository.record(id)
            try repository.replace(id, expected: original, source: source + Data("\n# update\n".utf8),
                choices: [:], sourceURL: nil, nodeCount: 1, groupCount: 1, ruleCount: 1)
            #expect(counter.count == 3)
            try repository.activate(id)
            try repository.saveChoices([:], for: id)
            _ = try repository.cleanup()
            #expect(counter.count == 3)
            _ = try repository.delete([id])
            #expect(counter.count == 4)
            _ = try repository.delete([id])
            #expect(counter.count == 4)
        }
    }

    @Test func cloudReplicaCommitsDoNotStartAnUploadLoop() throws {
        try SubscriptionRepository.transaction {
            let storage = MemorySubscriptionStorage()
            let repository = SubscriptionRepository(storage: storage)
            let counter = CommitCounter()
            let observer = NotificationCenter.default.addObserver(
                forName: SubscriptionRepository.didCommitLocalChange, object: nil, queue: nil
            ) { _ in counter.increment() }
            defer { NotificationCenter.default.removeObserver(observer) }
            let id = UUID()
            let mutation = try repository.installReplica(id: id, title: "Replica", fileName: nil,
                record: .init(source: Data(PrototypeSelfCheck.fixture.utf8)), nodeCount: 1,
                groupCount: 1, ruleCount: 1, expectedMutation: nil, allowCurrent: false,
                expectedRecord: nil, resources: storage)
            _ = try repository.deleteReplica(id, expectedMutation: mutation, allowCurrent: false)
            #expect(counter.count == 0)
        }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate())
    }
}

nonisolated private final class CommitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}
