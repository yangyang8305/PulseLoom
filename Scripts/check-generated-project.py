#!/usr/bin/env python3
"""Verify checked-in default Xcode generation; no Apple SDK or signing implied.
Run in a clean checkout before adding a personal Config/Local.xcconfig.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCOPES = ["PulseLoom.xcodeproj", "Config/project-manifest.json"]


def generate():
    subprocess.run(
        [sys.executable, "Scripts/generate-project.py", "--watch-layout", "plugins"],
        cwd=ROOT, check=True,
    )
    files = [ROOT / "Config/project-manifest.json"]
    files += sorted(p for p in (ROOT / "PulseLoom.xcodeproj").rglob("*") if p.is_file())
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def main():
    subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    first = generate()
    second = generate()
    if first != second:
        raise RuntimeError("Two default generations produced different bytes or file lists.")
    # Compare against HEAD, not just the working index. A staged stale project must fail too.
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", *SCOPES], cwd=ROOT, check=True)
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "--", *SCOPES], cwd=ROOT,
    ).decode("utf-8").strip()
    if untracked:
        raise RuntimeError("Generated files are missing from Git: " + untracked)
    manifest = json.loads((ROOT / "Config/project-manifest.json").read_text())
    print(json.dumps({
        "generated_files_verified": len(first),
        "targets": len(manifest["targets"]),
        "source_paths": len(manifest["sourceFiles"]),
        "watch_layout": manifest["watchEmbedLayout"],
        "matches_HEAD": True,
        "repeat_generation_identical": True,
        "apple_sdk_build": "not performed by this checker",
    }, indent=2))


if __name__ == "__main__":
    main()
