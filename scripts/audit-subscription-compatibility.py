#!/usr/bin/env python3
"""Inventory fictional format/field acceptance; no downloads, network or Keychain.
Run check-configuration.py once to prepare the pinned offline host bridge.
"""
import ast
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / '.build/host-config'
required = [out / 'core-bridge', out / 'libHako.dylib']
if not all(p.exists() for p in required):
    raise SystemExit('Run scripts/check-configuration.py first to prepare the host bridge.')
# Reuse the existing host source inventory without executing its build/download setup.
tree = ast.parse((root / 'scripts/check-configuration.py').read_text())
sources = next(ast.literal_eval(n.value) for n in tree.body
               if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'sources' for t in n.targets))
sources[-1] = 'scripts/audit-subscription-compatibility.swift'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / '.build/bridge-check-module-cache'),
                '-I', str(out), '-L', str(out), '-lHako', '-Xlinker', '-rpath', '-Xlinker', str(out),
                *[str(root / s) for s in sources], '-o', str(out / 'audit-compatibility')], check=True)
result = subprocess.run([str(out / 'audit-compatibility')], cwd=root,
                        env=dict(os.environ, CLASH_HOST_BRIDGE=str(out / 'core-bridge')),
                        check=True, capture_output=True)
report = json.loads(result.stdout)
(root / '.build/compatibility-audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(f"Inventory: {report['total']} synthetic cases; {report['accepted']} accepted, "
      f"{report['total']-report['accepted']} blocked. This is not a real-world compatibility percentage.")
print('Details: .build/compatibility-audit.json; no network, VPN, credentials or Keychain used.')
