package hako

import (
    "context"
    "errors"
    "sync"
    "sync/atomic"
    "testing"
    "time"

    "github.com/TokenPLS/Hako/common/utils"
    "github.com/TokenPLS/Hako/adapter"
    C "github.com/TokenPLS/Hako/constant"
)

type batchBlockingProxy struct {
    C.Proxy
    active atomic.Int32
    peak atomic.Int32
    reject atomic.Bool
    started chan struct{}
    finish chan struct{}
}
func (p *batchBlockingProxy) URLTestOutcome(ctx context.Context, _ string, statuses utils.IntRanges[uint16]) (adapter.URLTestOutcome, error) {
    n := p.active.Add(1)
    defer p.active.Add(-1)
    for old := p.peak.Load(); n > old && !p.peak.CompareAndSwap(old,n); old = p.peak.Load() {}
    if !statuses.Check(204) || statuses.Check(403) { return adapter.URLTestOutcome{}, errors.New("invalid status filter") }
    p.started <- struct{}{}
    select { case <-ctx.Done(): return adapter.URLTestOutcome{}, ctx.Err(); case <-p.finish: return adapter.URLTestOutcome{Delay:42,Satisfied:!p.reject.Load(),HTTPStatus:204}, nil }
}
func TestClashBatchCancellationAndConcurrency(t *testing.T) {
    p := &batchBlockingProxy{started:make(chan struct{}, 20),finish:make(chan struct{})}
    restore := swapTunnelProxies(map[string]C.Proxy{"TEST": p}, nil)
    defer restore()
    if NewCancellableURLTests(4) != nil { t.Fatal("accepted unsupported concurrency") }
    first, second := NewCancellableURLTests(5), NewCancellableURLTests(5)
    var wg sync.WaitGroup
    results := make(chan int32, 12)
    for i:=0;i<12;i++ { wg.Add(1); go func(i int) { defer wg.Done(); b:=first; if i%2==1 {b=second}; results <- b.Test("TEST","http://example.invalid/",10000) }(i) }
    for i:=0;i<5;i++ { select {case <-p.started: case <-time.After(2*time.Second): t.Fatal("workers did not start")} }
    select {case <-p.started: t.Fatal("more than five concurrent native requests"); case <-time.After(50*time.Millisecond):}
    first.Cancel(); second.Cancel()
    done:=make(chan struct{});go func(){wg.Wait();close(done)}()
    select {case <-done: case <-time.After(time.Second): t.Fatal("cancellation failed to release queued/in-flight requests")}
    close(results); for result:=range results {if result!=-2 {t.Fatalf("cancelled batch returned %d",result)}}
    if p.peak.Load()>5 || p.active.Load()!=0 {t.Fatal("native work leaked or exceeded shared limit")}
    fresh := NewCancellableURLTests(5)
    if got:=fresh.Test("TEST","http://example.invalid/",20);got!=-3 {t.Fatalf("deadline result %d",got)}
    close(p.finish)
    if got:=fresh.Test("TEST","http://example.invalid/",1000);got!=42 {t.Fatal("fresh batch did not recover after cancellation")}
    p.reject.Store(true)
    if fresh.Test("TEST","http://example.invalid/",1000)!=-1 {t.Fatal("non-2xx was counted as success")}
    for _,timeout:=range []int32{-1,0,10001} {if fresh.Test("TEST","http://example.invalid/",timeout)!=-1 {t.Fatal("invalid timeout accepted")}}
    if fresh.Test("MISSING","http://example.invalid/",1000)!=-1 {t.Fatal("missing node accepted")}
}
