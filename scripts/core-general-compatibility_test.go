package hako

import (
 "encoding/json"
 "os"
 "path/filepath"
 "slices"
 "testing"
)

// No service/start/listeners or provider Initial calls: inline providers are already materialized.
func TestHorizonGeneralCompatibility(t *testing.T) {
 options:=testOptions(t);options.PrivateDiagnostics=true;options.DisablePersistentCache=true
 if err:=Setup(options);err!=nil {t.Fatal(err)}
 directory:=filepath.Join(os.Getenv("CLASH_FIXTURE_DIR"),"general-compatibility")
 var manifest []struct{Name string;Groups []struct{Name string;Members []string}}
 data,err:=os.ReadFile(filepath.Join(directory,"manifest.json"));if err!=nil {t.Fatal(err)}
 if err=json.Unmarshal(data,&manifest);err!=nil {t.Fatal(err)}
 for _,fixture:=range manifest {t.Run(fixture.Name,func(t *testing.T){
  for _,suffix:=range []string{"","-native"} {
   data,err:=os.ReadFile(filepath.Join(directory,fixture.Name+suffix+".json"));if err!=nil {t.Fatal(err)}
   if err=CheckConfig(string(data));err!=nil {t.Fatalf("%s preflight: %v",suffix,err)}
   cfg,err:=parseConfigForIOS(string(data),true);if err!=nil {t.Fatal(err)}
   defer closeCatalogObjects(cfg.Proxies,cfg.Providers)
   for _,expected:=range fixture.Groups {
    proxy:=cfg.Proxies[expected.Name];if proxy==nil {t.Fatal("group missing")}
    bytes,err:=proxy.Adapter().MarshalJSON();if err!=nil {t.Fatal(err)}
    var result struct{All []string};if json.Unmarshal(bytes,&result)!=nil {t.Fatal("JSON")}
    // Native include-all may repeat explicitly listed names. App discloses stable de-duplication.
    unique:=[]string{};for _,name:=range result.All {if !slices.Contains(unique,name) {unique=append(unique,name)}}
    if !slices.Equal(unique,expected.Members) {t.Fatalf("%s membership mismatch: %v != %v",suffix,unique,expected.Members)}
    selector,ok:=proxy.Adapter().(interface{Set(string) error;Now() string});if !ok {t.Fatal("selector missing")}
    for _,name:=range expected.Members {if selector.Set(name)!=nil || selector.Now()!=name {t.Fatal("member cannot be selected")}}
    if selector.Set("NONEXISTENT-SYNTHETIC-NODE")==nil {t.Fatal("missing member selected")}
   }
  }
 })}
}
