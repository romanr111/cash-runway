# Continuity Ledger

## Snapshot — Bulk delete transactions feature (More → Data)

Branch: `codex/bulk-delete-transactions`
Worktree: `~/.codex/worktrees/cash-runway-bulk-delete-transactions`
Base: `dev` @ 3f85ec0
Status: implemented, local gates green, not committed/pushed.

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
- Sources/CashRunwayCore/DeletePeriod.swift (NEW) — enum + TransactionDeletionSummary
- Sources/CashRunwayCore/CashRunwayRepository.swift — transactionDeletionSummary(for:), deleteTransactions(for:), private deletePeriodPredicate
- Sources/CashRunwayCore/L10n.swift — deleteTransactionsButtonTitle(_:) plural helper
- Sources/CashRunwayUI/AppModel.swift — transactionDeletionSummary(for:), deleteTransactions(for:) wrappers
- Sources/CashRunwayUI/DeleteTransactionsView.swift (NEW) — destructive sheet (4-step flow)
- Sources/CashRunwayUI/SettingsView.swift — row in Data section + sheet wiring (routes backup→isBackupExportWarningPresented)
- Sources/CashRunwayUI/AccessibilityIdentifiers.swift — settings.deleteTransactions.row + sheet IDs
- AppHost/Localizable.xcstrings — 14 new EN/uk keys via Scripts/localize-xcstrings.py
- CashRunway.xcodeproj/project.pbxproj — registered DeleteTransactionsView.swift (backup at .bak)
- Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift (NEW) — 7 tests

## Validation
- swift build (SwiftPM, Core+UI): Build complete
- just check-unit-parallel: EXIT 0, no failures
- just test-filter BulkDeleteTransactionsTests: 7/7 passed
- swiftlint --strict (touched files): 0 violations
- just build (iPhone 17 sim): BUILD SUCCEEDED
- Launch smoke (simctl install+launch dev.roman.cashrunway): app alive, PID running, no crash

## Skipped gates (report)
- Interactive UI navigation to the new sheet (More→Data→Delete Transactions→
  type DELETE): NOT run. No MCP Xcode tools in session; XCUITest disallowed
  locally by AGENTS; simctl has no tap API. Manual gate for the reviewer.
- Screenshot taken (/tmp/cr-home.png) but model cannot read images; visual
  confirmation deferred to reviewer.
- just check (full CI gate incl. integration/perf): not run; additive change,
  unit gate + sim build used. Run before push if desired.

## Open / follow-ups
- Dangling half-transfer when only one half of a transfer is in a deleted
  period (accepted per decision). Future: consider demoting the orphan half.
- CONTINUITY.md on dev still has a stale merge-conflict marker from a prior
  session (pre-existing, not touched here).
