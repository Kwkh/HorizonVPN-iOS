#!/usr/bin/env python3
"""Verify real Mac core symbols and their inclusion outside an archived App."""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('dynamic_core', ROOT / 'scripts/build-macos-dynamic-core.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def size(path):
    return sum(p.stat().st_size for p in path.rglob('*') if p.is_file() and not p.is_symlink())


def verify(binary, dsym):
    ids = core.validate_symbols(binary, dsym)
    for arch in ids:
        text = subprocess.check_output(['xcrun', 'dwarfdump', '--arch=' + arch,
            '--name=github.com/TokenPLS/Hako/bind/hako.NewService', str(dsym)], text=True)
        address = re.search(r'DW_AT_low_pc\s+\((0x[0-9a-f]+)\)', text).group(1)
        symbol = subprocess.check_output(['xcrun', 'atos', '-arch', arch, '-o',
            str(dsym / 'Contents/Resources/DWARF/Hako'), '-l', '0', address], text=True).strip()
        if 'hako.NewService' not in symbol or 'service.go:' not in symbol:
            raise RuntimeError('Cannot symbolicate a Go core frame: ' + symbol)
        print('PASS', arch, 'core source symbolication:', symbol)
    commands = subprocess.check_output(['xcrun', 'otool', '-l', str(binary)], text=True)
    if 'segname __DWARF' in commands:
        raise RuntimeError('Release core still embeds DWARF instead of keeping it in the dSYM')
    return ids


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    xc = ROOT / '.build/macos/artifacts/HakoDynamic.xcframework'
    info = plistlib.loads((xc / 'Info.plist').read_bytes())['AvailableLibraries'][0]
    if info.get('DebugSymbolsPath') != 'dSYMs':
        raise RuntimeError('XCFramework does not advertise its symbols to Xcode')
    slice_path = xc / info['LibraryIdentifier']
    binary = slice_path / 'Hako.framework/Versions/A/Hako'
    dsym = slice_path / 'dSYMs/Hako.framework.dSYM'
    result = {'xcframeworkUUIDs': verify(binary, dsym), 'coreBytes': binary.stat().st_size,
              'symbolBytes': size(dsym)}
    if args.archive:
        archive = args.archive.resolve()
        app = archive / 'Products/Applications/HorizonMac.app'
        if not app.is_dir():
            raise RuntimeError('HorizonMac.app missing from archive')
        archived_core = app / 'Contents/Frameworks/Hako.framework/Versions/A/Hako'
        archived_dsym = archive / 'dSYMs/Hako.framework.dSYM'
        result['archiveCoreUUIDs'] = verify(archived_core, archived_dsym)
        if result['archiveCoreUUIDs'] != result['xcframeworkUUIDs']:
            raise RuntimeError('Archive contains a stale core instead of the current XCFramework')
        available = {}
        for companion in (archive / 'dSYMs').glob('*.dSYM'):
            available.update({(arch, uuid): companion.name for arch, uuid in core.uuids(companion).items()})
        coverage = {}
        for bundle in [app, *(app / 'Contents/PlugIns').glob('*.appex')]:
            meta = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
            exe = bundle / 'Contents/MacOS' / meta['CFBundleExecutable']
            ids = core.uuids(exe)
            if set(ids) != {'arm64', 'x86_64'} or any((a, u) not in available for a, u in ids.items()):
                raise RuntimeError('Missing or mismatched App/extension dSYM: ' + bundle.name)
            coverage[bundle.name] = ids
        frameworks = list(app.rglob('Hako.framework'))
        if len(frameworks) != 1 or list(app.rglob('*.dSYM')):
            raise RuntimeError('App must embed one shared Hako framework and no dSYM bundles')
        result.update(archive=str(archive), appBytes=size(app), appAndExtensionSymbols=coverage,
                      embeddedCoreCopies=1, embeddedDSYMs=0)
        print('PASS archive: App, tunnel and core UUIDs match; one embedded core; dSYMs outside App')
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
