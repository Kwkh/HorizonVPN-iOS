package hako

import (
 "os"
 "path/filepath"
 "net/netip"
 "testing"
 C "github.com/TokenPLS/Hako/constant"
)

func TestHorizonTargetPreflightAndRules(t *testing.T) {
 options:=testOptions(t)
 options.PrivateDiagnostics=true
 options.DisablePersistentCache=true
 if Setup(options)!=nil {t.Fatal("setup")}
 for _, name:=range []string{"target-protocols", "target-rules"} {
  raw,err:=os.ReadFile(filepath.Join(os.Getenv("CLASH_FIXTURE_DIR"),name+"-runtime.json"))
  if err!=nil {t.Fatal("missing synthetic runtime")}
  if err=CheckConfig(string(raw));err!=nil {t.Fatalf("synthetic %s preflight: %v",name,err)}
  cfg,err:=parseConfigForIOS(string(raw),true)
  if err!=nil {t.Fatal("parse")}
  defer closeCatalogObjects(cfg.Proxies,cfg.Providers)
  if name=="target-rules" {
   if len(cfg.Rules)!=3 {t.Fatal("unexpected active rules")}
   if ok,target:=cfg.Rules[0].Match(&C.Metadata{DstIP:netip.MustParseAddr("2001:db8::1")},C.RuleMatchHelper{});!ok||target!="DIRECT" {t.Fatal("IPv6 IP-CIDR alias mismatch")}
   if ok,_:=cfg.Rules[0].Match(&C.Metadata{DstIP:netip.MustParseAddr("2001:db9::1")},C.RuleMatchHelper{});ok {t.Fatal("IPv6 overmatch")}
   if ok,target:=cfg.Rules[1].Match(&C.Metadata{Host:"sub.xn--fsqu00a.xn--0zwm56d"},C.RuleMatchHelper{});!ok||target!="DIRECT" {t.Fatal("IDNA suffix mismatch")}
   for _,rule:=range cfg.Rules {if rule.RuleType()==C.ProcessName {t.Fatal("desktop process rule left active")}}
  }
 }
}
