#!/usr/bin/env python3
"""Validate emitted App Intents metadata and actionable build diagnostics.
This verifies build products, not Siri registration or a real Apple account.
"""
from pathlib import Path
import json, re, sys
R = Path(__file__).resolve().parents[1]
artifacts = R / "Artifacts"
errors = []
lines = []
def report(value):
    lines.append(value)
    print(value)
app = artifacts / "DerivedData/Build/Products/Debug-iphonesimulator/PulseLoom.app"
metadata = app / "Metadata.appintents/extract.actionsdata"
try:
    data = json.loads(metadata.read_text())
    action = data["actions"]["OpenPulseLoomIntent"]
    assert action["openAppWhenRun"] is True
    assert any(p["name"] == "pattern" for p in action["parameters"])
    assert "PresetEntity" in data["entities"]
    assert "PresetQuery" in data["queries"]
    assert any(s["actionIdentifier"] == "OpenPulseLoomIntent" for s in data["autoShortcuts"])
    report("Main intent, entity, query, optional parameter and shortcut metadata present.")
except (OSError, ValueError, KeyError, AssertionError, TypeError) as error:
    errors.append("App Intents metadata missing/invalid: " + str(error))
# Read compiler-produced dependency inventories without modifying them.
for listing in sorted(artifacts.glob("**/*DependencyMetadataFileList")):
    if "PulseLoom.build" not in str(listing) or "Debug-iphonesimulator" not in str(listing): continue
    report("Dependency inventory: " + str(listing.relative_to(R)))
    for item in listing.read_text().splitlines():
        path = Path(item)
        candidate = path / "extract.actionsdata" if path.is_dir() else path
        report("  " + item + " exists=" + str(candidate.exists()))
        if candidate.exists() and candidate.is_file():
            try:
                value = json.loads(candidate.read_text())
                report("  JSON keys=" + ",".join(sorted(value)))
            except (OSError, ValueError, TypeError, UnicodeError) as error:
                report("  unreadable=" + str(error))
for name in ["ios-build.log", "watch-build.log", "ios-service-tests.log", "ios-ui-tests.log"]:
    path = artifacts / name
    if not path.exists():
        errors.append("Required build/test log missing: " + name)
        continue
    text = path.read_text(errors="replace")
    for line in text.splitlines():
        if ("Unable to parse extract.actionsdata" in line or
            "non-sendable result type 'MusicCatalogSearchResponse'" in line or
            "trailing closure in this context is confusable" in line):
            errors.append(name + ": " + line)
report(json.dumps({"status": "failed" if errors else "passed", "errors": errors,
                   "runtime_siri_registration": "not verified"}, ensure_ascii=False, indent=2))
artifacts.mkdir(exist_ok=True)
(artifacts / "app-intents-inspection.log").write_text("\n".join(lines) + "\n")
raise SystemExit(1 if errors else 0)
