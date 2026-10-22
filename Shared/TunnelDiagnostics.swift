import Foundation

/// Shared, credential-free vocabulary for the app and extension.
nonisolated enum TunnelDiagnostics {
    static let errorDomain = "Clash.PacketTunnel"
    static let coreUnavailable = 1001
    static let profileMarker = "clash-diagnostics-v1"

    static func startupError() -> NSError {
        NSError(domain: errorDomain, code: coreUnavailable, userInfo: [
            NSLocalizedDescriptionKey: "扩展入口已执行；代理内核尚未接入，隧道未建立。"
        ])
    }

    /// Never display arbitrary localizedDescription, userInfo, or a foreign domain:
    /// those may eventually contain subscription URLs and credentials.
    static func safeErrorSummary(_ error: Error) -> String {
        let value = error as NSError
        if value.domain == errorDomain, value.code == coreUnavailable {
            return "扩展返回内核未接入（1001）；请结合本次设备日志确认入口执行。"
        }
        switch value.domain {
        case "NEVPNErrorDomain", "NETunnelProviderErrorDomain", "NEConfigurationErrorDomain":
            return "Network Extension 错误（\(value.code)）；请检查授权与签名。"
        default:
            return "操作未完成（错误码 \(value.code)）；未显示原始错误内容。"
        }
    }
}
