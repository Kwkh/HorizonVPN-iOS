package hako

import (
    "os"
    "path/filepath"
    "testing"

    "github.com/TokenPLS/Hako/component/profile/cachefile"
    "github.com/TokenPLS/Hako/config"
)

// Run in a fresh go test process; no service Start, sockets or real configuration.
func TestClashEphemeralServiceLifecycle(t *testing.T) {
    base := t.TempDir()
    options := &SetupOptions{
        BasePath: base, WorkingPath: base, TempPath: filepath.Join(base, "tmp"),
        RuntimeProfile: "iosPacketTunnel", PrivateDiagnostics: true,
        DisablePersistentCache: true, TunMTU: 1280,
        IPQueryMode: "config", TunIPv6Mode: "enabled", MemoryLimit: 40*1024*1024, MaxProcs: 2,
    }
    platform := newRecordingPlatform()
    platform.underNetworkExtension = true
    if err := Setup(options); err != nil { t.Fatal("app-only setup failed") }
    if _, err := NewService(platform); err == nil { t.Fatal("app-only service guard lost") }

    options.EphemeralPacketTunnel = true
    options.PrivateDiagnostics = false
    if err := Setup(options); err == nil { t.Fatal("accepted ephemeral mode without privacy") }
    options.PrivateDiagnostics = true
    options.DisablePersistentCache = false
    if err := Setup(options); err == nil { t.Fatal("accepted ephemeral mode with persistent cache") }
    options.DisablePersistentCache = true
    options.RuntimeProfile = "macOSApplication"
    if err := Setup(options); err == nil { t.Fatal("accepted unsupported ephemeral platform") }
    options.RuntimeProfile = "iosPacketTunnel"
    options.DisableClashAPISocket = true
    if err := Setup(options); err != nil { t.Fatal("ephemeral setup failed") }
    if bindingSocketPathFor(ClashAPIPath()) != "" { t.Fatal("internal API socket remains enabled") }
    if err := startControlPlane(&config.Config{}, ClashAPIPath()); err != nil {
        t.Fatal("native IPC mode failed to initialize without socket")
    }
    stopClashAPI(ClashAPIPath())

    if _, err := NewService(newRecordingPlatform()); err == nil { t.Fatal("accepted non-NE ephemeral service") }
    if err := CheckConfig(helloYAML); err != nil { t.Fatal("synthetic config failed") }
    for i := 0; i < 3; i++ {
        service, err := NewService(platform)
        if err != nil || service == nil { t.Fatal("ephemeral service creation failed") }
        if service.running { t.Fatal("creation unexpectedly started core") }
        if err := service.Close(); err != nil { t.Fatal("close failed") }
        if err := service.Close(); err != nil { t.Fatal("idempotent close failed") }
    }
    if cachefile.Cache().DB != nil { t.Fatal("persistent DB is open") }
    if platform.monitorStarts != 0 { t.Fatal("creation started network monitoring") }
    if err := filepath.Walk(base, func(_ string, info os.FileInfo, err error) error {
        if err != nil { return err }
        if !info.IsDir() { t.Error("unexpected persisted file") }
        return nil
    }); err != nil { t.Fatal("could not inspect temporary storage") }
}
