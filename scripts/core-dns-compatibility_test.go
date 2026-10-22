package hako

import (
 "context"
 "net"
 "os"
 "path/filepath"
 "strings"
 "testing"
 "time"
 "github.com/TokenPLS/Hako/dns"
 "github.com/TokenPLS/Hako/component/geodata"
 D "github.com/miekg/dns"
)

// Only loopback DNS traffic. Public IPs below are synthetic answer data, never destinations.
func TestHorizonDNSFallback(t *testing.T) {
 mode:=os.Getenv("HORIZON_DNS_MODE")
 dir:=filepath.Join(os.Getenv("CLASH_FIXTURE_DIR"),"dns-"+mode)
 raw,err:=os.ReadFile(filepath.Join(dir,"runtime.json")); if err!=nil {t.Fatal(err)}
 options:=testOptions(t); options.PrivateDiagnostics=true; options.DisablePersistentCache=true
 if err=Setup(options); err!=nil {t.Fatal(err)}
 name:="geoip.metadb"; if mode=="dat" {name="GeoIP.dat"}
 payload,err:=os.ReadFile(filepath.Join(dir,name)); if err!=nil {t.Fatal(err)}
 if err=os.WriteFile(filepath.Join(options.WorkingPath,name),payload,0600);err!=nil {t.Fatal(err)}
 if mode=="dat" { result,e:=PrepareGeoIPCache(string(raw),true);if e!=nil || !strings.Contains(result,"0 failed") {t.Fatalf("cache: %s %v",result,e)} }
 if err=CheckConfig(string(raw));err!=nil {t.Fatal(err)}
 cfg,err:=parseConfigForIOS(string(raw),true);if err!=nil {t.Fatal(err)}
 defer closeCatalogObjects(cfg.Proxies,cfg.Providers)
 // Preflight restores globals; the service executor installs this mode before DNS runs.
 geodata.SetGeodataMode(cfg.General.GeodataMode)
 defer geodata.SetGeodataMode(false)
 if len(cfg.DNS.FallbackIPFilter)!=1 {t.Fatal("country filter missing")}
 server:=func(fallback bool) string {
  conn,e:=net.ListenPacket("udp","127.0.0.1:0");if e!=nil {t.Fatal(e)}
  s:=&D.Server{PacketConn:conn,Handler:D.HandlerFunc(func(w D.ResponseWriter,q *D.Msg) {
   m:=new(D.Msg);m.SetReply(q);host:=q.Question[0].Name
   ips:=[]string{"223.5.5.5"}
   if strings.HasPrefix(host,"foreign") {ips=[]string{"1.1.1.1"}}
   if strings.HasPrefix(host,"mixed") {ips=[]string{"223.5.5.5","1.1.1.1"}}
   if strings.HasPrefix(host,"lan") {ips=[]string{"192.168.1.1"}}
   if strings.HasPrefix(host,"empty") {ips=nil}
   if q.Question[0].Qtype==D.TypeAAAA {ips=[]string{"2400:3200::1"};if strings.HasPrefix(host,"foreign") {ips=[]string{"2606:4700:4700::1111"}}}
   if fallback {ips=[]string{"203.0.113.9"};if q.Question[0].Qtype==D.TypeAAAA {ips=[]string{"2001:db8::9"}}}
   if strings.HasPrefix(host,"bothfail") || (!fallback && strings.HasPrefix(host,"mainfail")) {m.Rcode=D.RcodeServerFailure;ips=nil}
   for _,ip:=range ips {typ:="A";if strings.Contains(ip,":") {typ="AAAA"};rr,_:=D.NewRR(host+" 60 IN "+typ+" "+ip);m.Answer=append(m.Answer,rr)}
   _=w.WriteMsg(m)
  })}
  go func(){_ = s.ActivateAndServe()}();t.Cleanup(func(){_ = s.Shutdown()});return conn.LocalAddr().String()
 }
 primary,backup:=server(false),server(true)
 resolver:=dns.NewResolver(dns.Config{Main:[]dns.NameServer{{Addr:primary}},Fallback:[]dns.NameServer{{Addr:backup}},IPv6:true,FallbackIPFilter:cfg.DNS.FallbackIPFilter,FallbackLazyQuery:true})
 defer resolver.CloseQueries()
 cases:=[]struct{name string;kind uint16;want string}{
  {"cn",D.TypeA,"223.5.5.5"},{"foreign",D.TypeA,"203.0.113.9"},{"mixed",D.TypeA,"203.0.113.9"},
  {"lan",D.TypeA,"192.168.1.1"},{"empty",D.TypeA,"203.0.113.9"},{"mainfail",D.TypeA,"203.0.113.9"},
  {"cn6",D.TypeAAAA,"2400:3200::1"},{"foreign6",D.TypeAAAA,"2001:db8::9"},{"bothfail",D.TypeA,""},
 }
 for _,test:=range cases {t.Run(test.name,func(t *testing.T){
  ctx,cancel:=context.WithTimeout(context.Background(),2*time.Second);defer cancel()
  q:=new(D.Msg);q.SetQuestion(test.name+".example.invalid.",test.kind)
  answer,e:=resolver.ExchangeContext(ctx,q)
  if test.want=="" {if e==nil && answer!=nil && len(answer.Answer)>0 {t.Fatal("failure yielded success")};return}
  if e!=nil || answer==nil || len(answer.Answer)!=1 {t.Fatalf("unexpected DNS response: %v",e)}
  var got string;switch rr:=answer.Answer[0].(type) {case *D.A:got=rr.A.String();case *D.AAAA:got=rr.AAAA.String()}
  if got!=test.want {t.Fatalf("got %s want %s",got,test.want)}
 })}
}
