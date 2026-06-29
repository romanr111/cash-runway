#!/usr/bin/env bash
# Fail if a Swift type declares `@unchecked Sendable` without a justification
# comment within 5 lines after the declaration. The comment must contain the
# word "justified" (case-insensitive). This guards against silent race
# regressions when a future edit adds mutable state to a class that was
# previously safe-by-construction.
#
# Usage:
#   Scripts/check-unchecked-sendable.sh            # lint Sources/ + AppHost/
#   Scripts/check-unchecked-sendable.sh --self-test # run built-in fixtures
set -euo pipefail

cd "$(dirname "$0")/.."

THRESHOLD=5

# For each file, find lines matching `@unchecked Sendable`, then check the
# next $THRESHOLD lines for a comment containing "justified".
check_file() {
    local file="$1"
    local rc=0
    # Get line numbers of @unchecked Sendable declarations. Match only
    # conformance syntax (": @unchecked Sendable" or ", @unchecked Sendable"),
    # not occurrences inside comments.
    local matches
    matches=$(grep -nE '[:,][[:space:]]*@unchecked[[:space:]]+Sendable' "$file" 2>/dev/null || true)
    [ -z "$matches" ] && return 0
    while IFS= read -r match; do
        local lineno
        lineno=$(echo "$match" | cut -d: -f1)
        # Look at the next $THRESHOLD lines for a comment containing "justified".
        local slice
        slice=$(sed -n "$((lineno+1)),$((lineno+THRESHOLD))p" "$file")
        if ! echo "$slice" | grep -qiE 'justified'; then
            echo "$file:$lineno: @unchecked Sendable without justification comment within $THRESHOLD lines"
            rc=1
        fi
    done <<< "$matches"
    return $rc
}

run_scan() {
    local label="$1" path="$2" expected="$3"
    local out rc
    out=$(check_file "$path" 2>&1) && rc=0 || rc=$?
    if [ "$expected" = "pass" ]; then
        if [ "$rc" -ne 0 ]; then
            echo "FAIL: $label — expected pass, got violations:" >&2
            echo "$out" >&2
            return 1
        fi
    else
        if [ "$rc" -eq 0 ]; then
            echo "FAIL: $label — expected a violation, but none was reported" >&2
            return 1
        fi
    fi
    echo "ok: $label"
}

self_test() {
    local tmp rc
    tmp=$(mktemp -d)
    # shellcheck disable=SC2064
    trap 'rm -rf "$tmp"' RETURN

    # 1. should pass: @unchecked Sendable with justification comment on next line
    cat >"$tmp/justified.swift" <<'EOF'
public final class Foo: @unchecked Sendable {
    // @unchecked Sendable is justified: immutable after init.
    private let x: Int
    public init() { x = 0 }
}
EOF

    # 2. should fail: @unchecked Sendable with no justification within 5 lines
    cat >"$tmp/unjustified.swift" <<'EOF'
public final class Bar: @unchecked Sendable {
    private var x: Int
    public init() { x = 0 }
}
EOF

    # 3. should pass: justification within 5 lines (3 lines later)
    cat >"$tmp/justified_late.swift" <<'EOF'
public final class Baz: @unchecked Sendable {
    private let a: Int
    private let b: Int

    // @unchecked Sendable is justified: all fields immutable.
    public init() { a = 0; b = 0 }
}
EOF

    # 4. should fail: justification is 6 lines away (beyond threshold)
    cat >"$tmp/too_far.swift" <<'EOF'
public final class Qux: @unchecked Sendable {
    private let a: Int
    private let b: Int
    private let c: Int
    private let d: Int
    private let e: Int

    // @unchecked Sendable is justified: too far away
    public init() { a = 0; b = 0; c = 0; d = 0; e = 0 }
}
EOF

    run_scan "justified (pass)"       "$tmp/justified.swift"     pass || rc=1
    run_scan "unjustified (fail)"      "$tmp/unjustified.swift"   fail || rc=1
    run_scan "justified late (pass)"   "$tmp/justified_late.swift" pass || rc=1
    run_scan "too far (fail)"          "$tmp/too_far.swift"       fail || rc=1
    rc=${rc:-0}
    if [ "$rc" -eq 0 ]; then
        echo "All self-tests passed."
    fi
    return "${rc:-0}"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

status=0
while IFS= read -r file; do
    check_file "$file" || status=1
done < <(find Sources AppHost -name '*.swift' -type f 2>/dev/null)

if [ "$status" -ne 0 ]; then
    echo ""
    echo "Add a comment containing 'justified' within $THRESHOLD lines of each"
    echo "@unchecked Sendable declaration explaining why the conformance is safe."
    exit 1
fi

echo "All @unchecked Sendable declarations have justification comments."