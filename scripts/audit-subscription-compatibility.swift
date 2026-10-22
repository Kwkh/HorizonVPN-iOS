import Foundation

/// Read-only compatibility inventory using fictional inputs. No network, VPN or Keychain.
/// Compile with the same supporting sources as check-configuration.swift, replacing its @main.
@main struct SubscriptionCompatibilityAudit {
    static func main() throws {
        let base = try PrototypeConfiguration.decode(Data(CompatibilityFixture.yaml.utf8))
        var results: [[String: Any]] = []
        func data(_ root: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) }
        func probe(_ name: String, _ source: Data) {
            do {
                let p = try PrototypeConfiguration.prepare(source)
                results.append(["case":name,"accepted":true,"nodes":p.catalog.nodes.count,"adaptations":p.adaptations.count])
            } catch let e as ConfigurationIssue {
                results.append(["case":name,"accepted":false,"reason":e.detail])
            } catch let e as PrototypeError {
                results.append(["case":name,"accepted":false,"reason":e.summary])
            } catch { results.append(["case":name,"accepted":false,"reason":"validation failed"]) }
        }
        func text(_ name: String, _ s: String) { probe(name,Data(s.utf8)) }
        func field(_ name: String, _ key: String, _ value: Any) { var r=base; r[key]=value; probe(name,data(r)) }
        text("format/clash-yaml",CompatibilityFixture.yaml)
        probe("format/clash-json",data(base))
        probe("format/proxies-only",data(["proxies":ExtendedCompatibilitySelfCheck.nodes]))
        text("format/yaml-bom","\u{feff}"+CompatibilityFixture.yaml)
        text("format/yaml-crlf",CompatibilityFixture.yaml.replacingOccurrences(of:"\n",with:"\r\n"))
        text("format/yaml-merge-anchor","""
        proxies:
          - &node {name: ONE, type: hysteria2, server: node.example.invalid, port: 443, password: FICTIONAL}
          - {<<: *node, name: TWO}
        """)
        text("format/yaml-extra-document",CompatibilityFixture.yaml+"\n---\n{}");
        probe("format/sing-box-json",data(["outbounds":[["type":"direct","tag":"direct"]]]))
        probe("format/xray-json",data(["outbounds":[["protocol":"freedom","tag":"direct"]]]))
        probe("format/shadowsocks-json",data(["server":"node.example.invalid","server_port":443,"password":"FICTIONAL","method":"aes-128-gcm"]))
        probe("format/sip008",data(["version":1,"servers":[["id":"11111111-1111-4111-8111-111111111111","remarks":"EXAMPLE","server":"node.example.invalid","server_port":443,"password":"FICTIONAL","method":"aes-128-gcm"]]]))
        text("format/surge-ini","[Proxy]\nEXAMPLE = trojan,node.example.invalid,443,password=FICTIONAL\n[Rule]\nFINAL,EXAMPLE")
        text("format/wireguard-ini","[Interface]\nPrivateKey = FICTIONAL\n[Peer]\nEndpoint = node.example.invalid:443")
        text("format/openvpn","client\ndev tun\nremote node.example.invalid 1194\nproto udp")
        let uri="hy2://FICTIONAL@node.example.invalid:443?sni=tls.example.invalid#EXAMPLE"
        text("format/uri",uri)
        text("format/uri-list",uri+"\n"+uri.replacingOccurrences(of:"EXAMPLE",with:"SECOND"))
        text("format/base64",Data(uri.utf8).base64EncodedString())
        text("format/base64url-unpadded",Data(uri.utf8).base64EncodedString().replacingOccurrences(of:"=",with:"").replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_"))
        text("format/uri-with-comment","# subscription\n"+uri)
        text("format/uri-with-bom","\u{feff}"+uri)
        text("uri/hy2-default-port",uri.replacingOccurrences(of:":443",with:""))
        text("uri/hy2-userpass",uri.replacingOccurrences(of:"FICTIONAL@",with:"user:FICTIONAL@"))
        text("uri/hy2-port-hopping",uri.replacingOccurrences(of:":443",with:":443,8443"))
        text("uri/hy2-insecure",uri.replacingOccurrences(of:"?sni=",with:"?insecure=1&sni="))
        let ss="ss://"+Data("aes-128-gcm:FICTIONAL".utf8).base64EncodedString()+"@node.example.invalid:443"
        text("uri/ss",ss)
        text("uri/ss-plugin",ss+"?plugin=obfs-local%3Bobfs%3Dhttp")
        text("uri/mixed-supported-unsupported",uri+"\nssr://FICTIONAL")
        let fields:[(String,Any)] = [("external-controller","127.0.0.1:19090"),("secret","FICTIONAL"),("tcp-concurrent",true),("profile",["store-selected":true]),("global-client-fingerprint","chrome"),("find-process-mode","off"),("keep-alive-interval",15),("external-ui","dashboard"),("authentication",["user:FICTIONAL"]),("redir-port",0),("tproxy-port",0),("tun",["enable":false]),("sniffer",["enable":false]),("proxy-providers",[:]),("rule-providers",[:]),("geodata-mode",true),("hosts",["test.example.invalid":"192.0.2.1"]),("mode","global")]
        for (key,value) in fields { field("top/"+key,key,value) }
        for kind in ["select","url-test","fallback","load-balance","relay"] {
            var groups=base["proxy-groups"] as! [[String:Any]]; groups[0]["type"]=kind
            field("group/"+kind,"proxy-groups",groups)
        }
        for (key,value) in [("icon","https://example.invalid/icon.png"),("url","https://example.invalid/probe"),("filter","EXAMPLE")] {
            var groups=base["proxy-groups"] as! [[String:Any]]; groups[0][key]=value
            field("group/select-"+key,"proxy-groups",groups)
        }
        for kind in ["tuic","anytls","ssr","hysteria","wireguard","http","socks5","snell"] {
            probe("node/"+kind,data(["proxies":[["name":"EXAMPLE","type":kind,"server":"node.example.invalid","port":443,"password":"FICTIONAL"]]]))
        }
        for key in ["udp","ports"] {
            var nodes=base["proxies"] as! [[String:Any]]; nodes[0][key] = key == "udp" ? true : "443,8443"
            field("node/hy2-"+key,"proxies",nodes)
        }
        var vmess=ExtendedCompatibilitySelfCheck.nodes.first { $0["name"] as? String == "vmess-tcp" }!
        vmess.removeValue(forKey:"cipher"); probe("node/vmess-default-cipher",data(["proxies":[vmess]]))
        for rule in ["DOMAIN,example.invalid,DIRECT","IP-CIDR6,2001:db8::/32,DIRECT,no-resolve","GEOIP,CN,DIRECT","GEOSITE,cn,DIRECT","RULE-SET,EXAMPLE,DIRECT","DST-PORT,443,DIRECT","NETWORK,UDP,DIRECT","PROCESS-NAME,EXAMPLE,DIRECT","AND,((NETWORK,TCP),(DST-PORT,443)),DIRECT"] {
            field("rule/"+String(rule.prefix(while:{$0 != ","})),"rules",[rule,"MATCH,TEST-SELECT"])
        }
        for (name,value) in [("plain-port","1.1.1.1:53"),("udp","udp://1.1.1.1:53"),("dot","tls://1.1.1.1"),("doh","https://1.1.1.1/dns-query"),("doq","quic://1.1.1.1"),("doh-query","https://1.1.1.1/dns-query?foo=bar"),("system","system"),("doh-proxy","https://1.1.1.1/dns-query#TEST-SELECT")] {
            var dns=base["dns"] as! [String:Any];dns["nameserver"]=[value];field("dns/"+name,"dns",dns)
        }
        for (key,value) in [("listen","0.0.0.0:53"),("fake-ip-filter-mode","rule")] {
            var dns=base["dns"] as! [String:Any];dns[key]=value;field("dns/"+key,"dns",dns)
        }
        var dns=base["dns"] as! [String:Any];dns["nameserver-policy"]=["geosite:cn":"https://1.1.1.1/dns-query"];field("dns/geosite-policy","dns",dns)
        var many:[String:Any] = [:]
        many["proxies"]=(0..<129).map { i -> [String:Any] in var n=ExtendedCompatibilitySelfCheck.nodes[0];n["name"]="N-\(i)";return n }
        probe("limit/129-nodes",data(many))
        let summary:[String:Any] = ["total":results.count,"accepted":results.filter{$0["accepted"] as? Bool == true}.count,"cases":results]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]))
    }
}
