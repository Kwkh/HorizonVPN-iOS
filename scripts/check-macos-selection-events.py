#!/usr/bin/env python3
"""Exercise selection event routing in hidden AppKit fixtures, without desktop input."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
output = root / '.build/macos/selection-event-check'
output.mkdir(parents=True, exist_ok=True)
sources = ['Horizon/Features/MacConfigurations/Components/MacConfigurationSelectionSurface.swift',
           'scripts/check-macos-selection-events.swift']
subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-cache-path',
                str(output / 'module-cache'), *[str(root / s) for s in sources],
                '-o', str(output / 'check')], check=True)
subprocess.run([str(output / 'check')], check=True)
