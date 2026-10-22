import Foundation
import Network
import Observation

/// Device path availability only; no reachability URL, probes, or VPN changes.
@MainActor @Observable
final class NetworkAvailability {
    enum Status: Sendable { case unknown, available, offline }
    private(set) var status: Status
    var isOffline: Bool { status == .offline }
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let monitorSystem: Bool

    init(initialStatus: Status = .unknown, monitorSystem: Bool = true) {
        status = initialStatus
        self.monitorSystem = monitorSystem
    }

    /// Called after first-run presentation has finished, never from App initialization.
    /// A cancelled NWPathMonitor cannot be restarted; keep one monitor for this lifetime.
    func startMonitoring() {
        guard monitorSystem, monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let status = Self.availability(for: path.status)
            Task { @MainActor [weak self] in self?.status = status }
        }
        monitor.start(queue: DispatchQueue(label: "Horizon.NetworkAvailability"))
    }

    deinit { monitor?.cancel() }

    nonisolated static func availability(for status: NWPath.Status) -> Status {
        switch status {
        case .unsatisfied: .offline
        // An on-demand path can become available when a connection is made.
        case .satisfied, .requiresConnection: .available
        @unknown default: .unknown
        }
    }

    #if DEBUG
    func setPreviewStatus(_ status: Status) {
        precondition(!monitorSystem, "Only isolated previews may override network state")
        self.status = status
    }
    #endif
}
