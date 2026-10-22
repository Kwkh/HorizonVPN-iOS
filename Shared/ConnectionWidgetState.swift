import Foundation
import WidgetKit

/// Presentation data only. Subscription credentials remain in the existing Keychain.
struct ConnectionWidgetState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case unavailable, disconnected, connecting, connected, reconnecting, disconnecting
        var isOn: Bool { self == .connected || self == .connecting || self == .reconnecting }
        var isTransitioning: Bool { self == .connecting || self == .reconnecting || self == .disconnecting }
    }
    var phase: Phase = .unavailable
    var subscription: String = ""
    var updatedAt: Date = .now
    static let group = "group.Kenote.Clash.widgets"
    static let widgetKind = "Horizon.Connection"
    static let controlKind = "Horizon.ConnectionControl"

    static func read() -> Self {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: "connection.presentation"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    static func publish(phase: Phase, subscription: String? = nil) {
        #if os(iOS)
        var next = read()
        guard next.phase != phase || (subscription != nil && next.subscription != subscription) else { return }
        next.phase = phase
        if let subscription { next.subscription = subscription }
        next.updatedAt = .now
        guard let data = try? JSONEncoder().encode(next) else { return }
        UserDefaults(suiteName: group)?.set(data, forKey: "connection.presentation")
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        ControlCenter.shared.reloadControls(ofKind: controlKind)
        #endif
    }
}
