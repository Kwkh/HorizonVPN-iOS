#!/usr/bin/env python3
"""Check probe byte counts, native timeout and unified delay; loopback traffic only."""
import importlib.util
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("corebuild", root / "scripts/build-core.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
env = module.prepare()
core = module.patched_core(env)
env.update(GOPROXY="off", GOSUMDB="off")
overlay = root / ".build/research/ping-core-overlay.json"
overlay.write_text(json.dumps({"Replace": {
    str(core / "bind/hako/clash_timed_urltest_test.go"): str(root / "scripts/core-timed-urltest_test.go"),
    str(core / "bind/hako/clash_batch_urltest_test.go"): str(root / "scripts/core-batch-urltest_test.go"),
    str(core / "adapter/clash_probe_traffic_test.go"): str(root / "scripts/core-probe-traffic_test.go"),
    str(core / "adapter/clash_unified_delay_test.go"): str(root / "scripts/core-unified-delay_test.go")
}}))
for cwd, package, tests in [
    (core / "bind/hako", "github.com/TokenPLS/Hako/adapter", "^TestClash(UnifiedDelayUsesSecondResponse|ProbeTraffic.*)$"),
    (core / "bind/hako", ".", "^TestClash(NativeProbeDeadlineAndStatus|BatchCancellationAndConcurrency)$")
]:
    subprocess.run(["go", "test", "-overlay", str(overlay),
        "-tags=with_gvisor,with_quic,with_low_memory,cmfa,no_easytier", "-run=" + tests,
        "-count=1", package], cwd=cwd, env=env, check=True)
print("PASS: unified second-request accounting and bounded native timeout, batch cancellation, shared concurrency limit and exact probe byte accounting; no real node used")
