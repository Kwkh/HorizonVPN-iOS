import ActivityKit
import Foundation

nonisolated struct VPNActivityAttributes: ActivityAttributes {
    let sessionID: UUID
    let chinese: Bool
    var isDemo = false

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case connected, reconnecting, disconnected }
        enum Probe: String, Codable { case idle, running, success, timedOut, failed, busy, unavailable, changed }
        var phase: Phase
        var sampledAt: Date
        // Optional fields allow an activity from an earlier build to decode safely.
        var nodeLabel: String? = nil
        var targetID: String? = nil
        var probe: Probe? = nil
        var milliseconds: Int32? = nil
        var probeStartedAt: Date? = nil

        func status(chinese: Bool, stale: Bool) -> String {
            switch phase {
            case .connected: chinese ? "已连接" : "Connected"
            case .reconnecting: chinese ? "恢复连接中" : "Reconnecting"
            case .disconnected: chinese ? "已断开" : "Disconnected"
            }
        }
        func probeLabel(chinese: Bool, stale: Bool) -> String {
            switch probe ?? .idle {
            case .idle: "Ping"
            case .running: stale ? (chinese ? "重试" : "Retry") : (chinese ? "测试中" : "Testing")
            case .success: milliseconds.map { "\($0) ms" } ?? "Ping"
            case .timedOut: chinese ? "超时" : "Timeout"
            case .failed: chinese ? "失败" : "Failed"
            case .busy: chinese ? "忙碌" : "Busy"
            case .unavailable: chinese ? "暂不可用" : "Unavailable"
            case .changed: chinese ? "打开 App 更新" : "Open app to update"
            }
        }
        var staleDate: Date? {
            probe == .running ? probeStartedAt?.addingTimeInterval(15) : nil
        }
        func identifies(_ target: String) -> Bool { targetID == target && !target.isEmpty }
    }
}
