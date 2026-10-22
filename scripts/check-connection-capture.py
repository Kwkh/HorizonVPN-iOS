#!/usr/bin/env python3
"""Run after check-configuration.py. Connection capture privacy and lifecycle; no network/Keychain."""
import ast, os, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
tree = ast.parse((root / 'scripts/check-configuration.py').read_text())
sources = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'sources' for t in n.targets))[:-1]
sources += ['Horizon/Services/SubscriptionDownloader.swift', 'Horizon/Services/SubscriptionResourceLoader.swift', 'Horizon/Services/BundledGeoData.swift', 'Horizon/Services/ConfigurationDiagnosticText.swift', 'Horizon/Services/DiagnosticText.swift', 'Shared/NetworkInspection.swift', 'Shared/ConnectionCapture.swift', 'Shared/ConnectivityReport.swift', 'scripts/check-network-inspection.swift']
out = root / '.build/host-config'
subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(root / '.build/bridge-check-module-cache'),'-I',str(out),'-L',str(out),'-lHako','-Xlinker','-rpath','-Xlinker',str(out),*[str(root/s) for s in sources],'-o',str(out/'check-connection-capture')],check=True)
env = dict(os.environ, CLASH_HOST_BRIDGE=str(out/'core-bridge'))
subprocess.run([str(out/'check-connection-capture')],cwd=root,env=env,check=True)
