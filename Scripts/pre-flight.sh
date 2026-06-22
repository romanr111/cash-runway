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
echo "=== CashRunwayCore Xcode target membership ==="
find Sources/CashRunwayCore -name "*.swift" | sort > /tmp/canonical.txt
grep -oE 'Sources/CashRunwayCore/[^[:space:];"]+\.swift' CashRunway.xcodeproj/project.pbxproj | sort -u > /tmp/xcode.txt
missing=$(comm -23 /tmp/canonical.txt /tmp/xcode.txt || true)
if [[ -n "$missing" ]]; then
  echo "WARNING: The following CashRunwayCore source files are missing from the Xcode app target build phase:"
  echo "$missing"
  exit 1
fi
echo "OK: All CashRunwayCore source files have Xcode target membership."
