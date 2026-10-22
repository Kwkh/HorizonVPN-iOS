package adapter

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/TokenPLS/Hako/adapter/outbound"
	"github.com/TokenPLS/Hako/tunnel/statistic"
)

// Independent server-side byte accounting verifies the actual HTTP stream,
// including unified delay's two requests on one connection.
type clashProbeListener struct {
	net.Listener
	received atomic.Int64
	sent     atomic.Int64
	requests atomic.Int64
}

func (l *clashProbeListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return &clashProbePeer{Conn: c, owner: l}, nil
}

type clashProbePeer struct {
	net.Conn
	owner *clashProbeListener
}

func (c *clashProbePeer) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	c.owner.received.Add(int64(n))
	return n, err
}
func (c *clashProbePeer) Write(b []byte) (int, error) {
	n, err := c.Conn.Write(b)
	c.owner.sent.Add(int64(n))
	return n, err
}

func TestClashProbeTrafficMatchesWire(t *testing.T) {
	oldUnified := UnifiedDelay.Load()
	defer UnifiedDelay.Store(oldUnified)
	for _, tc := range []struct {
		name             string
		unified          bool
		status, parallel int
	}{
		{"single", false, 204, 1}, {"unified", true, 204, 1},
		{"failed-status", false, 503, 1}, {"batch", true, 204, 3},
	} {
		t.Run(tc.name, func(t *testing.T) {
			UnifiedDelay.Store(tc.unified)
			var peer *clashProbeListener
			server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				peer.requests.Add(1)
				if r.Method != http.MethodHead {
					t.Error("probe method changed")
				}
				w.WriteHeader(tc.status)
			}))
			peer = &clashProbeListener{Listener: server.Listener}
			server.Listener = peer
			server.Start()
			defer server.Close()
			beforeUp, beforeDown := statistic.DefaultManager.Total()
			beforeDirect := statistic.DefaultManager.OutboundTotals().Direct
			var wg sync.WaitGroup
			for i := 0; i < tc.parallel; i++ {
				wg.Add(1)
				go func() {
					defer wg.Done()
					proxy := NewProxy(outbound.NewDirect())
					ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
					defer cancel()
					result, err := proxy.URLTestOutcome(ctx, server.URL, statusRanges(t, "200-299"))
					if err != nil || result.Satisfied != (tc.status == 204) {
						t.Error("unexpected outcome")
					}
				}()
			}
			wg.Wait()
			server.Close()
			up, down := statistic.DefaultManager.Total()
			gotUp, gotDown := up-beforeUp, down-beforeDown
			if gotUp <= 0 || gotDown <= 0 || gotUp != peer.received.Load() || gotDown != peer.sent.Load() {
				t.Fatalf("counted %d/%d, server received/sent %d/%d", gotUp, gotDown, peer.received.Load(), peer.sent.Load())
			}
			afterDirect := statistic.DefaultManager.OutboundTotals().Direct
			if afterDirect.Up-beforeDirect.Up != gotUp || afterDirect.Down-beforeDirect.Down != gotDown {
				t.Fatal("outbound bucket mismatch")
			}
			want := int64(tc.parallel)
			if tc.unified {
				want *= 2
			}
			if peer.requests.Load() != want {
				t.Fatal("probe request count changed")
			}
		})
	}
}

func TestClashProbeTrafficCancellation(t *testing.T) {
	oldUnified := UnifiedDelay.Load()
	UnifiedDelay.Store(false)
	defer UnifiedDelay.Store(oldUnified)
	started := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { close(started); <-r.Context().Done() }))
	defer server.Close()
	upBefore, downBefore := statistic.DefaultManager.Total()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		_, err := NewProxy(outbound.NewDirect()).URLTestOutcome(ctx, server.URL, statusRanges(t, "200-299"))
		done <- err
	}()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("request never arrived")
	}
	up, down := statistic.DefaultManager.Total()
	if up <= upBefore || down != downBefore {
		t.Fatal("request bytes must be counted before test completes")
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled probe succeeded")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("probe did not cancel")
	}
	up, down = statistic.DefaultManager.Total()
	if up <= upBefore || down != downBefore {
		t.Fatal("cancellation lost bytes or invented a response")
	}
}

type clashPartialProbeConn struct{ net.Conn }

func (*clashPartialProbeConn) Read(b []byte) (int, error)  { copy(b, "abc"); return 3, io.EOF }
func (*clashPartialProbeConn) Write(b []byte) (int, error) { return 2, io.ErrClosedPipe }
func TestClashProbeTrafficPartialIO(t *testing.T) {
	manager := new(statistic.Manager)
	c := urlTestCountingConn{Conn: &clashPartialProbeConn{}, manager: manager, outbound: "TEST"}
	if n, err := c.Read(make([]byte, 8)); n != 3 || !errors.Is(err, io.EOF) {
		t.Fatal("read result changed")
	}
	if n, err := c.Write([]byte("hello")); n != 2 || !errors.Is(err, io.ErrClosedPipe) {
		t.Fatal("write result changed")
	}
	up, down := manager.Total()
	if up != 2 || down != 3 {
		t.Fatal("partial I/O must count returned bytes, not buffer length")
	}
	bucket := manager.OutboundTotals().Proxy
	if bucket.Up != up || bucket.Down != down {
		t.Fatal("proxy bucket mismatch")
	}
}
