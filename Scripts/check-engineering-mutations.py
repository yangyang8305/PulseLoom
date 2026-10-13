#!/usr/bin/env python3
"""Validate model-test sensitivity using disposable copies. Never mutates the real Core source."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output")
args = parser.parse_args()
out = Path(args.output).resolve() if args.output else ROOT / "Artifacts" / ("Engineering-Mutations-" + uuid.uuid4().hex[:8])
out.mkdir(parents=True, exist_ok=False)
package = out / "CoreCopy"
shutil.copytree(ROOT / "Packages/PulseLoomCore", package, ignore=shutil.ignore_patterns(".build", ".swiftpm"))
env = os.environ.copy()
if sys.platform == "darwin":
    env["SDKROOT"] = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).decode().strip()
mutations = [
    ("resume-counts-paused-time", "SessionState.swift", "anchor = now\n        state = .playing\n        generation &+= 1",
     "anchor = now - 1\n        state = .playing\n        generation &+= 1", "testSessionClockAgainstIndependentModel16000Operations"),
    ("revocation-does-not-remove-permission", "RemoteProtocol.swift", "public mutating func revoke() { allowed = false }",
     "public mutating func revoke() { allowed = true }", "testConsentRandomTransitionsFailClosedAndNeverExceedLimit"),
]
results = []
for name, file, before, after, test in mutations:
    path = package / "Sources/PulseLoomCore" / file
    original = path.read_text()
    if original.count(before) != 1:
        results.append({"mutation": name, "detected": False, "error": "Mutation site no longer matches uniquely"})
        continue
    path.write_text(original.replace(before, after))
    log = out / (name + ".log")
    try:
        with log.open("w") as stream:
            result = subprocess.run(["swift", "test", "--package-path", str(package), "--filter", "EngineeringStateMachineTests/" + test],
                                    cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        text = log.read_text()
        detected = result.returncode != 0 and "XCTAssert" in text and "Test Case" in text and test in text
        results.append({"mutation": name, "detected": detected, "exit_code": result.returncode,
                        "oracle": "A selected model test executed and failed assertions; compile errors do not count"})
    finally:
        path.write_text(original)
(out / "summary.json").write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
raise SystemExit(0 if all(r["detected"] for r in results) else 1)
