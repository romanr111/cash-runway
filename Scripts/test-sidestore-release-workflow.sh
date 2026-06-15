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

echo "SideStore release workflow metadata test passed"
