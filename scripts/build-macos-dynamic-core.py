#!/usr/bin/env python3
"""Package the complete Mac static Hako SDK into one shared dynamic framework.

Does not rebuild Go, change build tags, or touch mobile artifacts. Existing static
SDK remains available for rollback and comparison. Xcode signs the embedded copy.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / '.build/macos/artifacts/HakoSymbols.xcframework'
OUTPUT = ROOT / '.build/macos/artifacts/HakoDynamic.xcframework'


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def uuids(path):
    output = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    return {arch: uuid for uuid, arch in re.findall(r'UUID: ([A-F0-9-]+) \(([^)]+)\)', output)}


def validate_symbols(binary, dsym):
    expected = uuids(binary)
    if set(expected) != {'arm64', 'x86_64'} or uuids(dsym) != expected:
        raise RuntimeError('Hako dSYM must match both executable architecture UUIDs')
    # Do not accept an empty dSYM that merely silences the upload warning.
    for arch in expected:
        dwarf = subprocess.check_output(['xcrun', 'dwarfdump', '--arch=' + arch,
            '--name=github.com/TokenPLS/Hako/bind/hako.NewService', str(dsym)], text=True)
        if not all(field in dwarf for field in ['DW_TAG_subprogram', 'DW_AT_low_pc',
                                                'DW_AT_decl_file', 'DW_AT_decl_line']):
            raise RuntimeError('Missing real Go function/line information for ' + arch)
    return expected


def build():
    if not STATIC.exists():
        raise RuntimeError('Run scripts/build-macos-core.py --build to create the symbol-bearing Mac SDK')
    info = plistlib.loads((STATIC / 'Info.plist').read_bytes())['AvailableLibraries']
    assert len(info) == 1 and info[0]['SupportedPlatform'] == 'macos'
    assert set(info[0]['SupportedArchitectures']) == {'arm64', 'x86_64'}
    source = STATIC / info[0]['LibraryIdentifier'] / 'Hako.framework'
    archive = source / 'Versions/A/Hako'
    fingerprint = hashlib.sha256(archive.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='horizon-mac-dynamic-') as temporary:
        work = Path(temporary)
        framework = work / 'Hako.framework'
        shutil.copytree(source, framework, symlinks=True)
        # Static SDK signatures, if any, cannot describe the new executable.
        for signature in framework.rglob('_CodeSignature'):
            shutil.rmtree(signature)
        (framework / 'Versions/A/Resources/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'Kenote.Horizon.HakoCore',
            'CFBundleExecutable': 'Hako', 'CFBundleName': 'Hako',
            'CFBundlePackageType': 'FMWK', 'CFBundleVersion': '1',
            'CFBundleShortVersionString': '1.0', 'CFBundleSupportedPlatforms': ['MacOSX'],
            'LSMinimumSystemVersion': '26.0',
        }))
        binaries = []
        for arch in ['arm64', 'x86_64']:
            thin = work / (arch + '.a')
            binary = work / (arch + '.dylib')
            run('xcrun', 'lipo', archive, '-thin', arch, '-output', thin)
            run('xcrun', '--sdk', 'macosx', 'clang', '-arch', arch,
                '-mmacosx-version-min=26.0', '-dynamiclib', '-fapplication-extension',
                '-Wl,-force_load,' + str(thin),
                '-install_name', '@rpath/Hako.framework/Versions/A/Hako',
                '-Wl,-headerpad_max_install_names', '-lresolv',
                '-framework', 'Foundation', '-framework', 'Security',
                '-framework', 'CoreFoundation', '-framework', 'SystemConfiguration',
                '-o', binary)
            binaries.append(binary)
        destination = framework / 'Versions/A/Hako'
        destination.unlink()
        run('xcrun', 'lipo', '-create', *binaries, '-output', destination)
        # dsymutil needs the unstripped link map and the thin archives above.
        # Produce the companion while those objects still exist, before strip.
        dsym = work / 'Hako.framework.dSYM'
        run('xcrun', 'dsymutil', destination, '-o', dsym)
        validate_symbols(destination, dsym)
        run('xcrun', 'strip', '-S', destination)
        # Ad-hoc signing supports local CLI regression. App builds re-sign on copy.
        run('/usr/bin/codesign', '--force', '--sign', '-', framework)
        candidate = work / 'HakoDynamic.xcframework'
        run('xcodebuild', '-create-xcframework', '-framework', framework,
            '-debug-symbols', dsym, '-output', candidate)
        slice_path = candidate / 'macos-arm64_x86_64'
        symbol_uuids = validate_symbols(slice_path / 'Hako.framework/Versions/A/Hako',
                                       slice_path / 'dSYMs/Hako.framework.dSYM')
        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        shutil.copytree(candidate, OUTPUT, symlinks=True)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == fingerprint
    manifest = {'sourceSHA256': fingerprint, 'staticSDKUnchanged': True,
                'sourceSDK': STATIC.name, 'symbolUUIDs': symbol_uuids,
                'dSYMPath': 'macos-arm64_x86_64/dSYMs/Hako.framework.dSYM',
                'architectures': ['arm64', 'x86_64'], 'minimumMacOS': '26.0',
                'installName': '@rpath/Hako.framework/Versions/A/Hako',
                'dynamicSHA256': hashlib.sha256((OUTPUT / 'macos-arm64_x86_64/Hako.framework/Versions/A/Hako').read_bytes()).hexdigest()}
    (OUTPUT.parent / 'dynamic-core-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Shared Mac framework ready; complete static SDK and mobile artifacts retained.')


if __name__ == '__main__':
    build()
