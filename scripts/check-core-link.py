#!/usr/bin/env python3
"""Verify Swift imports and links the built iOS core; does not execute it."""
import json
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parents[1]
artifact = root / ".build/artifacts/Hako.xcframework"
output = root / ".build/core-link-check"
output.mkdir(parents=True, exist_ok=True)
with (artifact / "Info.plist").open("rb") as stream:
    libraries = plistlib.load(stream)["AvailableLibraries"]
results = []
for library in libraries:
    assert library["SupportedPlatform"] == "ios", "Unexpected non-iOS slice"
    variant = library.get("SupportedPlatformVariant")
    assert variant in (None, "simulator")
    simulator = variant == "simulator"
    sdk = "iphonesimulator" if simulator else "iphoneos"
    sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
    for arch in library["SupportedArchitectures"]:
        target = arch + "-apple-ios26.5" + ("-simulator" if simulator else "")
        binary = output / (target + ".dylib")
        command = [
            "xcrun", "--sdk", sdk, "swiftc", "-parse-as-library", "-emit-library",
            "-sdk", sdk_path, "-target", target,
            "-module-cache-path", str(output / "module-cache"),
            "-F", str(artifact / library["LibraryIdentifier"]),
            "-framework", "Hako", "-lresolv",
            str(root / "scripts/CoreLinkProbe.swift"), "-o", str(binary),
        ]
        subprocess.run(command, check=True)
        print("PASS: Swift import and link for " + target, flush=True)
        results.append({"target": target, "binary": binary.name, "executed": False})
assert len(results) == 3, "Expected one device and two simulator architectures"
(output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
