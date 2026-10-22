package hako

import (
    "errors"
    "os"
    "path/filepath"
    "strings"
    "testing"
)

// Included through go test -overlay; never copied into the pinned checkout.
func TestClashPrivateDiagnosticsDoNotPersistRawText(t *testing.T) {
    base := t.TempDir()
    err := Setup(&SetupOptions{
        BasePath: base, WorkingPath: base, TempPath: filepath.Join(base, "tmp"),
        RuntimeProfile: "iosPacketTunnel", PrivateDiagnostics: true,
        DisablePersistentCache: true, TunMTU: 1280,
    })
    if err != nil { t.Fatal("setup failed") }
    const sentinel = "TEST-ONLY-SECRET-DO-NOT-PERSIST"
    for _, test := range []struct{ detail, expected string }{
        {" timeout", "timeout"}, {" certificate invalid", "tls"},
        {" authentication failed", "authentication"}, {" no such host", "dns-name"},
        {" network is unreachable", "network"}, {" operation not permitted", "permission"},
        {" connection refused", "refused"}, {" deadline exceeded", "timeout"}, {"", "failed"},
    } {
        if privateProbeReason(errors.New(sentinel + test.detail)) != test.expected {
            t.Fatal("private probe classification failed")
        }
    }
    if strings.Contains(PrivateNodeProbeJSON(sentinel), sentinel) { t.Fatal("private probe leaked input") }
    writer := &platformLogWriter{}
    if n, err := writer.Write([]byte(sentinel)); err != nil || n != len(sentinel) {
        t.Fatal("raw log suppression failed")
    }
    setStartupBreadcrumbRecording(true)
    recordStartupStageNaming("test", sentinel)
    recordStartupResource(sentinel)
    recordStartupFailure(errors.New(sentinel))
    startupPhase(sentinel)
    if breadcrumbPath() != "" || startupPhaseLogPath() != "" { t.Fatal("diagnostic path still enabled") }
    for _, name := range []string{goCrashReportFileName, breadcrumbFileName, "hako-core-phases.log"} {
        if _, err := os.Stat(filepath.Join(base, name)); !os.IsNotExist(err) { t.Fatal("unexpected diagnostic file") }
    }
}
