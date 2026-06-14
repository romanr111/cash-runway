<!--
Rules:
- Rewrite Snapshot to current truth after a meaningful update.
- Meaningful update: file modified, decision made, blocker hit or resolved,
  task completed or abandoned, or validation result changed.
- Reading or searching does not trigger a rewrite.
- Current state: one sentence, past tense, what is true now.
- Next action: one imperative sentence, one concrete step.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
-->

## Snapshot

- Goal: Fix screenshot-feedback and CodeGraph status-parser review findings on a branch, then merge the result back to `main`.
- Success criteria: Preserve the approved `screenshots` feedback field, stop parsing undocumented `Project:` from `codegraph status`, cover the CodeGraph change with regression tests, and land the branch on `main`.
- Current state: The screenshot-feedback and CodeGraph status-parser fixes landed on local `main`.
- Next action: None.
- Handoff trigger: Rewrite this Snapshot before context compaction, a major task switch, or task completion.

## Git Context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- Base: `origin/main` at `0cca853`

## Working Set

- `agent_docs/instructions/reporting-api.md`
- `Scripts/codegraph-bootstrap.sh`
- `Scripts/test-codegraph-bootstrap.sh`
- `CONTINUITY.md`

## Receipts

- 2026-06-14 [RESOLVED] Narrowed `agent_docs/instructions/reporting-api.md` so it preserves the approved `screenshots` feedback field while continuing to forbid unapproved files and sensitive data.
- 2026-06-14 [VALIDATED] Added CodeGraph bootstrap regression coverage for documented status output without `Project:`; `Scripts/test-codegraph-bootstrap.sh`, `just graph-bootstrap`, `Scripts/pre-flight.sh`, `git diff --check`, and `bash -n Scripts/codegraph-bootstrap.sh Scripts/test-codegraph-bootstrap.sh` passed.
- 2026-06-14 [MERGED] PR `#44` merged as squash commit `0cca853`, and local `main` was fast-forwarded to that commit before this branch.
- 2026-06-13 [MERGED] PR `#45` was merged via squash commit `7cd38d5`, compacting root/scoped agent instructions.
