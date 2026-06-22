#!/usr/bin/env bash
# CashRunwayCore module-wiring validation.
# Ensures Core is compiled only by its SwiftPM target and consumed as a package product.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="CashRunway.xcodeproj/project.pbxproj"
PACKAGE="Package.swift"

fail() {
  echo "❌ $1" >&2
  exit 1
}

pass() {
  echo "✅ $1"
}

# 1. Package.swift declares the CashRunwayCore library product.
if ! grep -q 'name: "CashRunwayCore"' "$PACKAGE"; then
  fail "Package.swift does not declare a CashRunwayCore product"
fi
pass "Package.swift declares CashRunwayCore product"

# 2. Tests depend on the SwiftPM CashRunwayCore target.
if ! grep -q 'name: "CashRunwayCoreTests"' "$PACKAGE"; then
  fail "Package.swift does not declare CashRunwayCoreTests"
fi
if ! grep -A5 'name: "CashRunwayCoreTests"' "$PACKAGE" | grep -q '"CashRunwayCore"'; then
  fail "CashRunwayCoreTests does not depend on CashRunwayCore target"
fi
pass "CashRunwayCoreTests depends on CashRunwayCore target"

# 3. Xcode references the local CashRunwayCore package.
if ! grep -q 'XCRemoteSwiftPackageReference "CashRunwayWorkspace"' "$PROJECT" && \
   ! grep -q 'XCLocalSwiftPackageReference' "$PROJECT"; then
  fail "Xcode project does not reference the local CashRunwayCore package"
fi
pass "Xcode project references the local CashRunwayCore package"

# 4. The CashRunway app target links CashRunwayCore exactly once.
# Count references inside the PBXFrameworksBuildPhase section only.
frameworks_phase=$(sed -n '/\/\* Begin PBXFrameworksBuildPhase section \*\//,\/\* End PBXFrameworksBuildPhase section \*\//p' "$PROJECT")
core_links=$(echo "$frameworks_phase" | grep -c 'CashRunwayCore in Frameworks' || true)
if [[ "$core_links" -eq 0 ]]; then
  fail "CashRunway target does not link CashRunwayCore"
fi
if [[ "$core_links" -gt 1 ]]; then
  fail "CashRunway target links CashRunwayCore $core_links times (expected 1)"
fi
pass "CashRunway target links CashRunwayCore exactly once"

# 5. No Core source file appears in the app target's PBXSourcesBuildPhase.
# Parse only the PBXSourcesBuildPhase section for the app target (first Sources phase).
section=$(sed -n '/\/\* Begin PBXSourcesBuildPhase section \*\//,\/\* End PBXSourcesBuildPhase section \*\//p' "$PROJECT")
app_sources_phase=$(echo "$section" | sed -n '/A00600010001000100010001 \/\* Sources \*\//,/);/p')
direct_core=$(echo "$app_sources_phase" | grep -c 'Sources/CashRunwayCore/' || true)
if [[ "$direct_core" -gt 0 ]]; then
  fail "The CashRunway app Sources build phase still includes $direct_core Core source file(s)"
fi
pass "No Core source files in CashRunway app Sources build phase"

# 6. No Core source PBXBuildFile entry is also present in the Sources phase.
# (Redundant with check 5, but confirms the object graph is consistent.)
if echo "$app_sources_phase" | grep -q 'Sources/CashRunwayCore/.*in Sources'; then
  fail "Core source PBXBuildFile entries remain in the app Sources phase"
fi
pass "No Core source PBXBuildFile entries in app Sources phase"

echo ""
echo "OK: CashRunwayCore module wiring is correct."
