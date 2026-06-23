#!/bin/bash
set -euo pipefail

# Cash Runway Deterministic Seeded Simulator Smoke Script
# Usage:
#   Scripts/smoke-seeded-simulator.sh
#   Scripts/smoke-seeded-simulator.sh <scenario> <start_screen>
#
# Simulator env var rules:
#   - simctl launch strips the SIMCTL_CHILD_ prefix automatically.
#   - Do NOT use --env flags with simctl launch; they are invalid.
#   - Use: env SIMCTL_CHILD_VAR=value simctl launch ...
#
# Known benign log patterns (excluded from error scan):
#   BackgroundTask, BoardServices, RunningBoardServices, XPCErrors,
#   BKSProcessAssertion, app_launch_measurement, CA Event
#   FontServices/XPC noise is scoped to the com.apple.FontServices and
#   com.apple.xpc:connection system subsystems, so a genuine app-level
#   XPC/FontServices error (subsystem dev.roman.cashrunway) is never masked.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO="${1:-transaction_core}"
START_SCREEN="${2:-}"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_DIR="/tmp/cash-runway-agent-validation/${RUN_ID}"
mkdir -p "$LOG_DIR"

DB_PATH="/tmp/cash-runway-ui-smoke-${RUN_ID}.sqlite"
BUNDLE_ID="dev.roman.cashrunway"
PASS=true
BOOT_TIMEOUT_SECONDS="${CASH_RUNWAY_SMOKE_BOOT_TIMEOUT_SECONDS:-120}"

log() {
    echo "$1" | tee -a "$LOG_DIR/smoke.log"
}

fail() {
    PASS=false
    log "❌ $1"
}

wait_for_simulator_boot() {
    local phase="$1"
    local status=0

    perl -e '
        my $timeout = shift @ARGV;
        my $pid = fork();
        die "fork failed\n" unless defined $pid;
        if ($pid == 0) {
            exec @ARGV;
            die "exec failed: $!\n";
        }
        $SIG{ALRM} = sub {
            kill "TERM", $pid;
            sleep 1;
            kill "KILL", $pid;
            waitpid($pid, 0);
            exit 124;
        };
        alarm $timeout;
        waitpid($pid, 0);
        my $status = $?;
        exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
    ' "$BOOT_TIMEOUT_SECONDS" xcrun simctl bootstatus "$DEVICE_UDID" > /dev/null 2>&1 || status=$?

    if [[ "$status" -eq 0 ]]; then
        return 0
    fi

    if [[ "$status" -eq 124 ]]; then
        fail "Timed out waiting for $DEVICE_NAME simulator to boot during $phase"
        echo "❌ Seeded simulator smoke failed: $DEVICE_NAME"
        echo "Logs: $LOG_DIR"
        exit 1
    fi

    return "$status"
}

simulator_is_booted() {
    xcrun simctl list devices available | grep -q "$DEVICE_UDID.*(Booted)"
}

cd "$PROJECT_DIR"

# --- Find or boot iPhone 17 simulator ---
DEVICE_NAME="iPhone 17"
DEVICE_UDID=$(xcrun simctl list devices available | grep -E "^\\s*${DEVICE_NAME} \\(" | head -1 | awk -F'[()]' '{print $2}')

if [[ -z "$DEVICE_UDID" ]]; then
    log "iPhone 17 not found; trying newest available iPhone ..."
    DEVICE_LINE=$(xcrun simctl list devices available | grep -E "^\\s*iPhone [0-9]+ \\(" | head -1)
    DEVICE_NAME=$(echo "$DEVICE_LINE" | sed -E 's/^\\s*([^(]+)\\s*\\(.*/\\1/' | sed 's/ *$//')
    DEVICE_UDID=$(echo "$DEVICE_LINE" | awk -F'[()]' '{print $2}')
fi

if [[ -z "$DEVICE_UDID" ]]; then
    fail "No available iPhone simulator found"
    echo "❌ Seeded simulator smoke failed: $DEVICE_NAME"
    exit 1
fi

log "Using simulator: $DEVICE_NAME ($DEVICE_UDID)"

# Boot if not already booted
if ! simulator_is_booted; then
    log "Booting simulator ..."
    xcrun simctl boot "$DEVICE_UDID" > "$LOG_DIR/boot.log" 2>&1 || true
fi
wait_for_simulator_boot "boot"
sleep 3

# --- Build ---
log "Building for simulator ..."
if ! xcodebuild -scheme CashRunway -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    build > "$LOG_DIR/xcodebuild.log" 2>&1; then
    fail "Simulator build failed"
    grep -E "(warning:|error:|BUILD SUCCEEDED|BUILD FAILED)" "$LOG_DIR/xcodebuild.log" | tail -20 >> "$LOG_DIR/smoke.log"
    echo "❌ Seeded simulator smoke failed: $DEVICE_NAME"
    echo "Logs: $LOG_DIR"
    exit 1
