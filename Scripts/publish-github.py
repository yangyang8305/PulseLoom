#!/usr/bin/env python3
"""User-run, authenticated new PRIVATE repo creation. Never overwrites an existing repo or force-pushes."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OWNER, REPOSITORY = "yangyang8305", "PulseLoom"

def run(*args, check=True):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or str(args))
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--create", action="store_true", help="Explicitly authorize creation and upload.")
    args = parser.parse_args()
    if not args.create:
        parser.error("No change made. Use --create to create yangyang8305/PulseLoom as PRIVATE.")
    if not all((ROOT / p).exists() for p in ["App/Application/PulseLoomApp.swift", "Config/Base.xcconfig", "README.md"]):
        raise RuntimeError("This is not the expected PulseLoom source directory.")
    run("git", "--version")
    run("gh", "auth", "status", "--hostname", "github.com")
    login = run("gh", "api", "user", "--jq", ".login").stdout.strip()
    if login != OWNER:
        raise RuntimeError(f"Expected GitHub account {OWNER}; authenticated as {login}. No repository created.")
    probe = run("gh", "api", f"repos/{OWNER}/{REPOSITORY}", check=False)
    if probe.returncode == 0:
        raise RuntimeError("Target repository already exists. No overwrite or push performed. Inspect it manually.")
    if "HTTP 404" not in probe.stderr:
        raise RuntimeError("Could not establish target state; creation stopped. " + probe.stderr.strip())
    # The ZIP is a source snapshot; the companion bundle preserves the delivered commit history.
    if not (ROOT / ".git").exists():
        run("git", "init", "--initial-branch=main")
        run("git", "config", "user.name", OWNER)
        run("git", "config", "user.email", f"{OWNER}@users.noreply.github.com")
        run("git", "add", ".")
        run("git", "commit", "-m", "Import PulseLoom native implementation based on approved v0.6")
    if Path(run("git", "rev-parse", "--show-toplevel").stdout.strip()).resolve() != ROOT:
        raise RuntimeError("Refusing to operate in a different enclosing Git repository.")
    if run("git", "branch", "--show-current").stdout.strip() != "main":
        raise RuntimeError("Only main can be published by this script.")
    if run("git", "status", "--porcelain").stdout.strip():
        raise RuntimeError("Working tree has changes. Review and commit them before upload.")
    remotes = run("git", "remote").stdout.split()
    bundle_origin = False
    if remotes:
        # A clone of the delivered offline bundle has a local-file origin, not a GitHub remote.
        # Only that verified local bundle may be detached; all network remotes are left untouched.
        url = run("git", "remote", "get-url", "origin", check=False).stdout.strip()
        candidate = Path(url).expanduser()
        if not candidate.is_absolute(): candidate = ROOT / candidate
        bundle_origin = remotes == ["origin"] and candidate.is_file() and candidate.suffix == ".bundle"
        if bundle_origin:
            run("git", "bundle", "verify", str(candidate.resolve()))
        else:
            raise RuntimeError("A non-bundle remote is already configured. Inspect it before any push; it will not be replaced.")
    tracked = run("git", "ls-files").stdout.splitlines()
    for name in tracked:
        f = Path(name)
        if name == "Config/Local.xcconfig" or f.suffix in {".p8", ".p12", ".key", ".mobileprovision"} or f.name.startswith(".env") and f.name != ".env.example":
            raise RuntimeError(f"Potential private configuration is tracked: {name}")
    if bundle_origin: run("git", "remote", "remove", "origin")
    print("Creating PRIVATE repository yangyang8305/PulseLoom and uploading main.", flush=True)
    run("gh", "auth", "setup-git", "--hostname", "github.com")
    run("gh", "repo", "create", f"{OWNER}/{REPOSITORY}", "--private", "--source", str(ROOT), "--remote", "origin", "--disable-wiki", "--description", "Native iPhone haptics, music sync, creative patterns, Watch and Widgets; approved v0.6 UX.")
    # Repo creation and push have separate failure states. A failed push does not mean creation failed.
    run("git", "push", "--set-upstream", "origin", "main")
    run("gh", "repo", "edit", f"{OWNER}/{REPOSITORY}", "--default-branch", "main")
    local = run("git", "rev-parse", "main").stdout.strip()
    remote = run("gh", "api", f"repos/{OWNER}/{REPOSITORY}/commits/main", "--jq", ".sha").stdout.strip()
    info = json.loads(run("gh", "api", f"repos/{OWNER}/{REPOSITORY}").stdout)
    if local != remote or info.get("default_branch") != "main" or not info.get("private"):
        raise RuntimeError("Post-upload verification did not match expected SHA/main/private. Inspect before retrying.")
    print(json.dumps({"repository": info["html_url"], "private": True, "default_branch": "main", "sha": remote}, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
