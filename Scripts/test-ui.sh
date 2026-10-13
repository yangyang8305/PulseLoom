#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo "Xcode is required." >&2; exit 2; }
# Select an installed iPhone simulator automatically, or pass an explicit destination.
if [[ -n "${PULSELOOM_TEST_DESTINATION:-}" ]]; then destination="$PULSELOOM_TEST_DESTINATION"; else
  # Prefer a dedicated English-language test simulator when one exists (system share sheets and
  # Files pickers follow the simulator's system language, which journeys match in English).
  udid=$(xcrun simctl list devices available -j | python3 -c 'import json,sys;d=json.load(sys.stdin);a=[x for k,v in d["devices"].items() if ".iOS-" in k for x in v if "iPhone" in x["name"]];p=[x for x in a if x["name"]=="PulseLoom-UITest-EN"];print((p or a)[0]["udid"] if a else "")')
  [[ -n "$udid" ]] || { echo "No installed iPhone simulator. Install one in Xcode Settings." >&2; exit 2; }
  destination="platform=iOS Simulator,id=$udid,arch=$(uname -m)"
fi
mkdir -p Artifacts
result="Artifacts/UITests-$(date +%Y%m%d-%H%M%S).xcresult"
# Generic validation builds both simulator architectures. XCTest runs on one selected
# simulator, so the app, extensions, tests, and Swift package must all use its active
# architecture. Keep their products separate to avoid reusing a mixed-architecture .o.
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom -configuration Debug \
  -destination "$destination" -derivedDataPath Artifacts/UITestDerivedData \
  -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test \
  2>&1 | tee Artifacts/ios-ui-tests.log
