#!/usr/bin/env python3
"""Select one signed Horizon extension for local Run; never start/stop a VPN.

Without --apply, only prints the intended changes. Run with --app pointing to
/Applications/HorizonMac.app to restore registration for the installed version.
"""
import argparse
import json
import plistlib
import re
import subprocess
from pathlib import Path

APP_ID = 'Kenote.Clash'
EXT_ID = 'Kenote.Clash.MacPacketTunnel'
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def bundle_id(path):
    with (path / 'Contents/Info.plist').open('rb') as stream:
        return plistlib.load(stream).get('CFBundleIdentifier')


def registrations():
    output = run('/usr/bin/pluginkit', '-m', '-A', '-D', '-vv', '-i', EXT_ID)
    return sorted(set(Path(p.strip()).resolve() for p in re.findall(r'^\s*Path = (.+)$', output, re.M)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    target = app / 'Contents/PlugIns/HorizonMacTunnel.appex'
    if bundle_id(app) != APP_ID or bundle_id(target) != EXT_ID:
        raise RuntimeError('Refusing a bundle outside Horizon.')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    services = run('/usr/sbin/scutil', '--nc', 'list')
    horizon = [line for line in services.splitlines() if '[VPN:' + APP_ID + ']' in line]
    if any('(Disconnected)' not in line for line in horizon):
        print('Horizon VPN is active or transitioning; registration preparation skipped.')
        return
    before = registrations()
    for plugin in before:
        # Validate every affected live bundle before making any registry changes.
        if plugin.exists() and (bundle_id(plugin) != EXT_ID or
                                plugin.parent.name != 'PlugIns' or
                                bundle_id(plugin.parent.parent.parent) != APP_ID):
            raise RuntimeError('Unexpected extension path; refusing registry changes.')
    report = {'app': str(app), 'target': str(target), 'before': list(map(str, before)), 'applied': False}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('Horizon extension target:', target)
    print('Other Horizon registrations:', sum(p != target for p in before))
    if not args.apply:
        return
    try:
        run(LSREGISTER, '-f', str(app))
        run('/usr/bin/pluginkit', '-a', str(target))
        # Re-read after LaunchServices registration; it may discover another copy.
        for plugin in registrations():
            if plugin != target:
                run('/usr/bin/pluginkit', '-r', str(plugin))
        after = registrations()
        if after != [target]:
            raise RuntimeError('Registration did not converge to the requested extension.')
    except Exception:
        # Restore the prior registration set if preparation fails; files stay intact.
        for plugin in before:
            if plugin.exists():
                run('/usr/bin/pluginkit', '-a', str(plugin))
        if target not in before:
            run('/usr/bin/pluginkit', '-r', str(target))
        raise
    report.update(applied=True, after=list(map(str, after)))
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('Horizon registration ready. No app files, VPN profiles or network connections changed.')


if __name__ == '__main__':
    main()
