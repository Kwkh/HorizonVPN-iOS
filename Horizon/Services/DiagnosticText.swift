import Foundation

/// Translates only already-sanitized app diagnostics. Never pass raw core errors,
/// domains, userInfo or subscription content to this formatter.
nonisolated enum DiagnosticText {
    static func english(_ text: String) -> String {
        if let translated = ConfigurationFormat.english(text) { return translated }
        if let translated = resourceDownloadEnglish(text) { return translated }
        if let translated = messages[text] { return translated }
        if let translated = ConfigurationDiagnosticText.english(text) { return translated }
        if let error = PrototypeError.allCases.first(where: { $0.summary == text }), let detail = errors[error.rawValue] { return detail }
        let retainedSuffix = "；现有版本保留。"
        if text.hasSuffix(retainedSuffix) {
            let reason = String(text.dropLast(retainedSuffix.count))
            if let failure = SubscriptionDownloader.Failure.allCases.first(where: { $0.safeReason == reason }) {
                return failure.englishReason + ". The existing revision is retained."
            }
        }
        let profilePrefix = "VPN 配置未就绪，可能未授权或签名有误。"
        if text.hasPrefix(profilePrefix) {
            return "VPN profile setup failed. Check permission and signing. " + english(String(text.dropFirst(profilePrefix.count)))
        }
        if text.hasPrefix("系统状态：") { return "System status: " + english(String(text.dropFirst(5))) }
        if let match = text.range(of: #"^成功 · [0-9]+ ms$"#, options: .regularExpression) {
            return String(text[match]).replacingOccurrences(of: "成功", with: "Succeeded")
        }
        if let codeRange = text.range(of: #"[（(](?:错误码 )?-?[0-9]+[）)]"#, options: .regularExpression) {
            let code = text[codeRange].filter { $0.isASCII && ($0.isNumber || $0 == "-") }
            if text.hasPrefix("Network Extension 错误") {
                return "Network Extension error (\(code)). Check VPN permission and signing."
            }
            if text.hasPrefix("操作未完成") {
                return "Operation failed (\(code)). Raw error details are hidden."
            }
            let detailText = String(text[..<codeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let detail = ConfigurationDiagnosticText.english(detailText) {
                return detail + " (\(code))"
            }
            if let number = Int(code), let detail = errors[number] {
                return "\(detail) (\(number))"
            }
            return "Operation failed (\(code)). Raw error details are hidden."
        }
        // Preserve fixed technical strings. An unrecognized localized message must
        // not expose arbitrary content as a fallback or silently appear successful.
        if text.range(of: #"\p{script=Han}"#, options: .regularExpression) != nil {
            return "Diagnostic details are unavailable in English. Check the configuration report or device stage logs."
        }
        return text
    }
    static func importEnglish(_ text: String) -> String {
        english(text)
    }
    /// Only app-generated labels may be translated; provider names/URLs never enter this message.
    static func resourceDownloadEnglish(_ text: String) -> String? {
        let pattern = #"^依赖 ([1-9][0-9]?)（(GeoIP 数据|GeoSite 数据|节点列表|规则集|外部数据)( / GitHub)?）：([^。]+)。现有订阅未改变；请检查当前网络后重试。(?:[ ]*[（(]2022[）)])?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func part(_ index: Int) -> String {
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        let kinds = ["GeoIP 数据": "GeoIP data", "GeoSite 数据": "GeoSite data", "节点列表": "proxy provider", "规则集": "rule provider", "外部数据": "external data"]
        let reasons = [
            "需要有效 HTTPS 来源": "a valid HTTPS source is required",
            "HTTPS 跳转被安全策略阻止": "HTTPS redirect blocked by the security policy",
            "服务器未返回成功响应": "the server returned an unsuccessful HTTP response",
            "下载内容超过大小限制": "download exceeds the size limit",
            "服务器返回空内容": "the server returned an empty response",
            "网络请求失败": "network request failed",
            "下载超时": "download timed out",
            "无法解析下载服务器": "could not resolve the download server",
            "当前网络不可用或未获网络访问权限": "network unavailable or network access not permitted",
            "下载服务器的 TLS 或证书校验失败": "TLS or certificate validation failed",
            "下载途中连接中断": "connection lost during download",
            "无法连接下载服务器": "could not connect to the download server"
        ]
        guard let kind = kinds[part(2)], let reason = reasons[part(4)] else { return nil }
        return "Dependency \(part(1)) (\(kind)\(part(3))): \(reason). Existing configurations are unchanged. Check the current network and retry. (2022)"
    }
    private static let messages: [String: String] = [
        "请重试。": "Please retry.",
        "订阅无法读取；未更改现有记录。": "Could not read the configuration. Existing records are unchanged.",
        "离线演示不下载订阅。": "Offline demos do not download subscriptions.",
        "请先设置来源链接。": "Set a source URL first.",
        "订阅内容没有变化。": "Configuration unchanged.",
        "已取消刷新；现有版本保留。": "Refresh cancelled. The existing revision is retained.",
        "下载失败；现有版本保留。": "Download failed. The existing revision is retained.",
        "需要完整 HTTPS 地址，不接受内嵌账号密码或片段。": "Use a complete HTTPS URL without embedded credentials or fragments.",
        "候选版本校验失败；现有版本保留。": "Candidate validation failed. The existing revision is retained.",
        "请求失败或超时": "Request failed or timed out",
        "等待测试结果超时": "Timed out waiting for test results",
        "内核正在执行另一项测试": "The core is running another test",
        "测试暂不可用": "Testing is unavailable",
        "智能分流需要有效的末尾 MATCH 规则。": "Smart routing requires a valid final MATCH rule.",
        "智能分流需要末尾 MATCH 指向代理节点或策略组；原配置保持不变。": "Smart routing requires a proxy node or group as the MATCH fallback. Nothing changed.",
        "规则数量已达上限，无法添加智能分流。": "The rule limit was reached. Smart routing was not applied.",
        "分流方案准备失败；原配置保持不变。": "Could not prepare routing. The original configuration is unchanged.",
        "分流：智能分流（原有规则优先，国内直连，剩余流量使用原代理目标）。": "Routing: Smart (existing rules first, domestic direct, original proxy fallback).",
        "分流：恢复遵循订阅，移除智能分流附加规则与 DNS。": "Routing: Follow configuration. Remove added smart rules and DNS.",
        "当前无网络连接，请检查 Wi-Fi 或蜂窝数据。": "No network connection. Check Wi-Fi or cellular data.",
        "尚未读取系统 VPN 配置。": "System VPN preferences have not been loaded.",
        "模拟器仅供界面检查；Packet Tunnel 验收需要真机。": "Simulator UI only. Packet Tunnel validation requires a physical device.",
        "离线启动测试：模拟状态读取失败。": "Offline launch check: simulated preference read failure.",
        "发现多个本应用的 VPN 配置；请在系统设置中确认后重试。": "Multiple profiles for this app were found. Check VPN profiles in Settings and retry.",
        "本机已保存测试配置。": "A configuration is saved on this device.",
        "请先导入测试 YAML；不会自动连接。": "Import a configuration first. VPN will not connect automatically.",
        "文件未能读取；现有配置保持不变。": "Could not read the file. The existing configuration is unchanged.",
        "订阅已保存；相同内容沿用已有记录和节点选择，不会覆盖其他订阅。": "Configuration saved. Identical content keeps its existing record and node selections; other configurations are unchanged.",
        "VPN 配置已准备；仅手动连接。": "VPN profile ready. Connections remain manual.",
        "新版本已启动；节点可达性仍需验证。": "The new revision started. Node reachability still needs verification.",
        "新版本启动失败，暂无历史版本可恢复。": "The new revision failed to start. No previous revision is available.",
        "已请求连接；系统连接状态不代表节点和 DNS 已通过验收。": "Connection requested. System tunnel status alone does not verify the node or DNS.",
        "已请求断开，等待系统状态。": "Disconnection requested. Waiting for system status.",
        "扩展统计暂不可用；请检查真机固定阶段日志。": "Extension statistics are unavailable. Check the device stage logs.",
        "联网诊断未返回结果；可以断开恢复网络后重试。": "Connectivity checks returned no result. Disconnect to restore networking, then retry.",
        "系统未提供断开原因，请结合设备日志判断。": "The system supplied no disconnect reason. Consult device logs.",
        "本应用的 VPN 配置已移除；钥匙串配置可单独删除。": "This app’s VPN profile was removed. Saved Keychain configurations can be deleted separately.",
        "切换结果无法确认，已请求断开；保留原选择，请检查系统状态后重新连接。": "Could not confirm the switch. Disconnection requested; the previous selection is retained. Check system status before reconnecting.",
        "内核未接受切换；选择保持不变。请等待其他测试结束后重试。": "The core did not accept the switch. Selection is unchanged. Wait for other tests to finish and retry.",
        "选择已保存，下次连接生效。": "Selection saved for the next connection.",
        "节点已切换；新连接使用新选择，已有连接保留原路径。": "Node switched. New connections use the selection; existing connections keep their routes.",
        "当前订阅已切换，使用这份订阅保存的节点选择。": "Configuration switched, using its saved node selections.",
        "当前订阅正在连接；请确认断开 VPN 后再删除。": "The active configuration is in use. Confirm VPN disconnection before deletion.",
        "所选订阅已删除；原始 YAML 文件保留。": "Selected configurations deleted. Original YAML files are retained.",
        "列表已移除所选订阅，但钥匙串清理未完成，请点重试清理。": "Configurations removed from the list. Keychain cleanup is incomplete; retry cleanup.",
        "订阅名称已更新。": "Configuration renamed.",
        "钥匙串清理完成。": "Keychain cleanup complete.",
        "清理仍未完成，请解锁手机后重试。": "Cleanup is incomplete. Unlock the phone and retry.",
        "正在断开当前隧道，完成后再更新订阅。": "Disconnecting the current tunnel before updating the configuration.",
        "新版本已启动；节点可达性仍需 Ping 或真实请求验证。": "The new revision started. Verify reachability with Ping or a real request.",
        "版本已保存，历史版本可手动回滚；未自动连接。": "Revision saved. Previous revisions can be restored manually. VPN was not connected automatically.",
        "更新未保存；原版本保持不变并已重新启动。": "Update was not saved. The unchanged previous revision has been restarted.",
        "更新未保存；原版本仍在，请手动检查连接。": "Update was not saved. The previous revision remains; check the connection.",
        "新版本启动失败；已恢复保留版本并重新启动。请检查真实请求。": "The new revision failed. The retained revision was restored and restarted. Verify a real request.",
        "恢复未完成，已保留历史版本；请检查 VPN 状态，在版本历史中手动恢复。": "Recovery is incomplete. History is retained. Check VPN status and restore manually from revision history.",
        "无法获取当前隧道，请重试。": "Could not read the current tunnel. Retry.",
        "会话已改变或快照不可用，已停止记录。": "Recording stopped: the session changed or its snapshot is unavailable.",
        "请输入域名，不包含 URL、路径、端口或凭据；国际域名请使用 Punycode。": "Enter a domain without a URL scheme, path, port or credentials. Use Punycode for international domains.",
        "无法获取当前隧道。": "Could not read the current tunnel.",
        "诊断响应失效；请检查隧道状态。": "The diagnostic response is no longer valid. Check tunnel status.",
        "内核忙或检查不可用；请稍后重试。": "The core is busy or checks are unavailable. Retry later.",
        "等待超时；内核中已发出的查询仍受内核自身超时限制。": "Timed out waiting. In-flight core queries retain their own timeouts.",
        "解析成功": "Resolved",
        "超时": "Timed out",
        "未执行": "Not run",
        "无解析结果": "No DNS answer",
        "证书或 TLS 错误": "Certificate or TLS error",
        "认证错误": "Authentication error",
        "网络不可达": "Network unreachable",
        "操作未获允许": "Permission denied",
        "连接被拒绝": "Connection refused",
        "暂不可用": "Unavailable",
        "失败（原始错误已隐藏）": "Failed (raw error hidden)",
        "未返回 IPv4 记录": "No IPv4 answers",
        "诊断格式异常": "Invalid diagnostic response",
        "已收到 HTTPS 响应（非 2xx）": "HTTPS response received (non-2xx)",
        "无有效 VPN 配置": "No valid VPN profile",
        "未连接": "Disconnected",
        "连接中": "Connecting",
        "系统隧道已连接": "System tunnel connected",
        "等待网络恢复": "Waiting for network recovery",
        "正在断开": "Disconnecting",
        "未知系统状态": "Unknown system status",
        "订阅已改变，请重新刷新或打开预览。": "Configuration changed. Refresh or reopen the preview.",
        "订阅记录无法读取，已停止操作以保留现有数据。": "Could not read the library. Operation stopped to preserve existing data.",
        "订阅已不存在，请刷新列表。": "Configuration no longer exists. Refresh the list.",
        "当前最多保存 128 份订阅，请先删除不再使用的记录。": "Up to 128 configurations can be saved. Remove unused records first.",
        "请输入有效的订阅名称。": "Enter a valid configuration name.",
        "等待隧道断开超时，未切换或删除当前订阅；请确认系统状态后重试。": "Timed out waiting for disconnection. The active configuration was not switched or deleted. Check system status and retry."
    ]
    private static let errors: [Int: String] = [
        2001: "Invalid input. Use valid UTF-8 YAML, supported node URIs or a Base64 node list up to 1 MiB.",
        2002: "Unsupported configuration structure, field type or reference.",
        2003: "Unsupported configuration fields. Import was rejected; existing data is unchanged.",
        2004: "Core validation failed. Raw errors are hidden to protect credentials.",
        2005: "Unexpected core configuration adaptation. Activation blocked.",
        2006: "Import and confirm a configuration first. Unlock the device and retry.",
        2007: "Keychain access failed. Check access-group signing.",
        2008: "Core initialization failed.",
        2009: "No Wi-Fi or cellular network available.",
        2010: "Could not apply iOS tunnel routes or DNS.",
        2011: "Packet bridge failed. The tunnel stopped.",
        2012: "Core startup failed. Check device stage logs.",
        2013: "Startup cancelled.",
        2014: "Generated runtime configuration failed core validation.",
        2015: "Could not read the core adaptation report. Activation blocked.",
        2016: "Invalid node port. Use an integer from 1 to 65535 or a quoted decimal without leading zeros.",
        2017: "Core service creation failed. Forwarding has not started.",
        2018: "Could not prepare the core temporary directory.",
        2019: "Pre-tunnel system DNS is unavailable. Disconnect other VPNs and check networking.",
        2020: "Incompatible or unrecognized configuration format. Provide Clash / Mihomo configuration or supported node URIs.",
        2021: "This configuration contains nodes that skip certificate verification. Confirm in the app before connecting.",
        2022: "Subscription dependency download failed. Existing configurations are unchanged. Check the current network and retry.",
        1001: "Extension entry ran, but the core is not integrated. Check device stage logs."
    ]
}
