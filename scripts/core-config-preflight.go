// A synthetic-only full core preflight; never starts a service or installs routes.
package main

import (
    "encoding/json"
    "fmt"
    "os"
    "strings"
    h "github.com/TokenPLS/Hako/bind/hako"
)

func main() {
    if len(os.Args) != 2 { os.Exit(1) }
    raw, err := os.ReadFile(os.Args[1])
    if err != nil { os.Exit(1) }
    var document struct { Proxies []struct { Server string } }
    if json.Unmarshal(raw, &document) != nil || len(document.Proxies) == 0 { os.Exit(1) }
    for _, node := range document.Proxies {
        if !strings.HasSuffix(node.Server, ".invalid") { fmt.Println("REFUSED: synthetic profiles only"); os.Exit(1) }
    }
    root, err := os.MkdirTemp("", "clash-synthetic-preflight-")
    if err != nil { os.Exit(1) }
    defer os.RemoveAll(root)
    err = h.Setup(&h.SetupOptions{BasePath:root, WorkingPath:root, TempPath:root+"/tmp",
        RuntimeProfile:"iosPacketTunnel", IPQueryMode:"config", TunIPv6Mode:"enabled",
        TunMTU:1280, PrivateDiagnostics:true, DisablePersistentCache:true, MemoryLimit:40*1024*1024})
    if err != nil { fmt.Println("FAIL: setup"); os.Exit(1) }
    if h.CheckConfig(string(raw)) != nil { fmt.Println("FAIL: core configuration (details suppressed)"); os.Exit(1) }
    fmt.Println("PASS: synthetic protocol matrix core preflight; no service or node connection")
}
