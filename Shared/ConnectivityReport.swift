import Foundation

/// Only fixed outcomes and counts cross the extension boundary.
struct ConnectivityReport: Codable {
    let nodeHTTPSMilliseconds: Int32
    let dns: DNSOutcome
    let bootstrap: String
    let nodeFailure: String

    var nodeResponded: Bool { nodeFailure == "success" || nodeFailure == "http-status" }
    var nodeSummary: String {
        if nodeFailure == "http-status" { return "已收到 HTTPS 响应（非 2xx）" }
        if nodeHTTPSMilliseconds >= 0 { return "成功 · \(nodeHTTPSMilliseconds) ms" }
        return statusSummary(nodeFailure)
    }
    var bootstrapSummary: String { statusSummary(bootstrap) }
    private func statusSummary(_ value: String) -> String {
        switch value {
        case "resolved": "解析成功"
        case "timeout": "超时"
        case "not-run": "未执行"
        case "no-answer", "dns-name": "无解析结果"
        case "tls": "证书或 TLS 错误"
        case "authentication": "认证错误"
        case "network": "网络不可达"
        case "permission": "操作未获允许"
        case "refused": "连接被拒绝"
        case "unavailable": "暂不可用"
        default: "失败（原始错误已隐藏）"
        }
    }

    static func safeProbeStatus(_ value: String?) -> String {
        let allowed: Set<String> = ["unavailable", "not-run", "resolved", "no-answer", "success", "http-status", "tls", "authentication", "dns-name", "network", "permission", "refused", "timeout", "failed"]
        guard let value, allowed.contains(value) else { return "failed" }
        return value
    }

    enum DNSOutcome: String, Codable {
        case resolved, noAnswer, timeout, tls, authentication, network, failed, malformed

        static func decode(_ json: String) -> Self {
            guard let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .malformed }
            if let error = root["error"] as? String {
                let text = error.lowercased()
                if text.contains("timeout") || text.contains("deadline exceeded") { return .timeout }
                if text.contains("certificate") || text.contains("tls:") { return .tls }
                if text.contains("authentication") || text.contains("auth failed") { return .authentication }
                if text.contains("unreachable") || text.contains("network is down") { return .network }
                return .failed
            }
            guard root["Status"] as? Int == 0 else { return .failed }
            return (root["Answer"] as? [[String: Any]])?.contains { $0["type"] as? Int == 1 } == true ? .resolved : .noAnswer
        }

        var summary: String {
            switch self {
            case .resolved: "解析成功"
            case .noAnswer: "未返回 IPv4 记录"
            case .timeout: "超时"
            case .tls: "证书或 TLS 错误"
            case .authentication: "认证错误"
            case .network: "网络不可达"
            case .failed: "失败（原始错误已隐藏）"
            case .malformed: "诊断格式异常"
            }
        }
    }
}
