import Foundation
import Testing
@testable import Horizon

struct LiveActivityTests {
    @Test func targetFingerprintIsStableAndChangesWithSelection() {
        let original = ActivityNodePingCommand.targetID(configurationID: "config-a", selections: [1: 2, 0: 3])
        #expect(original == ActivityNodePingCommand.targetID(configurationID: "config-a", selections: [0: 3, 1: 2]))
        #expect(original != ActivityNodePingCommand.targetID(configurationID: "config-a", selections: [0: 4, 1: 2]))
        #expect(original != ActivityNodePingCommand.targetID(configurationID: "config-b", selections: [0: 3, 1: 2]))
        #expect(ActivityNodePingCommand.targetID(configurationID: "a", selections: nil) != ActivityNodePingCommand.targetID(configurationID: "a", selections: [:]))
    }
    @Test func commandOnlyContainsOpaqueIdentity() throws {
        let session = UUID()
        let command = ActivityNodePingCommand(sessionID: session, targetID: "digest")
        let data = try JSONEncoder().encode(command)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["kind", "sessionID", "targetID"])
        #expect(try JSONDecoder().decode(ActivityNodePingCommand.self, from: data).sessionID == session)
    }
    @Test func oldActivityDecodesWithoutInventingNodeOrResult() throws {
        let data = Data(#"{"phase":"connected","sampledAt":0,"upload":3900,"download":4700,"refreshPaused":true}"#.utf8)
        let state = try JSONDecoder().decode(VPNActivityAttributes.ContentState.self, from: data)
        #expect(state.nodeLabel == nil && state.targetID == nil && state.milliseconds == nil)
        #expect(!state.identifies("target"))
        #expect(state.probeLabel(chinese: false, stale: false) == "Ping")
    }
    @Test func timeoutAllowsRetryInsteadOfPermanentLoading() {
        let now = Date()
        let state = VPNActivityAttributes.ContentState(phase: .connected, sampledAt: now,
            nodeLabel: "Node 1", targetID: "target", probe: .running, probeStartedAt: now)
        #expect(state.staleDate == now.addingTimeInterval(15))
        #expect(state.probeLabel(chinese: false, stale: false) == "Testing")
        #expect(state.probeLabel(chinese: false, stale: true) == "Retry")
        #expect(state.probeLabel(chinese: true, stale: true) == "重试")
        #expect(state.identifies("target") && !state.identifies("another"))
    }
    @Test func nodeCardHasNoRateFieldsAndStableResult() throws {
        let state = VPNActivityAttributes.ContentState(phase: .connected, sampledAt: Date(),
            nodeLabel: "Node 1 · HYSTERIA2", targetID: "digest", probe: .success, milliseconds: 257)
        #expect(state.staleDate == nil)
        #expect(state.probeLabel(chinese: true, stale: false) == "257 ms")
        #expect(state.probeLabel(chinese: false, stale: false) == "257 ms")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        #expect(object["upload"] == nil && object["download"] == nil)
        #expect(object["nodeLabel"] as? String == "Node 1 · HYSTERIA2")
    }
}
