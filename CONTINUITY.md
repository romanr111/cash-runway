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

- Goal: Repair the top three token-efficiency audit findings for agent
  instructions.
- Success criteria: Root and scoped instruction files have complete readable
  prose; model/output routing policy is present; continuity reflects this
  branch and current task.
- Current state: The top three audit items were addressed in the isolated
  worktree, and the token-efficiency audit was formalized under `docs/testing/`.
- Next action: Review the final diff and decide whether to commit or adjust.
- Handoff trigger: Rewrite this Snapshot before context compaction, a major task
  switch, or task completion.

## Git Context

- Repo root: `/Users/roman/.codex/worktrees/cash-runway-agent-instructions-top3`
- Branch: `codex/agent-instructions-top3`
- Base: `main` at `eadfa82`
- Primary checkout: `/Users/roman/Documents/Development/Cash Runway`
- Primary checkout local state at branch creation: `D PLAN-SettingsUITests.md`,
  `D PLAN.md`, untracked `PLAN_Optimization.md`, and untracked
  `docs/testing/token-efficiency-audit-2026-06-14.md`.

## Working Set

- `AGENTS.md`
- `agent_docs/instructions/ios.md`
- `agent_docs/instructions/reporting-api.md`
- `agent_docs/instructions/security-privacy.md`
- `agent_docs/instructions/validation.md`
- `agent_docs/instructions/worktrees.md`
- `docs/testing/token-efficiency-audit-2026-06-14.md`
- `CONTINUITY.md`

## Receipts

- 2026-06-14 [DECISION] Used an isolated worktree to avoid modifying unrelated
  local changes in the primary checkout.
- 2026-06-14 [VALIDATED] `Scripts/pre-flight.sh` passed in the isolated worktree;
  mirrored core sources were in sync before edits.
- 2026-06-14 [VALIDATED] `git diff --check`, `just --list`, shell syntax checks
  for repository scripts, and `python3 -m py_compile Scripts/localize-xcstrings.py`
  passed after edits.
- 2026-06-14 [DECISION] Formalized
  `docs/testing/token-efficiency-audit-2026-06-14.md` as a clean durable audit
  note instead of committing the compressed draft verbatim or discarding it.
- 2026-06-13 [MERGED] PR `#45` was merged via squash commit `7cd38d5`, compacting
  root/scoped agent instructions.
- 2026-06-13 [VALIDATED] Core mirror diff, `git diff --check`, focused
  `ReportIssueTests`, full `swift test`, clean iPhone 17 simulator build, and
  seeded simulator smoke passed for the prior PR.
