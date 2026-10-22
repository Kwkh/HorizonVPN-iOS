package adapter

import (
    "context"
    "net/http"
    "net/http/httptest"
    "sync"
    "testing"
    "time"

    "github.com/TokenPLS/Hako/adapter/outbound"
)

// Controlled clock isolates the accounting change from network timing noise.
// The only real traffic is two HEAD requests to a loopback test server.
func TestClashUnifiedDelayUsesSecondResponse(t *testing.T) {
    previous := UnifiedDelay.Load()
    defer UnifiedDelay.Store(previous)
    for _, unified := range []bool{false, true} {
        UnifiedDelay.Store(unified)
        var mu sync.Mutex
        var peers []string
        var methods []string
        server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            mu.Lock()
            peers = append(peers, r.RemoteAddr)
            methods = append(methods, r.Method)
            mu.Unlock()
            w.WriteHeader(http.StatusNoContent)
        }))
        proxy := NewProxy(outbound.NewDirect())
        ticks := []time.Duration{0, 800*time.Millisecond}
        if unified { ticks = []time.Duration{0, 600*time.Millisecond, 800*time.Millisecond} }
        index := 0
        proxy.now = func() time.Time {
            if index >= len(ticks) { t.Fatal("unexpected measurement clock read") }
            tick := ticks[index]; index++
            return time.Unix(1_700_000_000, 0).Add(tick)
        }
        ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
        outcome, err := proxy.URLTestOutcome(ctx, server.URL, statusRanges(t, "200-299"))
        cancel()
        server.Close()
        if err != nil || !outcome.Satisfied { t.Fatal("loopback probe failed") }
        wantDelay, wantCount := uint16(800), 1
        if unified { wantDelay, wantCount = 200, 2 }
        mu.Lock()
        if outcome.Delay != wantDelay || len(peers) != wantCount { t.Fatal("wrong request count or measured interval") }
        for i := range peers {
            if peers[i] != peers[0] || methods[i] != http.MethodHead { t.Fatal("probe did not reuse its HEAD connection") }
        }
        mu.Unlock()
    }
}
