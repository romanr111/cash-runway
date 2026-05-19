<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true true.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Move coverage and E2E UI tests to a nightly workflow; optimize E2E text entry and test flows.
- Success criteria: PR pipeline runs only fast checks; nightly workflow runs coverage + E2E; text entry is faster with fallback safety; all tests pass.
- Current state: PR `#22` merged to `main`. Nightly workflow (`ios-nightly.yml`) runs at 03:00 UTC with optional manual dispatch. PR pipeline (`ios-ci.yml`) trimmed to static-analysis → unit-tests → integration-tests. `fastEnterText` helper added with KVC `setValue` + verification fallback. UIKit animations disabled in test mode. SPM package caching added. Branches and remotes cleaned up.
- Next action: Monitor first nightly run for timing and `fastEnterText` fallback rate.
- Open questions: None.
- Merge status: merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- Base branch: `origin/main`
- Merge status: merged

## Working set

- `.github/workflows/ios-nightly.yml`
- `.github/workflows/ios-ci.yml`
- `AppHost/CashRunwayApp.swift`
- `Tests/CashRunwayUITests/CashRunwayUITestCase.swift`
- `Tests/CashRunwayUITests/TransactionCRUDUITests.swift`
- `Tests/CashRunwayUITests/TransactionOverviewUITests.swift`
- `Tests/CashRunwayUITests/MonobankConnectionUITests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-19 [MERGE] PR `#22` (`feat/nightly-ci-e2e-optimizations`) merged and pushed. Branch deleted locally and remotely.
- 2026-05-19 [CLEANUP] PR `#20` branch `feat/ui-test-class-level-launch` deleted locally and remotely.
- 2026-05-19 [CODE] Added `ios-nightly.yml`: scheduled + `workflow_dispatch` with `run_coverage` / `run_e2e` booleans.
- 2026-05-19 [CODE] Trimmed `ios-ci.yml`: removed coverage, build-e2e, and E2E test jobs.
- 2026-05-19 [CODE] Added `fastEnterText` to `XCUIElement`: KVC `setValue` with verification and `clearAndEnterText` fallback.
- 2026-05-19 [CODE] Added local FAB fallback in `openAddTransaction()` when exists but not hittable.
- 2026-05-19 [CODE] Refactored slow transaction tests: removed redundant waits, explicit cleanup, and scroll-to-save.
- 2026-05-19 [CODE] Disabled UIKit animations in test mode via `UIView.setAnimationsEnabled(false)`.
- 2026-05-19 [CODE] Added conservative SPM package caching (`~/.swiftpm/cache`) to CI workflows.
- 2026-05-19 [CHECK] `swift test` passed (unit + integration). `xcodebuild clean build` and `build-for-testing` succeeded.

## Receipts

- 2026-05-19 [PR] `#22` — ci+e2e: nightly workflow, fast text entry, UIKit animation disable
- 2026-05-19 [COMMIT] `1aebf87` on `feat/nightly-ci-e2e-optimizations`
