#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

pr="${1:-}"

section() {
    printf '\n== %s ==\n' "$1"
}

run_check() {
    local label="$1"
    shift

    if "$@" > "/tmp/cash-runway-pr-status-${label}.log" 2>&1; then
        printf 'PASS %s\n' "$label"
    else
        printf 'FAIL %s (see /tmp/cash-runway-pr-status-%s.log)\n' "$label" "$label"
        return 1
    fi
}

section "Git"
printf 'branch: %s\n' "$(git rev-parse --abbrev-ref HEAD)"
printf 'head: %s\n' "$(git rev-parse --short HEAD)"
printf 'status:\n'
status_output="$(git status --short)"
if [[ -n "$status_output" ]]; then
    printf '%s\n' "$status_output"
else
    printf 'clean\n'
fi

section "Repository Checks"
run_check mirror-diff diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore || true
run_check diff-check git diff --check || true
if [[ -x Scripts/generate-mcc-mapping.py ]]; then
    run_check mcc-mapping Scripts/generate-mcc-mapping.py --check || true
else
    printf 'SKIP mcc-mapping (Scripts/generate-mcc-mapping.py not executable)\n'
fi

if [[ -z "$pr" ]]; then
    section "Pull Request"
    printf 'SKIP GitHub PR checks (no PR number or URL provided)\n'
    exit 0
fi

if ! command -v gh > /dev/null 2>&1; then
    section "Pull Request"
    printf 'SKIP GitHub PR checks (gh CLI not found)\n'
    exit 0
fi

section "Pull Request"
if gh pr view "$pr" --json number,title,url,isDraft,baseRefName,headRefName,mergeable --jq '"#\(.number) \(.title)\nurl: \(.url)\ndraft: \(.isDraft)\nbase: \(.baseRefName)\nhead: \(.headRefName)\nmergeable: \(.mergeable)"'; then
    :
else
    printf 'WARN unable to read PR metadata for %s\n' "$pr"
fi

section "GitHub Checks"
if gh pr checks "$pr"; then
    :
else
    printf 'WARN unable to read PR checks for %s\n' "$pr"
fi

section "Readiness Buckets"
printf 'repo validation: see checks above\n'
printf 'runtime smoke: run just smoke when required\n'
printf 'backend/API reachability: run reporting-api gates when API files changed\n'
printf 'release readiness: requires explicit release gates and physical-device rehearsal when applicable\n'
