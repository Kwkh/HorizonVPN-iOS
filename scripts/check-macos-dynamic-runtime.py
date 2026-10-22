#!/usr/bin/env python3
"""Run real dynamic core initialization on arm64 and Intel/Rosetta, no VPN."""
from pathlib import Path
import platform
import subprocess
ROOT = Path(__file__).resolve().parents[1]
frameworks = ROOT / '.build/macos/artifacts/HakoDynamic.xcframework/macos-arm64_x86_64'
output = ROOT / '.build/macos/dynamic-runtime-check'
output.mkdir(parents=True, exist_ok=True)
for arch in ['arm64', 'x86_64']:
    binary = output / arch
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-target', arch + '-apple-macos26.0',
        '-module-cache-path', str(output / 'module-cache'), '-F', str(frameworks),
        '-framework', 'Hako', '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        str(ROOT / 'scripts/check-macos-dynamic-runtime.swift'), '-o', str(binary)], check=True)
    if arch != platform.machine() and subprocess.run(['/usr/bin/arch', '-' + arch, '/usr/bin/true'], capture_output=True).returncode:
        print('PASS linked; runtime unavailable on this host:', arch)
        continue
    for attempt in range(3):
        subprocess.run(['/usr/bin/arch', '-' + arch, str(binary)], check=True, timeout=20)
