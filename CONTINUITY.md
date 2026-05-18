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

- Goal: Fix the post-PR `#13` E2E Overview wallet-filter failure without broad UI-test churn.
- Success criteria: CI no longer leaves all-wallet transaction rows visible after selecting the Savings wallet, and local non-UI validation passes.
- Current state: The stale async filter fix passed local non-UI validation and was ready for PR publication.
- Next action: Push the branch and open a PR for CI E2E verification.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-e2e-overview-wallet-filter-fix`
- Branch: `codex/e2e-overview-wallet-filter-fix`
- Base branch: `origin/main`

## Working set

- `CONTINUITY.md`
- `Sources/CashRunwayUI/AppModel.swift`
- `Sources/CashRunwayUI/DashboardView.swift`
- `Tests/CashRunwayUITests/CashRunwayUITestCase.swift`

## Done (recent)

- 2026-05-18 [TOOL] Downloaded failed E2E artifacts for run `26002715288` to `/tmp/cash-runway-e2e-26002715288`.
- 2026-05-18 [DECISION] Root cause was scoped to stale `reloadAll()` results: the CI log showed the `timeline.wallet.savings` option was tapped, but old all-wallet rows remained visible.
- 2026-05-18 [CODE] Added a stale-scope guard to `reloadAll()`, routed Dashboard wallet menu actions through `selectWallet(_:)`, and made UI-test menu selection prefer stable wallet option identifiers.
- 2026-05-18 [TOOL] `git diff --check` passed.
- 2026-05-18 [TOOL] `swift test --filter '(ModelSerializationTests|UtilityAndModelTests|BankCategoryMapperTests|BankSyncServiceTests)'` passed with 38 tests in 4 suites.
- 2026-05-18 [TOOL] `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` passed with `** BUILD SUCCEEDED **`.
- 2026-05-18 [TOOL] Simulator launch smoke check installed and launched `dev.roman.cashrunway` on iPhone 17 as PID `89158`.
- 2026-05-18 [REVIEW] Self-review of PR `#13` found no blockers; local validation had already passed and live checks had `Static Analysis` and `Unit Tests` passing when the user asked not to wait for the full pipeline.
- 2026-05-18 [TOOL] Squash-merged PR `#13` into `main` as `20d587f`.
- 2026-05-18 [TOOL] Removed `/Users/roman/.codex/worktrees/cash-runway-e2e-ci-optimization` and deleted local branch `codex/e2e-ci-optimization`.
- 2026-05-17 [TOOL] Merged PR `#12` for `codex/cash-runway-lint-fix` into `main`, deleted its local/remote branches, and removed `/Users/roman/.codex/worktrees/cash-runway-lint-fix`.

## Receipts

- 2026-05-18 [TOOL] `git fetch --prune origin` moved `origin/main` from `cd8a309` to `20d587f` and pruned `origin/codex/e2e-ci-optimization`.
- 2026-05-18 [TOOL] `git merge --ff-only origin/main` fast-forwarded the primary checkout to `20d587f` after stashing the prior local `CONTINUITY.md` cleanup note.
- 2026-05-18 [FAILURE] Run `26002715288`, job `76429296272`, failed `OverviewFlowUITests.testSearchAndWalletFilterCanBeClearedWithoutLosingFeedState` at `TransactionOverviewUITests.swift:28`.
- 2026-05-17 [TOOL] `xcodebuild -help` confirmed support for `-test-timeouts-enabled`, `-default-test-execution-time-allowance`, `-maximum-test-execution-time-allowance`, `build-for-testing`, and `test-without-building`.
- 2026-05-17 [TOOL] `gh api repos/romanr111/cash-runway/branches/main/protection` returned `Branch not protected`, so removing the exact `iOS App Build` check name should not block branch protection.
- 2026-05-17 [TOOL] Local `swiftlint` executable was not installed, so local SwiftLint validation was skipped; GitHub Actions will run repository lint.
- 2026-05-17 [TOOL] `swift test` emitted existing GRDB Sendable warnings while compiling vendored code.
