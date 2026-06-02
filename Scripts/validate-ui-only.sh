#!/bin/bash
set -euo pipefail

# Cash Runway Fast UI-Only Validation Script
# Thin wrapper around agent-validate.sh --ui-only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/agent-validate.sh" --ui-only
