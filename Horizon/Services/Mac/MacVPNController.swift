#if os(macOS)
import Foundation
import NetworkExtension
import Observation

@MainActor @Observable final class MacVPNController {
    private(set) var status: NEVPNStatus = .disconnected
    private(set) var working = false
    private var connectionEpoch = UUID()
    private var manager: NETunnelProviderManager?
    private let offline: Bool
    @ObservationIgnored private var observer: NSObjectProtocol?
    static let providerID = "Kenote.Clash.MacPacketTunnel"

    init(offline: Bool) {
        self.offline = offline
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let next = self.manager?.connection.status ?? .disconnected
                if next != self.status { self.connectionEpoch = UUID(); self.status = next }
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    var isIdle: Bool { status == .disconnected || status == .invalid }
    var title: String {
        switch status {
        case .connected: MacText.value("已连接", "Connected")
        case .connecting: MacText.value("连接中", "Connecting")
        case .reasserting: MacText.value("重新连接中", "Reconnecting")
        case .disconnecting: MacText.value("断开连接中", "Disconnecting")
        default: MacText.value("未连接", "Disconnected")
        }
    }
    func load() async throws {
        guard !offline else { return }
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerID }
        status = manager?.connection.status ?? .disconnected
    }
    /// Only the explicit Connect action creates/enables a profile or starts a tunnel.
    func connect() async throws {
        guard !offline, isIdle, !working else { return }
        working = true; defer { working = false }
        try await load()
        guard isIdle else { return }
        let current = manager ?? NETunnelProviderManager()
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = Self.providerID
        configuration.providerConfiguration = ["purpose": PrototypeConfiguration.policyVersion]
        configuration.serverAddress = "Horizon"
        configuration.disconnectOnSleep = false
        current.protocolConfiguration = configuration
        current.localizedDescription = "Horizon"
        current.isEnabled = true
        try await current.saveToPreferences()
        try await current.loadFromPreferences()
        guard current.isEnabled,
              (current.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerID else { throw PrototypeError.start }
        manager = current
        try current.connection.startVPNTunnel()
        // startVPNTunnel only submits the request. PlugInKit can reject the
        // extension asynchronously, even before SwiftUI sees Connecting.
        do { try await waitForStartup(current.connection) }
        catch {
            if current.connection.status != .disconnected && current.connection.status != .invalid {
                current.connection.stopVPNTunnel()
            }
            status = current.connection.status
            throw error
        }
    }
    private func waitForStartup(_ connection: NEVPNConnection) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        var startup = MacVPNStartup()
        while true {
            try Task.checkCancellation()
            let next = connection.status
            if next != status { connectionEpoch = UUID(); status = next }
            switch startup.observe(next, elapsed: started.duration(to: clock.now)) {
            case .connected: return
            case .failed:
                do { try await connection.fetchLastDisconnectError() }
                catch { throw MacVPNFailure.classify(error) }
                throw MacVPNFailure.start
            case .timedOut: throw MacVPNFailure.timeout
            case .waiting: try await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    func message(_ payload: Data, limit: Int = 2048) async -> Data? {
        guard !offline, status == .connected, let session = manager?.connection as? NETunnelProviderSession else { return nil }
        let epoch = connectionEpoch
        let reply = MacProviderReply()
        let result: Data? = await withCheckedContinuation { continuation in
            reply.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reply.finish(nil) }
            do { try session.sendProviderMessage(payload) { data in Task { @MainActor in reply.finish(data) } } }
            catch { reply.finish(nil) }
        }
        guard !Task.isCancelled, epoch == connectionEpoch, status == .connected, let result, result.count <= limit else { return nil }
        return result
    }
    func disconnect() {
        guard !offline else { return }
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnected
    }
    func disconnectAndWait() async throws {
        guard !offline else { return }
        disconnect()
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while true {
            let next = manager?.connection.status ?? .disconnected
            if next != status { connectionEpoch = UUID(); status = next }
            if isIdle { return }
            guard ContinuousClock.now < deadline else { throw MacVPNFailure.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// A short idle grace period covers delivery of the start request. Once the
/// system starts connecting, returning to idle is a failure, not success.
struct MacVPNStartup {
    enum Outcome: Equatable { case waiting, connected, failed, timedOut }
    private var sawProgress = false
    mutating func observe(_ status: NEVPNStatus, elapsed: Duration) -> Outcome {
        if status == .connected { return .connected }
        if status == .connecting || status == .reasserting { sawProgress = true }
        if status == .disconnecting { return .failed }
        if status == .disconnected || status == .invalid {
            if sawProgress || elapsed >= .seconds(1) { return .failed }
        }
        return elapsed >= .seconds(30) ? .timedOut : .waiting
    }
}

enum MacVPNFailure: Error {
    case extensionStart, noNetwork, configuration, timeout, start
    case provider(PrototypeError)
    static func classify(_ error: Error) -> Self {
        let failure = error as NSError
        if failure.domain == TunnelDiagnostics.errorDomain,
           let known = PrototypeError(rawValue: failure.code) { return .provider(known) }
        guard failure.domain == NEVPNConnectionErrorDomain else { return .start }
        switch NEVPNConnectionError(rawValue: failure.code) {
        case .pluginFailed, .pluginDisabled: return .extensionStart
        case .noNetworkAvailable: return .noNetwork
        case .configurationFailed, .configurationNotFound: return .configuration
        default: return .start
        }
    }
    var summary: String {
        switch self {
        case .extensionStart:
            MacText.value("系统未能启动 Horizon VPN 扩展。请退出 App 后重试；若刚更新过版本，可重新安装或重启 Mac。", "macOS could not start the Horizon VPN extension. Quit and reopen the app. If you recently updated it, reinstall the app or restart your Mac.")
        case .noNetwork:
            MacText.value("当前没有可用网络，请检查网络后重试。", "No network is available. Check your connection and try again.")
        case .configuration:
            MacText.value("系统 VPN 配置不可用，请重新允许 Horizon 添加 VPN 配置。", "The VPN configuration is unavailable. Allow Horizon to add its VPN configuration again.")
        case .timeout:
            MacText.value("VPN 连接超时，请检查网络或节点后重试。", "The VPN connection timed out. Check your network or node and try again.")
        case .start:
            MacText.value("VPN 未能连接。请检查系统 VPN 权限、网络或节点后重试。", "The VPN could not connect. Check VPN permissions, your network, or the selected node and try again.")
        case .provider(let failure): MacText.error(failure)
        }
    }
}

@MainActor private final class MacProviderReply {
    var continuation: CheckedContinuation<Data?, Never>?
    func finish(_ data: Data?) { let current = continuation; continuation = nil; current?.resume(returning: data) }
}
#endif
