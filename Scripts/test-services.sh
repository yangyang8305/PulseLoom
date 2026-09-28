#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo "Xcode is required." >&2; exit 2; }
# Select an installed iPhone simulator automatically, or pass an explicit destination.
if [[ -n "${PULSELOOM_TEST_DESTINATION:-}" ]]; then destination="$PULSELOOM_TEST_DESTINATION"; else
  udid=$(xcrun simctl list devices available -j | python3 -c 'import json,sys;d=json.load(sys.stdin);print(next((x["udid"] for k,v in d["devices"].items() if ".iOS-" in k for x in v if "iPhone" in x["name"]),""))')
  [[ -n "$udid" ]] || { echo "No installed iPhone simulator. Install one in Xcode Settings." >&2; exit 2; }
  destination="platform=iOS Simulator,id=$udid,arch=$(uname -m)"
fi
mkdir -p Artifacts
result="Artifacts/ServiceTests-$(date +%Y%m%d-%H%M%S).xcresult"
# Generic validation builds both simulator architectures. XCTest runs on one selected
# simulator, so the app, extensions, tests, and Swift package must all use its active
# architecture. Keep their products separate to avoid reusing a mixed-architecture .o.
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom-ServiceTests -configuration Debug \
  -destination "$destination" -derivedDataPath Artifacts/ServiceTestDerivedData \
  -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test \
  2>&1 | tee Artifacts/ios-service-tests.log
