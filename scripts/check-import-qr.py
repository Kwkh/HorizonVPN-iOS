#!/usr/bin/env python3
"""Run after check-configuration.py; synthetic QR pixels, no network or Keychain."""
import os
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
out = root / '.build/host-config'
sources = ['Shared/ConfigurationSelectionPolicy.swift', 'Shared/CompiledGeoCache.swift', 'Shared/ConfigurationRouting.swift', 'scripts/check-subscription-qr.swift', 'Horizon/Services/SubscriptionQRCode.swift',
 'Horizon/Services/SubscriptionImportLoader.swift', 'Horizon/Services/SubscriptionDownloader.swift',
 'Horizon/Services/QRCodeImageReader.swift', 'Shared/ConfigurationSnapshot.swift', 'Shared/ConfigurationResources.swift', 'Shared/SubscriptionLibrary.swift', 'Shared/ConfigurationPolicy.swift', 'Shared/ConfigurationGroups.swift', 'Shared/ConfigurationInput.swift', 'Shared/ConfigurationFormat.swift', 'Shared/NodeURI.swift',
 'Shared/ConfigurationNodeOptions.swift', 'Shared/PrototypeConfiguration.swift', 'Shared/PrototypeError.swift',
 'Shared/ConfigurationCatalog.swift', 'Shared/ConfigurationValidation.swift', 'Shared/ConfigurationDNS.swift',
 'Shared/ConfigurationRules.swift', 'Shared/TunnelDiagnostics.swift', 'Shared/SubscriptionRevision.swift']
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / '.build/bridge-check-module-cache'),
 '-I', str(out), '-L', str(out), '-lHako', '-Xlinker', '-rpath', '-Xlinker', str(out),
 *[str(root / s) for s in sources], '-o', str(out / 'check-qr')], check=True)
env = dict(os.environ, CLASH_HOST_BRIDGE=str(out / 'core-bridge'))
subprocess.run([str(out / 'check-qr')], cwd=root, env=env, check=True)
