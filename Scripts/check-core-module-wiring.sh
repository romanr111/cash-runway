#!/usr/bin/env bash
# CashRunwayCore module-wiring validation.
# Thin shim that delegates to the plistlib-based parser in
# check_core_module_wiring.py (kept as .sh so existing callers/CI are unchanged).
set -euo pipefail
exec python3 "$(dirname "$0")/check_core_module_wiring.py" "$@"
