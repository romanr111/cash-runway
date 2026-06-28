# Continuity Ledger

## Snapshot — Two-tap category detail navigation

Branch: `codex/two-tap-category-detail` @ `09a5190`.
Worktree: `/Users/roman/.codex/worktrees/cash-runway-two-tap-category-detail`.
Goal: Implement Overview category row behavior where the first user tap selects/arms a row and the second tap on the same selected row opens `CategoryDetailOverviewView` for the current month and wallet filter.
Status: implemented, committed locally.

## Notes
- Source work is isolated from the dirty `dev` worktree.
- Changed `Sources/CashRunwayUI/DashboardView.swift` to add route state, row arming state, `navigationDestination`, row tap handling, and context resets.
- Changed `Tests/CashRunwayUITests/TransactionOverviewUITests.swift` to require two taps before category detail drilldown.
- CodeGraph bootstrap initially left a partial `.codegraph` directory without `.codegraph/worktree-root`; removed the generated partial directory, re-ran bootstrap, and synced successfully.

## Validation
- `just build` (iPhone 17 simulator): BUILD SUCCEEDED. Warnings: duplicate `AppHost/uk.lproj/InfoPlist.strings` project reference, signed SQLCipher not stripped, AppIntents metadata skipped.
- `git diff --check`: passed.
- `just graph-sync`: passed after CodeGraph repair.
- Detailed code review: no blocking or important issues found; no code fixes applied during review.

## Skipped gates
- XCUITest run: skipped per repo policy and implementation plan; test source was updated but not executed locally.

## Snapshot — Delete All History + success confirmation + UI polish (uncommitted on `dev`)

Branch: `dev` @ `a07f25f` (audit commit). Work in main checkout, no worktree.
Goal: Add "All History" option (skull icon) to the Delete Transactions sheet, a success confirmation screen after any bulk delete, and UI polish.
Status: implemented, all gates green, uncommitted.

