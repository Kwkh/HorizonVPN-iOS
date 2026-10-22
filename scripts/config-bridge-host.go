// Offline helper for the Swift host contract tests. Raw payloads stay in pipes.
package main

import (
    "encoding/json"
    "io"
    "strconv"
    "os"
    "path/filepath"
    h "github.com/TokenPLS/Hako/bind/hako"
    "github.com/TokenPLS/Hako/log"
)

func main() {
    log.SetLevel(log.SILENT)
    input, err := io.ReadAll(io.LimitReader(os.Stdin, 48*1024*1024))
    if err != nil || len(os.Args) != 2 { return }
    var value string
    valid := false
    switch os.Args[1] {
    case "check":
        path := os.Getenv("CLASH_HOST_CORE_DIR")
        if path != "" && h.Setup(&h.SetupOptions{BasePath:path, WorkingPath:path, TempPath:filepath.Join(path,"tmp"), RuntimeProfile:"iosPacketTunnel", PrivateDiagnostics:true, DisablePersistentCache:true}) == nil {
            valid = h.CheckConfig(string(input)) == nil
        }
    case "dns-order":
        var p struct { Source, Runtime string }
        if json.Unmarshal(input,&p)==nil { box,e:=h.PreserveDNSPolicyOrderForIOS(p.Source,p.Runtime);if e==nil {valid=true;value=box.Value} }
    case "policy":
        box, e := h.ResolvePolicyForIOS(string(input)); if e == nil { valid = true; value = box.Value }
    case "plan":
        box, e := h.PlanResourcesForIOS(string(input)); if e == nil { valid = true; value = box.Value }
    case "provider":
        var p struct { Kind, Behavior, Format string; Payload []byte }
        if json.Unmarshal(input, &p) == nil { n, e := h.InspectProviderForIOS(p.Kind,p.Behavior,p.Format,p.Payload); if e == nil { valid=true; value=strconv.FormatInt(int64(n),10) } }
    case "geo":
        var p struct { Kind, Format, Path, Codes string }
        if json.Unmarshal(input, &p) == nil { valid=h.ValidateGeodataCodesForIOS(p.Kind,p.Format,p.Path,p.Codes)==nil }
    case "shape": valid = h.ValidateConfigShape(string(input)) == nil
    case "json":
        box, e := h.JSONToYaml(string(input)); if e == nil { valid = true; value = box.Value }
    case "yaml":
        box, e := h.YamlToJSON(string(input)); if e == nil { valid = true; value = box.Value }
    case "deviations":
        box, e := h.ConfigDeviationsJSON(string(input), "iosPacketTunnel"); if e == nil { valid = true; value = box.Value }
    }
    json.NewEncoder(os.Stdout).Encode(struct { OK bool; Value string }{valid, value})
}
