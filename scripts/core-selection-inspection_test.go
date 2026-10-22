package hako

import (
    "encoding/json"
    "testing"
    "github.com/TokenPLS/Hako/config"
    "github.com/TokenPLS/Hako/component/profile"
    "github.com/TokenPLS/Hako/component/profile/cachefile"
    "github.com/TokenPLS/Hako/tunnel"
)

// Selector mutation only: no listeners, DNS request, VPN or external traffic.
func TestClashSelectProxyAcknowledgesAndRejectsInvalidMember(t *testing.T) {
    profile.StoreSelected.Store(false)
    configuration, err := config.Parse([]byte(`mode: rule
proxy-groups:
  - name: FIXTURE-SELECT
    type: select
    proxies: [DIRECT, REJECT]
rules: ["MATCH,FIXTURE-SELECT"]
`))
    if err != nil { t.Fatal("synthetic parse failed") }
    tunnel.UpdateProxies(configuration.Proxies, configuration.Providers)
    check := func(expected string) {
        t.Helper()
        var snapshot struct { Proxies map[string]struct { Now string `json:"now"` } `json:"proxies"` }
        if json.Unmarshal([]byte(ProxiesJSON()), &snapshot) != nil || snapshot.Proxies["FIXTURE-SELECT"].Now != expected {
            t.Fatal("core selector state differs from acknowledged selection")
        }
    }
    check("DIRECT")
    if err := SelectProxy("FIXTURE-SELECT", "REJECT"); err != nil { t.Fatal("select failed") }
    check("REJECT")
    if err := SelectProxy("FIXTURE-SELECT", "MISSING"); err == nil { t.Fatal("accepted missing member") }
    check("REJECT")
    if err := SelectProxy("FIXTURE-SELECT", "DIRECT"); err != nil { t.Fatal("rollback failed") }
    check("DIRECT")
    if cachefile.Cache().DB != nil { t.Fatal("selection opened persistent cache") }
}
