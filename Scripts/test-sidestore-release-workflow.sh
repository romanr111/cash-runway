#!/bin/bash
set -euo pipefail

WORKFLOW=".github/workflows/sidestore-release.yml"

if [[ ! -f "$WORKFLOW" ]]; then
    echo "missing $WORKFLOW" >&2
    exit 1
fi

if ! grep -q 'git log --first-parent --format=' "$WORKFLOW"; then
    echo "release workflow must derive notes from the previous release commit on main history" >&2
    exit 1
fi

if ! grep -q 'current_version="${VERSION}"' "$WORKFLOW"; then
    echo "release workflow must exclude the current release from its own note baseline" >&2
    exit 1
fi

if ! awk '
  /- name: Generate release notes from git log/ { in_notes_step = 1; next }
  in_notes_step && /^      - name:/ { exit }
  in_notes_step && /VERSION="\$\{\{ steps\.meta\.outputs\.version \}\}"/ { found = 1 }
  END { exit !found }
' "$WORKFLOW"; then
    echo "release notes step must define VERSION from resolved release metadata" >&2
    exit 1
fi

if grep -q 'PREV_TAG=$(git tag --sort=-version:refname' "$WORKFLOW"; then
    echo "release workflow must not use an unreachable release tag as the note baseline" >&2
    exit 1
fi

if grep -q 'print \$1; exit' "$WORKFLOW"; then
    echo "release workflow must drain the commit log after selecting the prior release" >&2
    exit 1
fi

if ! grep -q 'MARKETING_VERSION="${{ steps.meta.outputs.version }}"' "$WORKFLOW"; then
    echo "release xcodebuild must set MARKETING_VERSION from release metadata" >&2
    exit 1
fi

if ! grep -q 'CURRENT_PROJECT_VERSION="${{ steps.meta.outputs.build }}"' "$WORKFLOW"; then
    echo "release xcodebuild must set CURRENT_PROJECT_VERSION from release metadata" >&2
    exit 1
fi

if ! grep -q 'Verify packaged app metadata' "$WORKFLOW"; then
    echo "release workflow must verify packaged IPA metadata before publishing source.json" >&2
    exit 1
fi

if ! grep -q 'CFBundleShortVersionString' "$WORKFLOW"; then
    echo "release workflow must inspect CFBundleShortVersionString" >&2
    exit 1
fi

if ! grep -q 'CFBundleVersion' "$WORKFLOW"; then
    echo "release workflow must inspect CFBundleVersion" >&2
    exit 1
fi

if ! grep -q 'Configure feedback reporting' "$WORKFLOW"; then
    echo "release workflow must configure feedback reporting before building" >&2
    exit 1
fi

if ! grep -q 'CASH_RUNWAY_REPORTING_ENABLED=YES' "$WORKFLOW"; then
    echo "release workflow must enable feedback reporting for SideStore builds" >&2
    exit 1
fi

if ! grep -q 'CASH_RUNWAY_REPORT_ENDPOINT_URL="${REPORT_ENDPOINT_URL}"' "$WORKFLOW"; then
  echo "release workflow must pass the reporting endpoint to xcodebuild" >&2
  exit 1
fi

if ! grep -q 'REPORT_ENDPOINT_URL="${REPORT_ENDPOINT_URL%/}"' "$WORKFLOW" ||
  ! grep -q 'REPORT_ENDPOINT_URL="${REPORT_ENDPOINT_URL}/api/reports"' "$WORKFLOW"; then
  echo "release workflow must normalize bare reporting domains to /api/reports" >&2
  exit 1
fi

if ! grep -q "REPORT_ENDPOINT_URL=%s\\\\n" "$WORKFLOW"; then
  echo "release workflow must persist the normalized reporting endpoint for build steps" >&2
  exit 1
fi

if ! grep -q 'CASH_RUNWAY_REPORT_ENVIRONMENT=sidestore' "$WORKFLOW"; then
  echo "release workflow must mark SideStore report environment" >&2
  exit 1
fi

if ! grep -q 'Scripts/generate-reporting-secrets.swift' "$WORKFLOW"; then
    echo "release workflow must generate reporting secrets before building" >&2
    exit 1
fi

if ! grep -q 'CashRunwayReportingEnabled' "$WORKFLOW"; then
    echo "release workflow must verify packaged reporting flag" >&2
    exit 1
fi

echo "SideStore release workflow metadata test passed"
