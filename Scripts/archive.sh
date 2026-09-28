#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo "Xcode is required." >&2; exit 2; }
[[ -f Config/Local.xcconfig ]] || { echo "Copy Config/Local.xcconfig.example and configure your own account first." >&2; exit 2; }
[[ "${PULSELOOM_RELEASE_CHECKLIST_ACCEPTED:-}" == "YES" ]] || {
  echo "Complete Docs/RELEASE_CHECKLIST.md. Then set PULSELOOM_RELEASE_CHECKLIST_ACCEPTED=YES." >&2; exit 2;
}
major=$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)
layout=${PULSELOOM_WATCH_LAYOUT:-plugins}; if [[ "$major" -lt 26 ]]; then layout=${PULSELOOM_WATCH_LAYOUT:-watch}; fi
python3 Scripts/generate-project.py --watch-layout "$layout"
mkdir -p Artifacts
xcodebuild -project PulseLoom.xcodeproj -scheme PulseLoom -configuration Release \
  -destination 'generic/platform=iOS' -archivePath Artifacts/PulseLoom.xcarchive \
  -allowProvisioningUpdates archive 2>&1 | tee Artifacts/archive.log
# Distribution and submission are separate, explicit actions in Xcode Organizer.
