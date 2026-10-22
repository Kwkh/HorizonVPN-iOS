package hako

import (
 "os"
 "path/filepath"
 "runtime"
 "strings"
 "testing"
 "time"
 C "github.com/TokenPLS/Hako/constant"
 "github.com/TokenPLS/Hako/tunnel"
 "github.com/TokenPLS/Hako/adapter/outboundgroup"
 "github.com/TokenPLS/Hako/component/resolver"
)

// Uses only materialized snapshots. Initializes only the synthetic inline rule provider.
// Does not start service, network listeners or health checks.
func TestHorizonPriorityCompatibility(t *testing.T) {
 options:=testOptions(t); options.PrivateDiagnostics=true; options.DisablePersistentCache=true
 if err:=Setup(options);err!=nil {t.Fatal(err)}
 base:=filepath.Join(os.Getenv("CLASH_FIXTURE_DIR"),"priority-compatibility")
 fixtures,err:=os.ReadDir(base);if err!=nil {t.Fatal(err)}
 for _,fixture:=range fixtures {if !fixture.IsDir(){continue};t.Run(fixture.Name(),func(t *testing.T){
  files,err:=os.ReadDir(filepath.Join(base,fixture.Name()));if err!=nil {t.Fatal(err)}
  for _,file:=range files {if file.Name()=="runtime.json" {continue};data,e:=os.ReadFile(filepath.Join(base,fixture.Name(),file.Name()));if e!=nil {t.Fatal(e)};if e=os.WriteFile(filepath.Join(options.WorkingPath,file.Name()),data,0600);e!=nil {t.Fatal(e)}}
  data,err:=os.ReadFile(filepath.Join(base,fixture.Name(),"runtime.json"));if err!=nil {t.Fatal(err)}
  if err=CheckConfig(string(data));err!=nil {t.Fatal(err)}
  runtime.GC();var before,after runtime.MemStats;runtime.ReadMemStats(&before);start:=time.Now()
  cfg,err:=parseConfigForIOS(string(data),true);if err!=nil {t.Fatal(err)}
  defer closeCatalogObjects(cfg.Proxies,cfg.Providers)
  if fixture.Name()=="large" {runtime.ReadMemStats(&after);t.Logf("512 nodes / 64 groups / 8192 rules parse: %v; allocated delta %.2f MiB; live heap %.2f MiB",time.Since(start),float64(after.TotalAlloc-before.TotalAlloc)/(1<<20),float64(after.HeapAlloc)/(1<<20));if len(cfg.Rules)!=8192 {t.Fatal("rules lost")}}
  if strings.HasPrefix(fixture.Name(),"balance-") {
   lb,ok:=cfg.Proxies["BALANCE"].Adapter().(*outboundgroup.LoadBalance);if !ok {t.Fatal("wrong group type")}
   metadata:=&C.Metadata{Host:"www.example.com"}
   a,b:=lb.Unwrap(metadata,true),lb.Unwrap(metadata,true)
   if a==nil || b==nil {t.Fatal("missing selection")}
   if fixture.Name()=="balance-round-robin" && a.Name()==b.Name() {t.Fatal("round robin did not rotate")}
   if fixture.Name()!="balance-round-robin" && a.Name()!=b.Name() {t.Fatal("stable strategy changed same destination")}
  }
  if fixture.Name()=="dns-ruleset-hosts" {
   provider:=cfg.RuleProviders["domains"];if provider==nil || provider.Initial()!=nil {t.Fatal("inline rule provider failed to initialize")}
   if !cfg.DNS.UseHosts {t.Fatal("hosts disabled")}
   hosts:=resolver.NewHosts(cfg.Hosts);value,ok:=hosts.Search("host.example.invalid",false);if !ok || value==nil {t.Fatal("hosts lost")}
   addr,err:=value.RandIP();if err!=nil || (addr.String()!="192.0.2.5" && addr.String()!="2001:db8::5") {t.Fatal("hosts addresses changed")}
   if len(cfg.DNS.NameServerPolicy)<2 {t.Fatal("ruleset policy missing")}
   tunnel.UpdateRules(cfg.Rules,cfg.SubRules,cfg.RuleProviders)
   matched:=false
   for _,policy:=range cfg.DNS.NameServerPolicy {if policy.Matcher!=nil && policy.Matcher.MatchDomain("sub.example.invalid") {matched=true;if len(policy.NameServers)!=1 || policy.NameServers[0].ProxyName!="SELECT" {t.Fatal("DNS policy proxy routing lost")}}}
   if !matched {t.Fatal("rule-set domain did not match") }
  }
  if fixture.Name()=="dns-order" {
   for _,provider:=range cfg.RuleProviders {if provider.Initial()!=nil {t.Fatal("rule provider initialization")}}
   tunnel.UpdateRules(cfg.Rules,cfg.SubRules,cfg.RuleProviders)
   if len(cfg.DNS.NameServerPolicy)!=2 {t.Fatal("DNS policies missing")}
   first:=cfg.DNS.NameServerPolicy[0]
   if first.Matcher==nil || !first.Matcher.MatchDomain("sub.example.invalid") || first.NameServers[0].ProxyName!="SELECT" {t.Fatal("overlapping policy precedence changed")}
  }
  if fixture.Name()=="dns-geosite-fallback" && len(cfg.DNS.FallbackDomainFilter)==0 {t.Fatal("GeoSite fallback matcher missing")}
  if fixture.Name()=="dns-geosite-policy" && len(cfg.DNS.NameServerPolicy)==0 {t.Fatal("GeoSite policy matcher missing")}
 })}
}
