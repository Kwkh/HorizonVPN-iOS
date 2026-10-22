#!/usr/bin/env python3
"""Link both native Mac architectures; run synthetic validation on this Mac only."""
import ast
import json
from pathlib import Path
import platform
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / ".build/macos/artifacts/HakoDynamic.xcframework"
OUTPUT = ROOT / ".build/macos/core-check"
OUTPUT.mkdir(parents=True, exist_ok=True)
with (ARTIFACT / "Info.plist").open("rb") as stream:
    libraries = plistlib.load(stream)["AvailableLibraries"]
assert len(libraries) == 1 and libraries[0]["SupportedPlatform"] == "macos"
assert set(libraries[0]["SupportedArchitectures"]) == {"arm64", "x86_64"}
frameworks = ARTIFACT / libraries[0]["LibraryIdentifier"]
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
common = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-sdk", sdk,
          "-module-cache-path", str(OUTPUT / "module-cache"), "-F", str(frameworks),
          "-framework", "Hako", "-lresolv", "-Xlinker", "-rpath", "-Xlinker", str(frameworks)]
results = []
for arch in libraries[0]["SupportedArchitectures"]:
    target = arch + "-apple-macos26.0"
    subprocess.run(common + ["-target", target, "-emit-library",
        str(ROOT / "scripts/CoreLinkProbe.swift"), "-o", str(OUTPUT / (arch + "-link.dylib"))], check=True)
    results.append({"target": target, "linked": True, "executed": False})
    print("PASS native macOS Swift import/link: " + target, flush=True)

# Reuse the same source set as the existing compatibility regression, but link
# the real native XCFramework instead of its host-only parser shim.
tree = ast.parse((ROOT / "scripts/check-configuration.py").read_text())
sources = next(ast.literal_eval(node.value) for node in tree.body
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "sources" for t in node.targets))[:-1]
binary = OUTPUT / "check-macos-core"
subprocess.run(common + ["-target", platform.machine() + "-apple-macos26.0",
    *[str(ROOT / source) for source in sources], str(ROOT / "scripts/check-macos-core.swift"),
    "-o", str(binary)], check=True)
subprocess.run([str(binary)], cwd=ROOT, check=True)
(OUTPUT / "results.json").write_text(json.dumps({
    "link": results, "syntheticValidationExecutedOn": platform.machine(), "tunnelStarted": False,
}, indent=2) + "\n")
