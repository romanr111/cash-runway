#!/usr/bin/env bash
# Fail if Swift sources contain print()/NSLog() outside the #if DEBUG
# true-branch. Logger (os.Logger) is the sanctioned logging API per AGENTS.md.
#
# Usage:
#   Scripts/check-no-ungated-logging.sh            # lint Sources/ + AppHost/
#   Scripts/check-no-ungated-logging.sh --self-test # run built-in fixtures
set -euo pipefail

cd "$(dirname "$0")/.."

# awk program used both for linting real sources and for self-test fixtures.
AWK_SCAN='
    BEGIN { in_debug = 0; depth = 0; else_branch = 0 }
    /^[[:space:]]*#if[[:space:]]+DEBUG/ {
        in_debug = 1; depth = 1; else_branch = 0; next
    }
    /^[[:space:]]*#if[[:space:]]/ {
        if (in_debug || else_branch) depth++
        next
    }
    /^[[:space:]]*#else[[:space:]]*$/ {
        if (in_debug && depth == 1) { in_debug = 0; else_branch = 1 }
        next
    }
    /^[[:space:]]*#elseif/ {
        if (in_debug && depth == 1) { in_debug = 0; else_branch = 1 }
        next
    }
    /^[[:space:]]*#endif/ {
        if (depth > 0) {
            depth--
            if (depth == 0) { in_debug = 0; else_branch = 0 }
        }
        next
    }
    {
        if (in_debug) next
        line = $0
        sub(/^[[:space:]]+/, "", line)
        if (line ~ /^(print|NSLog)\(/) {
            printf "%s:%d: ungated logging: %s\n", file, NR, $0
            rc = 1
        }
    }
    END { exit (rc ? 1 : 0) }
'

run_scan() {
    # $1 = label for messages, $2 = file path, $3 = expected: pass|fail
    local label="$1" path="$2" expected="$3"
    local out rc
    out=$(awk -v file="$path" "$AWK_SCAN" "$path" 2>&1) && rc=0 || rc=$?
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
    trap 'rm -rf "$tmp"' RETURN

    # 1. should pass: print inside #if DEBUG true-branch
    cat >"$tmp/debug_only.swift" <<'EOF'
import Foundation
#if DEBUG
print("debug only")
#endif
EOF
    # 2. should fail: print outside #if DEBUG
    cat >"$tmp/outside.swift" <<'EOF'
import Foundation
print("this ships in release")
EOF
    # 3. should fail: print inside #else of #if DEBUG (the release branch)
    cat >"$tmp/else_release.swift" <<'EOF'
import Foundation
#if DEBUG
print("debug only")
#else
print("this ships in release")
#endif
EOF
    # 4. should pass: nested #if inside #if DEBUG true-branch
    cat >"$tmp/nested_debug.swift" <<'EOF'
import Foundation
#if DEBUG
#if SOME_FLAG
print("inside nested debug")
#endif
print("still inside debug")
#endif
EOF
    # 5. should pass: print inside #elseif of #if DEBUG when condition is DEBUG-false
    #    (the elseif-true branch is only compiled when DEBUG is false, i.e. release)
    #    Wait — #elseif is evaluated at compile time; if DEBUG is false the elseif
    #    branch that IS selected compiles. We treat #elseif as release-branch => fail.
    cat >"$tmp/elseif_release.swift" <<'EOF'
import Foundation
#if DEBUG
print("debug only")
#elseif OTHER
print("this ships in release when DEBUG is false")
#endif
EOF

    run_scan "print inside #if DEBUG (pass)"      "$tmp/debug_only.swift"     pass || rc=1
    run_scan "print outside #if DEBUG (fail)"      "$tmp/outside.swift"        fail || rc=1
    run_scan "print inside #else of #if DEBUG (fail)" "$tmp/else_release.swift"  fail || rc=1
    run_scan "nested #if inside #if DEBUG (pass)"  "$tmp/nested_debug.swift"   pass || rc=1
    run_scan "print inside #elseif of #if DEBUG (fail)" "$tmp/elseif_release.swift" fail || rc=1
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
    awk -v file="$file" "$AWK_SCAN" "$file" || status=1
done < <(find Sources AppHost -name '*.swift' -type f)

if [ "$status" -ne 0 ]; then
    echo ""
    echo "Use Logger (os.Logger) with privacy annotations, or gate with #if DEBUG."
    exit 1
fi

echo "No ungated print()/NSLog() calls found."