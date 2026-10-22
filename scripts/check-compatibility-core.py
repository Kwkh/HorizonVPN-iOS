#!/usr/bin/env python3
"""Native automatic group, provider probe and real rule-match regressions. No network/VPN."""
import importlib.util, json, os, tempfile, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('corebuild',root/'scripts/build-core.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
env=m.prepare();core=m.patched_core(env)
env.update(GOPROXY='off',GOSUMDB='off',CLASH_FIXTURE_DIR=str(root/'.build/research'),CLASH_FIXTURE_RESOURCE_DIR=str(Path(tempfile.gettempdir())/'PrivateCore'))
overlay=root/'.build/research/compatibility-batches-overlay.json'
overlay.write_text(json.dumps({'Replace':{str(core/'bind/hako/clash_compatibility_batches_test.go'):str(root/'scripts/core-compatibility-batches_test.go')}}))
subprocess.run(['go','test','-overlay',str(overlay),'-tags=with_gvisor,with_quic,with_low_memory,cmfa,no_easytier','-run=^TestClash(ResourcePreflightAndRuleMatches|AutomaticNowAndProviderBatch)$','-count=1','.'],cwd=core/'bind/hako',env=env,check=True)
