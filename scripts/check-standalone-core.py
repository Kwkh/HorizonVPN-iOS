#!/usr/bin/env python3
"""Exercise isolated node tests via loopback SOCKS; never starts a VPN or external request."""
import importlib.util,json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('corebuild',root/'scripts/build-core.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
env=m.prepare();core=m.patched_core(env)
env.update(GOPROXY='off',GOSUMDB='off')
overlay=root/'.build/standalone-core-overlay.json'
overlay.write_text(json.dumps({'Replace':{str(core/'bind/hako/horizon_standalone_probe_test.go'):str(root/'scripts/core-standalone-probe_test.go')}}))
subprocess.run(['go','test','-v','-overlay',str(overlay),'-tags=with_gvisor,with_quic,with_low_memory,cmfa,no_easytier','-run=^TestHorizonStandaloneProbe$','-count=1','.'],cwd=core/'bind/hako',env=env,check=True)
