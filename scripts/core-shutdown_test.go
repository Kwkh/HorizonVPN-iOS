package hako

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"testing"
	"time"

	"github.com/TokenPLS/Hako/component/resolver"
	C "github.com/TokenPLS/Hako/constant"
	R "github.com/TokenPLS/Hako/rules"
	"github.com/TokenPLS/Hako/tunnel"
	D "github.com/miekg/dns"
)

// The DNS backend is synthetic; rule matching, the configuration lock and
// shutdownCore are real. Neither a VPN nor a remote server is involved.
type shutdownBlockedResolver struct {
	resolver.Resolver
	started   chan struct{}
	cancelled chan struct{}
	once      sync.Once
	closeOnce sync.Once
}

func (r *shutdownBlockedResolver) Invalid() bool { return true }
func (r *shutdownBlockedResolver) LookupIP(ctx context.Context, _ string) ([]netip.Addr, error) {
	r.once.Do(func() { close(r.started) })
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-r.cancelled:
		return nil, context.Canceled
	}
}
func (r *shutdownBlockedResolver) LookupIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	return r.LookupIP(ctx, host)
}
func (r *shutdownBlockedResolver) LookupIPv6(ctx context.Context, host string) ([]netip.Addr, error) {
	return r.LookupIP(ctx, host)
}
func (r *shutdownBlockedResolver) CloseQueries() {
	r.closeOnce.Do(func() { close(r.cancelled) })
}
func (*shutdownBlockedResolver) ResetConnection() {}

func TestHorizonShutdownCancelsRuleDNSBeforeConfigurationReset(t *testing.T) {
	priorResolver, priorTimeout := resolver.DefaultResolver, resolver.DefaultDNSTimeout
	priorRules, priorMode, priorStatus := tunnel.Rules(), tunnel.Mode(), tunnel.Status()
	backend := &shutdownBlockedResolver{started: make(chan struct{}), cancelled: make(chan struct{})}
	resolver.DefaultResolver = backend
	resolver.DefaultDNSTimeout = 3 * time.Second
	// GEOIP,lan has exactly the same resolving Match implementation as CN,
	// but needs no downloaded Geo database. Failed DNS stops before classification.
	rule, err := R.ParseRule("GEOIP", "lan", "DIRECT", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	tunnel.UpdateRules([]C.Rule{rule}, nil, nil)
	tunnel.SetMode(tunnel.Rule)
	tunnel.OnRunning()
	client, inbound := net.Pipe()
	defer client.Close()
	handlerDone, shutdownDone := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(handlerDone)
		tunnel.Tunnel.HandleTCPConnContext(context.Background(), inbound, &C.Metadata{
			NetWork: C.TCP, Type: C.TUN, Host: "shutdown.example.invalid", DstPort: 443,
		})
	}()
	t.Cleanup(func() {
		backend.CloseQueries()
		inbound.Close()
		<-handlerDone
		<-shutdownDone
		resolver.DefaultResolver, resolver.DefaultDNSTimeout = priorResolver, priorTimeout
		tunnel.UpdateRules(priorRules, nil, nil)
		tunnel.SetMode(priorMode)
		switch priorStatus {
		case tunnel.Running:
			tunnel.OnRunning()
		case tunnel.Inner:
			tunnel.OnInnerLoading()
		default:
			tunnel.OnSuspend()
		}
	})
	select {
	case <-backend.started:
	case <-time.After(time.Second):
		// Ensure cleanup can join the goroutine even if setup fails.
		close(shutdownDone)
		t.Fatal("GEOIP rule did not reach the DNS backend")
	}
	started := time.Now()
	go func() { defer close(shutdownDone); shutdownCore() }()
	select {
	case <-shutdownDone:
	case <-time.After(time.Second):
		t.Fatal("shutdown waited for the DNS deadline instead of cancelling before the configuration write lock")
	}
	if tunnel.Status() != tunnel.Suspend {
		t.Fatal("shutdown still accepts new tunnel flows")
	}
	t.Logf("shutdown with a pending resolving rule completed in %s", time.Since(started))
}

func TestHorizonShutdownAllowsRepeatedServiceStart(t *testing.T) {
	options := testOptions(t)
	options.PrivateDiagnostics = true
	if err := Setup(options); err != nil {
		t.Fatal(err)
	}
	// Only an ephemeral loopback DNS responder is contacted. The declared
	// Hysteria2/VLESS nodes are documentation addresses and are never dialled.
	packet, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &D.Server{PacketConn: packet, Handler: D.HandlerFunc(func(w D.ResponseWriter, q *D.Msg) {
		answer := new(D.Msg)
		answer.SetReply(q)
		answer.Answer = []D.RR{&D.A{Hdr: D.RR_Header{
			Name: q.Question[0].Name, Rrtype: D.TypeA, Class: D.ClassINET, Ttl: 60,
		}, A: net.IPv4(192, 0, 2, 10)}}
		_ = w.WriteMsg(answer)
	})}
	go func() { _ = server.ActivateAndServe() }()
	t.Cleanup(func() { _ = server.Shutdown(); _ = packet.Close() })
	nodes := []map[string]any{
		nil,
		{"name": "relay", "type": "hysteria2", "server": "192.0.2.1", "port": 443, "password": "synthetic-test-password"},
		{"name": "relay", "type": "vless", "server": "192.0.2.1", "port": 443, "uuid": "00000000-0000-4000-8000-000000000001", "tls": true},
	}
	for cycle, node := range nodes {
		proxies, target := []any{}, "DIRECT"
		if node != nil {
			proxies, target = append(proxies, node), "relay"
		}
		configuration, err := json.Marshal(map[string]any{
			"mode": "rule", "proxies": proxies, "proxy-groups": []any{}, "rules": []string{"MATCH," + target},
			"dns": map[string]any{"enable": true, "enhanced-mode": "redir-host", "ipv6": false,
				"nameserver": []string{packet.LocalAddr().String()}}, "tun": map[string]any{"enable": false},
		})
		if err != nil {
			t.Fatal(err)
		}
		service, err := NewService(newRecordingPlatform())
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = service.Close() })
		if err := service.Start(string(configuration)); err != nil {
			service.Close()
			t.Fatalf("cycle %d start: %v", cycle, err)
		}
		if tunnel.Status() != tunnel.Running || service.Status() != "running" {
			t.Fatal("new service did not reopen tunnel flow admission")
		}
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		ips, err := resolver.LookupIPv4(ctx, fmt.Sprintf("cycle-%d.example.invalid", cycle))
		cancel()
		if err != nil || len(ips) != 1 || ips[0] != netip.MustParseAddr("192.0.2.10") {
			t.Fatalf("cycle %d DNS did not recover after restart: %v %v", cycle, ips, err)
		}
		if err := service.Close(); err != nil {
			t.Fatal(err)
		}
		if err := service.Close(); err != nil {
			t.Fatal("repeated close failed:", err)
		}
		if activeCoreCount.Load() != 0 || tunnel.Status() != tunnel.Suspend {
			t.Fatal("closed service retained active state")
		}
	}
}
