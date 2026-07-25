---
name: cash-runway-pr-repair
description: Repair or update an existing Cash Runway PR after review findings, failed GitHub checks, or CI drift. Covers worktree safety, focused fixes, local lint/tests, push, and GitHub check annotation triage.
---

# Cash Runway PR Repair

Use this when the user asks to fix, update, or push an existing Cash Runway PR,
especially after review findings or failed checks.

## Required Inputs

- PR number or branch name.
- Target branch, if not already visible from GitHub.
- Whether the PR should remain draft or be marked ready.

If the PR number is available, discover branch and base with:

```bash
gh pr view <PR> --json number,title,headRefName,baseRefName,state,isDraft,url,mergeStateStatus
```

## Start Safely

Before editing, committing, or pushing:

```bash
git worktree list
git rev-parse --abbrev-ref HEAD
git status --short
git diff --stat
```

If dirty files are unrelated, leave them alone. If they affect files you must
touch, inspect them and integrate with them. Never use `git add -A`.

Run the repo preflight helpers required by `AGENTS.md` where feasible. If
CodeGraph is unavailable, report the fallback and keep searches narrow.

## Repair Loop

1. Read the review finding, failed check annotation, or user-supplied blocker.
2. Reproduce with the smallest focused test or lint command.
3. Make the smallest code or test change that addresses that blocker.
4. Run focused verification for the touched behavior.
5. Run `just lint` before the first push after source/test edits.
6. Stage explicit files only.
7. Before commit, run:

```bash
git status --short
git diff --cached --stat
git diff --cached --name-only
```

Abort the commit if generated files, secrets/config, backups, lock files, or
unrelated files are staged unexpectedly.

## SwiftPM Focused Test Fallback

Prefer repository `just` recipes. For focused Swift package tests:

```bash
just test-isolated --filter <SuiteOrTest>
```

If isolated compilation is killed before tests run with `signal 9`, retry once:

```bash
just test-isolated --jobs 1 --filter <SuiteOrTest>
```

If that is killed before tests run too, stop retrying isolated builds and use
the cached, lower-concurrency path:

```bash
just test --jobs 1 --filter <SuiteOrTest>
```

Report the isolated failures as build-environment/compiler-memory failures and
state whether the cached focused run passed.

## Push And Check

Before creating a remote branch, verify it does not unexpectedly exist:

```bash
git ls-remote origin refs/heads/<branch>
```

For an existing PR branch, push the current branch normally:

```bash
git push origin <branch>
```

After push:

```bash
gh pr checks <PR>
```

If a check fails, use check-run annotations before full logs:

```bash
gh api repos/romanr111/cash-runway/check-runs/<job_id>/annotations --paginate
```

Only inspect full logs when annotations do not identify the actionable failure.

## Final Report

Report:

- PR URL, branch, base, and draft/ready state.
- Commits pushed.
- Local validation commands that passed.
- GitHub checks that are passing, pending, skipped, or failing.
- Any skipped gate and why.
- CodeGraph availability and any fallback used.
- Headroom proxy status if the repo instructions required checking it.
