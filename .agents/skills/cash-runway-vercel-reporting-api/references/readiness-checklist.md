# Reporting API Readiness Checklist

Use this checklist before auditing, deploying, or declaring Cash Runway reporting API readiness.

## Worktree Truth

Run from the active Cash Runway worktree:

```bash
git worktree list
git rev-parse --abbrev-ref HEAD
git status --short
git log --oneline -5
```

If `CONTINUITY.md` exists, read it before trusting any handoff. If ledger truth differs from git or PR truth, treat the ledger as stale and update/report that mismatch before continuing.

## PR Truth

For PR #32-style work:

```bash
gh pr view 32 --repo romanr111/cash-runway \
  --json isDraft,mergeable,state,headRefOid,statusCheckRollup,url
```

Required merge-ready evidence:

- PR is open.
- PR is not draft, unless intentionally still in staging.
- `mergeable` is `MERGEABLE`.
- Required current checks are successful or intentionally skipped by CI policy.
- The PR head SHA matches the local branch HEAD being evaluated.

## Reporting API Local Checks

Run from `reporting-api/`:

```bash
npm test
npm run typecheck
npm audit --omit=dev
```

Expected for PR #32-style readiness:

- Test suite passes.
- TypeScript typecheck passes.
- Production dependency audit has no vulnerabilities or explicitly documented accepted findings.

## Vercel Checks

Verify these before using a deployment URL in conclusions:

- Project name is `cash-runway-reporting-api`.
- Project root directory is `reporting-api`.
- Latest relevant deployment is `Ready`.
- Preview env variable names are present; do not print values.
- Public route check reaches the app:

```bash
curl -i "$DEPLOYMENT_URL/api/reports"
```

Expected public GET result is an app-level `405` response such as `{"error":"Method not allowed."}`. A Vercel-level `401` means Deployment Protection is still blocking iOS clients.

## Environment Mode

Classify the environment before testing:

- Placeholder mode: env names exist but values are placeholders. This permits build, route, and deployment smoke only.
- Real env mode: GitHub App, repo, report secret, and Upstash/KV values are real. This permits functional POST verification.

Use Vercel env-name listings only to prove names/scopes. Never dump env values, private keys, tokens, local xcconfig values, or generated report secrets.

For Upstash/Vercel KV, prefer the current project code's expected names. PR #32 evolved from `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` to Vercel KV-style names such as `KV_REST_API_URL` and `KV_REST_API_TOKEN`; verify against code before declaring a name mismatch.

## GitHub App Evidence Caveat

Functional issue creation proves:

- the app can authenticate;
- the app can create issues in `romanr111/cash-runway`;
- labels and issue formatting can be verified from the created issue.

It does not prove:

- the app is installed only on `romanr111/cash-runway`;
- Issues permission is exactly read/write;
- webhook is disabled.

Those remain `manual-dashboard-only` unless directly inspected in GitHub App settings with sufficient access.

## Functional POST Verification

Only run real POST verification in real env mode. Use a harmless staging/manual report title and close or label the created issue if appropriate. Record:

- deployment URL used;
- HTTP status class;
- created issue URL/number;
- app/bot author;
- labels;
- whether any sensitive content was avoided.

Do not include secrets, full request body if it contains private markers, or generated report secret values in logs or final output.

## Final Readiness Matrix

Use this exact matrix shape:

| Gate | Status | Evidence |
| --- | --- | --- |
| configured | confirmed/partial/blocked | Vercel project, root, env names, repo link |
| deployed | confirmed/blocked | latest Ready deployment URL |
| publicly reachable | confirmed/blocked | public GET app-level 405, not Vercel 401 |
| functionally verified | confirmed/blocked/not-applicable | real POST issue or placeholder-mode limit |
| merge-ready | confirmed/blocked | PR mergeability, checks, local validation |

When evidence is indirect, say so. Avoid converting runtime inference into dashboard confirmation.
