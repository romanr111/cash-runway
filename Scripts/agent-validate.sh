#!/bin/bash
set -euo pipefail

# Cash Runway Agent Validation Script
# Usage:
#   Scripts/agent-validate.sh --focused 'DatabaseTransactionSafetyTests/categoryMerge|BankCategoryMapperTests'
#   Scripts/agent-validate.sh --focused '...' --full
#   Scripts/agent-validate.sh --ui-build
#   Scripts/agent-validate.sh --ui-only
#   Scripts/agent-validate.sh --all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_DIR="/tmp/cash-runway-agent-validation/${RUN_ID}"
mkdir -p "$LOG_DIR"

FOCUSED_FILTER=""
RUN_FULL_TESTS=false
RUN_UI_BUILD=false
RUN_UI_ONLY=false
RUN_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --focused)
            FOCUSED_FILTER="$2"
            shift 2
            ;;
        --full)
            RUN_FULL_TESTS=true
            shift
            ;;
        --ui-build)
            RUN_UI_BUILD=true
            shift
            ;;
        --ui-only)
            RUN_UI_ONLY=true
            shift
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$FOCUSED_FILTER" && "$RUN_FULL_TESTS" == false && "$RUN_UI_BUILD" == false && "$RUN_UI_ONLY" == false && "$RUN_ALL" == false ]]; then
    echo "Usage: $0 --focused '<filter>' [--full] | --ui-build | --ui-only | --all" >&2
    exit 1
fi

FAILED_STEP=""
PASS=true

log() {
    echo "$1" | tee -a "$LOG_DIR/validation.log"
}

fail() {
    PASS=false
    if [[ -z "$FAILED_STEP" ]]; then
        FAILED_STEP="$1"
    fi
    log "❌ $1"
}

pass() {
    log "✅ $1"
}

cd "$PROJECT_DIR"

# --- Core mirror diff ---
if ! diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore > "$LOG_DIR/mirror-diff.log" 2>&1; then
    fail "Core mirror diff mismatch"
    cat "$LOG_DIR/mirror-diff.log" >> "$LOG_DIR/validation.log"
else
    pass "Core mirror diff"
fi

# --- git diff --check ---
if ! git diff --check > "$LOG_DIR/git-diff-check.log" 2>&1; then
    fail "git diff --check found issues"
    cat "$LOG_DIR/git-diff-check.log" >> "$LOG_DIR/validation.log"
else
    pass "git diff --check"
fi

# --- Swift tests ---
if [[ -n "$FOCUSED_FILTER" ]]; then
    log "Running focused swift test --filter '$FOCUSED_FILTER' ..."
    if swift test --filter "$FOCUSED_FILTER" > "$LOG_DIR/swift-test-focused.log" 2>&1; then
        pass "Focused swift test"
    else
        fail "Focused swift test failed"
        tail -30 "$LOG_DIR/swift-test-focused.log" >> "$LOG_DIR/validation.log"
    fi
fi

if [[ "$RUN_FULL_TESTS" == true || "$RUN_ALL" == true ]]; then
    log "Running full swift test ..."
    if swift test > "$LOG_DIR/swift-test-full.log" 2>&1; then
        pass "Full swift test"
    else
        fail "Full swift test failed"
        tail -60 "$LOG_DIR/swift-test-full.log" >> "$LOG_DIR/validation.log"
    fi
fi

# --- Simulator build ---
if [[ "$RUN_UI_BUILD" == true || "$RUN_UI_ONLY" == true || "$RUN_ALL" == true ]]; then
    DESTINATION="platform=iOS Simulator,name=iPhone 17"
    log "Running clean simulator build for '$DESTINATION' ..."
    if xcodebuild -scheme CashRunway -sdk iphonesimulator \
        -destination "$DESTINATION" \
        clean build > "$LOG_DIR/xcodebuild.log" 2>&1; then
        pass "iPhone 17 simulator build"
    else
        # Try newest available iPhone if iPhone 17 fails
        NEWEST=$(xcrun simctl list devices available | grep -i "iPhone" | head -1 | sed 's/.*iPhone/iPhone/' | sed 's/ (.*//')
        if [[ -n "$NEWEST" && "$NEWEST" != "iPhone 17" ]]; then
            log "iPhone 17 unavailable; trying '$NEWEST' ..."
            DESTINATION="platform=iOS Simulator,name=$NEWEST"
            if xcodebuild -scheme CashRunway -sdk iphonesimulator \
                -destination "$DESTINATION" \
                clean build > "$LOG_DIR/xcodebuild.log" 2>&1; then
                pass "${NEWEST} simulator build"
            else
                fail "Simulator build failed"
                grep -E "(warning:|error:|BUILD SUCCEEDED|BUILD FAILED)" "$LOG_DIR/xcodebuild.log" | tail -20 >> "$LOG_DIR/validation.log"
            fi
        else
            fail "Simulator build failed"
            grep -E "(warning:|error:|BUILD SUCCEEDED|BUILD FAILED)" "$LOG_DIR/xcodebuild.log" | tail -20 >> "$LOG_DIR/validation.log"
        fi
    fi
fi

# --- Category icon catalog check (if Theme.swift touched) ---
if git diff --name-only | grep -q "Theme.swift"; then
    log "Theme.swift changed; running category icon catalog check ..."
    if swift "$SCRIPT_DIR/check-category-icons.swift" > "$LOG_DIR/category-icons.log" 2>&1; then
        pass "Category icon catalog"
    else
        fail "Category icon catalog check failed"
        cat "$LOG_DIR/category-icons.log" >> "$LOG_DIR/validation.log"
    fi
fi

# --- Summary ---
log ""
log "Logs: $LOG_DIR"
if [[ "$PASS" == true ]]; then
    echo "✅ Agent validation passed"
    exit 0
else
    echo "❌ Agent validation failed: $FAILED_STEP"
    exit 1
fi
