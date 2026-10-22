package hako

import (
 "net/netip"
 "net"
 "context"
 "time"
 "github.com/TokenPLS/Hako/dns"
 D "github.com/miekg/dns"
 "os"
 "path/filepath"
 "testing"
 "strings"
 C "github.com/TokenPLS/Hako/constant"
 "github.com/TokenPLS/Hako/component/geodata"
)

// Real pinned-core matching with bundled data. Only local synthetic DNS listeners.
func TestHorizonSmartRouting(t *testing.T) {
 options:=testOptions(t); options.PrivateDiagnostics=true; options.DisablePersistentCache=true
 options.MemoryLimit=40*1024*1024
 if err:=Setup(options);err!=nil {t.Fatal(err)}
 base:=filepath.Join(os.Getenv("CLASH_FIXTURE_DIR"),"smart-routing")
 for _,name:=range []string{"GeoSite.dat","geoip.metadb"} {
  data,e:=os.ReadFile(filepath.Join(base,name));if e!=nil {t.Fatal(e)}
  if e=os.WriteFile(filepath.Join(options.WorkingPath,name),data,0600);e!=nil {t.Fatal(e)}
 }
 raw,err:=os.ReadFile(filepath.Join(base,"runtime.json"));if err!=nil {t.Fatal(err)}
 if result,e:=PrepareGeoSiteCache(string(raw)); e!=nil || !strings.Contains(result,", 0 failed of ") {t.Fatalf("GeoSite compilation failed: %s %v",result,e)}
 if err=CheckConfig(string(raw));err!=nil {t.Fatal(err)}
 cfg,err:=parseConfigForIOS(string(raw),true);if err!=nil {t.Fatal(err)}
 defer closeCatalogObjects(cfg.Proxies,cfg.Providers)
 geodata.SetGeodataMode(cfg.General.GeodataMode)
 defer geodata.SetGeodataMode(false)
 fallback:=cfg.Rules[len(cfg.Rules)-1].Adapter()
 cases:=[]struct{name,host,ip,want string}{
  {"wechat-domain","weixin.qq.com","","DIRECT"},
  {"bilibili-domain","www.bilibili.com","","DIRECT"},
  {"domestic-ipv4","","223.5.5.5","DIRECT"},
  {"domestic-ipv6","","2400:3200::1","DIRECT"},
  {"foreign-ipv4","","1.1.1.1",fallback},
  {"foreign-ipv6","","2606:4700:4700::1111",fallback},
  {"foreign-domain","www.example.invalid","1.1.1.1",fallback},
 }
 for _,network:=range []C.NetWork{C.TCP,C.UDP} {
 for _,tc:=range cases {t.Run(tc.name+"-"+network.String(),func(t *testing.T){
  m:=&C.Metadata{Host:tc.host,NetWork:network};if tc.ip!="" {m.DstIP=netip.MustParseAddr(tc.ip)}
  var got string
  for _,rule:=range cfg.Rules {if ok,target:=rule.Match(m,C.RuleMatchHelper{});ok {got=target;break}}
  if got!=tc.want {t.Fatalf("got %s, want %s",got,tc.want)}
 })}
 }
 if len(cfg.DNS.NameServerPolicy)!=1 || !cfg.DNS.NameServerPolicy[0].Matcher.MatchDomain("weixin.qq.com") {t.Fatal("domestic DNS policy missing")}
 for _,server:=range cfg.DNS.NameServerPolicy[0].NameServers {if server.ProxyName!="DIRECT" {t.Fatal("domestic DNS depends on proxy")}}
 if len(cfg.DNS.DirectNameServer)!=2 {t.Fatal("direct resolver missing")}
 for _,server:=range cfg.DNS.DirectNameServer {if server.ProxyName!="DIRECT" || server.Net!="https" {t.Fatal("direct DNS not explicitly direct encrypted")}}
 if len(cfg.DNS.NameServer)!=1 || cfg.DNS.NameServer[0].ProxyName!=fallback {t.Fatal("foreign DNS does not follow proxy fallback")}
 if len(cfg.DNS.ProxyServerNameserver)==0 {t.Fatal("node bootstrap missing")}
 // Exercise actual DNS dispatch with local synthetic responders, never public resolvers.
 server:=func(address string) string {
  conn,e:=net.ListenPacket("udp","127.0.0.1:0");if e!=nil {t.Fatal(e)}
  srv:=&D.Server{PacketConn:conn,Handler:D.HandlerFunc(func(w D.ResponseWriter,q *D.Msg){
   response:=new(D.Msg);response.SetReply(q)
   typ:="A";ip:=address
   if q.Question[0].Qtype==D.TypeAAAA {typ="AAAA";if address=="192.0.2.1" {ip="2001:db8::1"} else {ip="2001:db8::2"}}
   rr,_:=D.NewRR(q.Question[0].Name+" 60 IN "+typ+" "+ip);response.Answer=[]D.RR{rr};_ = w.WriteMsg(response)
  })}
  go func(){_ = srv.ActivateAndServe()}();t.Cleanup(func(){_ = srv.Shutdown()});return conn.LocalAddr().String()
 }
 domestic,foreign:=server("192.0.2.1"),server("192.0.2.2")
 policies:=append([]dns.Policy(nil),cfg.DNS.NameServerPolicy...)
 for i:=range policies {policies[i].NameServers=[]dns.NameServer{{Addr:domestic}}}
 resolvers:=dns.NewResolver(dns.Config{Main:[]dns.NameServer{{Addr:foreign}},DirectServer:[]dns.NameServer{{Addr:domestic}},Policy:policies,IPv6:true})
 defer resolvers.CloseQueries()
 for _,test:=range []struct{name string;kind uint16;want string}{
  {"weixin.qq.com",D.TypeA,"192.0.2.1"},{"weixin.qq.com",D.TypeAAAA,"2001:db8::1"},
  {"foreign.example.invalid",D.TypeA,"192.0.2.2"},{"foreign.example.invalid",D.TypeAAAA,"2001:db8::2"},
 } {t.Run("dns-"+test.name+"-"+D.TypeToString[test.kind],func(t *testing.T){
  ctx,cancel:=context.WithTimeout(context.Background(),2*time.Second);defer cancel()
  q:=new(D.Msg);q.SetQuestion(test.name+".",test.kind)
  answer,e:=resolvers.ExchangeContext(ctx,q);if e!=nil || len(answer.Answer)!=1 {t.Fatalf("DNS response: %v",e)}
  var ip string;switch rr:=answer.Answer[0].(type){case *D.A:ip=rr.A.String();case *D.AAAA:ip=rr.AAAA.String()}
  if ip!=test.want {t.Fatalf("wrong resolver: %s",ip)}
 })}
 // Explicit existing reject rules survive the overlay.
 custom,err:=os.ReadFile(filepath.Join(base,"custom/runtime.json"));if err!=nil {t.Fatal(err)}
 cfg2,err:=parseConfigForIOS(string(custom),true);if err!=nil {t.Fatal(err)}
 defer closeCatalogObjects(cfg2.Proxies,cfg2.Providers)
 if ok,target:=cfg2.Rules[0].Match(&C.Metadata{Host:"weixin.qq.com"},C.RuleMatchHelper{});!ok || target!="REJECT" {t.Fatal("explicit exception lost")}
 if len(cfg2.DNS.DirectNameServer)!=1 || cfg2.DNS.DirectNameServer[0].Addr!="223.6.6.6:53" {t.Fatal("custom direct resolver changed")}
}
