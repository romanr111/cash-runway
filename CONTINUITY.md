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

- Goal: Keep Cash Runway repo state clear and current in the primary checkout.
- Success criteria: `CONTINUITY.md` reflects live Git state and preserves only current decisions and receipts.
- Current state: PR `#13` was squash-merged into `origin/main`, and the local `codex/e2e-ci-optimization` worktree and branch were cleaned up.
- Next action: Record any new repo changes here before editing files again.
- Open questions: None.
- Merge status: merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- Base branch: `origin/main`

## Working set

- `CONTINUITY.md`

## Done (recent)

- 2026-05-18 [REVIEW] Self-review of PR `#13` found no blockers; local validation had already passed and live checks had `Static Analysis` and `Unit Tests` passing when the user asked not to wait for the full pipeline.
- 2026-05-18 [TOOL] Squash-merged PR `#13` into `main` as `20d587f`.
- 2026-05-18 [TOOL] Removed `/Users/roman/.codex/worktrees/cash-runway-e2e-ci-optimization` and deleted local branch `codex/e2e-ci-optimization`.
- 2026-05-17 [TOOL] Merged PR `#12` for `codex/cash-runway-lint-fix` into `main`, deleted its local/remote branches, and removed `/Users/roman/.codex/worktrees/cash-runway-lint-fix`.

## Receipts

- 2026-05-18 [TOOL] `git fetch --prune origin` moved `origin/main` from `cd8a309` to `20d587f` and pruned `origin/codex/e2e-ci-optimization`.
- 2026-05-18 [TOOL] `git merge --ff-only origin/main` fast-forwarded the primary checkout to `20d587f` after stashing the prior local `CONTINUITY.md` cleanup note.
- 2026-05-17 [TOOL] `xcodebuild -help` confirmed support for `-test-timeouts-enabled`, `-default-test-execution-time-allowance`, `-maximum-test-execution-time-allowance`, `build-for-testing`, and `test-without-building`.
- 2026-05-17 [TOOL] `gh api repos/romanr111/cash-runway/branches/main/protection` returned `Branch not protected`, so removing the exact `iOS App Build` check name should not block branch protection.
- 2026-05-17 [TOOL] Local `swiftlint` executable was not installed, so local SwiftLint validation was skipped; GitHub Actions will run repository lint.
- 2026-05-17 [TOOL] `swift test` emitted existing GRDB Sendable warnings while compiling vendored code.
