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
- Sources/CashRunwayCore/DeletePeriod.swift (NEW type) — `TransactionDeletionPlan` + `TransactionDeletionError.planStale`
- Sources/CashRunwayCore/Collection+Chunked.swift (NEW) — chunked delete helper for SQLite variable limit
- Sources/CashRunwayCore/CashRunwayRepository.swift — `transactionDeletionPlan(for:)` (frozen IDs + summary), `deleteTransactions(_ plan:)` (recomputes IDs, aborts on set change, deletes exact IDs), chunked cascade delete
- Sources/CashRunwayCore/L10n.swift — no direct changes; new key added via localize script
- Sources/CashRunwayUI/AppModel.swift — `transactionDeletionPlan(for:)`, `deleteTransactions(plan:)` async wrapper
- Sources/CashRunwayUI/DeleteTransactionsView.swift — captures plan on period selection; impact card + delete CTA use the plan
- AppHost/Localizable.xcstrings — new EN/uk key for stale-plan error
- Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift — 25 tests incl. frozen-scope boundary tests and race-condition staleness tests

## Review-driven fixes (3rd commit)
- P1 scope race: preview now creates an immutable `TransactionDeletionPlan` that
  freezes the reference day/month/year keys and the exact transaction UUIDs.
  Execution recomputes the matching set from the frozen keys and throws
  `TransactionDeletionError.planStale` if the ID set changed, requiring the user
  to review a fresh plan instead of deleting a mutated scope.
- Delete-by-IDs: the write transaction deletes exactly the planned UUIDs in
  SQLite-variable-limit chunks, reverses aggregate contributions per row, and
  cascades to `transaction_labels` / `transaction_search`.
- Boundary tests: day/month/year preview/execute across calendar boundaries
  (June 30 → July 1, Dec 31 → Jan 1) now assert the frozen scope is honored.
- Identity tests: insert/remove/replace (same count/totals, different IDs)
  all abort with `planStale` and delete nothing.
- Chunk test: 901-row plan exercises the chunked delete path.

## Validation
- swift build (SwiftPM, Core+UI): Build complete
- just check-integration: EXIT 0, 379 tests passed (2 pre-existing known issues in CSVIdempotencyTests)
- just test-filter BulkDeleteTransactionsTests: 25/25 passed
- swiftlint --strict (touched files): 0 violations
- just build (iPhone 17 sim): BUILD SUCCEEDED
- Scripts/pre-flight.sh: CashRunwayCore wiring OK; new `Collection+Chunked.swift` is SwiftPM-only

## Skipped gates (report)
- llvm-cov: recipe not present in justfile; bulk-delete paths covered by the
  25 targeted tests including the chunk path.
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
- Untracked `CashRunway.xcodeproj/project.pbxproj.bak` remains from earlier
  backup step; not touched by this fix.
