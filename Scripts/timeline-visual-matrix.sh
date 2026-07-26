#!/usr/bin/env bash
#
# Timeline visual matrix — capture the redesigned Timeline across the
# self-QA visual matrix (docs/plans/timeline-redesign-self-qa.md sec. 3.5)
# without XCUITest. Each fixture state renders on launch, so we only need
# `simctl launch + screenshot` per combination.
#
# Usage:
#   Scripts/timeline-visual-matrix.sh
#   DEVICE_NAME="iPhone 17" Scripts/timeline-visual-matrix.sh
#
# Covers a priority subset (not the full cartesian):
#   languages  : en, uk
#   appearance : light, dark
#   states     : near_equal, large_value, zero_income   (fixture: timeline_qa)
#   Dynamic Type: default grid + a sweep (large / xxxl / accessibility) on one combo
#
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
BUNDLE_ID="dev.roman.cashrunway"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
OUT_DIR="${OUT_DIR:-/tmp/timeline-visual-matrix/${RUN_ID}}"
mkdir -p "$OUT_DIR"

DEVICE_UDID="$(xcrun simctl list devices available | awk -F'[()]' -v n="$DEVICE_NAME" '$0 ~ n" \\(" { print $2; exit }')"
[[ -z "$DEVICE_UDID" ]] && { echo "No available simulator named '$DEVICE_NAME'." >&2; exit 1; }
echo "Device: $DEVICE_NAME ($DEVICE_UDID)"
echo "Output: $OUT_DIR"

xcrun simctl bootstatus "$DEVICE_UDID" -b >/dev/null 2>&1 || true

echo "Building + installing…"
xcodebuild -scheme CashRunway -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" build >"$OUT_DIR/build.log" 2>&1 \
    || { echo "Build failed — see $OUT_DIR/build.log" >&2; exit 1; }
APP_PATH="$(xcodebuild -scheme CashRunway -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')"
xcrun simctl install "$DEVICE_UDID" "$APP_PATH"

reset_ui() {
    xcrun simctl ui "$DEVICE_UDID" appearance light >/dev/null 2>&1 || true
    xcrun simctl ui "$DEVICE_UDID" content_size medium >/dev/null 2>&1 || true
}
trap reset_ui EXIT

# capture <lang> <appearance> <state> <content_size> <name>
capture() {
    local lang="$1" appearance="$2" state="$3" size="$4" name="$5"
    local db="/tmp/cr-visual-${RUN_ID}-${name}.sqlite"
    xcrun simctl ui "$DEVICE_UDID" appearance "$appearance" >/dev/null 2>&1 || true
    xcrun simctl ui "$DEVICE_UDID" content_size "$size" >/dev/null 2>&1 || true
    xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    env \
        SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_MODE=1 \
        SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_SCENARIO=timeline_qa \
        SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_TIMELINE_STATE="$state" \
        SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_DB_PATH="$db" \
        xcrun simctl launch --terminate-running-process "$DEVICE_UDID" "$BUNDLE_ID" \
        -cashRunway.languagePreference "$lang" -AppleLanguages "($lang)" -AppleLocale "${lang}_UA" >/dev/null
    # allow render
    /usr/bin/python3 -c "import time; time.sleep(5)"
    local out="$OUT_DIR/${name}.png"
    xcrun simctl io "$DEVICE_UDID" screenshot "$out" >/dev/null 2>&1 && echo "  $out"
}

echo "Core grid (language × appearance × state, default type)…"
for lang in en uk; do
    for appearance in light dark; do
        for state in near_equal large_value zero_income; do
            capture "$lang" "$appearance" "$state" medium "${state}-${lang}-${appearance}-default"
        done
    done
done

echo "Dynamic Type sweep (uk, light, near_equal)…"
for size in large extra-extra-extra-large accessibility-extra-large; do
    capture uk light near_equal "$size" "near_equal-uk-light-${size}"
done

echo "Done. ${OUT_DIR}"
