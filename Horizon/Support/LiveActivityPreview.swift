#if DEBUG
import ActivityKit
import Foundation
import OSLog

/// Simulator-only visual fixture. Does not create a VPN profile or make requests.
@MainActor enum LiveActivityPreview {
    /// Exercise the real system intent route without touching a tunnel or network.
    static func handlePing(sessionID: String) async -> Bool {
        #if targetEnvironment(simulator)
        let activities = Activity<VPNActivityAttributes>.activities
        Logger(subsystem: "Kenote.Clash", category: "LiveActivityPing")
            .info("Offline probe: valid session \(UUID(uuidString: sessionID) != nil), activities \(activities.count), matching \(activities.contains { $0.attributes.sessionID.uuidString == sessionID })")
        guard let id = UUID(uuidString: sessionID),
              let activity = activities.first(where: {
                  $0.attributes.isDemo && $0.attributes.sessionID == id
              }) else { return false }
        var state = activity.content.state
        state.milliseconds = (state.milliseconds ?? 0) + 1
        state.probe = .success
        state.sampledAt = Date()
        await activity.update(ActivityContent(state: state, staleDate: nil),
                              alertConfiguration: nil, timestamp: state.sampledAt)
        return true
        #else
        return false
        #endif
    }

    static func runIfRequested() async {
        #if targetEnvironment(simulator)
        for activity in Activity<VPNActivityAttributes>.activities where activity.attributes.isDemo {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard ProcessInfo.processInfo.environment["CLASH_ACTIVITY_PREVIEW"] == "1" else { return }
        let state = VPNActivityAttributes.ContentState(phase: .connected, sampledAt: Date(), nodeLabel: "DEMO · Offline counter", targetID: "preview", probe: .idle, milliseconds: 0)
        guard let activity = try? Activity.request(attributes: VPNActivityAttributes(sessionID: UUID(), chinese: false, isDemo: true),
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(300)), pushType: nil) else { return }
        try? await Task.sleep(for: .seconds(300))
        await activity.end(nil, dismissalPolicy: .immediate)
        #endif
    }
}
#endif
