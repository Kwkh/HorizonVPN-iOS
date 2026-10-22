#!/usr/bin/env python3
"""Exercise the actual AppKit curve layers with synthetic traffic, without a VPN."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
output = root / '.build/macos/traffic-check'
output.mkdir(parents=True, exist_ok=True)
sources = ['Shared/LiveTelemetry.swift', 'Shared/TelemetryHistory.swift',
           'Horizon/Features/Home/Components/TrafficPlotGeometry.swift',
           'Horizon/Features/MacHome/Components/MacScrollingTrafficPlot.swift',
           'scripts/check-macos-traffic.swift']
subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-cache-path',
                str(output / 'module-cache'), *[str(root / s) for s in sources],
                '-o', str(output / 'check')], check=True)
subprocess.run([str(output / 'check')], check=True)
