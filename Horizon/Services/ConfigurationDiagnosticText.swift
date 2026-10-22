import Foundation

/// Presentation translations for fixed, sanitized parser output. Never translates YAML values.
nonisolated enum ConfigurationDiagnosticText {
    static func english(_ text: String) -> String? {
        if let value = messages[text] { return value }
        let desktopPrefix = "不启用桌面监听设置：", desktopSuffix = "；手机流量由 Packet Tunnel 接入。"
        if text.hasPrefix(desktopPrefix), text.hasSuffix(desktopSuffix) {
            let fields = text.dropFirst(desktopPrefix.count).dropLast(desktopSuffix.count).components(separatedBy: "、")
            if !fields.isEmpty, fields.allSatisfy({ ConfigurationPolicy.desktopPorts.union(["allow-lan", "bind-address"]).contains($0) }) {
                return "Desktop listeners are disabled: " + fields.joined(separator: ", ") + ". iOS traffic uses Packet Tunnel."
            }
        }
        let boundsSuffix = " 超出支持范围。"
        if text.hasSuffix(boundsSuffix) {
            let field = String(text.dropLast(boundsSuffix.count))
            let tuicField = field.hasPrefix("TUIC ") ? String(field.dropFirst(5)) : field
            if ConfigurationNodeOptions.fields("tuic").union(ConfigurationPolicy.groupFields).contains(tuicField) {
                return field + " is out of the supported range."
            }
        }
        if text.hasPrefix("尚未支持字段：") {
            let field = String(text.dropFirst("尚未支持字段：".count).dropLast())
            if ConfigurationPolicy.knownFields.contains(field) { return "Unsupported field: " + field + "." }
        }
        if text.hasPrefix("尚未支持 ") || text.hasPrefix("；另有 ") {
            let pieces = text.trimmingCharacters(in: CharacterSet(charactersIn: "。" )).components(separatedBy: "；另有 ")
            let fields = pieces[0].hasPrefix("尚未支持 ") ? String(pieces[0].dropFirst(5)).components(separatedBy: "、") : []
            guard fields.allSatisfy({ ConfigurationPolicy.knownFields.contains($0) }) else { return nil }
            var result = fields.isEmpty ? "" : "Unsupported fields: " + fields.joined(separator: ", ")
            if pieces.count == 2 {
                let count = pieces[1].prefix(while: { $0.isASCII && $0.isNumber })
                guard !count.isEmpty, pieces[1] == count + " 个未识别字段（名称已隐藏）" else { return nil }
                result += (result.isEmpty ? "" : "; ") + count + " unrecognized fields (names hidden)"
            }
            if !result.isEmpty { return result + "." }
        }
        for (pattern, template) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { continue }
            return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
        if let separator = text.range(of: "："), let location = location(String(text[..<separator.lowerBound])),
           let detail = english(String(text[separator.upperBound...])) {
            return location + ": " + detail
        }
        return nil
    }

    static func location(_ text: String) -> String? {
        let labels = ["顶层": "Top level", "导入内容": "Import content", "依赖": "Dependencies",
                      "配置结构": "Configuration structure", "完整校验": "Full validation", "iOS 规则": "iOS rules",
                      "规则集": "Rule provider", "策略组": "Policy group", "策略组自动收集": "Automatic group membership",
                      "节点列表": "Node list"]
        if let value = labels[text] { return value }
        let prefixes = ["节点 ": "Node ", "策略组 ": "Group ", "规则 ": "Rule ", "链接 ": "URI "]
        for (prefix, translated) in prefixes where text.hasPrefix(prefix) {
            let remainder = text.dropFirst(prefix.count)
            let number = remainder.prefix(while: { $0.isASCII && $0.isNumber })
            guard !number.isEmpty else { return nil }
            let suffix = String(remainder.dropFirst(number.count))
            if suffix.isEmpty { return translated + number }
            if suffix.hasPrefix(" · "), let field = location(String(suffix.dropFirst(3))) { return translated + number + " · " + field }
            if [" WS", " gRPC", " Reality"].contains(suffix) { return translated + number + suffix }
            return nil
        }
        for separator in [" · ", " "] {
            if let range = text.range(of: separator), let prefix = labels[String(text[..<range.lowerBound])],
               let suffix = location(String(text[range.upperBound...])) { return prefix + separator + suffix }
        }
        if text == "DNS" || text == "YAML" || text == "iOS" { return text }
        for prefix in ["DNS · ", "DNS "] where text.hasPrefix(prefix) {
            if let field = location(String(text.dropFirst(prefix.count))) { return prefix + field }
        }
        if text.range(of: #"^(proxy|rule)-providers [0-9]+(?: override)?$"#, options: .regularExpression) != nil { return text }
        let fields = ConfigurationPolicy.knownFields.union(ConfigurationResources.providerFields)
            .union(ConfigurationNodeOptions.kinds.flatMap { ConfigurationNodeOptions.fields($0) })
            .union(["fallback-filter", "proxy-name", "public-key", "short-id", "grpc-service-name"])
        return fields.contains(text) ? text : nil
    }

    private static let patterns: [(String, String)] = [
        (#"^([0-9]+) 个节点、([0-9]+) 个策略组、([0-9]+) 条规则。$"#, "$1 nodes · $2 groups · $3 rules"),
        (#"^节点新增 ([0-9]+) · 删除 ([0-9]+) · 字段变化 ([0-9]+)$"#, "Nodes added: $1 · Removed: $2 · Changed: $3"),
        (#"^需重新选择的策略组：([0-9]+)$"#, "Groups requiring a new selection: $1"),
        (#"^依赖资源变化：([0-9]+) 项；回滚将一并恢复。$"#, "Dependencies changed: $1. Rollback restores them too."),
        (#"^成员 ([0-9]+) 引用了不存在的目标。$"#, "Member $1 references a missing target."),
        (#"^未支持字段 ([0-9]+)（名称已隐藏）。$"#, "Unsupported field $1 (name hidden)."),
        (#"^上游 ([0-9]+) 的格式或协议尚未支持。$"#, "Upstream $1 uses an unsupported format or protocol."),
        (#"^策略 ([0-9]+) 不是受支持的普通域名模式。$"#, "Policy $1 uses an unsupported domain pattern."),
        (#"^策略 ([0-9]+) 的上游格式未支持。$"#, "Policy $1 uses an unsupported upstream format."),
        (#"^包含 ([0-9]+) 个跳过证书校验的节点；保存不会启用它们，连接前必须明确授权此配置版本。更新后需重新确认。$"#, "Contains $1 nodes that skip certificate verification. Saving does not authorize them; approve this revision before connecting. Updates require approval again."),
        (#"^iOS 无法使用桌面进程名：运行配置停用 ([0-9]+) 条 PROCESS-NAME 规则，流量继续匹配后续规则；原始规则保留用于刷新及回滚。$"#, "iOS cannot match desktop process names. $1 PROCESS-NAME rules are disabled; traffic continues to later rules. Original rules are retained for refresh and rollback."),
        (#"^本版本含 ([0-9]+) 项内置 Geo 数据，首次导入无需联网下载；可在订阅维护中手动更新。原始规则保留，数据版本随订阅一起回滚。$"#, "This revision includes $1 bundled Geo resources, so first import needs no Geo download. Update them manually in subscription maintenance. Original rules are retained, and rollback restores the data version too."),
        (#"^DNS fallback 保留 GeoIP 国家筛选（([A-Z]{2})）：主 DNS 返回非目标国家 IP 时使用 fallback；数据随订阅快照校验和保存。省略 geoip / geoip-code 时沿用内核默认 true / CN。$"#, "DNS fallback retains GeoIP filtering ($1): use fallback when primary DNS returns IPs outside the target country. Data is validated and saved with the snapshot. Missing geoip / geoip-code uses core defaults true / CN.")
    ]

    private static let messages: [String: String] = [
        "external-controller：iOS 不启用订阅中的外部控制接口；App 使用隧道 IPC，不开放该管理端口。": "external-controller: iOS disables the subscription’s external controller. The app uses tunnel IPC without exposing a management port.",
        "顶层 secret：仅用于外部控制接口认证，iOS 运行配置不采用；节点密码保持原样。": "Top-level secret authenticates the external controller and is omitted from iOS runtime settings. Node passwords are unchanged.",
        "未设置 unified-delay：默认开启，与当前 Mac Verge 一致；手动测速使用 Cloudflare HTTP 204，超时 10 秒。": "unified-delay is unspecified and defaults to enabled, matching Mac Verge. Manual tests use Cloudflare HTTP 204 with a 10-second timeout.",
        "保留文件的 unified-delay 设置；手动测速使用 Cloudflare HTTP 204，超时 10 秒。": "Retain the configuration’s unified-delay setting. Manual tests use Cloudflare HTTP 204 with a 10-second timeout.",
        "此输入没有策略组和分流规则：已补充一个手动 select 组（默认首节点）与 MATCH 规则，普通流量统一交给所选节点；DNS 使用系统引导 + Cloudflare DoH。原有元数据保留并校验，保存不会自动连接。": "No groups or routing rules were defined. Add a manual select group (first node by default) and MATCH rule; ordinary traffic uses the selected node. DNS uses system bootstrap and Cloudflare DoH. Existing metadata is retained and validated; saving does not connect VPN.",
        "此输入没有策略组和分流规则：已补充一个手动 select 组（默认首节点）与 MATCH 规则，普通流量统一交给所选节点；保留输入中的 DNS，按同一兼容性流程校验。原有元数据保留并校验，保存不会自动连接。": "No groups or routing rules were defined. Add a manual select group (first node by default) and MATCH rule; ordinary traffic uses the selected node. Retain and validate the input DNS. Existing metadata is retained and validated; saving does not connect VPN.",
        "格式无效。": "Invalid format.",
        "格式错误。": "Invalid format.",
        "CIDR 格式错误。": "Invalid CIDR.",
        "DNS rule-set 必须引用已定义的 domain 规则集。": "DNS rule-set must reference a defined domain rule provider.",
        "DNS 上游引用不存在的代理，或节点引导 DNS 使用代理造成递归风险。": "DNS references a missing proxy, or proxy-based node bootstrap would cause a resolver loop.",
        "DNS 模式未支持。": "Unsupported DNS mode.",
        "DNS 策略中的上游格式未支持。": "Unsupported DNS policy upstream format.",
        "DNS 策略格式错误。": "Invalid DNS policy format.",
        "DNS 策略模式无效。": "Invalid DNS policy pattern.",
        "DNS 策略顺序无法保留；未启用候选配置。": "DNS policy order could not be preserved. The candidate was not activated.",
        "Geo 分类格式无效。": "Invalid Geo category format.",
        "Geo 数据无效或缺少所引用分类；未启用候选配置。": "Geo data is invalid or lacks a referenced category. The candidate was not activated.",
        "Geo 数据来源或格式未支持。": "Unsupported Geo source or format.",
        "Geo 规则需要有效的 HTTPS 数据来源；geox-url 配置缺失或无效。": "Geo rules require a valid HTTPS data source. geox-url is missing or invalid.",
        "Hysteria2 凭据或 SNI 格式错误。": "Invalid Hysteria2 credentials or SNI.",
        "Hysteria2 原生支持 UDP，目前不能通过 udp:false 关闭。": "Hysteria2 supports UDP natively; udp:false cannot disable it.",
        "MATCH 必须是最后一条，且指向有效目标。": "MATCH must be last and reference a valid target.",
        "NETWORK 支持 TCP 或 UDP。": "NETWORK supports TCP or UDP.",
        "QUIC 节点不使用 TCP Fast Open。": "QUIC nodes do not use TCP Fast Open.",
        "Reality public-key 格式错误。": "Invalid Reality public-key.",
        "Reality short-id 格式错误。": "Invalid Reality short-id.",
        "Reality 当前支持 TCP 或 gRPC，且需要 TLS。": "Reality supports TCP or gRPC and requires TLS.",
        "Reality 格式错误。": "Invalid Reality options.",
        "Reality 需要 client-fingerprint。": "Reality requires client-fingerprint.",
        "SS 客户端指纹需要 v2ray-plugin TLS。": "SS client fingerprint requires v2ray-plugin TLS.",
        "SS 插件 mode 未支持。": "Unsupported SS plugin mode.",
        "SS 插件仅接入 obfs 与 v2ray-plugin，且需 plugin-opts。": "SS supports obfs and v2ray-plugin with plugin-opts.",
        "SS 需要受支持的 AEAD／SS2022 cipher 与密码；旧式加密尚未接入。": "SS requires a supported AEAD/SS2022 cipher and password. Legacy ciphers are unsupported.",
        "SS2022 密钥编码或长度无效。": "Invalid SS2022 key encoding or length.",
        "TLS 参数需要启用 TLS。": "TLS options require TLS to be enabled.",
        "TUIC v5 需要有效 UUID、密码及 SNI；暂不支持 v4 token。": "TUIC v5 requires a valid UUID, password and SNI. v4 tokens are unsupported.",
        "Trojan 凭据或 SNI 无效。": "Invalid Trojan credentials or SNI.",
        "UDP over TCP 版本必须为 1 或 2。": "UDP over TCP version must be 1 or 2.",
        "VLESS 要求有效 UUID；flow 可为 Vision。": "VLESS requires a valid UUID; flow may use Vision.",
        "VMess UUID、cipher、alterId 或 TLS 名称无效。": "Invalid VMess UUID, cipher, alterId or TLS name.",
        "Vision flow 需要 TCP + TLS，不能与 gRPC 组合。": "Vision flow requires TCP + TLS and cannot use gRPC.",
        "WS early data header 无效。": "Invalid WS early-data header.",
        "WS early data 超出范围。": "WS early-data limit is out of range.",
        "WS headers 格式无效。": "Invalid WS headers.",
        "WS 路径无效。": "Invalid WS path.",
        "alpn 必须是非空字符串列表。": "alpn must be a nonempty string list.",
        "behavior / format 或健康检查组合未支持。": "Unsupported behavior / format / health-check combination.",
        "classical 最多 4096 条。": "classical supports up to 4096 entries.",
        "dns 必须是映射。": "dns must be a mapping.",
        "dns.listen 需要 IP:端口、:端口（IPv6 使用方括号）或空字符串。": "dns.listen requires IP:port, :port or an empty string. Bracket IPv6 addresses.",
        "dns.prefer-h3: true 尚未完成 iOS HTTP/3 验证；支持 false，不会静默关闭 HTTP/3 偏好。": "dns.prefer-h3: true is not validated on iOS. false is supported; HTTP/3 preference is never silently disabled.",
        "expected-status 需要 HTTP 状态码或范围。": "expected-status requires an HTTP status code or range.",
        "fake-ip-filter 当前只支持普通域名模式。": "fake-ip-filter supports plain domain patterns only.",
        "fake-ip-filter-mode 暂不支持规则模式。": "Rule mode is unsupported for fake-ip-filter-mode.",
        "fake-ip-range 必须是 IPv4 CIDR。": "fake-ip-range must be an IPv4 CIDR.",
        "fallback-filter domain 格式错误。": "Invalid fallback-filter domain format.",
        "fallback-filter geosite 分类无效。": "Invalid fallback-filter geosite category.",
        "fallback-filter ipcidr 格式错误。": "Invalid fallback-filter ipcidr format.",
        "fallback-filter 格式错误。": "Invalid fallback-filter format.",
        "fallback-filter.geoip-code 需要两位国家代码。": "fallback-filter.geoip-code requires a two-letter country code.",
        "find-process-mode：iOS 不支持进程探测；只接受 off。": "find-process-mode: iOS does not support process detection. Use off.",
        "fingerprint 必须是 SHA-256 证书指纹，不是浏览器名称。": "fingerprint must be a SHA-256 certificate fingerprint, not a browser name.",
        "gRPC 字段格式无效。": "Invalid gRPC field format.",
        "geo-update-interval 格式错误。": "Invalid geo-update-interval.",
        "geodata-loader 格式错误。": "Invalid geodata-loader.",
        "geox-url 需要映射。": "geox-url must be a mapping.",
        "geox-url：数据来源需要 HTTPS。": "geox-url: Data sources require HTTPS.",
        "global-client-fingerprint 尚未支持此值。": "Unsupported global-client-fingerprint value.",
        "grpc-opts 需要 gRPC 传输。": "grpc-opts requires gRPC transport.",
        "header 需要字符串数组映射。": "header requires a mapping of string arrays.",
        "health-check 格式错误。": "Invalid health-check format.",
        "hosts 当前支持域名模式到 IPv4/IPv6 地址或地址列表；不接受无效地址或域名别名。": "hosts supports domain patterns mapped to IPv4/IPv6 addresses or address lists. Invalid addresses and domain aliases are rejected.",
        "hosts 需要最多 1024 项映射。": "hosts requires a mapping of up to 1024 entries.",
        "iOS 不读取桌面系统 hosts；use-system-hosts: true 尚不支持。": "iOS does not read desktop system hosts; use-system-hosts: true is unsupported.",
        "iOS 隧道需要内核 DNS；dns.enable: false 尚不支持。": "The iOS tunnel requires core DNS; dns.enable: false is unsupported.",
        "icon 格式错误。": "Invalid icon format.",
        "inline 只接受 payload，不能混用远程来源或 MRS。": "inline accepts payload only, without remote sources or MRS.",
        "interval 无效。": "Invalid interval.",
        "ip-version 无效。": "Invalid ip-version.",
        "override ip-version 无效。": "Invalid override ip-version.",
        "override 字符串格式无效。": "Invalid override string format.",
        "override 带宽格式无效。": "Invalid override bandwidth.",
        "override 需要映射。": "override must be a mapping.",
        "path 类型无效。": "Invalid path type.",
        "profile 必须是映射。": "profile must be a mapping.",
        "proxy-name 需要 pattern 与 target 字符串。": "proxy-name requires pattern and target strings.",
        "proxy-name 需要最多 16 项替换列表。": "proxy-name requires up to 16 replacement entries.",
        "size-limit 无效。": "Invalid size-limit.",
        "smux protocol 无效。": "Invalid smux protocol.",
        "smux 并发参数超出范围。": "smux concurrency options are out of range.",
        "smux 需要布尔 enabled。": "smux requires a Boolean enabled field.",
        "strategy 仅适用于 load-balance，且必须为受支持策略。": "strategy requires load-balance and a supported balancing strategy.",
        "tolerance 仅适用于 url-test。": "tolerance applies only to url-test.",
        "ws-opts 需要 WebSocket 传输。": "ws-opts requires WebSocket transport.",
        "不支持此 client-fingerprint。": "Unsupported client-fingerprint.",
        "不支持此 packet-encoding。": "Unsupported packet-encoding.",
        "传输仅支持 TCP、WebSocket、gRPC。": "Supported transports are TCP, WebSocket and gRPC.",
        "依赖分片缺失。": "Missing dependency chunk.",
        "依赖完整性失败。": "Dependency integrity check failed.",
        "依赖快照完整性检查失败。": "Dependency snapshot integrity check failed.",
        "依赖快照缺失；请手动刷新或回滚，未从网络自动补齐。": "Missing dependency snapshot. Refresh manually or roll back; no automatic download was attempted.",
        "依赖超过限制：最多 35 项、单项 32 MiB、总计 64 MiB。": "Dependency limits: 35 items, 32 MiB each and 64 MiB total.",
        "候选依赖内存已达上限，请取消其他预览后重试。": "Candidate dependency memory limit reached. Cancel other previews and retry.",
        "内容、条目数量或格式无效。": "Invalid content, entry count or format.",
        "内核无法规划依赖，请检查配置结构。": "The core could not plan dependencies. Check the configuration structure.",
        "包含无效域名或 CIDR，禁止静默丢弃规则。": "Invalid domains or CIDRs were found. Rules are not silently discarded.",
        "原始节点名称或类型无效／重名。": "Original node names or types are invalid or duplicated.",
        "原始节点数量需为 1–512。": "The original node count must be 1–512.",
        "名称或服务器字段格式错误。": "Invalid name or server field format.",
        "名称或结构无效。": "Invalid name or structure.",
        "国际化域名规则无法转换。": "Could not convert the internationalized domain rule.",
        "域名关键词需要 ASCII 文本。": "Domain keywords require ASCII text.",
        "域名规则格式错误。": "Invalid domain rule format.",
        "字符串格式错误（值已隐藏）。": "Invalid string format (value hidden).",
        "布尔字段类型错误。": "Invalid Boolean field type.",
        "带宽字段格式错误。": "Invalid bandwidth field format.",
        "当前仅接受空列表 []。": "Only an empty list [] is supported.",
        "当前仅支持 Salamander 混淆，且必须提供混淆密码。": "Only Salamander obfuscation is supported, with an obfuscation password.",
        "当前仅支持布尔 false；不将启用或错误类型静默改为关闭。": "Only Boolean false is supported. Enabled or incorrectly typed values are not silently disabled.",
        "当前仅接受显式布尔 enable: false；启用、缺少开关或错误类型均不支持。": "An explicit Boolean enable: false is required. Enabled, missing or incorrectly typed flags are unsupported.",
        "插件 host 无效。": "Invalid plugin host.",
        "插件客户端指纹无效。": "Invalid plugin client fingerprint.",
        "插件证书指纹无效。": "Invalid plugin certificate fingerprint.",
        "插件证书指纹类型无效。": "Invalid plugin certificate fingerprint type.",
        "插件证书选项需要 TLS。": "Plugin certificate options require TLS.",
        "支持 HTTPS http 或 inline；不读取订阅指定的本地文件路径。": "Providers support HTTPS http or inline. Subscription-specified local file paths are not read.",
        "支持 select、url-test、fallback、load-balance，且需要有效名称。": "Use select, url-test, fallback or load-balance with a valid name.",
        "支持域名、IP-CIDR、SRC-IP-CIDR、DST/SRC-PORT、NETWORK、RULE-SET、GEOIP、GEOSITE、MATCH；其他规则未接入。": "Supported rules: domain, IP-CIDR, SRC-IP-CIDR, DST/SRC-PORT, NETWORK, RULE-SET, GEOIP, GEOSITE and MATCH.",
        "文本编码无效。": "Invalid text encoding.",
        "最多 32 项映射。": "Use a mapping of up to 32 entries.",
        "此协议尚未接入。": "This protocol is unsupported.",
        "此协议未接入 smux。": "smux is unsupported for this protocol.",
        "测速地址需要 HTTP(S)，不能携带用户信息或片段。": "The test URL must use HTTP(S), without user information or fragments.",
        "目标引用或选项错误。": "Invalid target reference or options.",
        "离线测试未配置依赖存储。": "Dependency storage is not configured for offline tests.",
        "端口范围无效。": "Invalid port range.",
        "策略组引用了不存在的目标。": "The group references a missing target.",
        "策略组引用了不存在的节点 provider。": "The group references a missing proxy provider.",
        "筛选字段需要有限长度的字符串；最多 16 段表达式。": "Filter fields require bounded strings with up to 16 expressions.",
        "筛选／改名表达式无效、超过计算限额，或筛选后没有可用成员；未启用候选配置。": "Filtering/renaming is invalid, exceeds computation limits or leaves no members. The candidate was not activated.",
        "缺少快照。": "Missing snapshot.",
        "缺少规则快照。": "Missing rule snapshot.",
        "自定义 DNS 需要非空 nameserver；不会静默替换为默认上游。": "Custom DNS requires a nonempty nameserver. Default upstreams are not substituted silently.",
        "节点 provider 需要 Clash 节点 YAML。": "Proxy providers require Clash node YAML.",
        "节点列表需要 1–512 个具名节点。": "Node lists require 1–512 named nodes.",
        "节点筛选与 override 不适用于规则 provider。": "Node filtering and override do not apply to rule providers.",
        "节点链接数量需为 1–512。": "Provide 1–512 node URIs.",
        "规则 provider 引用不存在。": "The referenced rule provider does not exist.",
        "规则数量需为 1–20000。": "Provide 1–20000 rules.",
        "规则集 YAML 规范化失败。": "Rule-provider YAML normalization failed.",
        "规则集 payload 无效。": "Invalid rule-provider payload.",
        "规则集需要 UTF-8 文本。": "Rule providers require UTF-8 text.",
        "规则集需要字符串 payload 列表。": "Rule providers require a string payload list.",
        "订阅依赖快照损坏；原有版本未被替换。": "The dependency snapshot is damaged. The existing revision was not replaced.",
        "请求头格式未支持（内容已隐藏）。": "Unsupported request-header format (content hidden).",
        "进程规则停用与国际化域名适配目前仅支持主配置 rules；此 classical 条目未启用。": "Process-rule disabling and IDN adaptation apply only to main rules. This classical entry was not activated.",
        "进程规则格式或引用错误。": "Invalid process-rule format or reference.",
        "远程依赖尚未完整下载并校验；请通过导入或手动刷新建立完整快照。": "Remote dependencies are incomplete or unvalidated. Import or refresh manually to build a complete snapshot.",
        "远程依赖总数超过 35 项。": "Remote dependency count exceeds 35.",
        "需要 0–86400 秒的整数。": "Use an integer from 0 to 86400 seconds.",
        "需要 HTTPS 来源；远程 payload 回退尚不支持。": "An HTTPS source is required. Remote payload fallback is unsupported.",
        "需要 payload 规则列表。": "A payload rule list is required.",
        "需要 proxies 节点列表。": "A proxies node list is required.",
        "需要末尾 MATCH 规则，明确默认流量目标。": "A final MATCH rule must define the default traffic target.",
        "成员需要字符串列表。": "Members must be a string list.",
        "use 需要不重复的 provider 名称列表。": "use requires a list of unique provider names.",
        "use 引用了不存在的节点 provider。": "use references a missing proxy provider.",
        "上游地址列表格式未支持。": "Unsupported upstream address list.",
        "空配置不产生运行行为，运行配置省略此项；原文保留。非空内容仍需单独支持。": "Empty settings have no runtime effect and are omitted from runtime configuration. The original is retained; nonempty settings require separate support.",
        "桌面管理界面资源在 iOS 不加载；不下载或开放外部管理服务。": "Desktop management resources are not loaded on iOS. No external management service is downloaded or exposed.",
        "缺少配置": "No configuration",
        "结构或字段无效。": "Invalid structure or fields.",
        "依赖校验未通过。": "Dependency validation failed.",
        "校验未通过。": "Validation failed.",
        "协议与节点字段通过当前支持范围校验。": "Protocol and node fields passed compatibility validation.",
        "此节点跳过证书校验；首次使用此配置版本前必须明确授权，导入不会自动启用。": "This node skips certificate verification. Approve this revision before first use; importing does not authorize it.",
        "需要不超过 1 MiB 的 UTF-8 单文档 YAML 映射；请先修复语法，再检查全部字段。": "Use a single UTF-8 YAML mapping up to 1 MiB. Fix syntax before checking all fields.",
        "只支持 rule 模式。": "Only rule mode is supported.",
        "需要内联 proxies 成员列表。": "An inline proxies member list is required.",
        "MATCH 必须位于末尾。": "MATCH must be the last rule.",
        "策略组：未改变": "Groups: Unchanged", "策略组：已改变": "Groups: Changed",
        "规则：未改变": "Rules: Unchanged", "规则：已改变": "Rules: Changed",
        "DNS：未改变": "DNS: Unchanged", "DNS：已改变": "DNS: Changed",
        "其他配置：未改变": "Other settings: Unchanged", "其他配置：已改变": "Other settings: Changed",
        "仅原文排版或注释不同。": "Only formatting or comments changed.",
        "来源链接保持不变。": "Source URL unchanged.",
        "来源链接将更新并保存到本机钥匙串。": "The updated source URL will be saved in device Keychain.",
        "文件未定义 DNS：添加 redir-host 和经规则访问 Cloudflare DoH；节点引导解析使用连接前的系统 DNS，切网后需手动重连。": "No DNS was defined. Add redir-host and Cloudflare DoH through routing rules. Node bootstrap uses pre-connection system DNS; reconnect after changing networks.",
        "保留文件的 DNS 模式、上游、节点引导解析器和 DNS IPv6 设置，不改成原型默认 DNS。": "Retain the configuration’s DNS mode, upstreams, node bootstrap resolvers and DNS IPv6 settings.",
        "dns.listen 为桌面监听设置：iOS 使用 Packet Tunnel 的 DNS 接入，不开放该监听端口；原始设置保留在订阅中。": "dns.listen is a desktop listener. iOS uses Packet Tunnel DNS without opening that port; the original setting is retained.",
        "未启用 fallback GeoIP 筛选：不加载其国家分类，原始 geoip-code 保留在订阅中。": "Fallback GeoIP filtering is disabled. Its country data is not loaded; the original geoip-code is retained.",
        "缺少 default-nameserver：使用连接前的系统 DNS 引导上游域名，切网后需重连。": "No default-nameserver: upstream bootstrap uses pre-connection system DNS. Reconnect after changing networks.",
        "缺少 proxy-server-nameserver：使用上述引导 DNS 解析节点域名。": "No proxy-server-nameserver: node domains use the bootstrap DNS described above.",
        "system DNS 标记替换为连接前获取的系统 DNS 地址，避免隧道内循环解析；切网后重连获取新地址。": "Replace system DNS markers with pre-connection system DNS to avoid resolver loops. Reconnect after changing networks.",
        "未设置 dns.ipv6：沿用 Clash 默认值 false。": "dns.ipv6 is unspecified; use the Clash default false.",
        "不读取系统 hosts；fake-ip 映射仅在本次隧道会话中保存，重连后重建。": "System hosts are not read. Fake-IP mappings last only for this tunnel session and are rebuilt on reconnection.",
        "包含未启用 TLS 且协议本身不加密的节点；按原输入保留，没有自动增加 TLS。": "Contains nodes without TLS or protocol encryption. Original settings are retained; TLS is not added automatically.",
        "日志固定为 silent；关闭内核磁盘缓存。选择结果和原文件共同保存在本机钥匙串，不写入日志。": "Core logging is silent and disk caching is disabled. Selections and original configurations stay in device Keychain, outside logs.",
        "TUN 使用 gvisor、MTU 1280，由 iOS 安装 IPv4/IPv6 默认路由；不提供 ICMP 或局域网代理，系统保留流量可能不受默认路由覆盖。": "TUN uses gvisor, MTU 1280 and iOS IPv4/IPv6 default routes. ICMP and LAN proxy listeners are unavailable; some system traffic may bypass default routes.",
        "保留 ipv6: false。为避免手机原生 IPv6 绕过，仍接入 IPv6 默认路由，并在规则最前增加 IPv6 拒绝规则。": "Retain ipv6: false. Capture the IPv6 default route and prepend an IPv6 reject rule to prevent native IPv6 bypass.",
        "国际化域名规则在运行配置中转换为 ASCII/Punycode，以匹配 DNS 域名；原文保留。": "Convert internationalized domain rules to ASCII/Punycode for DNS matching. Original text is retained.",
        "智能分流：原有规则优先，在末尾 MATCH 前增加国内域名与中国大陆 IP 直连；其他流量保留原代理目标。国内分类基于规则数据，不能保证覆盖所有服务。": "Smart routing keeps existing rules first, adds mainland China domain/IP direct routes before MATCH, and retains the proxy fallback. Classification data cannot cover every service.",
        "智能 DNS：直连出口使用国内加密 DNS，经 DIRECT 发出；默认业务 DNS 经末尾代理目标发出，节点域名用连接前系统 DNS 引导。": "Smart DNS uses encrypted domestic resolvers through DIRECT for direct routes, the final proxy target for default DNS, and pre-connection system DNS for node bootstrap.",
        "智能 DNS：补充国内直连解析器，保留原 DNS 域名策略、默认上游、IPv6 和节点引导配置。": "Smart DNS adds a domestic direct resolver, retaining existing domain policies, default upstreams, IPv6 and node bootstrap settings.",
        "智能 DNS：订阅已指定直连解析器，完整保留；实际分流与解析需通过诊断确认。": "Smart DNS retains the subscription’s direct resolver. Verify actual routing and DNS with diagnostics.",
        "保留已支持的节点连接选项；显式 false 与关闭的 smux 从运行配置省略。smux.enabled:false 的其余子字段不应用，原文保留；MPTCP 仍仅接受关闭。": "Retain supported node options. Omit explicit false flags and disabled smux from runtime settings. Other disabled-smux fields remain only in the original; MPTCP must remain disabled.",
        "空 network 按内核默认 TCP 处理；空 packet-encoding 使用原始 UDP 编码。原文保留，不修改显式非空选项。": "Empty network uses default TCP; empty packet-encoding uses original UDP encoding. Preserve original text and explicit nonempty options.",
        "Hysteria2 的 udp:true 按协议原生 UDP 能力处理；此字段不传给不读取该开关的内核，原文保留。": "Hysteria2 uses native UDP support. udp:true is retained in the original but omitted from the core, which does not read it.",
        "profile：节点选择由 App 钥匙串管理；内核选择和 fake-IP 磁盘缓存关闭。": "profile: The app manages selections in Keychain. Core selection and Fake-IP disk caches are disabled.",
        "Geo 自动更新由完整订阅的手动刷新取代；运行期间不单独替换依赖，保证可回滚。": "Geo auto-update is replaced by manual subscription refresh. Dependencies are not replaced independently while running, preserving rollback.",
        "geodata-loader：iOS 固定使用 memconservative。": "geodata-loader: iOS uses memconservative.",
        "tun.enable: false：订阅的桌面 TUN 块已关闭，其余子字段不应用也不作功能校验；原文保留。连接时仍使用 App 管理的 iOS Packet Tunnel。": "tun.enable: false disables the desktop TUN block. Its other fields remain in the original without runtime validation. Connections still use the app-managed iOS Packet Tunnel.",
        "sniffer.enable: false：保留关闭语义，其余子字段不应用也不作功能校验；原文保留，不启用域名嗅探。": "sniffer.enable: false keeps sniffing disabled. Other fields remain in the original without runtime validation.",
        "节点链接已在本机转换；未使用公共转换服务。链接节点的 UDP 开关设为 true；保留原始输入供刷新与回滚。": "Node URIs are converted locally without public conversion services. UDP is enabled for URI nodes; original input is retained for refresh and rollback.",
        "节点链接中存在重名，已添加序号以保留全部节点。": "Duplicate URI node names receive number suffixes to retain every node.",
        "select 组指定的正数健康检查间隔最低适配为 60 秒。": "Positive select-group health-check intervals have a minimum of 60 seconds.",
        "策略组 icon / hidden 属于客户端展示提示：iOS 使用现有图标并显示全部组，不下载远程图标；组选择语义保留。": "Group icon / hidden fields are display hints. iOS uses existing icons and shows all groups without downloading icons; selection semantics are preserved.",
        "策略组筛选沿用固定内核：filter 筛选自动收集与 provider 成员，不排除显式 proxies；exclude-filter 与 exclude-type 对全部成员生效。空组拒绝导入，不自动直连。": "Core group filtering applies filter to automatic/provider members, not explicit proxies. exclude-filter and exclude-type apply to all members. Empty groups are rejected rather than routed directly.",
        "include-all 按内核顺序展开：显式成员优先，自动节点与 providers 按名称排序；自动收集不重复加入已有节点，不收集策略组。include-all-providers 替代 use。每次刷新重新计算，原始字段保留；空组仍明确拒绝，避免自动直连。": "include-all expands in core order: explicit members first, then sorted automatic nodes/providers. It adds no duplicate nodes or groups. include-all-providers replaces use. Refresh recalculates membership, retaining original fields; empty groups are rejected.",
        "url-test / fallback / load-balance 由内核执行自动选择或连接分配；未指定测速地址时使用 Cloudflare HTTPS 204，默认 300 秒、lazy=true；正数间隔最低适配为 60 秒，0 采用内核默认 300 秒。测速会产生网络请求和耗电，断开隧道后停止。": "The core handles url-test / fallback / load-balance selection or distribution. Defaults are Cloudflare HTTPS 204, 300 seconds and lazy=true. Positive intervals have a 60-second minimum; 0 uses 300 seconds. Checks use network and battery and stop with the tunnel.",
        "provider 健康检查保留，启用时默认 300 秒、lazy=true，正数间隔最低 60 秒；会产生请求与耗电。": "Provider health checks are retained. Defaults are 300 seconds and lazy=true, with a 60-second minimum positive interval. Checks use network and battery.",
        "provider 按原节点名称和类型筛选，再应用 override；改名、UDP、证书与带宽覆盖后重新校验有效节点。有效快照保留健康检查；刷新和回滚从各版本原文重新计算，改名重名或空结果拒绝采用。": "Providers filter original node names/types before applying overrides. Revalidate renamed nodes and UDP, certificate and bandwidth overrides. Snapshots retain health checks; refresh/rollback recalculate from original input. Duplicate names or empty results are rejected.",
        "providers 与 Geo 资源在 App 中受控准备并校验；默认 Geo 优先使用完整本地快照或内置 MetaCubeX 数据，自定义来源不替换；手动更新访问对应来源，仅这些固定无凭据地址允许跳转至 GitHub release CDN。依赖和主订阅共同保存、刷新与回滚；扩展只读取快照，不按 interval 独立更新。桌面 path 被替换，不读取任意本地路径；规则集 YAML 规范化为块列表供内核读取，快照保留原文。": "The app prepares and validates provider/Geo resources. Default Geo uses complete local snapshots or bundled MetaCubeX data; custom sources are retained. Manual updates fetch original sources; only pinned public sources may redirect to GitHub’s release CDN. Dependencies refresh and roll back with the subscription. The extension reads snapshots without interval updates. Desktop paths are replaced; arbitrary local paths are not read. Rule YAML is normalized for the core while snapshots retain original text."
    ]
}
