#!/usr/bin/env python3
"""Exercise real core shutdown ordering and restart with synthetic data only."""
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
overlay = root / ".build/research/shutdown-core-overlay.json"
overlay.parent.mkdir(parents=True, exist_ok=True)
overlay.write_text(json.dumps({"Replace": {
    str(core / "bind/hako/horizon_shutdown_test.go"):
        str(root / "scripts/core-shutdown_test.go")
}}))
for test in ("TestHorizonShutdownCancelsRuleDNSBeforeConfigurationReset",
             "TestHorizonShutdownAllowsRepeatedServiceStart"):
    subprocess.run(["go", "test", "-overlay", str(overlay),
                    "-tags=with_gvisor,with_quic,with_low_memory,cmfa,no_easytier",
                    "-run=^" + test + "$", "-count=1", "-timeout=30s", "-v", "."],
                   cwd=core / "bind/hako", env=env, check=True)
