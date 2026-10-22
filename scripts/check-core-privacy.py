#!/usr/bin/env python3
"""Exercise the recorded core privacy patch with synthetic values only."""
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
overlay = root / ".build/research/core-privacy-overlay.json"
overlay.parent.mkdir(parents=True, exist_ok=True)
overlay.write_text(json.dumps({"Replace": {
    str(core / "bind/hako/clash_private_diagnostics_test.go"):
        str(root / "scripts/core-private-diagnostics_test.go"),
    str(core / "bind/hako/clash_ephemeral_service_test.go"):
        str(root / "scripts/core-ephemeral-service_test.go")
}}))
for test in ["TestClashPrivateDiagnosticsDoNotPersistRawText", "TestClashEphemeralServiceLifecycle"]:
    subprocess.run(["go", "test", "-overlay", str(overlay),
        "-tags=with_gvisor,with_quic,with_low_memory,cmfa,no_easytier",
        "-run=^" + test + "$", "-count=1", "."],
        cwd=core / "bind/hako", env=env, check=True)
