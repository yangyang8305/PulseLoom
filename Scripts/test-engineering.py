#!/usr/bin/env python3
"""Run every engineering test layer, preserving failures and a fingerprint of the dirty working tree.
Never signs/installs on a physical device, changes product code, or publishes anything.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def fingerprint():
    paths = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode().split("\0")
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
            for p in sorted(set(paths)) if p and (ROOT / p).is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", default=sys.executable, help="Python environment with Server/requirements-dev.txt installed")
    parser.add_argument("--destination", help="xcodebuild iOS Simulator destination; never a physical device")
    parser.add_argument("--output", help="New evidence directory (must not already exist)")
    parser.add_argument("--mutations", action="store_true", help="Validate model test sensitivity using disposable fault-injected Core copies")
    parser.add_argument("--small-screen", action="store_true", help="Also run dedicated SE3 maximum-text acceptance/layout tests")
    parser.add_argument("--portable-only", action="store_true", help="Explicit reduced scope; Apple layers are marked NOT RUN")
    args = parser.parse_args()
    if args.destination and "platform=iOS Simulator," not in args.destination:
        parser.error("--destination must select an iOS Simulator")
    out = Path(args.output).resolve() if args.output else ROOT / "Artifacts" / ("Engineering-" + uuid.uuid4().hex[:10])
    out.mkdir(parents=True, exist_ok=False)
    before = fingerprint()
    (out / "source-files.json").write_text(json.dumps(before, indent=2))
    summary = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
               "working_tree_sha256": hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest(),
               "scope": "portable-only" if args.portable_only else "portable + native services + system/acceptance UI + Watch builds",
               "stages": [], "physical_haptics_and_external_accounts": "NOT ACCEPTED by automated tests"}
    env = os.environ.copy()
    if args.destination:
        env["PULSELOOM_TEST_DESTINATION"] = args.destination
    stages = [
        ("unit-model-integration-random", ["swift", "test", "--package-path", "Packages/PulseLoomCore"]),
        ("relay-integration-system-random", [args.python, "-m", "pytest", "Server/tests", "-q"]),
        ("checker-unit", [args.python, "-m", "unittest", "discover", "-s", "Scripts/tests", "-v"]),
        ("source-contracts", [args.python, "Scripts/validate-source.py", "--no-swift-parse"]),
    ]
    if args.mutations:
        stages.append(("model-test-sensitivity", [args.python, "Scripts/check-engineering-mutations.py", "--output", str(out / "mutations")]))
    if not args.portable_only:
        destination = args.destination
        if destination is None:
            inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], cwd=ROOT))
            devices = [d for runtime, group in inventory["devices"].items() if ".iOS-" in runtime for d in group if "iPhone" in d["name"]]
            devices.sort(key=lambda d: d["name"] != "PulseLoom-UITest-EN")
            destination = "platform=iOS Simulator,id=" + devices[0]["udid"] + ",arch=" + os.uname().machine if devices else "platform=iOS Simulator,name=MissingTestDevice"
        def native_test(scheme, bundle):
            return ["xcodebuild", "-project", "PulseLoom.xcodeproj", "-scheme", scheme, "-configuration", "Debug",
                    "-destination", destination, "-derivedDataPath", "Artifacts/ServiceTestDerivedData",
                    "-resultBundlePath", str(out / bundle), "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                    "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES", "test"]
        import re
        uid_match = re.search(r"(?:^|,)id=([^,]+)", destination)
        if uid_match:
            device_id = uid_match.group(1)
        else:
            named = re.search(r"(?:^|,)name=([^,]+)", destination)
            device_id = next(d["udid"] for runtime, group in json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"].items()
                             if ".iOS-" in runtime for d in group if named and d["name"] == named.group(1))
        stages += [("native-integration-and-random", native_test("PulseLoom-ServiceTests", "Services.xcresult")),
                   ("ui-test-harness-cache-reset", [args.python, "Scripts/reset-engineering-runner.py", "--device", device_id,
                       "--app-info", "Artifacts/ServiceTestDerivedData/Build/Products/Debug-iphonesimulator/PulseLoom.app/Info.plist"]),
                   ("system-and-acceptance", native_test("PulseLoom", "UI.xcresult"))]
        if args.small_screen:
            env["PULSELOOM_ENGINEERING_SMALL_OUTPUT"] = str(out / "small-screen")
            stages.append(("small-screen-acceptance", ["bash", "Scripts/test-engineering-small.sh"]))
        stages.append(("app-widget-release-build", ["xcodebuild", "-project", "PulseLoom.xcodeproj", "-scheme", "PulseLoom",
            "-configuration", "Release", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", "Artifacts/ServiceTestDerivedData", "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES", "ARCHS=" + os.uname().machine, "build"]))
        for config in ["Debug", "Release"]:
            stages.append(("watch-build-" + config.lower(), ["xcodebuild", "-project", "PulseLoom.xcodeproj", "-scheme", "PulseLoomWatch",
                "-configuration", config, "-destination", "generic/platform=watchOS Simulator", "-derivedDataPath", "Artifacts/ServiceTestDerivedData",
                "CODE_SIGNING_ALLOWED=NO", "build"]))
    else:
        summary["not_run"] = ["native services", "system/acceptance XCUI", "Watch builds"]
    for name, cmd in stages:
        print("Running " + name, flush=True)
        start = time.monotonic()
        with (out / (name + ".log")).open("w") as log:
            try:
                stage_env = env.copy()
                if cmd[0] in ["xcodebuild", "bash"]:
                    stage_env.pop("SDKROOT", None)
                if cmd[0] == "swift" and sys.platform == "darwin":
                    # Pin SDK to the selected Xcode, avoiding inherited CLT/Xcode version mismatch.
                    stage_env["SDKROOT"] = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], cwd=ROOT).decode().strip()
                result = subprocess.run(cmd, cwd=ROOT, env=stage_env, stdout=log, stderr=subprocess.STDOUT)
                code = result.returncode
            except OSError as exc:
                log.write(str(exc)); code = 127
        stage = {"name": name, "command": cmd, "exit_code": code, "status": "PASS" if code == 0 else "FAIL",
                 "elapsed_seconds": round(time.monotonic() - start, 3)}
        summary["stages"].append(stage)
        (out / "summary.json").write_text(json.dumps(summary, indent=2))
        print(name + ": " + stage["status"], flush=True)
    after = fingerprint()
    summary["changed_during_run"] = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
    summary["success"] = all(s["exit_code"] == 0 for s in summary["stages"]) and not summary["changed_during_run"]
    (out / "summary.json").write_text(json.dumps(summary, indent=2))
    print("Evidence: " + str(out), flush=True)
    return 0 if summary["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
