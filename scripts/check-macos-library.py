#!/usr/bin/env python3
"""Exercise the native Mac worker/profile against the real framework; in-memory fixtures only."""
import ast
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
tree = ast.parse((root / 'scripts/check-configuration.py').read_text())
sources = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
               and any(isinstance(t, ast.Name) and t.id == 'sources' for t in n.targets))[:-1]
sources += ['Shared/ConfigurationVault.swift', 'Shared/CoreRuntime.swift', 'Shared/LiveTelemetry.swift', 'Shared/TelemetryHistory.swift', 'Shared/RuntimeGroupChoices.swift', 'Shared/BatchProbe.swift', 'Shared/ProbeAdmissionQueue.swift', 'Shared/PingReport.swift']
sources += ['Horizon/Services/' + n + '.swift' for n in ['SubscriptionResourceLoader', 'BundledGeoData',
            'SubscriptionDownloader', 'SubscriptionImportLoader', 'SubscriptionQRCode']]
sources += ['Horizon/Services/Mac/' + n + '.swift' for n in ['MacSubscriptionWorker', 'MacText', 'MacProbeStore', 'MacLibraryActivity', 'MacVPNController', 'MacLibraryStore', 'MacTelemetryStore', 'MacCloudSubscriptionInventory', 'MacMenuBarActions']]
sources += ['Horizon/Services/StandaloneProbeSession.swift', 'Horizon/Services/ConfigurationImportWorker.swift', 'Horizon/Services/Mac/MacICloudSubscriptionSyncStore.swift']
sources += [str(p.relative_to(root)) for p in sorted((root / 'Horizon/Services/CloudSync').glob('*.swift')) if p.name != 'ICloudSubscriptionSyncStore.swift']
sources += ['Horizon/Features/MacConfigurations/Components/MacConfigurationSelection.swift']
sources += ['Shared/NetworkInspection.swift', 'Shared/ConnectionCapture.swift', 'Shared/ConnectivityReport.swift']
output = root / '.build/macos/library-check'
output.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-D', 'HORIZON_NATIVE_MAC',
    '-module-cache-path', str(output / 'module-cache'), '-F',
    str(root / '.build/macos/artifacts/HakoDynamic.xcframework/macos-arm64_x86_64'),
    '-framework', 'Hako', '-lresolv', '-Xlinker', '-rpath', '-Xlinker',
    str(root / '.build/macos/artifacts/HakoDynamic.xcframework/macos-arm64_x86_64'), *[str(root / s) for s in sources],
    str(root / 'scripts/check-macos-library.swift'), str(root / 'scripts/check-macos-cloud-sync.swift'), str(root / 'scripts/check-macos-menu-bar.swift'), '-o', str(output / 'check')], check=True)
subprocess.run([str(output / 'check')], check=True, cwd=root)
