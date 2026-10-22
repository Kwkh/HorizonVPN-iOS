import Foundation

@main struct DiagnosticTextChecks {
    static func main() {
        precondition(DiagnosticText.english("系统状态：系统隧道已连接") == "System status: System tunnel connected")
        precondition(DiagnosticText.english("成功 · 257 ms") == "Succeeded · 257 ms")
        precondition(DiagnosticText.english("内核初始化失败。（2008）") == "Core initialization failed. (2008)")
        precondition(DiagnosticText.english("Network Extension 错误（5）；请检查授权与签名。") == "Network Extension error (5). Check VPN permission and signing.")
        precondition(DiagnosticText.english("操作未完成（错误码 2008）；未显示原始错误内容。") == "Operation failed (2008). Raw error details are hidden.")
        precondition(DiagnosticText.english("操作未完成（错误码 -50）；未显示原始错误内容。").contains("(-50)"))
        precondition(DiagnosticText.english("VPN 配置未就绪，可能未授权或签名有误。Network Extension 错误（5）；请检查授权与签名。").hasSuffix("Check VPN permission and signing."))
        precondition(DiagnosticText.english("无法获取当前隧道。").contains("Could not read"))
        precondition(DiagnosticText.english("未返回 IPv4 记录") == "No IPv4 answers")
        precondition(!DiagnosticText.english("未知提示：TEST-ONLY-SECRET").contains("TEST-ONLY-SECRET"))
        precondition(!DiagnosticText.english("未知提示：TEST-ONLY-SECRET（2003）").contains("TEST-ONLY-SECRET"))
        let dependency = "依赖 1（GeoIP 数据 / GitHub）：下载超时。现有订阅未改变；请检查当前网络后重试。"
        precondition(DiagnosticText.importEnglish(dependency).contains("download timed out"))
        precondition(DiagnosticText.english(dependency + "（2022）").contains("GeoIP data / GitHub"))
        precondition(DiagnosticText.resourceDownloadEnglish(dependency.replacingOccurrences(of: "下载超时", with: "FICTIONAL-SECRET")) == nil)
        for code in 2001...2022 {
            let result = DiagnosticText.english("固定错误（\(code)）")
            precondition(result.contains("(\(code))") && !result.contains("details are unavailable"))
        }
        print("Diagnostic text: fixed messages, timing, error domains/codes and redacted fallback passed")
    }
}
