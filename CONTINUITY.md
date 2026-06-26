# Continuity Ledger

## Snapshot — Bulk delete transactions feature (More → Data)

Branch: `codex/bulk-delete-transactions`
Worktree: `~/.codex/worktrees/cash-runway-bulk-delete-transactions`
Base: `dev` @ 26c4de4
Status: implemented, merged with current `dev`, local gates green, pushed to remote, awaiting reviewer approval/merge.

## Feature
Adds "Delete Transactions" to the More/Ще → Data section. User picks a period
(This Day / This Month / This Year), sees live counts + total affected, then a
4-step destructive flow: open sheet → select period → backup prompt (routes to
existing Export Full Backup on "Back up") → type DELETE/ВИДАЛИТИ to enable the
red CTA. Hard-deletes all transaction rows in the period regardless of source
(manual/Monobank/CSV/recurring instances); recurring TEMPLATES preserved.
Transfers: only the in-period half is removed.

## Decisions (locked with user)
- Transfer pairs: delete only in-period half.
- Confirmation depth: 4 steps incl. type-DELETE; live counters on period rows.
- Backup: not automatic; mid-flow prompt offers route to Export Full Backup.
- Scope: all sources; recurring instances deleted, templates preserved.

## Changed files
- Sources/CashRunwayCore/DeletePeriod.swift (NEW) — `DeletePeriod`, `TransactionDeletionPlan`, `TransactionDeletionError.planStale`, `TransactionDeletionResult`
- Sources/CashRunwayCore/Collection+Chunked.swift (NEW) — chunked delete helper for SQLite variable limit
- Sources/CashRunwayCore/CashRunwayRepository.swift — `transactionDeletionSummary(for:)` (SQL aggregates), `transactionDeletionPlan(for:)` (frozen IDs), `deleteTransactions(_ plan:)` (recomputes IDs, aborts on set change, deletes exact IDs), chunked cascade delete
- Sources/CashRunwayCore/L10n.swift — `deleteTransactionsButtonTitle(_:)` plural helper
- Sources/CashRunwayUI/AppModel.swift — async `transactionDeletionSummary(for:)`, `transactionDeletionPlan(for:)`, `deleteTransactions(plan:)` (awaits refresh, returns `TransactionDeletionResult`)
- Sources/CashRunwayUI/DeleteTransactionsView.swift — async summary loading, period selection, impact card, confirmation field, delete CTA
- Sources/CashRunwayUI/AccessibilityIdentifiers.swift — sheet/row/continue/confirm identifiers
- Sources/CashRunwayUI/SettingsView.swift — "Delete Transactions" row and sheet presentation
- AppHost/Localizable.xcstrings — new EN/uk strings for delete flow and stale-plan error
- CashRunway.xcodeproj/project.pbxproj — added `DeleteTransactionsView.swift` to UI group and app target
- Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift — 28 tests incl. frozen-scope, tombstone, chunking, identity, period-mismatch, and aggregate-summary guards

## Review-driven fixes
- P2 refresh reporting: `deleteTransactions(plan:)` now awaits `reloadAll()` and returns a structured `TransactionDeletionResult` so the UI can distinguish "delete succeeded, refresh failed" from complete success, and the sheet only dismisses after refresh succeeds.
- P2/P3 summary loading: `transactionDeletionSummary(for:)` uses SQL `COUNT`/`SUM` aggregates (no row materialization) and `DeleteTransactionsView` loads summaries asynchronously with `isLoadingSummaries` gating the Continue button.
- P1 scope race: preview creates an immutable `TransactionDeletionPlan` that
  freezes the reference day/month/year keys and the exact transaction UUIDs.
  Execution recomputes the matching set from the frozen keys and throws
  `TransactionDeletionError.planStale` if the ID set changed.
- P1 out-of-order plan loading race: `DeleteTransactionsView` tags each plan
  request with a `planRequestID`, and accepts a result only when the task is not
  cancelled, the request ID is still current, `selectedPeriod` is unchanged,
  and `plan.period == selectedPeriod`. `hasSelectedTransactions` and
  `performDelete()` independently enforce the period invariant.
- Cancellation propagation: `CashRunwayAppModel.transactionDeletionPlan(for:)`
  wraps the detached plan task in `withTaskCancellationHandler` so caller
  cancellation cancels the detached work, and `CancellationError` is swallowed
  rather than surfaced as a user-facing error.
- P2 tombstone corruption: `deletePeriodPredicate` includes `is_deleted = 0` so
  summary, plan, and execution ignore tombstoned rows; aggregate reversal
  therefore cannot be skewed by pre-deleted rows.
- Sheet dismissal: `.interactiveDismissDisabled(isDeleting)` prevents swipe-to-
  dismiss while deletion runs.
- UI polish: theme-token spacing, distinct accessibility identifiers, impact
  card transition, consolidated destructive messaging.

## Validation
- `swift build --target CashRunwayCore` — passed
- `just test-filter BulkDeleteTransactionsTests` — passed, 28/28
- `just build` (iPhone 17 simulator) — passed, BUILD SUCCEEDED
- `just lint` — passed, 0 violations

## Skipped gates
- True SwiftUI `.task(id:)` race cannot be unit-tested from SwiftPM because
  `CashRunwayUI` is an Xcode-only target; XCUITest changes are out of scope per
  AGENTS.md. The invariant is covered at the plan level and enforced in the view.
- Interactive UI navigation to the new sheet remains a recommended manual gate.

## Open / follow-ups
- Dangling half-transfer when only one half of a transfer is in a deleted period
  (accepted per decision). Future: consider demoting the orphan half.
- Untracked `CashRunway.xcodeproj/project.pbxproj.bak` remains from an earlier
  backup step; clean up before final PR merge.

## Note
- The `origin/dev` ledger snapshot for `codex/wallet-selection-transaction-editor`
  belongs to a separate worktree and is intentionally not duplicated here.
