#!/usr/bin/env python3
"""Use the built, pinned host parser from check-configuration.py. No downloads or credentials."""
import ast
import os
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
tree = ast.parse((root / 'scripts/check-configuration.py').read_text())
sources = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'sources' for t in n.targets))[:-1]
sources += ['Horizon/Services/SubscriptionDownloader.swift', 'Horizon/Services/ConfigurationDiagnosticText.swift', 'Horizon/Services/DiagnosticText.swift', 'scripts/check-import-formats.swift']
out = root / '.build/host-config'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / '.build/bridge-check-module-cache'), '-I', str(out), '-L', str(out), '-lHako', '-Xlinker', '-rpath', '-Xlinker', str(out), *[str(root/s) for s in sources], '-o', str(out/'check-formats')], check=True)
subprocess.run([str(out/'check-formats')], cwd=root, env=dict(os.environ, CLASH_HOST_BRIDGE=str(out/'core-bridge')), check=True)
