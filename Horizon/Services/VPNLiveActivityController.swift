import ActivityKit
import NetworkExtension
import Observation

@MainActor @Observable final class VPNLiveActivityController {
    static let shared = VPNLiveActivityController()
    @ObservationIgnored private var synchronizing = false
    @ObservationIgnored private var lifecycleGeneration = 0
    private(set) var unavailable = false
    @ObservationIgnored private var attemptedSession: UUID?
    @ObservationIgnored private let publisher = VPNActivityPublisher()

    func endAll() async {
        lifecycleGeneration += 1
        for activity in Activity<VPNActivityAttributes>.activities where !activity.attributes.isDemo {
            await publisher.end(session: activity.attributes.sessionID)
        }
        attemptedSession = nil
    }

    func synchronize(tunnel: TunnelController, settings: AppSettings) async {
        // MainActor is reentrant across telemetry/ActivityKit awaits. Queue a second
        // caller rather than dropping the intent's only background synchronization.
        while synchronizing {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        let generation = lifecycleGeneration
        synchronizing = true
        defer { synchronizing = false }
        let activities = Activity<VPNActivityAttributes>.activities.filter { !$0.attributes.isDemo }
        guard settings.liveActivityEnabled else {
            for activity in activities { await publisher.end(session: activity.attributes.sessionID) }
            attemptedSession = nil; unavailable = false
            return
        }
        guard tunnel.didFinishInitialRefresh else { return }
        if [.invalid, .disconnected, .disconnecting].contains(tunnel.status) {
            for activity in activities { await publisher.end(session: activity.attributes.sessionID) }
            attemptedSession = nil
            return
        }
        if tunnel.status == .reasserting {
            for activity in activities where activity.content.state.phase != .reconnecting {
                var state = activity.content.state
                state.phase = .reconnecting; state.probe = .unavailable; state.milliseconds = nil
                state.probeStartedAt = nil; state.sampledAt = Date()
                await publisher.publish(session: activity.attributes.sessionID, state: state)
            }
            return
        }
        guard tunnel.status == .connected, let sample = await tunnel.liveSample(),
              tunnel.status == .connected, generation == lifecycleGeneration, !Task.isCancelled else { return }
        for activity in activities where activity.attributes.sessionID != sample.sessionID {
            await publisher.end(session: activity.attributes.sessionID)
        }
        unavailable = !ActivityAuthorizationInfo().areActivitiesEnabled
        guard !unavailable else { return }
        let label: String
        if let catalog = tunnel.catalog, let node = tunnel.selectedNode {
            label = String(settings.nodeLabel(catalog, name: node).prefix(160))
        } else { label = settings.text("由策略组选择", "Selected by policy group") }
        let target = ActivityNodePingCommand.targetID(configurationID: sample.configurationID, selections: sample.groupSelections)
        let existing = activities.first { $0.attributes.sessionID == sample.sessionID && $0.activityState != .ended && $0.activityState != .dismissed }
        if let existing {
            var state = existing.content.state
            if !state.identifies(target) {
                state.probe = .idle; state.milliseconds = nil; state.probeStartedAt = nil
            }
            if state.probe == .running, let started = state.probeStartedAt, Date().timeIntervalSince(started) > 15 {
                state.probe = .timedOut; state.probeStartedAt = nil
            }
            state.phase = .connected; state.nodeLabel = label; state.targetID = target
            guard state != existing.content.state else { return }
            state.sampledAt = Date()
            await publisher.publish(session: sample.sessionID, state: state)
        } else {
            // Respect a user dismissal until reconnect or toggle.
            guard attemptedSession != sample.sessionID else { return }
            await publisher.begin(session: sample.sessionID)
            guard !Task.isCancelled, generation == lifecycleGeneration, tunnel.status == .connected else { return }
            attemptedSession = sample.sessionID
            do {
                _ = try Activity.request(attributes: VPNActivityAttributes(sessionID: sample.sessionID, chinese: settings.isChinese),
                    content: ActivityContent(state: .init(phase: .connected, sampledAt: Date(), nodeLabel: label,
                        targetID: target, probe: .idle), staleDate: nil), pushType: nil)
            } catch { unavailable = true }
        }
    }
}
