#!/usr/bin/env bash
set -u

PR_NUMBER="${1:-32}"
DEPLOYMENT_URL="${2:-}"
REPO="${CASH_RUNWAY_REPO:-romanr111/cash-runway}"
PROJECT_NAME="${VERCEL_PROJECT_NAME:-cash-runway-reporting-api}"

overall_rc=0

say() {
  printf '%s\n' "$*"
}

section() {
  printf '\n[%s]\n' "$1"
}

mark_problem() {
  overall_rc=1
  say "$*"
}

section "git"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  head="$(git rev-parse --short HEAD 2>/dev/null || true)"
  status="$(git status --short 2>/dev/null || true)"
  say "root: ${root:-unknown}"
  say "branch: ${branch:-unknown}"
  say "head: ${head:-unknown}"
  if [ -z "$status" ]; then
    say "status: clean"
  else
    say "status: dirty"
    git status --short | sed 's/^/  /'
  fi
else
  mark_problem "not a git worktree"
fi

section "pr"
if command -v gh >/dev/null 2>&1; then
  pr_json="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json isDraft,mergeable,state,headRefOid,url 2>/dev/null || true)"
  if [ -n "$pr_json" ]; then
    python3 - "$pr_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
head = data.get("headRefOid") or ""
print(f"number: {data.get('url', '').rstrip('/').split('/')[-1] or 'unknown'}")
print(f"state: {data.get('state')}")
print(f"draft: {data.get('isDraft')}")
print(f"mergeable: {data.get('mergeable')}")
print(f"head: {head[:12] if head else 'unknown'}")
print(f"url: {data.get('url')}")
PY
  else
    mark_problem "pr: unavailable via gh"
  fi
else
  mark_problem "pr: gh not found"
fi

section "vercel"
if command -v vercel >/dev/null 2>&1; then
  if [ -d ".vercel" ]; then
    say "local link: .vercel present"
  else
    say "local link: .vercel not present"
  fi

  env_output="$(vercel env ls 2>/dev/null || true)"
  if [ -n "$env_output" ]; then
    say "env names:"
    printf '%s\n' "$env_output" |
      awk '
        NR == 1 { next }
        /^name[[:space:]]/ { next }
        /^Common next commands:/ { exit }
        NF > 0 { print "  " $1 }
      ' |
      grep -E '^(  )[A-Z0-9_]+$' |
      sort -u
  else
    say "env names: unavailable"
  fi

  say "expected project: ${PROJECT_NAME}"
else
  mark_problem "vercel: cli not found"
fi

section "public route"
if [ -n "$DEPLOYMENT_URL" ]; then
  trimmed="${DEPLOYMENT_URL%/}"
  url="${trimmed}/api/reports"
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
  if [ -n "$code" ]; then
    say "url: $url"
    say "get_status: $code"
    if [ "$code" = "405" ]; then
      say "reachability: confirmed app-level response"
    elif [ "$code" = "401" ]; then
      mark_problem "reachability: blocked by auth/protection"
    else
      say "reachability: unexpected status; inspect app/deployment logs"
    fi
  else
    mark_problem "reachability: curl failed"
  fi
else
  say "url: not provided"
  say "reachability: not checked"
fi

section "manual confirmations"
say "github_app_install_scope: manual-dashboard-only unless directly inspected"
say "github_app_issues_permission: manual-dashboard-only unless directly inspected"
say "github_app_webhook_disabled: manual-dashboard-only unless directly inspected"
say "issue_creation_runtime: confirmed only when a real POST creates an issue"

exit "$overall_rc"
