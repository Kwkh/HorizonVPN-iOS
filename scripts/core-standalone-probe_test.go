package hako

import (
 "encoding/binary"
 "encoding/json"
 "io"
 "net"
 "net/http"
 "net/http/httptest"
 "sync"
 "sync/atomic"
 "testing"
 "time"
)

// The fake node only forwards to a loopback HTTP server, never the public network.
func horizonSOCKS(t *testing.T, target string, accepted *atomic.Int32) string {
 t.Helper()
 listener,err:=net.Listen("tcp","127.0.0.1:0");if err!=nil {t.Fatal(err)}
 var wg sync.WaitGroup
 t.Cleanup(func(){listener.Close();wg.Wait()})
 go func(){for {conn,err:=listener.Accept();if err!=nil{return};wg.Add(1);go func(){
  defer wg.Done();defer conn.Close();conn.SetDeadline(time.Now().Add(3*time.Second))
  h:=make([]byte,2);if _,err:=io.ReadFull(conn,h);err!=nil{return};methods:=make([]byte,int(h[1]));if _,err=io.ReadFull(conn,methods);err!=nil{return};conn.Write([]byte{5,0})
  request:=make([]byte,4);if _,err=io.ReadFull(conn,request);err!=nil{return}
  n:=0;switch request[3]{case 1:n=4;case 4:n=16;case 3:var b [1]byte;if _,err=io.ReadFull(conn,b[:]);err!=nil{return};n=int(b[0]);default:return}
  address:=make([]byte,n+2);if _,err=io.ReadFull(conn,address);err!=nil{return}
  // Synthetic target cannot be reached without this node; ignored only by our fixture.
  _=binary.BigEndian.Uint16(address[n:]);accepted.Add(1)
  upstream,err:=net.DialTimeout("tcp",target,time.Second);if err!=nil{return};defer upstream.Close()
  conn.Write([]byte{5,0,0,1,127,0,0,1,0,0})
  done:=make(chan struct{});go func(){io.Copy(upstream,conn);upstream.Close();close(done)}()
  io.Copy(conn,upstream);conn.Close();<-done
 }()}}()
 host,port,_:=net.SplitHostPort(listener.Addr().String());var p int;for _,r:=range port{p=p*10+int(r-'0')}
 raw,_:=json.Marshal(map[string]any{"name":"LOCAL-FIXTURE","type":"socks5","server":host,"port":p})
 return string(raw)
}

func TestHorizonStandaloneProbe(t *testing.T) {
 options:=testOptions(t);options.PrivateDiagnostics=true;options.DisablePersistentCache=true;options.EphemeralPacketTunnel=true
 if err:=Setup(options);err!=nil{t.Fatal(err)}
 var requests,accepted,active,peak atomic.Int32
 server:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  requests.Add(1);now:=active.Add(1);defer active.Add(-1)
  for {p:=peak.Load();if now<=p || peak.CompareAndSwap(p,now){break}}
  if r.URL.Path=="/slow" {select{case<-time.After(time.Second):case<-r.Context().Done():return}} else {time.Sleep(15*time.Millisecond)}
  if r.URL.Path=="/bad" {w.WriteHeader(500)} else {w.WriteHeader(204)}
 }));defer server.Close()
 node:=horizonSOCKS(t,server.Listener.Addr().String(),&accepted)
 const base="http://198.51.100.12"
 t.Run("actual_proxy_and_unified_timing",func(t *testing.T){
  b:=NewCancellableURLTests(5);defer b.Cancel()
  for _,unified:=range []bool{false,true}{before:=requests.Load();delay:=b.TestStandalone(node,base+"/ok",2000,unified);if delay<=0{t.Fatalf("probe failed: %d",delay)};want:=int32(1);if unified{want=2};if requests.Load()-before!=want{t.Fatal("wrong HTTP request count")}}
  if accepted.Load()!=2{t.Fatal("did not route both probes through node")}
 })
 t.Run("timeout",func(t *testing.T){b:=NewCancellableURLTests(5);defer b.Cancel();start:=time.Now();if got:=b.TestStandalone(node,base+"/slow",120,false);got!=-3{t.Fatalf("timeout: %d",got)};if time.Since(start)>600*time.Millisecond{t.Fatal("timeout did not cancel promptly")}})
 t.Run("cancel",func(t *testing.T){b:=NewCancellableURLTests(5);done:=make(chan int32,1);go func(){done<-b.TestStandalone(node,base+"/slow",2000,false)}();time.Sleep(50*time.Millisecond);b.Cancel();select{case got:=<-done:if got!=-2{t.Fatalf("cancel: %d",got)};case<-time.After(500*time.Millisecond):t.Fatal("cancel blocked")}})
 t.Run("invalid_and_status",func(t *testing.T){b:=NewCancellableURLTests(5);defer b.Cancel();for _,input:=range []string{"{}","not-json"}{if b.TestStandalone(input,base,1000,true)!=-1{t.Fatal("invalid accepted")}};if b.TestStandalone(node,base+"/bad",1000,false)!=-1{t.Fatal("HTTP failure accepted")}})
 t.Run("global_five_slots_across_sessions",func(t *testing.T){
  time.Sleep(50*time.Millisecond);peak.Store(0)
  b,c:=NewCancellableURLTests(5),NewCancellableURLTests(5);defer b.Cancel();defer c.Cancel()
  var wg sync.WaitGroup;for i:=0;i<8;i++{wg.Add(1);go func(i int){defer wg.Done();batch:=b;if i%2==0{batch=c};if batch.TestStandalone(node,base+"/ok",2000,false)<=0{t.Error("concurrent probe failed")}}(i)};wg.Wait()
  if peak.Load()>5 || peak.Load()<2{t.Fatalf("concurrency %d",peak.Load())}
 })
}
