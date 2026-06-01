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

- Goal: Fix the broken Timeline Overview Categories donut on draft PR #23.
- Success criteria: Donut uses valid absolute category totals, renders centered and prominent, supports in-place category selection, keeps mirrored core in sync, and passes focused tests, full unit tests, simulator build, and boot smoke.
- Current state: Follow-up review fixes added visible donut category badges and deterministic collapsed-list selection on `codex/broader-ui-refresh`; validation and seeded real-data smoke passed.
- Next action: Commit and push the donut fix to PR #23 or request final adjustments.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-broader-ui-refresh`
- Branch: `codex/broader-ui-refresh`
- Base branch: `origin/main`
- Worktree reason: isolated-feature
- Merge status: not-merged

## Working set

- `Sources/CashRunwayUI/Theme.swift`
- `Sources/CashRunwayUI/SettingsView.swift`
- `Sources/CashRunwayUI/Editors.swift`
- `Sources/CashRunwayUI/TransactionsView.swift`
- `Sources/CashRunwayUI/DashboardView.swift`
- `Sources/CashRunwayCore/Models.swift`
- `Sources/CashRunwayCore/CSVSupport.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/Models.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CSVSupport.swift`
- `Tests/CashRunwayCoreTests/CashRunwayCoreTests.swift`
- `Tests/CashRunwayCoreTests/OverviewCategoryDistributionTests.swift`
- `Tests/CashRunwayCoreTests/UtilityAndModelTests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-31 [SETUP] Created isolated worktree `/Users/roman/.codex/worktrees/cash-runway-broader-ui-refresh` on branch `codex/broader-ui-refresh`.
- 2026-05-31 [PLAN] Broader UI refresh plan approved: Warm Functional Ledger, More + sheets first, preserve behavior and data interfaces.
- 2026-05-31 [CHECK] Requested overview worktree/branch were missing; decided to combine by implementing Overview/Categories changes directly in `codex/broader-ui-refresh`.
- 2026-05-31 [IMPLEMENTED] Refreshed shared theme tokens, Overview/Categories, category glyphs/catalog, More, management sheets, editors, transaction rows/details, and import/backup/Monobank presentation while preserving data interfaces.
- 2026-05-31 [TEST] Added focused core coverage for refined default category appearances and contextual CSV import category styling.
- 2026-05-31 [VALIDATED] `diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore`, `git diff --check`, `swift test`, and required iPhone 17 simulator clean build passed.
- 2026-05-31 [SMOKE] Booted the app on iPhone 17 simulator and opened Timeline, Overview, category drill-down, More, Categories add/edit/save, Labels, Wallets, Scheduled Transactions, Monobank, Transaction Details, and Add Transaction without crash.
- 2026-05-31 [REVIEW] Fixed major review findings: removed nested category row buttons, removed visible direct wallet deletion from management rows, and aligned CSV Food & Drink import color with the controlled palette in both mirrored core trees.
- 2026-05-31 [REVALIDATED] Focused appearance tests, `diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore`, `git diff --check`, full `swift test`, required iPhone 17 clean build, and review smoke passed.
- 2026-05-31 [PUBLISHED] Committed, pushed, and opened draft PR #23 for the combined UI refresh.
- 2026-05-31 [IMPLEMENTED] Consolidated transaction details/edit-delete flow into direct `Edit Transaction`: row taps open the editor, delete lives in the editor with confirmation, and the old details view was removed from active UI code.
- 2026-05-31 [TEST] Updated transaction UI test source expectations for direct edit flow and added delete-from-editor coverage; local UI/E2E execution remains intentionally skipped per policy.
- 2026-05-31 [VALIDATED] Direct edit/delete follow-up passed targeted delete invariant test, full `swift test`, required iPhone 17 clean build, UI test build-for-testing compile, and simulator smoke.
- 2026-05-31 [REVIEW] Detailed self-review found an important row UX/accessibility regression where refreshed transaction rows hid manual notes; fixed `TransactionRow` metadata and accessibility summary to include notes again.
- 2026-05-31 [VALIDATED] Post-review `diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore`, `git diff --check`, and full `swift test` passed after the row-note fix.
- 2026-05-31 [VALIDATED] Post-review iPhone 17 clean build passed, simulator boot smoke opened Timeline and direct Edit Transaction, row accessibility labels included notes, and log scan found no crash/error/warning matches.
- 2026-06-01 [SETUP] Corrected active worktree branch from `benchmarks-for-pr25` back to PR #23 branch `codex/broader-ui-refresh`; temporary wrong-branch stash was dropped after porting the fix.
- 2026-06-01 [IMPLEMENTED] Added mirrored `OverviewCategoryDistributionLayout` normalization and replaced the Overview Categories donut with a fixed-size, centered, selection-based ring using the category list as legend.
- 2026-06-01 [TEST] Added `OverviewCategoryDistributionTests` for absolute expense amounts, zero/invalid filtering, descending sort, full-ring single category, and empty fallback.
- 2026-06-01 [VALIDATED] Focused distribution tests, core mirror diff, diff check, full `swift test`, iPhone 17 build, XcodeBuildMCP simulator launch, empty Overview smoke, seeded real-data Overview smoke, and log scan passed.
- 2026-06-01 [REVIEW] Detailed self-review found missing category badges on the donut and a hidden-row selection gap when the category list was collapsed.
- 2026-06-01 [IMPLEMENTED] Added solid category badges over readable donut segments and moved collapsed selection policy into mirrored core `OverviewCategoryDisplayLayout`.
- 2026-06-01 [VALIDATED] Follow-up focused tests, full `swift test`, mirror diff, diff check, clean iPhone 17 build, seeded real-data smoke, and runtime/os log scan passed.

## Receipts

- 2026-05-31 [DECISION] Use a separate worktree because primary checkout had local edits.
- 2026-05-31 [BUILD] `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -5` ended with `** BUILD SUCCEEDED **`.
- 2026-05-31 [LOG] Review simulator log scan found no crash/error/warning matches.
- 2026-05-31 [COMMIT] `Refresh Cash Runway UI surfaces`.
- 2026-05-31 [PR] Draft PR #23: https://github.com/romanr111/cash-runway/pull/23.
- 2026-05-31 [BUILD] Direct edit/delete follow-up: `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -5` ended with `** BUILD SUCCEEDED **`.
- 2026-05-31 [BUILD] `xcodebuild ... build-for-testing` ended with `** TEST BUILD SUCCEEDED **`.
- 2026-05-31 [LOG] Direct edit/delete simulator log scan found no crash/error/warning matches.
- 2026-05-31 [BUILD] Review fix: required iPhone 17 clean build ended with `** BUILD SUCCEEDED **`.
- 2026-05-31 [LOG] Review fix simulator log scan found no crash/error/warning matches.
- 2026-06-01 [TEST] `swift test --filter OverviewCategoryDistributionTests` passed after first failing because `OverviewCategoryDistributionLayout` did not exist.
- 2026-06-01 [TEST] `swift test` passed with 236 tests in 23 suites.
- 2026-06-01 [BUILD] `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -60` ended with `** BUILD SUCCEEDED **`.
- 2026-06-01 [SMOKE] XcodeBuildMCP `build_run_sim` launched `dev.roman.cashrunway` on iPhone 17, Overview opened, empty-state donut was centered/prominent, and runtime/os log scan found no crash/error/warning matches.
- 2026-06-01 [SMOKE] Relaunched with `CASH_RUNWAY_UI_TEST_MODE=1`, `transaction_core`, reset DB `cash-runway-donut-smoke.sqlite`; May 2026 Overview showed real donut data: Restaurants 54% and Groceries 46%, with matching segment/row accessibility labels and no crash/error/warning log matches.
- 2026-06-01 [TEST] Follow-up `swift test --filter OverviewCategoryDistributionTests` passed with 5 tests after red failure for missing `OverviewCategoryDisplayLayout`.
- 2026-06-01 [TEST] Follow-up `swift test` passed with 238 tests in 23 suites.
- 2026-06-01 [BUILD] Follow-up `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -5` ended with `** BUILD SUCCEEDED **`.
- 2026-06-01 [SMOKE] Follow-up seeded smoke screenshot `/var/folders/y1/44_6v5x1685fclqcclfn375w0000gn/T/screenshot_optimized_09f04fe7-259b-487b-8d67-fb5b6b98a8b3.jpg` showed solid category badges over the real May donut; runtime/os log scan found no crash/error/warning matches.
