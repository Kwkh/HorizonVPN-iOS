import ActivityKit
import NetworkExtension

/// A bounded, user-triggered operation in the host app process. No UI instance,
/// network permission warm-up, subscription parsing or persistent timer is needed.
@MainActor final class LiveActivityPingService {
    static let shared = LiveActivityPingService()
    private var inFlight: Set<UUID> = []

    func run(sessionID: String) async {
        guard let id = UUID(uuidString: sessionID), !inFlight.contains(id),
              UserDefaults.standard.object(forKey: "connection.liveActivity") as? Bool != false,
              let activity = Activity<VPNActivityAttributes>.activities.first(where: {
                  $0.attributes.sessionID == id && !$0.attributes.isDemo && ($0.activityState == .active || $0.activityState == .stale)
              }) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences(),
              let manager = managers.first(where: {
                  ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "Kenote.Clash.PacketTunnel"
              }), let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected else {
            await finish(activity, probe: .unavailable); return
        }
        guard let before = await telemetry(session), before.sessionID == id else {
            await finish(activity, probe: .unavailable); return
        }
        let target = ActivityNodePingCommand.targetID(configurationID: before.configurationID, selections: before.groupSelections)
        guard activity.content.state.identifies(target) else {
            await finish(activity, probe: .changed); return
        }
        await finish(activity, probe: .running)
        let command = ActivityNodePingCommand(sessionID: id, targetID: target)
        guard let encoded = try? JSONEncoder().encode(command) else { return }
        let data = await message(session, data: encoded, timeout: PingReport.responseTimeout + 1, limit: 512)
        let after = await telemetry(session)
        guard session.status == .connected, after?.sessionID == id else {
            await finish(activity, probe: .unavailable); return
        }
        guard let after, target == ActivityNodePingCommand.targetID(configurationID: after.configurationID, selections: after.groupSelections),
              activity.content.state.identifies(target) else {
            // A foreground selection can already have published a new target. Never overwrite it.
            if activity.content.state.identifies(target) { await finish(activity, probe: .changed) }
            return
        }
        let report = data.flatMap { try? JSONDecoder().decode(PingReport.self, from: $0) }
        let outcome: VPNActivityAttributes.ContentState.Probe
        switch report?.outcome {
        case .success: outcome = .success
        case .timedOut, nil: outcome = .timedOut
        case .busy: outcome = .busy
        case .failed: outcome = .failed
        case .unavailable: outcome = .unavailable
        }
        await finish(activity, probe: outcome, milliseconds: report?.milliseconds)
    }

    private func finish(_ activity: Activity<VPNActivityAttributes>, probe: VPNActivityAttributes.ContentState.Probe,
                        milliseconds: Int32? = nil) async {
        guard activity.activityState == .active || activity.activityState == .stale else { return }
        var state = activity.content.state
        state.probe = probe; state.milliseconds = probe == .success ? milliseconds : nil
        state.probeStartedAt = probe == .running ? Date() : nil
        state.sampledAt = Date()
        await activity.update(ActivityContent(state: state, staleDate: state.staleDate),
                              alertConfiguration: nil, timestamp: state.sampledAt)
    }
    private func telemetry(_ session: NETunnelProviderSession) async -> LiveTelemetry? {
        guard let data = await message(session, data: Data("telemetry.v2".utf8), timeout: 3, limit: 8192),
              let sample = try? JSONDecoder().decode(LiveTelemetry.self, from: data), sample.version == 2, sample.coreReady else { return nil }
        return sample
    }
    private func message(_ session: NETunnelProviderSession, data: Data, timeout: Double, limit: Int) async -> Data? {
        guard session.status == .connected else { return nil }
        return await withCheckedContinuation { continuation in
            let reply = ActivityMessageReply(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { reply.finish(nil) }
            do {
                try session.sendProviderMessage(data) { response in
                    Task { @MainActor in reply.finish(response.flatMap { $0.count <= limit ? $0 : nil }) }
                }
            } catch { reply.finish(nil) }
        }
    }
}

@MainActor private final class ActivityMessageReply {
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func finish(_ data: Data?) { continuation?.resume(returning: data); continuation = nil }
}
