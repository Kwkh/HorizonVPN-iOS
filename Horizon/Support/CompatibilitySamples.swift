import Foundation

/// Reproducible fictional shapes, never copied from a credential-bearing subscription.
enum CompatibilitySamples {
    struct Sample: Identifiable {
        let id: String
        let title: String
        let yaml: String
        let usable: Bool
        var englishTitle: String {
            switch id {
            case "ss-plugins-balance": "SS plugins / Load balancing · Fictional nodes"
            case "dns-policy-hosts": "DNS rule sets / Proxy targets / Hosts"
            case "node-connection-options": "TFO / IP preference / smux"
            case "disabled-options": "Disabled options / Empty defaults"
            case "enabled-options-blocked": "Unsupported enabled features"
            case "reality-grpc-tuic": "Reality + gRPC / TUIC v5 · Fictional nodes"
            case "ios-process-idna": "Process rules / IPv6 aliases / IDN"
            case "provider-selection-policy": "Provider filtering / Renaming / Overrides"
            case "empty-filter-result": "Empty filter results · Import rejected"
            case "automatic-membership": "Automatic membership / HTTP status codes"
            case "node-bundle-metadata": "Node lists with DNS and metadata"
            case "automatic-groups": "Automatic testing / Fallback selection"
            case "inline-providers": "Inline proxy and rule providers"
            case "desktop-dns-listener": "Desktop DNS listener / prefer-h3: false"
            case "dns-h3-pending": "DNS HTTP/3 preference · true unsupported"
            case "desktop-metadata": "Desktop metadata / DNS IP:port"
            case "extended-protocols": "SS / SS2022 / VMess / VLESS / Trojan"
            case "dual-protocol": "HY2 + VLESS · select · fake-ip"
            case "desktop-controller": "Desktop controller / Secret · Disabled on iOS"
            case "system-dns": "System bootstrap DNS"
            case "unsupported-mixed": "Mixed protocols / Providers / Geo rules"
            case "unsupported-dns": "DoQ / Invalid fields"
            case "invalid-reference": "Invalid target references"
            default: "Compatibility example"
            }
        }
    }
    static let all: [Sample] = [
        .init(id: "ss-plugins-balance", title: "SS 插件／负载均衡 · 虚构节点", yaml: """
        proxies:
          - {name: OBFS, type: ss, server: node.example.invalid, port: 443, cipher: aes-128-gcm, password: FICTIONAL-ONLY, plugin: obfs, plugin-opts: {mode: tls, host: cdn.example.invalid}}
          - {name: WS, type: ss, server: node.example.invalid, port: 443, cipher: aes-128-gcm, password: FICTIONAL-ONLY, plugin: v2ray-plugin, plugin-opts: {mode: websocket, tls: true, skip-cert-verify: true, host: cdn.example.invalid, path: /ws}}
        proxy-groups:
          - {name: BALANCE, type: load-balance, strategy: round-robin, proxies: [OBFS, WS]}
        rules: ['MATCH,BALANCE']
        """, usable: true),
        .init(id: "dns-policy-hosts", title: "DNS 规则集／指定代理／hosts · 本地用例", yaml: """
        proxies:
          - {name: EXAMPLE, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [EXAMPLE]}
        rules: ['MATCH,SELECT']
        hosts: {host.example.invalid: [192.0.2.5, '2001:db8::5']}
        rule-providers:
          domains: {type: inline, behavior: domain, payload: ['+.example.invalid']}
        dns:
          nameserver: ['1.1.1.1']
          default-nameserver: ['1.1.1.1']
          use-hosts: true
          nameserver-policy:
            'rule-set:domains': ['https://1.1.1.1/dns-query#SELECT']
            '+.local.invalid': system
        """, usable: true),
        .init(id: "node-connection-options", title: "TFO／IP 偏好／smux · 参数保留", yaml: """
        proxies:
          - name: EXAMPLE
            type: vmess
            server: node.example.invalid
            port: 443
            uuid: 11111111-1111-4111-8111-111111111111
            cipher: auto
            alterId: 0
            tfo: true
            ip-version: ipv4-prefer
            global-padding: true
            authenticated-length: true
            smux: {enabled: true, protocol: h2mux, max-connections: 2, min-streams: 4, padding: true, only-tcp: true}
        """, usable: true),
        .init(id: "disabled-options", title: "显式关闭项与空默认值 · iOS 适配", yaml: """
        tun: {enable: false, stack: mixed, auto-route: true}
        sniffer: {enable: false, sniff: {TLS: {ports: [443]}}}
        hosts: {}
        listeners: []
        authentication: []
        proxies:
          - name: EXAMPLE
            type: vmess
            server: node.example.invalid
            port: 443
            uuid: 11111111-1111-4111-8111-111111111111
            cipher: auto
            alterId: 0
            network: ''
            packet-encoding: ''
            tfo: false
            mptcp: false
            smux: {enabled: false, protocol: smux}
            global-padding: false
            authenticated-length: false
        """, usable: true),
        .init(id: "enabled-options-blocked", title: "启用未接入功能 · 仍明确拒绝", yaml: PrototypeSelfCheck.fixture
            + "\ntun: {enable: true}\nsniffer: {enable: true}\n", usable: false),
        .init(id: "reality-grpc-tuic", title: "Reality + gRPC／TUIC v5 · 虚构节点", yaml: """
        proxies:
          - name: EXAMPLE-REALITY-GRPC
            type: vless
            server: node.example.invalid
            port: 443
            uuid: 11111111-1111-4111-8111-111111111111
            tls: true
            network: grpc
            servername: tls.example.invalid
            client-fingerprint: chrome
            reality-opts: {public-key: '\(CompatibilityFixture.publicKey)', short-id: '0123456789abcdef'}
            grpc-opts: {grpc-service-name: example}
          - {name: EXAMPLE-TUIC, type: tuic, server: node.example.invalid, port: 443, uuid: 11111111-1111-4111-8111-111111111111, password: FICTIONAL-ONLY, alpn: [h3], udp-relay-mode: native, congestion-controller: bbr}
        """, usable: true),
        .init(id: "ios-process-idna", title: "进程规则停用／IPv6 别名／国际化域名", yaml: """
        proxies:
          - {name: EXAMPLE, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY, skip-cert-verify: true}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [EXAMPLE]}
        rules:
          - PROCESS-NAME,ExampleDesktop,DIRECT
          - IP-CIDR,2001:db8::/32,DIRECT,no-resolve
          - DOMAIN-SUFFIX,例子.测试,DIRECT
          - MATCH,SELECT
        """, usable: true),
        .init(id: "provider-selection-policy", title: "节点筛选／排除 · provider 改名与覆盖", yaml: """
        proxy-providers:
          example:
            type: inline
            filter: '^(US|JP)-'
            exclude-filter: 'low$'
            override:
              additional-prefix: 'P-'
              udp: true
              skip-cert-verify: false
            payload:
              - {name: US-example, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
              - {name: JP-example, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
              - {name: US-low, type: trojan, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [DIRECT], include-all-providers: true, filter: '^P-US', exclude-type: Shadowsocks}
        rules: ['MATCH,SELECT']
        """, usable: true),
        .init(id: "empty-filter-result", title: "筛选结果为空 · 明确拒绝自动直连", yaml: PrototypeSelfCheck.fixture
            .replacingOccurrences(of: "type: select", with: "type: select\n    exclude-filter: '.*'"), usable: false),
        .init(id: "automatic-membership", title: "自动收集节点 · 数字 HTTP 状态码", yaml: """
        proxies:
          - {name: EXAMPLE-Z, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
          - {name: EXAMPLE-A, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: SELECT, type: select, include-all-proxies: true, expected-status: 204}
        rules: ['MATCH,SELECT']
        dns: {listen: ':1053', nameserver: ['1.1.1.1']}
        """, usable: true),
        .init(id: "node-bundle-metadata", title: "节点列表携带 DNS 与元数据", yaml: """
        proxies:
          - {name: EXAMPLE, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        ipv6: false
        log-level: info
        dns: {nameserver: ['9.9.9.9'], default-nameserver: ['1.1.1.1']}
        """, usable: true),
        .init(id: "automatic-groups", title: "自动测速与回退 · 不猜测离线选择", yaml: """
        proxies:
          - {name: EXAMPLE-A, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
          - {name: EXAMPLE-B, type: hysteria2, server: backup.example.invalid, port: 443, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [AUTO, BACKUP, EXAMPLE-A]}
          - {name: AUTO, type: url-test, proxies: [EXAMPLE-A, EXAMPLE-B], interval: 300, tolerance: 50, lazy: true}
          - {name: BACKUP, type: fallback, proxies: [EXAMPLE-A, EXAMPLE-B], interval: 300, lazy: true}
        rules: ['NETWORK,UDP,SELECT', 'DST-PORT,80/443,SELECT', 'MATCH,SELECT']
        """, usable: true),
        .init(id: "inline-providers", title: "内联节点与规则 provider · 完整本地用例", yaml: """
        proxy-providers:
          example:
            type: inline
            payload:
              - {name: EXAMPLE-A, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        rule-providers:
          example:
            type: inline
            behavior: domain
            payload: ['+.example.invalid']
        proxy-groups:
          - {name: SELECT, type: select, use: [example]}
        rules: ['RULE-SET,example,DIRECT', 'MATCH,SELECT']
        """, usable: true),
        .init(id: "desktop-dns-listener", title: "桌面 DNS 监听适配 · prefer-h3: false", yaml: PrototypeSelfCheck.fixture + "\ndns: {listen: '0.0.0.0:1053', prefer-h3: false, nameserver: ['1.1.1.1'], default-nameserver: ['1.1.1.1']}\n", usable: true),
        .init(id: "dns-h3-pending", title: "DNS HTTP/3 偏好 · 尚未支持 true", yaml: PrototypeSelfCheck.fixture + "\ndns: {prefer-h3: true, nameserver: ['https://1.1.1.1/dns-query']}\n", usable: false),
        .init(id: "desktop-metadata", title: "桌面元数据 · DNS IP:端口适配", yaml: PrototypeSelfCheck.fixture + "\nprofile: {store-selected: true, store-fake-ip: true}\nexternal-ui: 'fictional-ui'\nredir-port: 7893\ntcp-concurrent: true\nfind-process-mode: off\ndns: {nameserver: ['1.1.1.1:53'], default-nameserver: ['1.1.1.1']}\n", usable: true),
        .init(id: "extended-protocols", title: "SS／SS2022 · VMess／VLESS／Trojan · TCP／WS／gRPC", yaml: String(decoding: ExtendedCompatibilitySelfCheck.document, as: UTF8.self), usable: true),
        .init(id: "dual-protocol", title: "HY2 + VLESS · select · fake-ip", yaml: CompatibilityFixture.yaml, usable: true),
        .init(id: "desktop-controller", title: "桌面控制接口与密钥 · iOS 明确不启用", yaml: CompatibilityFixture.yaml
            + "\nexternal-controller: '127.0.0.1:19090'\nsecret: 'FICTIONAL-CONTROLLER-ONLY'\n", usable: true),
        .init(id: "system-dns", title: "系统引导 DNS 适配", yaml: """
        proxies:
          - {name: EXAMPLE, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: SELECT, type: select, proxies: [EXAMPLE]}
        rules: ['MATCH,SELECT']
        """, usable: true),
        .init(id: "unsupported-mixed", title: "混合协议、自动组、providers 和 Geo 规则", yaml: """
        proxy-providers: {}
        rule-providers: {}
        sniffer: {enable: true}
        proxies:
          - {name: EXAMPLE-SS, type: ss, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
          - {name: EXAMPLE-TUIC, type: tuic, server: node.example.invalid, port: 443, password: FICTIONAL-ONLY}
        proxy-groups:
          - {name: AUTO, type: url-test, proxies: [EXAMPLE-SS, EXAMPLE-TUIC], url: 'https://example.invalid/probe', interval: 300}
        rules: ['GEOSITE,cn,DIRECT', 'RULE-SET,remote,AUTO', 'MATCH,AUTO']
        """, usable: false),
        .init(id: "unsupported-dns", title: "DoQ 与多项字段错误", yaml: CompatibilityFixture.yaml
            .replacingOccurrences(of: "https://1.1.1.1/dns-query", with: "quic://dns.example.invalid")
            + "\nprofile: {store-selected: true}\nhosts: {}\n", usable: false),
        .init(id: "invalid-reference", title: "多条无效引用", yaml: CompatibilityFixture.yaml
            .replacingOccurrences(of: "proxies: [TEST-HY2, TEST-VLESS]", with: "proxies: [MISSING-A, MISSING-B]")
            .replacingOccurrences(of: "MATCH,TEST-SELECT", with: "MATCH,MISSING-C"), usable: false)
    ]
}