fi

# --- Install ---
log "Installing app ..."
BUILT_PRODUCTS_DIR=$(xcodebuild -scheme CashRunway -sdk iphonesimulator -destination "platform=iOS Simulator,name=$DEVICE_NAME" -showBuildSettings 2>/dev/null | grep -E "^\\s*BUILT_PRODUCTS_DIR" | head -1 | sed 's/.*= //')
APP_PATH="${BUILT_PRODUCTS_DIR}/CashRunway.app"

if [[ -z "$BUILT_PRODUCTS_DIR" || ! -d "$APP_PATH" ]]; then
    fail "Could not locate built .app bundle at $APP_PATH"
    echo "❌ Seeded simulator smoke failed: Could not locate .app"
    echo "Logs: $LOG_DIR"
    exit 1
fi

xcrun simctl install "$DEVICE_UDID" "$APP_PATH"

# Terminate any existing instance first
xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
sleep 1

# Launch with env vars via SIMCTL_CHILD_ prefix
log "Launching app with scenario=$SCENARIO ..."
ENV_ARGS=(
    "SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_MODE=1"
    "SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_SCENARIO=$SCENARIO"
    "SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_DB_PATH=$DB_PATH"
)
if [[ -n "$START_SCREEN" ]]; then
    ENV_ARGS+=("SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_START_SCREEN=$START_SCREEN")
fi
LAUNCH_OUT=$(env "${ENV_ARGS[@]}" xcrun simctl launch --terminate-running-process \
    "$DEVICE_UDID" "$BUNDLE_ID" 2>&1 | tee "$LOG_DIR/launch.log"
) || true

# --- Collect logs ---
sleep 5

# Screenshot
xcrun simctl io "$DEVICE_UDID" screenshot "$LOG_DIR/screenshot.png" 2>/dev/null || true

# Runtime log
xcrun simctl spawn "$DEVICE_UDID" log show --predicate 'subsystem == "dev.roman.cashrunway"' --last 2m > "$LOG_DIR/app-runtime.log" 2>/dev/null || true

# OS log
xcrun simctl spawn "$DEVICE_UDID" log show --predicate 'process == "CashRunway"' --last 2m > "$LOG_DIR/os.log" 2>/dev/null || true

# --- Scan logs for errors ---
log "Scanning logs for errors/warnings/crashes ..."
COMBINED_LOGS="$LOG_DIR/app-runtime.log $LOG_DIR/os.log $LOG_DIR/launch.log"

if grep -iE "error|warning|fatal|assert|crash|exception" $COMBINED_LOGS 2>/dev/null | grep -viE "UITEST|UI TEST|xcodebuild|simctl|BUILD SUCCEEDED|os_log|subsystem|category|BackgroundTask|BoardServices|RunningBoardServices|XPCErrors|assertion.*reference|BKSProcessAssertion|_UIBackgroundTaskInfo|Persistent SceneSession|Launch Background Task|Coalescing|Invalid device|app_launch_measurement|CA Event|com\.apple\.FontServices|com\.apple\.xpc:connection" | grep -v "^\s*$" > "$LOG_DIR/errors-found.log" 2>/dev/null; then
    ERROR_COUNT=$(wc -l < "$LOG_DIR/errors-found.log" | tr -d ' ')
    if [[ "$ERROR_COUNT" -gt 0 ]]; then
        # Filter out known benign patterns
        FILTERED=$(grep -viE "backgroundTask|BGTaskScheduler|BGProcessingTaskRequest|register.*task|schedule.*task|BackgroundMaintenanceCoordinator" "$LOG_DIR/errors-found.log" || true)
        if [[ -n "$FILTERED" ]]; then
            fail "Log scan found potential issues ($ERROR_COUNT lines)"
            echo "$FILTERED" | head -20 >> "$LOG_DIR/smoke.log"
        fi
    fi
fi

# --- Summary ---
log ""
log "Screenshot: $LOG_DIR/screenshot.png"
log "Logs: $LOG_DIR/"

if [[ "$PASS" == true ]]; then
    echo "✅ Seeded simulator smoke passed"
    echo "Screenshot: $LOG_DIR/screenshot.png"
    echo "Logs: $LOG_DIR/"
    exit 0
else
    echo "❌ Seeded simulator smoke failed"
    echo "Screenshot: $LOG_DIR/screenshot.png"
    echo "Logs: $LOG_DIR/"
    exit 1
fi
