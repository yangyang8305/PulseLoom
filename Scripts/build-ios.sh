#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Apple SDK unavailable: execute this script on macOS with full Xcode selected." >&2
  exit 2
fi
major=$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)
if [[ "$major" -lt 16 ]]; then echo "Xcode 16+ is required for MediaAccessibility Music Haptics symbols." >&2; exit 2; fi
# The default generator layout targets modern Xcode. Override for SDK packaging differences.
layout=${PULSELOOM_WATCH_LAYOUT:-plugins}
if [[ "$major" -lt 26 ]]; then layout=${PULSELOOM_WATCH_LAYOUT:-watch}; fi
python3 Scripts/generate-project.py --watch-layout "$layout"
mkdir -p Artifacts
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath Artifacts/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee Artifacts/ios-build.log
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoomWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath Artifacts/WatchDerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee Artifacts/watch-build.log
