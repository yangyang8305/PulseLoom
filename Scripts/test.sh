#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Artifacts
swift test --package-path Packages/PulseLoomCore 2>&1 | tee Artifacts/core-tests.log
python3 -m pytest Server/tests -q 2>&1 | tee Artifacts/server-tests.log
python3 Scripts/validate-source.py | tee Artifacts/source-checks.log
