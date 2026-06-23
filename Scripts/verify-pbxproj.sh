#!/usr/bin/env bash
# Quick validation that CashRunway.xcodeproj/project.pbxproj is not corrupted.
# Use after any hand-edit to pbxproj.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcodebuild -list -project CashRunway.xcodeproj >/dev/null 2>&1; then
    echo "ERROR: Xcode cannot read CashRunway.xcodeproj/project.pbxproj. It may be corrupted."
    echo "Restore from backup: cp CashRunway.xcodeproj/project.pbxproj.bak CashRunway.xcodeproj/project.pbxproj"
    exit 1
fi

echo "OK: project.pbxproj is readable by Xcode."
