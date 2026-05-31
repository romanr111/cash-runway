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

- Goal: Implement the broader Warm Functional Ledger UI refresh for Cash Runway in an isolated worktree.
- Success criteria: More/Settings, supporting management sheets, editors, transaction-adjacent surfaces, and import/backup/Monobank flows follow the refreshed UI language while preserving behavior, accessibility identifiers, data models, disabled/deprecated feature policy, and required iOS validation gates.
- Current state: Detailed code review found and fixed an important transaction-row note visibility regression; all required local validation passed after the fix.
- Next action: Commit and push the review fix to draft PR #23.
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
