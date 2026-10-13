#!/usr/bin/env bash
# Dedicated, disposable SE3. All assertions remain active; normal simulators and user stores are untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${PULSELOOM_ENGINEERING_SMALL_OUTPUT:-Artifacts/Engineering-Small-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:10])')}"
[[ ! -e "$output" ]] || { echo "Evidence directory already exists: $output" >&2; exit 2; }
mkdir -p "$output"
runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; a=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]]; a.sort(key=lambda r:tuple(int(v) for v in r["version"].split(".")),reverse=True); print(a[0]["identifier"] if a else "")')
[[ -n "$runtime" ]] || { echo "No installed iOS Simulator runtime" >&2; exit 2; }
udid=$(xcrun simctl create PulseLoom-Engineering-SE com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$runtime")
cleanup() { xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
{ xcodebuild -version; echo "device=$udid runtime=$runtime model=iPhone-SE-3rd-generation"; xcrun simctl ui "$udid" content_size; } > "$output/environment.log"
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom -configuration Debug \
 -destination "platform=iOS Simulator,id=$udid,arch=$(uname -m)" \
 -derivedDataPath "${PULSELOOM_ENGINEERING_SMALL_DERIVED_DATA:-Artifacts/UITestDerivedData}" -resultBundlePath "$output/Small.xcresult" \
 -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:PulseLoomUITests/EngineeringAcceptanceTests \
 -only-testing:PulseLoomUITests/LayoutJourneyTests \
 CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test > "$output/console.log" 2>&1
