#!/bin/bash
set -euo pipefail

WORKFLOW=".github/workflows/sidestore-release.yml"

if [[ ! -f "$WORKFLOW" ]]; then
    echo "missing $WORKFLOW" >&2
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
