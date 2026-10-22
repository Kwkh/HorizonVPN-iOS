#!/usr/bin/env python3
"""Rebuild a pinned experimental iOS core entirely inside .build/.

No system tool install, signing, device/network changes, or subscription access.
Default preparation downloads and inspects source; --build executes the pinned
Go tool installers and upstream SDK builder. Third-party licenses stay with source.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
LOCK = json.loads((ROOT / "Configuration/Core.lock.json").read_text())


def run(arguments, *, cwd=ROOT, env=None, capture=False):
    print("+ " + " ".join(map(str, arguments)), flush=True)
    return subprocess.run(list(map(str, arguments)), cwd=cwd, env=env, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def prepare():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("This toolchain lock is for Apple Silicon macOS only")
    downloads = BUILD / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    spec = LOCK["go"]
    archive = downloads / spec["archive"]
    if not archive.exists():
        temporary = archive.with_suffix(".partial")
        print("Downloading official " + spec["archive"], flush=True)
        with urllib.request.urlopen(spec["url"], timeout=60) as response, temporary.open("wb") as output:
            while block := response.read(1024 * 1024):
                output.write(block)
        if digest(temporary) != spec["sha256"]:
            raise RuntimeError("Go archive checksum mismatch; refusing extraction")
        temporary.replace(archive)
    if digest(archive) != spec["sha256"]:
        raise RuntimeError("Cached Go archive checksum mismatch")
    install = BUILD / "toolchains" / spec["version"]
    marker = install / "verified-archive-sha256"
    if not marker.exists():
        install.mkdir(parents=True, exist_ok=True)
        # The archive must be pinned and verified before extraction. Reject
        # escaping paths and links as an additional guard on extraction.
        with tarfile.open(archive) as package:
            for member in package.getmembers():
                destination = (install / member.name).resolve()
                if not destination.is_relative_to(install.resolve()):
                    raise RuntimeError("Unsafe archive path")
                if member.issym() or member.islnk():
                    raise RuntimeError("Unexpected archive link")
            package.extractall(install)
        marker.write_text(spec["sha256"] + "\n")
    elif marker.read_text().strip() != spec["sha256"]:
        raise RuntimeError("Installed toolchain does not match lock")

    env = os.environ.copy()
    env.update({
        "GOTOOLCHAIN": "local",
        "GOPATH": str(BUILD / "go-path"),
        "GOBIN": str(BUILD / "tools"),
        "GOCACHE": str(BUILD / "go-cache"),
        "GOMODCACHE": str(BUILD / "go-mod-cache"),
        "GOROOT": str(install / "go"),
        "GOENV": "off",
        "GOPROXY": "https://proxy.golang.org,direct",
        "GOSUMDB": "sum.golang.org",
        "GIT_TERMINAL_PROMPT": "0",
    })
    env["PATH"] = str(install / "go/bin") + os.pathsep + str(BUILD / "tools") + os.pathsep + env["PATH"]
    # Ignore inherited build options that would alter the declared source build.
    for key in ("GOFLAGS", "GOOS", "GOARCH", "GOWORK", "CGO_ENABLED"):
        env.pop(key, None)
    version = run(["go", "version"], env=env, capture=True).strip()
    if version != "go version " + spec["version"] + " darwin/arm64":
        raise RuntimeError("Unexpected Go version: " + version)
    print(version, flush=True)

    for source in LOCK["sources"]:
        checkout = BUILD / "core-sources" / source["name"]
        if not checkout.exists():
            checkout.mkdir(parents=True)
            run(["git", "init", "--quiet"], cwd=checkout, env=env)
            run(["git", "remote", "add", "origin", source["url"]], cwd=checkout, env=env)
        remote = run(["git", "remote", "get-url", "origin"], cwd=checkout, env=env, capture=True).strip()
        if remote != source["url"]:
            raise RuntimeError("Unexpected source origin; refusing to modify it")
        head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=checkout,
                              env=env, text=True, capture_output=True)
        if head.returncode:
            run(["git", "fetch", "--depth=1", "origin", source["revision"]], cwd=checkout, env=env)
            run(["git", "checkout", "--detach", source["revision"]], cwd=checkout, env=env)
        elif head.stdout.strip() != source["revision"]:
            raise RuntimeError("Source revision differs; preserve the checkout and inspect it")
        status = run(["git", "status", "--porcelain"], cwd=checkout, env=env, capture=True)
        if status.strip():
            raise RuntimeError("Source checkout is modified; refusing an unrecorded build")
    return env


def build(env):
    (BUILD / "tools").mkdir(parents=True, exist_ok=True)
    for tool in ("gomobile", "gobind"):
        run(["go", "install", LOCK[tool]], env=env)
    core = patched_core(env)
    output = BUILD / "artifacts/Hako.xcframework"
    output.parent.mkdir(parents=True, exist_ok=True)
    # The upstream builder applies Apple CPU overlays. License texts remain in
    # the pinned source; distribution also needs a separate license bundle.
    run(["go", "run", "./cmd/build_libbox", "-target", "apple", "-slices", LOCK["slices"],
         "-output", output], cwd=core, env=env)
    for module in [core, core / "bind/hako"]:
        run(["go", "mod", "verify"], cwd=module, env=env)
    # This checkout contains only the recorded, hash-locked local patches.
    run(["git", "diff", "--check"], cwd=core, env=env)
    manifest = {
        "lock": LOCK,
        "xcode": run(["xcodebuild", "-version"], env=env, capture=True).strip(),
        "go": run(["go", "version"], env=env, capture=True).strip(),
        "files": {str(path.relative_to(output)): digest(path)
                  for path in sorted(output.rglob("*")) if path.is_file()},
    }
    (output.parent / "core-build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    package_licenses(env, core)
    print("Built " + str(output), flush=True)


def package_licenses(env, core):
    output = BUILD / "artifacts/CoreLicenses"
    run(["go", "run", "./cmd/package_licenses", "-output", output], cwd=core, env=env)
    for source, target in [
        (core / "LICENSE", "Hako-LICENSE"),
        (core / "NOTICE", "Hako-NOTICE"),
        (BUILD / "core-sources/Hako-Adapter/LICENSE", "Hako-Adapter-LICENSE"),
        (Path(env["GOROOT"]) / "LICENSE", "Go-LICENSE"),
        (Path(env["GOMODCACHE"]) / "github.com/sagernet/gomobile@v0.1.13/LICENSE", "Gomobile-LICENSE"),
    ]:
        if not source.is_file():
            raise RuntimeError("Missing license input: " + str(source))
        shutil.copyfile(source, output / target)
    shutil.copyfile(ROOT / "Configuration/Core.lock.json", output / "Core.lock.json")
    shutil.copyfile(ROOT / "Configuration/Patches/hako-private-diagnostics.patch", output / "local-privacy.patch")
    for patch in LOCK.get("patches", []):
        shutil.copyfile(ROOT / patch["path"], output / Path(patch["path"]).name)
    (output / "ABOUT.txt").write_text(
        "Horizon personal client. Hako and Hako-Adapter source revisions are in Core.lock.json.\n"
        "Local patches provide private iOS services and bounded offline selection-policy projection.\n"
        "Module license inventory is upstream's host production graph; it may include unused modules.\n"
        "This inventory is not a complete iOS distribution/license compliance audit.\n"
        "Source build: https://github.com/TokenPLS/Hako and https://github.com/TokenPLS/Hako-Adapter\n")


def patched_core(env):
    patches = LOCK.get("patches", [])
    if not patches:
        return BUILD / "core-sources/Hako"
    for patch in patches:
        if digest(ROOT / patch["path"]) != patch["sha256"]:
            raise RuntimeError("Local patch does not match lock")
    identity = hashlib.sha256(json.dumps(patches, sort_keys=True).encode()).hexdigest()[:16]
    checkout = BUILD / "core-patched" / identity
    if not checkout.exists():
        checkout.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--local", "--no-hardlinks", BUILD / "core-sources/Hako", checkout], env=env)
        for patch in patches:
            run(["git", "apply", ROOT / patch["path"]], cwd=checkout, env=env)
    expected_revision = next(source["revision"] for source in LOCK["sources"] if source["name"] == "Hako")
    if run(["git", "rev-parse", "HEAD"], cwd=checkout, env=env, capture=True).strip() != expected_revision:
        raise RuntimeError("Patched checkout base revision differs from lock")
    # Reverse-apply check verifies that the expected hunks are present.
    for patch in reversed(patches):
        run(["git", "apply", "--reverse", "--check", ROOT / patch["path"]], cwd=checkout, env=env)
    expected = b"".join((ROOT / patch["path"]).read_bytes() for patch in patches)
    actual = subprocess.check_output(["git", "diff", "--no-ext-diff"], cwd=checkout)
    # Compare the resulting source bytes in a separate index, without touching
    # the caller's checkout or masking unrelated edits.
    changed = set(run(["git", "diff", "--name-only"], cwd=checkout, env=env, capture=True).splitlines())
    allowed = {line[6:] for line in expected.decode().splitlines() if line.startswith("+++ b/")}
    if changed != allowed or run(["git", "ls-files", "--others", "--exclude-standard"], cwd=checkout, env=env, capture=True).strip():
        raise RuntimeError("Unexpected changes in patched source checkout")
    # Hash the complete diff on first preparation; reject later local edits.
    marker = checkout.parent / (identity + ".diff-sha256")
    checksum = hashlib.sha256(actual).hexdigest()
    if marker.exists() and marker.read_text().strip() != checksum:
        raise RuntimeError("Patched source changed after preparation")
    marker.write_text(checksum + "\n")
    return checkout


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="install pinned Go tools and build the iOS SDK")
    args = parser.parse_args()
    try:
        environment = prepare()
        if args.build:
            build(environment)
        else:
            print("Prepared fixed toolchain and sources; SDK has not been built.")
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print("Build preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
