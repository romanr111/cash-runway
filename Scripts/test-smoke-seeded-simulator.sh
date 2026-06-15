#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/xcrun" <<'SH'
#!/bin/bash
set -euo pipefail

if [[ "$*" == "simctl list devices available" ]]; then
  echo "    iPhone 17 (FAKE-UDID) (Shutdown)"
  exit 0
fi

if [[ "$*" == "simctl bootstatus FAKE-UDID" ]]; then
  sleep 2
  exit 0
fi

if [[ "$*" == "simctl boot FAKE-UDID" ]]; then
  touch "${FAKE_BOOT_MARKER:?}"
  exit 0
fi

echo "unexpected xcrun invocation: $*" >&2
exit 99
SH

cat > "$TMP_DIR/bin/xcodebuild" <<'SH'
#!/bin/bash
echo "xcodebuild should not be reached" >&2
exit 88
SH

chmod +x "$TMP_DIR/bin/xcrun" "$TMP_DIR/bin/xcodebuild"

OUTPUT="$TMP_DIR/output.log"
set +e
PATH="$TMP_DIR/bin:$PATH" \
  FAKE_BOOT_MARKER="$TMP_DIR/boot-called" \
  CASH_RUNWAY_SMOKE_BOOT_TIMEOUT_SECONDS=1 \
  "$PROJECT_DIR/Scripts/smoke-seeded-simulator.sh" > "$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected smoke script to fail when simulator bootstatus times out" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

if ! grep -q "Timed out waiting for iPhone 17 simulator to boot" "$OUTPUT"; then
  echo "expected boot timeout message" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

if [[ ! -f "$TMP_DIR/boot-called" ]]; then
  echo "expected smoke script to request simulator boot before waiting" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

if grep -q "xcodebuild should not be reached" "$OUTPUT"; then
  echo "smoke script continued to build after boot timeout" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

echo "smoke script boot timeout test passed"
