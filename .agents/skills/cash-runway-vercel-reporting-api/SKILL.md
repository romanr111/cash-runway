---
name: cash-runway-vercel-reporting-api
description: Cash Runway Vercel reporting API deployment and readiness workflow. Use for PR #32-style reporting-api work involving Vercel project/root setup, placeholder versus real env mode, Upstash/KV variables, public API route smoke checks, GitHub App issue creation verification, PR readiness, or avoiding stale handoff conclusions.
---

# Cash Runway Reporting API

Use this skill for Cash Runway `reporting-api` deployment, Vercel readiness, GitHub App issue-creation verification, or PR #32-style handoff/audit work.

## Start With Current Truth

Before drawing conclusions from a handoff, prior trace, or memory:

1. Read the active worktree's `CONTINUITY.md` if it exists.
2. Verify `git worktree list`, active branch, `git status --short`, and recent HEAD.
3. Verify PR state, draft state, mergeability, checks, and head SHA.
4. Verify the current Vercel project/deployment, not only an older URL from a handoff.

Read `references/readiness-checklist.md` for exact commands and expected outcomes.

## Evidence Labels

Classify every important claim with one of these labels:

- `confirmed`: directly observed from repo, CLI, API, dashboard, or command output.
- `runtime-inferred`: proven by behavior, but not by direct settings inspection.
- `manual-dashboard-only`: requires a private dashboard/app-settings check.
- `blocked`: cannot be verified with current access or state.

Do not treat GitHub issue creation as proof of GitHub App installation scope or webhook status. Issue creation only proves the app can authenticate and write issues at runtime.

## Readiness Matrix

Before claiming completion, report this matrix:

| Gate | Status | Evidence |
| --- | --- | --- |
| configured | confirmed/partial/blocked | env names, root directory, project link |
| deployed | confirmed/blocked | latest deployment status and URL |
| publicly reachable | confirmed/blocked | public `GET /api/reports` app-level response |
| functionally verified | confirmed/blocked/not-applicable | real POST issue creation or placeholder-mode limit |
| merge-ready | confirmed/blocked | PR checks, mergeability, validation receipts |

Placeholder env mode can only reach build/route smoke readiness. Real env mode is required for functional POST verification.

## Validation Boundaries

This skill complements `$cash-runway-validation`; it does not replace iOS validation rules. For publish readiness, seeded simulator smoke is allowed when repo policy names it. Local UI/E2E execution remains prohibited unless the user explicitly asks.

## Helper

Use `scripts/reporting_api_readiness_snapshot.sh` for a compact read-only snapshot. It must not print secret values or mutate GitHub, Vercel, or repo state.
