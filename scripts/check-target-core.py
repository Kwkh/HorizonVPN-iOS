#!/usr/bin/env python3
"""Fixed-core preflight/rule semantics and loopback Reality gRPC / TUIC v5 interop."""
import importlib.util,json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('corebuild',root/'scripts/build-core.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
env=m.prepare();core=m.patched_core(env)
env.update(GOPROXY='off',GOSUMDB='off',CLASH_FIXTURE_DIR=str(root/'.build/research'))
overlay=root/'.build/research/target-core-overlay.json'
overlay.write_text(json.dumps({'Replace':{str(core/'bind/hako/horizon_target_compatibility_test.go'):str(root/'scripts/core-target-compatibility_test.go')}}))
subprocess.run(['go','test','-v','-overlay',str(overlay),'-tags=with_gvisor,with_quic,with_low_memory,cmfa,no_easytier','-run=^Test(HorizonTargetPreflightAndRules|ControlledRealityInterop|ControlledTUICInterop)$/^(VLESSGRPCHybrid|V5NativeBBR)$','-count=1','.'],cwd=core/'bind/hako',env=env,check=True)
