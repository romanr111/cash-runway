<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true now.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Finish the first-launch data behavior change and publish it as a PR into `origin/main`.
- Success criteria: Fresh first launch no longer creates fake starter wallets/budgets/transactions, fixture and UI-test paths seed their own test data, validation passes, and a PR is open against `origin/main`.
- Current state: The `codex/stop-fake-data` worktree was being rebased onto `origin/main` with conflicts resolved toward current-main continuity and explicit fixture seeding.
- Next action: Continue the rebase, run validation, then push and open the PR.
- Open questions: None.
- Merge status: not-merged.
- Worktree reason: isolated-feature.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data`
- Branch: `codex/stop-fake-data`
- Base branch: `origin/main`

## Working set

- `AppHost/UITestRuntime.swift`
- `Sources/CashRunwayCore/**`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/**`
- `Sources/CashRunwayUI/**`
- `Tests/CashRunwayCoreTests/**`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-17 [TOOL] Started from the preserved clean worktree `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data` on `codex/stop-fake-data`.
- 2026-05-17 [TOOL] Confirmed no open GitHub PR existed for the branch before publishing.
- 2026-05-17 [CODE] Rebased the feature branch onto current `origin/main` and resolved first-pass conflicts in `CONTINUITY.md` and `CSVEdgeCaseTests.swift`.
- 2026-05-15 [CODE] Changed `seedIfNeeded()` so fresh databases create default categories only; fake starter wallets, budgets, and transactions are no longer created on first launch.
- 2026-05-15 [CODE] Updated fixture, UI-test, and unit-test setup paths to seed wallets explicitly when tests need transaction-capable data.
- 2026-05-15 [CODE] Added zero-wallet UI guards and empty states so first launch remains usable without fake data.

## Receipts

- 2026-05-17 [TOOL] `git worktree list` showed primary checkout plus `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data`.
- 2026-05-17 [TOOL] `gh auth status` confirmed GitHub CLI authentication for `romanr111`.
- 2026-05-17 [TOOL] `git rebase origin/main` stopped on `CONTINUITY.md` and `Tests/CashRunwayCoreTests/CSVEdgeCaseTests.swift`; conflicts were resolved manually.
- 2026-05-17 [CODE] Decision: preserve current-main concise continuity format and discard stale legacy ledger blocks during conflict resolution.
