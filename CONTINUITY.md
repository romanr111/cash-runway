# Continuity Ledger

## Session: Testing roadmap — priority tests 1-5

Branch: `testing-roadmap-priority-tests`
Worktree: `~/.codex/worktrees/cash-runway-testing-roadmap-priority-tests`

## State
- Branch created from `main` (1293825).
- Clean worktree, all 386 tests pass.

## Implemented

### Production changes
1. **DatabaseManager.swift** — Refactored `makeMigrator()` into `allMigrations()` returning `[(String, @Sendable (Database) throws -> Void)]`, plus `makeMigrator(upTo:)` for partial-migration fixtures. Added `init(locationProvider:allowsDestructiveRecovery:keychain:migrator:)`.
2. **CashRunwayRepository.swift** — Added idempotency guard in `postRecurringInstance(id:on:)`: returns early if instance is already `.posted`, preventing double-creation of linked transactions.
3. **RunwayCalculator.swift** (new) — `RunwayCalculator` struct with `calculateGlobalRunway()` and `calculateWalletRunway(walletID:)`. Uses `monthly_wallet_cashflow` for historical burn rate, projects forward, injectable calendar/clock. Return types: `RunwayResult`, `RunwayMonthProjection`.

### Test files (new)
4. **MigrationIntegrityTests.swift** — `migrationFromPreviousEncryptedSchemaPreservesLedger`: creates encrypted fixture at `v3_import_idempotency` schema, populates with wallets/categories/transactions/transfer/labels/recurring/import records, then opens with full migrator. Verifies: migration applied, data preserved, quarantine absent, integrity_check ok.
5. **DatabaseKeyMismatchTests.swift** — `wrongDatabaseKeyFailsWithoutMutatingDatabase`: creates encrypted DB with known key and sentinel transaction, attempts opening with wrong key + `allowsDestructiveRecovery: false`. Verifies: throws, SQLite/WAL hashes unchanged, no quarantine, correct key still works.
6. **RecurringIdempotencyTests.swift** — `postingRecurringInstanceTwiceAppliesLedgerEffectOnce`: posts instance, verifies balance and transaction count, posts again, verifies no duplicate transaction.
7. **RunwayForecastTests.swift** — `runwayForecastMatchesGoldenLedgerAndTransferInvariant`: two wallets with 3 months of income/expense/transfer history, fixed Europe/Kyiv calendar. Verifies: global burn rate, balance, transfer does not change global result, wallet-scoped balances change correctly.
8. **MonobankImportRollbackTests.swift** — Two tests: `monobankBatchFailureRollsBackAllItems` (deletes fallback "Other Expense" category, verifies import throws and no partial commit) and `correctedImportSucceedsWithAllResolvableItems` (verifies successful import path).

## Validation
- `just mirror-core --force` — core trees identical.
- `swift test` — 386 tests, 0 failures.

## Open questions
- Test 4 (forecast) golden value assertions are lightweight: burn rate and balance checks pass, but per-month projection assertions are limited. A more rigorous golden-value scenario with exact months-remaining math could be added.
- Coverage policy and CI config (items 7-10 on the roadmap) not yet addressed.