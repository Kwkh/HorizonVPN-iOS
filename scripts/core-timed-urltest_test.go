package hako

import (
    "context"
    "testing"
    "time"

    "github.com/TokenPLS/Hako/adapter"
    "github.com/TokenPLS/Hako/common/utils"
    C "github.com/TokenPLS/Hako/constant"
)

type clashTimedProbe struct {
    C.Proxy
    calls int
    remaining time.Duration
    satisfied bool
    statusRangeOK bool
}

func (p *clashTimedProbe) URLTestOutcome(ctx context.Context, _ string, expected utils.IntRanges[uint16]) (adapter.URLTestOutcome, error) {
    p.calls++
    deadline, _ := ctx.Deadline()
    p.remaining = time.Until(deadline)
    p.statusRangeOK = expected.Check(204) && !expected.Check(403)
    return adapter.URLTestOutcome{Delay: 200, Satisfied: p.satisfied, HTTPStatus: 204}, nil
}

func TestClashNativeProbeDeadlineAndStatus(t *testing.T) {
    probe := &clashTimedProbe{satisfied: true}
    restore := swapTunnelProxies(map[string]C.Proxy{"TEST": probe}, nil)
    defer restore()
    if got := URLTestWithTimeout("TEST", "http://example.invalid/", 10_000); got != 200 {
        t.Fatalf("want measured 200 ms, got %d", got)
    }
    if probe.remaining < 9*time.Second || probe.remaining > 10*time.Second || !probe.statusRangeOK {
        t.Fatal("deadline or 2xx status validation was not forwarded")
    }
    probe.satisfied = false
    if URLTestWithTimeout("TEST", "http://example.invalid/", 10_000) != -1 {
        t.Fatal("unexpected status must not become a successful delay")
    }
    for _, timeout := range []int32{-1, 0, 60_001} {
        if URLTestWithTimeout("TEST", "http://example.invalid/", timeout) != -1 {
            t.Fatal("invalid timeout accepted")
        }
    }
    if probe.calls != 2 || URLTestWithTimeout("MISSING", "http://example.invalid/", 10_000) != -1 {
        t.Fatal("invalid requests must not dial a proxy")
    }
}
