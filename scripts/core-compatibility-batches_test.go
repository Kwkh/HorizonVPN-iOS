package hako

import (
    "bytes"
    "context"
    "encoding/json"
    "net/netip"
    "net"
    "os"
    "path/filepath"
    "strings"
    "testing"
    "github.com/TokenPLS/Hako/adapter"
    "github.com/TokenPLS/Hako/adapter/outboundgroup"
    "github.com/TokenPLS/Hako/adapter/outbound"
    provider "github.com/TokenPLS/Hako/adapter/provider"
    "github.com/TokenPLS/Hako/common/utils"
    "github.com/TokenPLS/Hako/component/geodata"
    "github.com/TokenPLS/Hako/component/mmdb"
    C "github.com/TokenPLS/Hako/constant"
    P "github.com/TokenPLS/Hako/constant/provider"
    ruleprovider "github.com/TokenPLS/Hako/rules/provider"
    "github.com/TokenPLS/Hako/tunnel"
)

// No core service, listener or dial: consume Swift-generated fictional resource snapshots.
func TestClashResourcePreflightAndRuleMatches(t *testing.T) {
    resourceDir := os.Getenv("CLASH_FIXTURE_RESOURCE_DIR")
    fixtureDir := os.Getenv("CLASH_FIXTURE_DIR")
    if resourceDir == "" || fixtureDir == "" { t.Fatal("fixture paths required") }
    options := testOptions(t)
    options.BasePath = resourceDir; options.WorkingPath = resourceDir; options.TempPath = filepath.Join(resourceDir,"tmp")
    options.PrivateDiagnostics = true; options.DisablePersistentCache = true
    if Setup(options) != nil { t.Fatal("setup") }
    for _, name := range []string{"automatic", "provider", "geo"} {
        raw, err := os.ReadFile(filepath.Join(fixtureDir,name+"-fixture-runtime.json"))
        if err != nil { t.Fatal("missing synthetic runtime") }
        content := string(raw)
        if name == "geo" {
            if summary,err := PrepareGeoSiteCache(content); err != nil || !strings.Contains(summary,", 0 failed of ") { t.Fatal("GeoSite compile") }
            if summary,err := PrepareGeoIPCache(content,true); err != nil || !strings.Contains(summary,", 0 failed of ") { t.Fatal("GeoIP compile") }
            geodata.SetGeodataMode(true)
        }
        if err := CheckConfig(content); err != nil { t.Fatalf("%s: preflight failed: %v",name,err) }
        cfg,err := parseConfigForIOS(content,true)
        if err != nil { t.Fatal("parse after preflight") }
        defer closeCatalogObjects(cfg.Proxies,cfg.Providers)
        if name == "provider" {
            pd := cfg.RuleProviders["remote"]
            if pd == nil || pd.Initial() != nil || pd.Count() != 1 { t.Fatal("rule provider did not load canonical YAML") }
            if !pd.Match(&C.Metadata{Host:"sub.example.invalid"}, C.RuleMatchHelper{}) { t.Fatal("rule provider matching failed") }
        }
        if name == "geo" {
            geodata.SetGeodataMode(true)
            if ok,_ := cfg.Rules[0].Match(&C.Metadata{Host:"example.invalid"}, C.RuleMatchHelper{}); !ok { t.Fatal("GEOSITE did not match actual fixture") }
            if ok,_ := cfg.Rules[1].Match(&C.Metadata{DstIP:netip.MustParseAddr("192.0.2.1")},C.RuleMatchHelper{}); !ok { t.Fatal("GEOIP did not match actual fixture") }
            if ok,_ := cfg.Rules[1].Match(&C.Metadata{DstIP:netip.MustParseAddr("198.51.100.1")},C.RuleMatchHelper{}); ok { t.Fatal("GEOIP overmatched") }
        }
    }
    // Replace source bytes without restarting the process, then roll back.
    // Each snapshot must replace the live MMDB reader; a corrupt update fails closed.
    for _, code := range []string{"a", "b", "a"} {
        data,err := os.ReadFile(filepath.Join("../../component/mmdb/testdata", "country-"+code+".mmdb"))
        if err != nil { t.Fatal("MMDB fixture") }
        if os.WriteFile(C.Path.MMDB(),data,0600) != nil { t.Fatal("MMDB write") }
        if _,err := PrepareGeoIPCache("",false); err != nil { t.Fatal("MMDB reload") }
        got := mmdb.IPInstance().LookupCode(net.ParseIP("1.0.0.1"))
        if len(got) != 1 || got[0] != code+code { t.Fatal("stale MMDB snapshot after update/rollback") }
    }
    if os.WriteFile(C.Path.MMDB(),[]byte("corrupt"),0600) != nil {t.Fatal("write")}
    if _,err := PrepareGeoIPCache("",false); err == nil { t.Fatal("corrupt MMDB reload accepted") }
    // Generate a native MRS, validate it, and leave it for the Swift import contract test.
    var binary bytes.Buffer
    if ruleprovider.ConvertToMrs([]byte("+.example.invalid\n"),P.Domain,P.TextRule,&binary) != nil { t.Fatal("MRS generation") }
    if n,e := InspectProviderForIOS("rule","domain","mrs",binary.Bytes()); e != nil || n != 1 { t.Fatal("MRS validation") }
    if os.WriteFile(filepath.Join(fixtureDir,"fixture-domain.mrs"),binary.Bytes(),0600) != nil { t.Fatal("MRS fixture write") }
}

