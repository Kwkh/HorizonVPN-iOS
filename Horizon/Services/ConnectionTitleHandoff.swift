import Foundation
import NetworkExtension

/// Presentation-only bridge; never changes the system VPN status or starts a tunnel.
struct ConnectionTitleHandoff {
    private enum Phase { case preparing, queued, submitted }
    private(set) var id: UUID?
    private var phase = Phase.preparing
    var isPending: Bool { id != nil }
    var isStarting: Bool { isPending && phase != .preparing }

    mutating func begin() -> UUID {
        let ticket = UUID()
        id = ticket
        phase = .preparing
        return ticket
    }
    mutating func enqueue(_ ticket: UUID) {
        guard id == ticket else { return }
        phase = .queued
    }
    mutating func submit() {
        guard isStarting else { return }
        phase = .submitted
    }
    mutating func preparationEnded(_ ticket: UUID) {
        if phase == .preparing { finish(ticket) }
    }
    mutating func finish(_ ticket: UUID) {
        guard id == ticket else { return }
        id = nil
    }
    mutating func observe(_ status: NEVPNStatus, notification: Bool = false) {
        guard phase == .submitted, let ticket = id else { return }
        switch status {
        case .connecting, .connected, .reasserting, .disconnecting:
            finish(ticket)
        case .invalid, .disconnected:
            // An immediate status read may still be the pre-start value. A later
            // system notification can report a real rejected/failed start.
            if notification { finish(ticket) }
        @unknown default:
            if notification { finish(ticket) }
        }
    }
    func titleStatus(system: NEVPNStatus, preparing: Bool) -> NEVPNStatus {
        if (isPending || preparing), system == .invalid || system == .disconnected {
            return .connecting
        }
        return system
    }
}
