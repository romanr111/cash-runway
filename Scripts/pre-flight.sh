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
echo "=== Core mirror diff ==="
if diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore; then
    echo "Core sources are in sync."
fi