## Changes
- `Sources/CashRunwayCore/DeletePeriod.swift` — added `.allHistory` case (last in `allCases`, renders at bottom of period list).
- `Sources/CashRunwayCore/CashRunwayRepository.swift` — `deletePeriodPredicate` handles `.allHistory` → `1 = 1` (no date scope). Routes through existing plan/summary/delete paths unchanged.
- `Sources/CashRunwayCore/L10n.swift` — `deletedTransactionsMessage(_:)` plural helper for the success card.
- `Sources/CashRunwayUI/DeleteTransactionsView.swift` — `Stage.done` (Equatable); `doneSection` (green checkmark.seal.fill + deleted-count + preserved-subtext + Done button, spring entrance via `.transition(.scale.combined(with: .opacity))` + `.animation(.bouncy, value: stage)`); `performDelete` routes success to `.done` instead of `onDismiss()`; `.allHistory` → `skull.fill` icon + "All History" title + DANGER red pill + denser glyph badge (18% fill + stroke ring + 20pt icon); header subtitle softened to "Choose transactions to remove"; section label "Choose a scope".
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift` — `deleteTransactionsDoneButton`.
- `AppHost/Localizable.xcstrings` — new EN/uk: "All History", "Choose transactions to remove", "Wallets, categories, and recurring templates were preserved.", "Choose a scope", "DANGER".
- `Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift` — 5 new all-history tests (scope, aggregates, recurring preservation, planStale, empty noop); updated `periodIdentityAndButtonTitleAreStable` for new `allCases` order (allHistory last).

## Decisions
- All-History row placed **last** (below This Year) — least-destructive options first.
- DANGER red pill on All History row as the screen's signature detail.
- Aggregate reversal: row-by-row via existing `applyContribution` loop (consistency over a fast-path drop/rebuild). Acceptable for a rare destructive op.
- Tombstones excluded (`is_deleted = 0` in predicate, unchanged).
- Recurring **templates** preserved; `recurring_instances.linked_transaction_id` nulled; `bank_transaction_imports.cash_runway_transaction_id` nulled.
- Success state applies to ALL delete options (Today/Month/Year/All History), not just All History. Refresh-failure path (`deletionCompleted` notice) unchanged.
- No `Spacer` pin-to-bottom in doneSection (collapses in ScrollView); inline Done button retained.

## Validation
- `swift build --target CashRunwayCore`: passed
- `just test-filter BulkDeleteTransactionsTests`: 36/36 passed
- `swiftlint --strict` (changed files): 0 violations
- `just build` (iPhone 17 sim): BUILD SUCCEEDED

## Skipped gates
- Interactive sheet navigation (open → select All History → type DELETE → success card → Done): manual gate, not exercised locally (XCUITest disallowed per AGENTS.md).

## Open / follow-ups
- Performance: row-by-row aggregate reversal for very large histories. Monitor; optimize to drop/rebuild aggregate tables only if reported slow.

---

## Snapshot — Bulk delete transactions feature (More → Data)

Branch: `codex/bulk-delete-transactions` (merged via PR #75, squash commit `dd941fe`)
Worktree: `~/.codex/worktrees/cash-runway-bulk-delete-transactions`
Base: `dev` @ d903f61
Status: MERGED into `dev`. All local gates passed at merge time (see PR #75 validation section).

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

## Validation (at PR #75 merge)
- SwiftPM build (Core + UI): passed
- `just check-integration`: 380/380 passed (2 pre-existing known issues in `CSVIdempotencyTests`)
- `just test-filter BulkDeleteTransactionsTests`: 26/26 passed
- `swiftlint --strict`: 0 violations
- `just build` (iPhone 17 simulator): BUILD SUCCEEDED
- `Scripts/pre-flight.sh`: CashRunwayCore wiring OK

## Skipped gates
- True SwiftUI `.task(id:)` race cannot be unit-tested from SwiftPM because
  `CashRunwayUI` is an Xcode-only target; XCUITest changes are out of scope per
  AGENTS.md. The invariant is covered at the plan level and enforced in the view.
- Interactive UI navigation to the new sheet remains a recommended manual gate.

## Open / follow-ups
- Dangling half-transfer when only one half of a transfer is in a deleted period
  (accepted per decision). Future: consider demoting the orphan half.

## Freshness check (verify before next session)
- [ ] `git status --short` is clean.
- [ ] `CashRunway.xcodeproj/project.pbxproj.bak` is not in the index or worktree.
- [ ] Validation counts reflect the latest test run.

## Note
- The `origin/dev` ledger snapshots for `codex/wallet-selection-transaction-editor`
  and `codex/custom-wallet-categories` belong to separate worktrees and are
  intentionally not duplicated here.

---

## Previous session: Architecture audit (read-only investigation)

Branch: `dev` @ `fed7859` (no worktree — investigated in main checkout)
Goal: Deep architecture audit of Cash Runway; produce a modernization plan covering maintainability, security/privacy, performance, and future LLM-agent integration. No code changes.

## Status
- Complete. Deliverable saved to `docs/ARCHITECTURE_AUDIT.md`.
- Static review only; no tests run (investigative task per instructions).
- Self-review performed against a 9-point review checklist; 2 factual errors + several nuances corrected in place.

## Deliverable
- `docs/ARCHITECTURE_AUDIT.md` — full report (Executive Summary, Current Architecture, Maintainability/Security/Performance findings tables, LLM-Agent Integration Architecture, Proposed Target Architecture, 6-phase Roadmap, Open Questions, Appendix).

## Key findings (top risks)
1. God repository — `Sources/CashRunwayCore/CashRunwayRepository.swift` (4,029 lines): DAO + bank sync + resolver + backup + recurring + aggregates in one `@unchecked Sendable` class.
2. Empty `AppHost/CashRunway.entitlements` (`<dict/>`) — no `com.apple.developer.default-data-protection` capability; DB file lacks iOS file-level protection (SQLCipher passphrase only).
3. `bank_transaction_imports.raw_json` stores full Monobank JSON indefinitely (no TTL/redaction). Not exported in JSON backups, but maximizes local PII surface.
4. `NSLog` calls in DEBUG-gated UI code (`Editors.swift:624`, `FeedbackReportScreenshotPicker.swift:164`) — not shipping, but violates AGENTS.md logging convention; cleanup item.
5. God view model — `Sources/CashRunwayUI/AppModel.swift` (1,045 lines) holds `repository`, `csvService`, `backupService`, `bankTokenStore`; direct persistence coupling.

## Notable facts verified
- The `Modules/CashRunwayCorePackage/` mirror described in the task brief **does not exist** on `dev` or the `codex/dedup-core` worktree. Single source tree at `Sources/CashRunwayCore/` (enforced by `Scripts/check-core-module-wiring.sh`).
- Migration `v3_bank_sync` is registered AFTER `v4_import_job_source_format_id` (names are identifiers, not sort keys — GRDB runs in registration order). **Must not be renamed** — GRDB tracks by identifier; renaming would break existing DBs.
- `bank_transaction_imports` is NOT included in `exportFullBackup` (verified in `insertBackupSourceData`).
- DEBUG recovery paths are correctly `#if DEBUG`-gated; `allowsDestructiveRecovery` is `FatalError` in release.

