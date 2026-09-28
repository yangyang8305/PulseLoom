#!/usr/bin/env bash
# Package the existing, unsigned generic simulator build. No third-party upload.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcrun >/dev/null || { echo 'Full Xcode is required.' >&2; exit 2; }
app="$PWD/Artifacts/DerivedData/Build/Products/Debug-iphonesimulator/PulseLoom.app"
out="$PWD/Artifacts/Preview"
[[ -d "$app" ]] || { echo 'Run Scripts/build-ios.sh first.' >&2; exit 2; }
[[ ! -e Config/Local.xcconfig ]] || { echo 'Refusing to package a locally configured account/service build.' >&2; exit 2; }
mkdir -p "$out"
exec > >(tee "$out/preview-smoke.log") 2>&1
sha=$(git rev-parse HEAD)
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
archs=$(xcrun lipo -archs "$app/$executable")
[[ " $archs " == *' arm64 '* ]] || { echo 'Missing ARM simulator slice.' >&2; exit 1; }
xcrun vtool -show-build "$app/$executable" | tee "$out/macho-platform.txt"
grep -q IOSSIMULATOR "$out/macho-platform.txt" || { echo 'Not an iOS Simulator binary.' >&2; exit 1; }
python3 - "$app/Info.plist" <<'PY'
import plistlib,sys
p=plistlib.load(open(sys.argv[1],'rb'))
assert 'iPhoneSimulator' in p.get('CFBundleSupportedPlatforms',[]), p
assert p.get('CFBundlePackageType')=='APPL'
# No developer-specific server/account configuration is injected in this build.
assert not p.get('RelayBaseURL','').strip(), 'Configured relay URL in preview'
print('Verified iPhoneSimulator platform; no configured relay endpoint.')
PY
archive="$out/PulseLoom-Simulator.app.zip"
# ditto preserves framework symlinks and executable bits; keep the .app at ZIP root.
/usr/bin/ditto -c -k --keepParent "$app" "$archive"
work=$(mktemp -d "${TMPDIR:-/tmp}/PulseLoom-preview.XXXXXX")
udid=''
cleanup() {
  if [[ -n "$udid" ]]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
/usr/bin/ditto -x -k "$archive" "$work/unpacked"
extracted="$work/unpacked/PulseLoom.app"
# Verify ZIP round-trip including nested extension/framework files before install.
diff -qr "$app" "$extracted"
xcrun simctl list devices available -j > "$work/devices.json"
python3 - "$work/devices.json" "$work/device.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
choices=[(r,d) for r,ds in j['devices'].items() if '.iOS-' in r for d in ds if 'iPhone' in d['name'] and d.get('isAvailable',True)]
if not choices: raise SystemExit('No installed iPhone Simulator runtime')
r,d=choices[0]
assert d.get('deviceTypeIdentifier'), 'Missing device type'
json.dump(dict(runtime=r,deviceType=d['deviceTypeIdentifier'],deviceName=d['name']),open(sys.argv[2],'w'))
PY
runtime=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["runtime"])' "$work/device.json")
devtype=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["deviceType"])' "$work/device.json")
udid=$(xcrun simctl create "PulseLoom preview ${sha:0:7}" "$devtype" "$runtime")
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$extracted"
# No test-ID, onboarding skip, fake Pro or success fixture on the preview launch.
xcrun simctl launch "$udid" "$bundle" | tee "$out/launch.txt"
pid=$(awk -F ': ' '/: [0-9]+$/{print $NF}' "$out/launch.txt" | tail -1)
[[ "$pid" =~ ^[0-9]+$ ]] || { echo 'No application PID returned.' >&2; exit 1; }
# Check sustained process existence; screenshot is separate visual evidence, not haptics acceptance.
for _ in 1 2 3; do sleep 5; kill -0 "$pid" || { echo 'Preview exited after launch.' >&2; exit 1; }; done
xcrun simctl io "$udid" screenshot "$out/preview-start.png"
xcrun simctl get_app_container "$udid" "$bundle" app > "$work/installed-path.txt"
(cd "$out" && shasum -a 256 PulseLoom-Simulator.app.zip > SHA256SUMS)
python3 - "$out" "$work/device.json" "$sha" "$archs" "$bundle" "$app/Info.plist" <<'PY'
import datetime,hashlib,json,pathlib,plistlib,subprocess,sys
out=pathlib.Path(sys.argv[1]);p=plistlib.load(open(sys.argv[6],'rb'))
metadata=dict(commit=sys.argv[3],platform='iphonesimulator',architectures=sys.argv[4].split(),bundleIdentifier=sys.argv[5],minimumOS=p['MinimumOSVersion'],configuration='Debug',codeSigningAllowed=False,simulator=json.load(open(sys.argv[2])),xcode=subprocess.check_output(['xcodebuild','-version'],text=True).strip(),zipSHA256=hashlib.sha256((out/'PulseLoom-Simulator.app.zip').read_bytes()).hexdigest(),zipRoundTripIdentical=True,installedFromExtractedZip=True,launchedWithoutTestFixtures=True,processAliveSeconds=15,physicalHapticsVerified=False,liveServicesVerified=False,uploadedToAppetize=False,verifiedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
(out/'preview-validation.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(metadata,indent=2))
PY
cp Docs/SIMULATOR_PREVIEW.md "$out/README.md"
echo 'Preview packaged, extracted, installed and launched. No third-party upload performed.'
