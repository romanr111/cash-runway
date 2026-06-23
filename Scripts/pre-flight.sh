#!/usr/bin/env bash
# Pre-flight inventory: run before starting feature work to avoid surprises.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Git status ==="
git status --short

echo ""
echo "=== Diff stat (last 20 files) ==="
git diff --stat | tail -20

echo ""
echo "=== Untracked / new files ==="
git ls-files --others --exclude-standard

echo ""
echo "=== CashRunwayCore module-wiring check ==="
Scripts/check-core-module-wiring.sh
