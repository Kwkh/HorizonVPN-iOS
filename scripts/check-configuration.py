#!/usr/bin/env python3
"""Run real Swift configuration validation against the pinned Go parser on macOS.

Optional --profile is read only, never exported or connected. The exported
example and derived runtime always come from the synthetic Swift fixture.
"""
import argparse
import importlib.util
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--profile", type=Path)
args = parser.parse_args()
spec = importlib.util.spec_from_file_location("corebuild", root / "scripts/build-core.py")
corebuild = importlib.util.module_from_spec(spec)
spec.loader.exec_module(corebuild)
env = corebuild.prepare()
core = corebuild.patched_core(env)
env.update(GOPROXY="off", GOSUMDB="off")
output = root / ".build/host-config"
output.mkdir(parents=True, exist_ok=True)
tags = "with_gvisor,with_quic,with_low_memory,cmfa,no_easytier"

def run(command, cwd=root):
    subprocess.run(list(map(str, command)), cwd=cwd, env=env, check=True)

run(["go", "build", "-tags=" + tags, "-o", output / "core-bridge",
     root / "scripts/config-bridge-host.go"], core / "bind/hako")
run(["xcrun", "swiftc", "-emit-library", "-emit-module", "-module-name", "Hako",
     "-module-cache-path", root / ".build/bridge-check-module-cache",
     root / "scripts/HostHako.swift", "-o", output / "libHako.dylib"])
sources = ["Shared/RoutingAssessment.swift", "Shared/CompiledGeoCache.swift", "Shared/ConfigurationRouting.swift", "Horizon/Support/ExtendedCompatibilitySelfCheck.swift", "Shared/ConfigurationSnapshot.swift", "Shared/ConfigurationResources.swift", "Shared/ConfigurationPolicy.swift", "Shared/ConfigurationGroups.swift", "Shared/ConfigurationSelectionPolicy.swift", "Shared/ConfigurationInput.swift", "Shared/ConfigurationFormat.swift", "Shared/NodeURI.swift", "Shared/ConfigurationNodeOptions.swift", "Shared/PrototypeConfiguration.swift", "Shared/PrototypeError.swift",
           "Shared/ConfigurationCatalog.swift", "Shared/ConfigurationValidation.swift",
           "Shared/ConfigurationDNS.swift", "Shared/ConfigurationRules.swift",
           "Shared/TunnelDiagnostics.swift", "Horizon/Support/PrototypeSelfCheck.swift",
           "Horizon/Support/CompatibilityFixture.swift", "Horizon/Support/SubscriptionSelfCheck.swift",
           "Shared/SubscriptionLibrary.swift", "Shared/SubscriptionRepository.swift",
           "Shared/SubscriptionRevision.swift", "Shared/ConfigurationCompatibility.swift",
           "Shared/SubscriptionChangeSummary.swift", "Horizon/Support/CompatibilitySamples.swift",
           "Horizon/Support/SubscriptionMaintenanceSelfCheck.swift", "scripts/check-configuration.swift"]
run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", root / ".build/bridge-check-module-cache",
     "-I", output, "-L", output, "-lHako", "-Xlinker", "-rpath", "-Xlinker", output,
     *[root / source for source in sources], "-o", output / "check-configuration"])
env["CLASH_HOST_BRIDGE"] = str(output / "core-bridge")
run([output / "check-configuration", *([args.profile.resolve()] if args.profile else [])])
run(["go", "run", "-tags=" + tags, root / "scripts/core-config-preflight.go",
     root / ".build/research/compat-fixture-runtime.json"], core / "bind/hako")

run(["go", "run", "-tags=" + tags, root / "scripts/core-config-preflight.go",
     root / ".build/research/expanded-fixture-runtime.json"], core / "bind/hako")
