import Foundation

@main struct ImportFormatChecks {
    static func main() throws {
        var checks = 0
        func check(_ name: String, _ condition: @autoclosure () throws -> Bool) throws {
            checks += 1
            guard try condition() else { fatalError("Failed synthetic format check: " + name) }
        }
        let fixtures: [(String, String, ConfigurationFormat)] = [
            ("sing-box", "{\"outbounds\":[{\"type\":\"shadowsocks\",\"password\":\"FICTIONAL-SECRET\"}]}", .singBox),
            ("xray", "{\"outbounds\":[{\"protocol\":\"vless\",\"settings\":{}}]}", .xray),
            ("ambiguous-empty", "{\"outbounds\":[]}", .outboundJSON),
            ("sing-box-yaml", "outbounds:\n  - type: direct\n", .singBox),
            ("json-comments", "// example\n{\"outbounds\": [{\"protocol\":\"freedom\"}]}", .xray),
            ("json-block-comments", "/* example */ {\"outbounds\": [{\"type\":\"direct\",\"tag\":\"https://example.invalid/\\\"/*\"}]}", .singBox),
            ("SIP008", "{\"version\":1,\"servers\":[]}", .shadowsocks),
            ("ss-json", "{\"server\":\"node.example.invalid\",\"method\":\"aes-128-gcm\",\"password\":\"FICTIONAL-SECRET\"}", .shadowsocks),
            ("wireguard-comments-bom-crlf", "\u{FEFF}# comment\r\n; comment\r\n[Interface]\r\nPrivateKey=FICTIONAL-SECRET\r\n[Peer]\r\n", .wireGuard),
            ("wireguard-inline-comment", "[Interface] # comment\nPrivateKey=FICTIONAL-SECRET", .wireGuard),
            ("surge-family", "# example\n[General]\nloglevel=notify\n[Proxy]\n", .proxyINI),
            ("quantumult", "[general]\nserver_check_url=https://example.invalid\n[server_remote]\n", .quantumult),
            ("openvpn", "# example\r\nclient\r\ndev tun\r\nremote node.example.invalid 443\r\n", .openVPN),
            ("html-comments", "<!-- example -->\n<!DOCTYPE HTML><html>FICTIONAL-SECRET</html>", .html),
            ("html-fragment", "<body>Sign in</body>", .html),
            ("apple-profile", "<?xml version=\"1.0\"?><plist><dict><key>PayloadType</key><string>Configuration</string></dict></plist>", .appleProfile),
            ("rule-fragment", "payload:\n  - DOMAIN,example.invalid\n", .ruleProvider),
            ("unknown-mapping", "FICTIONAL-SECRET: value\n", .unrecognized)
        ]
        for (name, content, expected) in fixtures {
            let data = Data(content.utf8)
            do {
                _ = try ConfigurationInput.read(data)
                fatalError("Foreign input unexpectedly accepted: " + name)
            } catch let issue as ConfigurationIssue {
                try check(name + " category", issue.code == .incompatibleFormat && issue.detail == expected.message)
                try check(name + " privacy", !issue.detail.contains("FICTIONAL-SECRET") && !issue.detail.contains("node.example.invalid"))
                try check(name + " English", DiagnosticText.english(issue.detail + "（2020）") == expected.englishMessage + " (2020)")
            } catch { fatalError("Missing format diagnosis: " + name) }
            let report = ConfigurationCompatibility.inspect(data)
            try check(name + " info", report.findings.count == 1 && report.findings.first?.detail == expected.message && !report.canUse)
        }
        let fixture = Data(CompatibilityFixture.yaml.utf8)
        let root = try PrototypeConfiguration.decode(fixture)
        try check("Clash YAML", try ConfigurationInput.read(fixture).root["proxies"] != nil)
        let json = try JSONSerialization.data(withJSONObject: root)
        try check("Clash JSON", try ConfigurationInput.read(json).root["proxies"] != nil)
        var tricky = root
        tricky["secret"] = "[Peer] <ca> outbounds FICTIONAL-SECRET"
        try check("markers inside values", try ConfigurationInput.read(JSONSerialization.data(withJSONObject: tricky)).root["proxies"] != nil)
        let yaml = String(decoding: fixture, as: UTF8.self) + "\nsecret: |\n  [Peer]\n  <ca>\n"
        try check("markers inside YAML block", try ConfigurationInput.read(Data(yaml.utf8)).root["proxies"] != nil)
        tricky["outbounds"] = []
        let report = ConfigurationCompatibility.inspect(try JSONSerialization.data(withJSONObject: tricky))
        try check("Clash extra fields stay field errors", !report.canUse && !report.findings.contains { $0.detail == ConfigurationFormat.outboundJSON.message })
        let nodes = try JSONSerialization.data(withJSONObject: ["proxies": root["proxies"]!])
        try check("nodes-only template", try ConfigurationInput.read(nodes).root["proxy-groups"] != nil)
        let uri = "hy2://FICTIONAL@node.example.invalid#Example"
        for input in [uri, Data(uri.utf8).base64EncodedString()] {
            try check("supported node input", try ConfigurationInput.read(Data(input.utf8)).root["proxies"] != nil)
        }
        for input in ["proxies: [", "proxies: []\nproxies: []\n", "proxies: []\n---\nproxies: []"] {
            do { _ = try ConfigurationInput.read(Data(input.utf8)); fatalError("Invalid syntax accepted") }
            catch { try check("invalid YAML still rejected", error is PrototypeError || error is ConfigurationIssue) }
        }
        let baseline = PrototypeSelfCheck.run()
        for failure in baseline.failures { FileHandle.standardError.write(Data(("Baseline failure: " + failure + "\n").utf8)) }
        try check("existing configuration and storage regression", baseline.failures.isEmpty)
        print(baseline.summary)
        print("Import format checks: \(checks) passed; synthetic inputs only, no network or Keychain.")
    }
}
