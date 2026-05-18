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

- Goal: Add a minimal CI coverage report for Cash Runway core tests.
- Success criteria: GitHub Actions has a dedicated `Coverage` job after integration tests, running in parallel with E2E and publishing a readable summary plus artifacts without enforcing a threshold.
- Current state: Branch `codex/ci-coverage-report` added and locally validated a SwiftPM coverage job in `.github/workflows/ios-ci.yml`.
- Next action: Open a PR so GitHub Actions can publish the first coverage baseline.
- Open questions: None.
- Merge status: merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `codex/ci-coverage-report`
- Base branch: `origin/main`

## Working set

- `.github/workflows/ios-ci.yml`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-18 [REVIEW] Self-review of PR `#13` found no blockers; local validation had already passed and live checks had `Static Analysis` and `Unit Tests` passing when the user asked not to wait for the full pipeline.
- 2026-05-18 [TOOL] Squash-merged PR `#13` into `main` as `20d587f`.
- 2026-05-18 [TOOL] Removed `/Users/roman/.codex/worktrees/cash-runway-e2e-ci-optimization` and deleted local branch `codex/e2e-ci-optimization`.
- 2026-05-18 [DECISION] Coverage v1 uses SwiftPM `swift test --enable-code-coverage` against product sources under `Modules/CashRunwayCorePackage/Sources/CashRunwayCore`, not `xcodebuild + xccov`, because the shared Xcode scheme currently drives UI tests.
- 2026-05-18 [CHECK] Local coverage validation passed: `swift test --enable-code-coverage` ran 219 tests, generated `Coverage/coverage-summary.md`, and reported CashRunwayCore line coverage at 89.45%.
- 2026-05-17 [TOOL] Merged PR `#12` for `codex/cash-runway-lint-fix` into `main`, deleted its local/remote branches, and removed `/Users/roman/.codex/worktrees/cash-runway-lint-fix`.

## Receipts

- 2026-05-18 [TOOL] `git fetch --prune origin` moved `origin/main` from `cd8a309` to `20d587f` and pruned `origin/codex/e2e-ci-optimization`.
- 2026-05-18 [TOOL] `git merge --ff-only origin/main` fast-forwarded the primary checkout to `20d587f` after stashing the prior local `CONTINUITY.md` cleanup note.
- 2026-05-17 [TOOL] `xcodebuild -help` confirmed support for `-test-timeouts-enabled`, `-default-test-execution-time-allowance`, `-maximum-test-execution-time-allowance`, `build-for-testing`, and `test-without-building`.
- 2026-05-17 [TOOL] `gh api repos/romanr111/cash-runway/branches/main/protection` returned `Branch not protected`, so removing the exact `iOS App Build` check name should not block branch protection.
- 2026-05-17 [TOOL] Local `swiftlint` executable was not installed, so local SwiftLint validation was skipped; GitHub Actions will run repository lint.
- 2026-05-17 [TOOL] `swift test` emitted existing GRDB Sendable warnings while compiling vendored code.
