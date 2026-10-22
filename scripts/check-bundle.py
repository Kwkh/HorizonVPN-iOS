#!/usr/bin/env python3
"""Verify extension packaging, not code signing or device operation."""
import pathlib
import plistlib
import sys

app = pathlib.Path(sys.argv[1])
extension = app / "PlugIns" / "PacketTunnel.appex"

def info(path):
    with (path / "Info.plist").open("rb") as file:
        return plistlib.load(file)

host, provider = info(app), info(extension)
for bundle in (app, *sorted((app / "PlugIns").glob("*.appex"))):
    display_name = info(bundle).get("CFBundleDisplayName")
    assert isinstance(display_name, str) and display_name.strip(), f"Missing CFBundleDisplayName: {bundle.name}"
print("PASS: app and every embedded extension declare a nonempty display name")
assert host["CFBundleDisplayName"] == "Horizon"
assert host["CFBundleName"] == "Horizon"
assert host["CFBundleExecutable"] == "Horizon"
print("PASS: Horizon app display name, bundle name and executable")
assert provider["CFBundleIdentifier"] == host["CFBundleIdentifier"] + ".PacketTunnel"
assert provider["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.networkextension.packet-tunnel"
assert provider["NSExtension"]["NSExtensionPrincipalClass"] == "PacketTunnel.PacketTunnelProvider"
assert provider["CFBundleShortVersionString"] == host["CFBundleShortVersionString"]
assert provider["CFBundleVersion"] == host["CFBundleVersion"]
assert provider["MinimumOSVersion"] == host["MinimumOSVersion"]
assert (extension / provider["CFBundleExecutable"]).is_file()
print("PASS: embedded extension identity, entry point, executable and versions")

# Geo resources are app-only; the extension consumes protected snapshots instead.
import hashlib
import json
geo_manifest = json.loads((app / 'BundledGeo.json').read_text())
for asset in geo_manifest['assets']:
    data = (app / asset['file']).read_bytes()
    assert len(data) == asset['bytes']
    assert hashlib.sha256(data).hexdigest() == asset['sha256']
assert (app / 'GeoData-LICENSE.txt').is_file()
assert (app / 'GeoData-UPSTREAM.md').is_file()
print('PASS: bundled Geo assets and provenance, exact byte counts and SHA-256')

# The widget is embedded separately; it does not link the proxy core.
widget = app / 'PlugIns' / 'HorizonLiveActivity.appex'
widget_info = info(widget)
assert host['NSSupportsLiveActivities'] is True
assert widget_info['CFBundleIdentifier'] == host['CFBundleIdentifier'] + '.LiveActivity'
assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
assert widget_info['CFBundleVersion'] == host['CFBundleVersion']
assert widget_info['CFBundleShortVersionString'] == host['CFBundleShortVersionString']
assert (widget / widget_info['CFBundleExecutable']).is_file()
print('PASS: embedded Live Activity widget, identities, versions and executable')

# Both system-facing declarations must route Ping to a background LiveActivityIntent.
for bundle in (app, widget):
    metadata = json.loads((bundle / 'Metadata.appintents' / 'extract.actionsdata').read_text())
    action = metadata['actions']['PingCurrentNodeIntent']
    assert action['openAppWhenRun'] is False
    assert action['supportedModes'] == 1  # IntentModes.background.rawValue in this SDK.
    assert 'com.apple.link.systemProtocol.SessionStarting' in action['systemProtocols']
print('PASS: host and widget Ping intents use background-only execution')
