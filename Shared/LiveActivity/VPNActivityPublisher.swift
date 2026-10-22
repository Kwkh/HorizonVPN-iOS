import ActivityKit
import Foundation

actor VPNActivityPublisher {
    private var ended: Set<UUID> = []
    private var lastUpdate: [UUID: Date] = [:]

    func begin(session: UUID) {
        ended.remove(session)
        lastUpdate[session] = nil
    }

    @discardableResult
    func publish(session: UUID, state: VPNActivityAttributes.ContentState) async -> Bool {
        guard !ended.contains(session), state.sampledAt > (lastUpdate[session] ?? .distantPast) else { return false }
        lastUpdate[session] = state.sampledAt
        var submitted = false
        for activity in Activity<VPNActivityAttributes>.activities where activity.attributes.sessionID == session && !activity.attributes.isDemo && activity.activityState != .ended && activity.activityState != .dismissed {
            guard !ended.contains(session) else { return false }
            // Explicit sample timestamps keep independent app/extension writers ordered.
            await activity.update(ActivityContent(state: state, staleDate: state.staleDate),
                alertConfiguration: nil, timestamp: state.sampledAt)
            submitted = true
        }
        return submitted
    }

    func end(session: UUID) async {
        ended.insert(session)
        lastUpdate[session] = nil
        for activity in Activity<VPNActivityAttributes>.activities where activity.attributes.sessionID == session && !activity.attributes.isDemo {
            let state = VPNActivityAttributes.ContentState(phase: .disconnected, sampledAt: Date())
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
