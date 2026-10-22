#!/usr/bin/env python3
"""Verify UDP bind permissions with signed sandbox apps, without using a VPN or remote host.

Pass --identity with a local Apple Development signing identity. Only network
entitlements are copied into these synthetic apps; no real app data is opened.
"""
import argparse
import plistlib
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--identity', required=True)
args = parser.parse_args()
source = r'''
#include <stdio.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <errno.h>
int main(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return 2;
    struct sockaddr_in address = {
        .sin_len = sizeof(address), .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK)
    };
    int result = bind(fd, (struct sockaddr *)&address, sizeof(address));
    int failure = result < 0 ? errno : 0;
    close(fd);
    printf("UDP loopback bind: errno=%d\n", failure);
    return result == 0 ? 0 : failure == EPERM ? 1 : 2;
}
'''
with tempfile.TemporaryDirectory(prefix='horizon-udp-', dir=root / 'build') as temporary:
    directory = Path(temporary)
    c = directory / 'check.c'
    c.write_text(source)
    cases = [('client-only-control', {
        'com.apple.security.app-sandbox': True,
        'com.apple.security.network.client': True,
    }, 1)]
    for name in ['App', 'Tunnel']:
        entitlements = plistlib.loads((root / 'Configuration/Mac' / (name + '.entitlements')).read_bytes())
        network = {key: entitlements.get(key, False) for key in [
            'com.apple.security.app-sandbox', 'com.apple.security.network.client',
            'com.apple.security.network.server']}
        cases.append((name.lower(), network, 0))
    for name, entitlements, expected in cases:
        contents = directory / (name + '.app') / 'Contents'
        executable = contents / 'MacOS/check'
        executable.parent.mkdir(parents=True)
        info = {'CFBundleExecutable': 'check', 'CFBundleIdentifier': 'Kenote.Horizon.UDPCheck.' + name,
                'CFBundleName': 'UDPCheck', 'CFBundlePackageType': 'APPL',
                'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0'}
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        permissions = directory / (name + '.plist')
        permissions.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(['xcrun', 'clang', str(c), '-o', str(executable)], check=True)
        subprocess.run(['codesign', '-s', args.identity, '--entitlements', str(permissions),
                        '--force', str(contents.parent)], check=True, capture_output=True)
        result = subprocess.run([str(executable)], capture_output=True, text=True)
        if result.returncode != expected:
            raise SystemExit('FAIL ' + name + ': ' + str(result.returncode) + ' ' + result.stdout)
        print('PASS ' + name + ': ' + result.stdout.strip())
print('No VPN, remote traffic, subscription or credential operation was performed.')
