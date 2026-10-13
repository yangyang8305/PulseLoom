#!/usr/bin/env bash
# Build, sign with a free Personal Team and install a Debug build on the owner's paired iPhone.
# This is NOT a release path:
#  - iCloud / App Group entitlements are stripped (a free Personal Team cannot hold them), so
#    CloudKit sync, Widget data sharing and Shortcuts selection are unavailable in this build;
#  - PULSELOOM_PERSONAL_PRO unlocks Pro for the owner's own device only. Release/CI never define it.
# Required: PULSELOOM_TEAM=<Apple Development team ID>. Optional: PULSELOOM_DEVICE=<device UDID>
# (defaults to the first paired device reported by devicectl), PULSELOOM_DERIVED=<DerivedData path>.
set -euo pipefail
cd "$(dirname "$0")/.."
team=${PULSELOOM_TEAM:?Set PULSELOOM_TEAM to your Apple Development team ID}
derived=${PULSELOOM_DERIVED:-Artifacts/iPhone15DerivedData}
mkdir -p Artifacts
entitlements="$PWD/Artifacts/PersonalDebug.entitlements"
if [[ ! -f "$entitlements" ]]; then
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict/>\n</plist>\n' > "$entitlements"
fi
device=${PULSELOOM_DEVICE:-}
if [[ -z "$device" ]]; then
  xcrun devicectl list devices --json-output Artifacts/personal-devices.json >/dev/null
  device=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))["result"]["devices"]
paired=[x for x in d if x.get("connectionProperties",{}).get("pairingState")=="paired"]
print(paired[0]["identifier"] if paired else "")' Artifacts/personal-devices.json)
  [[ -n "$device" ]] || { echo "No paired device. Pair the iPhone in Xcode or set PULSELOOM_DEVICE." >&2; exit 2; }
fi
echo "team=$team device=$device derived=$derived"
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom -configuration Debug \
  -destination generic/platform=iOS -derivedDataPath "$derived" \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_ENTITLEMENTS="$entitlements" \
  APP_GROUP_ID= CLOUD_CONTAINER_ID= \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG PULSELOOM_PERSONAL_PRO' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build \
  2>&1 | tee Artifacts/personal-device-build.log | grep -E "error:|warning: .*(entitle|provision)|BUILD (SUCCEEDED|FAILED)" || true
app="$derived/Build/Products/Debug-iphoneos/PulseLoom.app"
[[ -d "$app" ]] || { echo "Build product missing: $app" >&2; exit 1; }
grep -q "BUILD SUCCEEDED" Artifacts/personal-device-build.log || { echo "Build failed; see Artifacts/personal-device-build.log" >&2; exit 1; }
codesign --verify --deep --strict "$app"
echo "Info.plist identifiers (must be empty for a Personal Team build):"
plutil -p "$app/Info.plist" | grep -E '"(AppGroupID|CloudContainerID|CFBundleVersion|CFBundleShortVersionString)"'
echo "Source: $(git rev-parse HEAD) dirty=$(git status --short | wc -l | tr -d ' ')"
xcrun devicectl device install app --device "$device" "$app" --json-output Artifacts/personal-device-install.json
python3 -c 'import json,sys;r=json.load(open(sys.argv[1]));print("installed:",r["result"]["installedApplications"][0]["bundleID"],r["result"]["installedApplications"][0].get("installationURL",""))' Artifacts/personal-device-install.json
