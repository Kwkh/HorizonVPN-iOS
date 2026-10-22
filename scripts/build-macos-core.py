#!/usr/bin/env python3
"""Build an isolated native macOS SDK without replacing the shipped iOS SDK.

Uses the same pinned source, toolchain and recorded patches as build-core.py.
No application target, signing, VPN settings or real subscription is involved.
Mac-only patches are separately hash-locked; mobile inputs and artifacts stay intact.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("horizon_corebuild", ROOT / "scripts/build-core.py")
corebuild = importlib.util.module_from_spec(spec)
spec.loader.exec_module(corebuild)
OUTPUT = ROOT / ".build/macos/artifacts"
MAC_LOCK = json.loads((ROOT / "Configuration/MacCore.lock.json").read_text())


def patched_core(env):
    if corebuild.digest(ROOT / MAC_LOCK["baseLock"]) != MAC_LOCK["baseLockSHA256"]:
        raise RuntimeError("Mac lock must be reviewed after changing the mobile base lock")
    base = corebuild.patched_core(env)  # Verify the original mobile checkout first.
    patches = corebuild.LOCK["patches"] + MAC_LOCK["patches"]
    for patch in patches:
        if corebuild.digest(ROOT / patch["path"]) != patch["sha256"]:
            raise RuntimeError("Mac patch does not match lock")
    identity = hashlib.sha256(json.dumps(patches, sort_keys=True).encode()).hexdigest()[:16]
    checkout = ROOT / ".build/macos/core-patched" / identity
    marker = checkout.parent / (identity + ".diff-sha256")
    if not checkout.exists():
        checkout.parent.mkdir(parents=True, exist_ok=True)
        corebuild.run(["git", "clone", "--local", "--no-hardlinks", base, checkout], env=env)
        for patch in patches:
            corebuild.run(["git", "apply", ROOT / patch["path"]], cwd=checkout, env=env)
        diff = corebuild.run(["git", "diff", "--no-ext-diff"], cwd=checkout, env=env, capture=True)
        marker.write_text(hashlib.sha256(diff.encode()).hexdigest() + "\n")
    revision = corebuild.run(["git", "rev-parse", "HEAD"], cwd=base, env=env, capture=True)
    if corebuild.run(["git", "rev-parse", "HEAD"], cwd=checkout, env=env, capture=True) != revision:
        raise RuntimeError("Mac checkout revision differs from mobile base")
    diff = corebuild.run(["git", "diff", "--no-ext-diff"], cwd=checkout, env=env, capture=True)
    if not marker.exists() or marker.read_text().strip() != hashlib.sha256(diff.encode()).hexdigest():
        raise RuntimeError("Unexpected edits in Mac patched checkout")
    if corebuild.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=checkout, env=env, capture=True).strip():
        raise RuntimeError("Unexpected untracked Mac core sources")
    return checkout


def ios_fingerprint():
    """Check both the linked SDK and the license bundle used by the iOS target."""
    existing = ROOT / ".build/artifacts"
    return {str(path.relative_to(existing)): corebuild.digest(path)
            for path in sorted(existing.rglob("*")) if path.is_file()}


def build(env):
    before = ios_fingerprint()
    if not before:
        raise RuntimeError("Expected the existing iOS artifacts as a regression baseline")
    try:
        for tool in ("gomobile", "gobind"):
            corebuild.run(["go", "install", corebuild.LOCK[tool]], env=env)
        core = patched_core(env)
        # Upstream -debug only retains symbols/build IDs; it does not disable Go
        # optimization or enable the separate -internal diagnostic build tags.
        # Keep these Mac-only objects until the dynamic framework's dSYM is made.
        framework = OUTPUT / "HakoSymbols.xcframework"
        OUTPUT.mkdir(parents=True, exist_ok=True)
        corebuild.run(["go", "run", "./cmd/build_libbox", "-target", "apple",
                       "-slices", "macos", "-debug", "-output", framework], cwd=core, env=env)
        with (framework / "Info.plist").open("rb") as stream:
            libraries = plistlib.load(stream)["AvailableLibraries"]
        if len(libraries) != 1 or libraries[0]["SupportedPlatform"] != "macos" \
                or set(libraries[0]["SupportedArchitectures"]) != {"arm64", "x86_64"}:
            raise RuntimeError("Expected only the native macOS universal slice")
        for module in (core, core / "bind/hako"):
            corebuild.run(["go", "mod", "verify"], cwd=module, env=env)
        corebuild.run(["git", "diff", "--check"], cwd=core, env=env)

        licenses = OUTPUT / "CoreLicenses"
        corebuild.run(["go", "run", "./cmd/package_licenses", "-output", licenses], cwd=core, env=env)
        for source, target in (
            (core / "LICENSE", "Hako-LICENSE"), (core / "NOTICE", "Hako-NOTICE"),
            (corebuild.BUILD / "core-sources/Hako-Adapter/LICENSE", "Hako-Adapter-LICENSE"),
            (Path(env["GOROOT"]) / "LICENSE", "Go-LICENSE"),
            (Path(env["GOMODCACHE"]) / "github.com/sagernet/gomobile@v0.1.13/LICENSE", "Gomobile-LICENSE"),
            (ROOT / "Configuration/Core.lock.json", "Core.lock.json"),
        ):
            shutil.copyfile(source, licenses / target)
        shutil.copyfile(ROOT / "Configuration/MacCore.lock.json", licenses / "MacCore.lock.json")
        for patch in corebuild.LOCK.get("patches", []) + MAC_LOCK["patches"]:
            shutil.copyfile(ROOT / patch["path"], licenses / Path(patch["path"]).name)
        manifest = {
            "baseLock": corebuild.LOCK, "macLock": MAC_LOCK, "slices": "macos", "runtimeVerified": False,
            "staticSDKPath": framework.name, "retainedSymbols": True,
            "xcode": corebuild.run(["xcodebuild", "-version"], env=env, capture=True).strip(),
            "go": corebuild.run(["go", "version"], env=env, capture=True).strip(),
            "files": {str(path.relative_to(framework)): corebuild.digest(path)
                      for path in sorted(framework.rglob("*")) if path.is_file()},
            "iosArtifactsUnchanged": True,
        }
        # Assert before publishing a successful manifest, including on failures.
        if ios_fingerprint() != before:
            raise RuntimeError("iOS artifacts changed during the isolated Mac build")
        (OUTPUT / "core-build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        subprocess.run([sys.executable, str(ROOT / "scripts/build-macos-dynamic-core.py")], check=True)
        print("Built isolated native macOS SDK and shared dynamic framework; iOS artifacts unchanged.", flush=True)
    finally:
        if ios_fingerprint() != before:
            raise RuntimeError("iOS artifacts changed; preserve output and investigate")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="build the isolated arm64/x86_64 macOS SDK")
    args = parser.parse_args()
    try:
        environment = corebuild.prepare()
        if args.build:
            build(environment)
        else:
            patched_core(environment)
            print("Verified Mac build inputs; no SDK was built.")
    except Exception as error:
        print("Mac SDK preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