## Recommendations (prioritized)
- P0: Split god repository into focused internal services (BankSync → Recurring → Aggregates → Backup → DAOs), file/type-level first; keep `CashRunwayRepository` as a compatibility facade.
- P0: Add `com.apple.developer.default-data-protection` entitlement + `NSFileProtectionComplete`/`completeUnlessOpen` via a `FileProtectionService`; validate on real device.
- P0: Redact + TTL-purge `bank_transaction_imports.raw_json`; add `raw_json_expires_at` + purge job in `runMaintenance`.
- P1: Do not rename migrations; add a `MigrationIntegrityTests` assertion that the identifier set is stable.
- P1: Clean up DEBUG `NSLog`; add CI grep check preventing ungated `print`/`NSLog`.
- P1: Split `Editors.swift` (2,266 lines) and `DashboardView.swift` (1,658 lines) into per-view files.
- P2: Introduce `protocol CashRunwayRepositorying`; UI depends on protocol.
- P2: Keep `DatabaseQueue` (not `DatabasePool`) unless read contention is measured.
- Phase 5: LLM-agent access as local-first in-app `AgentAccessService` (consent-gated, read-only by default, redacted DTOs, audit log, short-lived sessions, immediate revocation). Reject direct DB access and localhost HTTP.

## Open questions for product/security
1. Data Protection class: `complete` (safer, blocks BG tasks when locked) vs `completeUnlessOpen`?
2. `raw_json` retention: N days for reprocessing, or drop after linking?
3. Database key rotation: support on user request?
4. Backup encryption: passphrase-encrypt exports?
5. Agent LLM host: on-device vs user-approved remote?
6. Budgets feature: remove frozen code/tables, or keep?

## Areas not inspected
- `Theme.swift`, `TransactionsView.swift`, `BudgetsView.swift`, coordinator files (listed/grepped only).
- `reporting-api/` Node backend, `sidestore/`, `DesignReferences/`, `docs/` content.
- `.swiftlint.yml` rules; `XLSXConverter`, `MCCategoryMapping`, `BankCategoryNameMapping`, `L10n`, `DateKeys`, `Money` internals.
- `CashRunway.xcodeproj/project.pbxproj` (not hand-edited per AGENTS.md).
- Nightly/release workflows beyond confirming existence.

## Earlier previous session
- `codex/custom-wallet-categories` (PR #79) — implementation complete; ledger snapshot moved to `dev`.
