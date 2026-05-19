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

- Goal: Optimize `TransactionFlowUITests` runtime in CI (currently ~8 min / ~476s).
- Success criteria: Transaction shard runs significantly faster in CI without flakiness; build passes; all 14 UI tests pass.
- Current state: PR `#20` branch `feat/ui-test-class-level-launch` has class-level app launch (14→6 launches), global animation disable, timeout reduction 5s→3s, build-once CI artifact sharing, scroll-to-top in returnToRoot(), and reverted typeText→setValue attempt. All 14 UI tests pass locally. Latest commit `3b20c57` pushed to PR branch.
- Next action: Monitor CI run on PR #20 for shard timing comparison against baseline.
- Open questions: Whether the combined optimizations bring Monobank shard from ~15m to under ~7m and Transactions shard from ~8m to under ~5m.
- Merge status: merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `feat/ui-test-class-level-launch`
- Base branch: `origin/main`
- Merge status: not-merged

## Working set

- `Sources/CashRunwayUI/RootView.swift`
- `Tests/CashRunwayUITests/CashRunwayUITestCase.swift`
- `Tests/CashRunwayUITests/TransactionCRUDUITests.swift`
- `Tests/CashRunwayUITests/TransactionOverviewUITests.swift`
- `Tests/CashRunwayUITests/MonobankConnectionUITests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-19 [CODE] Added `.transaction { transaction.animation = nil }` to `CashRunwayRootView.body` when `CASH_RUNWAY_UI_TEST_MODE == "1"`, disabling all SwiftUI animations globally for UI tests.
- 2026-05-19 [CODE] Reduced `waitForExistence(timeout: 5)` → `timeout: 3` and `waitForNonExistence(timeout: 5)` → `timeout: 3` across all UI test files (TransactionCRUD, TransactionOverview, MonobankConnection, and base CashRunwayUITestCase).
- 2026-05-19 [CHECK] `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` passed with `** BUILD SUCCEEDED **`.
- 2026-05-19 [CODE] PR `#20` implemented class-level `XCUIApplication` reuse via `launchSharedApp()` + `prepareSharedApp()` + `returnToRoot()`, reducing app launches from 14 → 6 and tightening common navigation timeouts 5s → 3s.
- 2026-05-19 [DECISION] `testTransferRequiresDestinationWalletAndDoesNotExposeCategories` retained per-test `launchApp()` because accumulated `ScrollView` offset breaks FAB hittability on shared app reuse.

## Receipts

- 2026-05-19 [TOOL] Build passed after animation-disable and timeout-reduction changes.
