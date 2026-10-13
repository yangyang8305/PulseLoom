#!/usr/bin/env python3
"""Reset only the simulator UI test harness cache, retaining the main app and its data."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--device", required=True)
parser.add_argument("--app-info", required=True)
args = parser.parse_args()
inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
device = next(d for runtime, group in inventory["devices"].items() if ".iOS-" in runtime for d in group if d["udid"] == args.device)
if device["state"] == "Shutdown":
    subprocess.run(["xcrun", "simctl", "boot", args.device], check=True)
subprocess.run(["xcrun", "simctl", "bootstatus", args.device, "-b"], check=True)
with Path(args.app_info).open("rb") as file:
    app_id = plistlib.load(file)["CFBundleIdentifier"]
runner = app_id + ".uitests.xctrunner"
subprocess.run(["xcrun", "simctl", "uninstall", args.device, runner], check=True)
print("Removed UI test harness only: " + runner)