type automaticFixtureProxy struct {
    C.Proxy
    name string
    delay uint16
    alive bool
}
func (p *automaticFixtureProxy) Name() string { return p.name }
func (p *automaticFixtureProxy) AliveForTestUrl(string) bool { return p.alive }
func (p *automaticFixtureProxy) LastDelayForTestUrl(string) uint16 { if !p.alive {return 65535}; return p.delay }
func (p *automaticFixtureProxy) URLTestOutcome(context.Context,string,utils.IntRanges[uint16]) (adapter.URLTestOutcome,error) {
    return adapter.URLTestOutcome{Delay:p.delay,Satisfied:true,HTTPStatus:204},nil
}

func TestClashAutomaticNowAndProviderBatch(t *testing.T) {
    a := &automaticFixtureProxy{Proxy:adapter.NewProxy(outbound.NewDirect()),name:"A",delay:100,alive:true}
    b := &automaticFixtureProxy{Proxy:adapter.NewProxy(outbound.NewDirect()),name:"B",delay:20,alive:true}
    hc := provider.NewHealthCheck([]C.Proxy{a,b},"",5000,0,true,nil)
    pd,err := provider.NewCompatibleProvider("fixture",[]C.Proxy{a,b},hc)
    if err != nil { t.Fatal("provider") }; defer pd.Close()
    option := outboundgroup.GroupCommonOption{Name:"Auto",Type:"url-test",URL:"https://example.invalid/probe"}
    auto,err := outboundgroup.NewURLTest(option,outboundgroup.URLTestOption{},a,[]P.ProxyProvider{pd})
    if err != nil {t.Fatal("auto")}
    if auto.Now() != "B" { t.Fatal("url-test did not choose lower measured latency") }
    option.Name="Fallback"; option.Type="fallback"
    fallback,err := outboundgroup.NewFallback(option,outboundgroup.FallbackOption{},a,[]P.ProxyProvider{pd})
    if err != nil {t.Fatal("fallback")}
    if fallback.Now() != "A" { t.Fatal("fallback did not retain priority order") }
    a.alive=false
    if fallback.Now() != "B" { t.Fatal("fallback did not recover to alive node") }
    a.alive=true
    if fallback.Now() != "A" { t.Fatal("fallback did not restore primary") }
    beforeProxies,beforeProviders := tunnel.Proxies(),tunnel.Providers()
    defer tunnel.UpdateProxies(beforeProxies,beforeProviders)
    tunnel.UpdateProxies(map[string]C.Proxy{"Auto":adapter.NewProxy(auto),"Fallback":adapter.NewProxy(fallback)},map[string]P.ProxyProvider{"fixture":pd})
    var snapshot struct { Proxies map[string]struct {Now string `json:"now"`} `json:"proxies"` }
    if json.Unmarshal([]byte(ProxiesJSON()),&snapshot) != nil || snapshot.Proxies["Auto"].Now != "B" { t.Fatal("actual runtime selection JSON") }
    batch := NewCancellableURLTests(5); defer batch.Cancel()
    if batch.Test("B","https://example.invalid/probe",1000) != 20 { t.Fatal("provider node batch lookup failed") }
    if URLTestWithTimeout("B","https://example.invalid/probe",1000) != 20 { t.Fatal("provider node Ping lookup failed") }
}
