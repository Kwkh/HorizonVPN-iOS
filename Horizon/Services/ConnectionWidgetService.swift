import Foundation
import NetworkExtension

@MainActor final class ConnectionWidgetService {
    static let shared = ConnectionWidgetService()
    weak var controller: TunnelController?
    private var running = false
    enum Failure: LocalizedError {
        case setupRequired, busy, failed
        var errorDescription: String? {
            switch self {
            case .setupRequired: String(localized: "Open HORIZON to complete VPN setup.")
            case .busy: String(localized: "A connection change is already in progress.")
            case .failed: String(localized: "Unable to complete the connection change. Open HORIZON to check its status.")
            }
        }
    }
    func setConnected(_ desired: Bool) async throws {
        guard !running else { throw Failure.busy }
        running = true
        defer { running = false }
        if !desired {
            try await disconnect()
            return
        }
        let tunnel = controller ?? TunnelController()
        guard !tunnel.isBusy else { throw Failure.busy }
        await tunnel.refresh()
        // Refresh failure must not operate on an old manager/configuration.
        guard tunnel.lastRefreshSucceeded else { throw Failure.setupRequired }
        if [.connected, .reasserting].contains(tunnel.status) {
            await synchronizeActivity(tunnel)
            return
        }
        guard ![.connecting, .disconnecting].contains(tunnel.status) else { throw Failure.busy }
        guard tunnel.profileReady, tunnel.hasConfiguration else { throw Failure.setupRequired }
        tunnel.network.startMonitoring()
        await tunnel.connectCurrentProfile()
        if tunnel.certificateApproval != nil { throw Failure.setupRequired }
        // Keep the host alive for a bounded user action; never report success just
        // because startVPNTunnel accepted the request. Existing startup recovery runs here too.
        for _ in 0..<120 {
            try Task.checkCancellation()
            tunnel.refreshWidgetConnectionStatus()
            if tunnel.status == .connected && !tunnel.isBusy {
                await synchronizeActivity(tunnel)
                return
            }
            if !tunnel.isBusy && !tunnel.isAwaitingConnectionStatus && tunnel.status == .disconnected {
                await synchronizeActivity(tunnel)
                throw Failure.failed
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw Failure.failed
    }
    private func synchronizeActivity(_ tunnel: TunnelController) async {
        // Called inside LiveActivityIntent.perform, including when the app has no visible scene.
        await VPNLiveActivityController.shared.synchronize(tunnel: tunnel, settings: AppSettings())
    }
    private func disconnect() async throws {
        // Disconnect must remain possible even if the saved subscription no longer parses.
        let profiles = try await NETunnelProviderManager.loadAllFromPreferences().filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "Kenote.Clash.PacketTunnel"
        }
        guard profiles.count <= 1 else { throw Failure.setupRequired }
        guard let profile = profiles.first else {
            ConnectionWidgetState.publish(phase: .unavailable)
            await VPNLiveActivityController.shared.endAll()
            return
        }
        if [.invalid, .disconnected].contains(profile.connection.status) {
            ConnectionWidgetState.publish(phase: .disconnected)
            await VPNLiveActivityController.shared.endAll()
            return
        }
        // Cancel the foreground controller's revision recovery as well as the system session.
        if let controller, controller.canStop { controller.stop() }
        profile.connection.stopVPNTunnel()
        ConnectionWidgetState.publish(phase: .disconnecting)
        for _ in 0..<80 {
            try Task.checkCancellation()
            if [.invalid, .disconnected].contains(profile.connection.status) {
                ConnectionWidgetState.publish(phase: .disconnected)
                await VPNLiveActivityController.shared.endAll()
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw Failure.failed
    }

}
