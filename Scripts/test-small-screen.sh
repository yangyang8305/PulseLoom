#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Artifacts/SmallScreen
runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and ".iOS-" in x["identifier"]]; a.sort(key=lambda x:(x["version"]!="18.6",x["version"])); print(a[0]["identifier"] if a else "")')
[[ -n "$runtime" ]] || exit 2
udid=$(xcrun simctl create PulseLoom-UserFlows-SE com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation "$runtime")
trap 'xcrun simctl shutdown "$udid" || true; xcrun simctl delete "$udid" || true' EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
{ xcodebuild -version; echo "device=$udid runtime=$runtime type=iPhone-SE-3rd-generation"; xcrun simctl ui "$udid" content_size; } | tee Artifacts/SmallScreen/environment.log
set +e
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom -configuration Debug \
 -destination "platform=iOS Simulator,id=$udid,arch=$(uname -m)" \
 -derivedDataPath Artifacts/SmallDerivedData -resultBundlePath Artifacts/SmallScreen.xcresult \
 -parallel-testing-enabled NO -only-testing:PulseLoomUITests/LayoutJourneyTests \
 CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test 2>&1 | tee Artifacts/SmallScreen/ui.log
status=${PIPESTATUS[0]}
python3 Scripts/export-userflow-evidence.py 'Artifacts/SmallScreen.xcresult' Artifacts/SmallScreen
export_status=$?
set -e
[[ "$status" == 0 && "$export_status" == 0 ]]
