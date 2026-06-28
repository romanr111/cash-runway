# Cash Runway — Architecture Audit & Modernization Plan

**Date:** 2026-06-27
**Branch inspected:** `dev` @ `fed7859`
**Scope:** static code review, no UI/E2E tests executed

---

## Severe Finding — Call Out First

### S1. Empty entitlements file — no Data Protection capability

`AppHost/CashRunway.entitlements` is an **empty dict** (`<dict/>`). The app has no `com.apple.developer.default-data-protection` capability, so the encrypted SQLite database file is **not** covered by iOS Data Protection classes beyond the default sandbox. The database is encrypted via SQLCipher passphrase (good), but the file itself is not registered with `NSFileProtectionComplete`. If the device is compromised or restored via a backup extraction, the file is reachable without first-unlock.

**Severity:** High (finance app).
**Recommendation:** Add the `com.apple.developer.default-data-protection` entitlement and set `NSFileProtectionComplete` (or `NSFileProtectionCompleteUnlessOpen` if background maintenance must run while locked) on the database file. See Security table S1/S2.

---

# Executive Summary

## Top 5 risks

1. **God repository** — `CashRunwayRepository.swift` (4,029 lines) is a single `@unchecked Sendable` class mixing DAO, bank sync, category resolution, backup, aggregate maintenance, FTS, and recurring logic. Every concern touches the same `dbQueue`. High blast radius for any change. (`Sources/CashRunwayCore/CashRunwayRepository.swift`)
2. **Empty entitlements / no file-level data protection** — encrypted DB relies only on SQLCipher passphrase; no `NSFileProtectionComplete` and no Data Protection entitlement. (S1 above)
3. **Raw bank payloads stored indefinitely** — `bank_transaction_imports.raw_json` stores full Monobank statement JSON (incl. `balance`, `counter_iban`, `masked_pan`) forever with no TTL or redaction. Encrypted at rest; not currently included in user-facing JSON backups, but maximizes local PII surface and device/file-backup exposure. (`DatabaseManager.swift:744`, `CashRunwayRepository.swift:3807`)
4. **`NSLog` calls in DEBUG-gated UI code** — `Editors.swift:624` and `FeedbackReportScreenshotPicker.swift:164` use `NSLog` inside `#if DEBUG`. They do not ship in release, but they violate AGENTS.md ("Do not use `print()` for production diagnostics"), risk future accidental leakage if the guard is removed, and interleave with other diagnostics inconsistently. Cleanup item, not a release blocker.
5. **God view model + direct persistence coupling** — `CashRunwayAppModel` (1,045 lines) is `@MainActor @Observable`, holds `repository`, `csvService`, `backupService`, `bankTokenStore`, and mutates state directly. No separation between presentation, domain, and persistence.

## Top 5 recommendations

1. **Split `CashRunwayRepository` into domain services + thin persistence DAOs.** Move bank sync, category resolution, backup, recurring, and aggregate maintenance into separate services. Keep the repository as a query/facade only.
2. **Harden file protection.** Add the `com.apple.developer.default-data-protection` entitlement; set `NSFileProtectionComplete` (or `completeUnlessOpen`) on the DB and all backup/recovery files via a small `FileProtectionService`; add a TTL/purge job for `raw_json`.
3. **Clean up `NSLog` calls** (DEBUG-gated, not shipping) — replace with `OSLog` `Logger` and explicit `privacy:` annotations; add a lint check to prevent ungated `print`/`NSLog` in production paths.
4. **Introduce a module split** (`CashRunwayPersistence`, `CashRunwaySecurity`, `CashRunwayDomain`) **gradually**, behind the existing single `CashRunwayCore` product, to preserve the one-source-tree invariant in AGENTS.md.
5. **Design the LLM-agent access layer as an in-app capability service** (local-first, consent-gated, read-only by default) — see LLM-Agent section.

## Suggested sequence of work

Phase 0 → 1 → 2 → 3 → 4 → 5 (see Roadmap). The ordering prioritizes removing the highest-blast-radius god object and the security hardening before performance and agent work.

---

# Current Architecture

## Module / dependency map

```
AppHost (Xcode app target)
  └─ CashRunwayApp.swift          @main, BGTask registration, DEBUG recovery
  └─ RootView is instantiated here
        │
        ▼
Sources/CashRunwayUI (NOT a separate SwiftPM target — compiled into the app)
  ├─ RootView.swift               composition, onboarding (disabled), startup error
  ├─ AppModel.swift               @MainActor @Observable god view model
  │   └─ BackgroundWork (actor)   offloads snapshot loads, CSV/backup prep
  ├─ DashboardView.swift          1,658 lines, timeline + overview
  ├─ Editors.swift                2,266 lines, transaction/wallet/category editors
  ├─ SettingsView.swift           699 lines, imports/exports/backup/feedback
  ├─ TransactionsView.swift
  ├─ MonobankCoordinator / CSVImportCoordinator / BackupCoordinator
  └─ Theme, AccessibilityIdentifiers, Localization
        │
        │  imports CashRunwayCore (SwiftPM product)
        ▼
Sources/CashRunwayCore (SwiftPM target, path: Sources/CashRunwayCore)
  ├─ DatabaseManager.swift        Keychain, DatabaseManager, migrations (830 lines)
  ├─ CashRunwayRepository.swift   GOD: repository + bank sync + resolver + backup (4,029 lines)
  ├─ Models.swift                 all domain + backup structs (1,955 lines)
  ├─ CSVSupport.swift             CSV import/export + fingerprints (1,378 lines)
  ├─ FeedbackReport.swift         report issue service (480 lines)
  ├─ ReportingSecrets.swift       reporting client-secret provider
  ├─ Fixtures.swift               benchmark seed generator
  ├─ L10n / DateKeys / Money / MCCCategoryMapping / BankCategoryNameMapping / XLSXConverter
        │
        ▼
Vendor/GRDB.swift (local SwiftPM dep)
CoreXLSX (remote SwiftPM dep)
```

**Important note on the "mirrored core" assumption:** The task brief states core sources are mirrored under `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/`. **No such directory exists on `dev` or on the `codex/dedup-core` worktree.** `Package.swift` declares a single target at `Sources/CashRunwayCore`. `Scripts/check-core-module-wiring.sh` enforces that the Xcode app target does **not** duplicate Core sources. The mirror appears to have been removed already (the `dedup-core` worktree is detached). Any future recommendation must assume a single source tree at `Sources/CashRunwayCore/`.

## App startup flow

1. `CashRunwayApp.init()` (`AppHost/CashRunwayApp.swift:16`): DEBUG recovery/self-test hooks, `CashRunwayAppRuntime.bootstrap()`, `BGTaskScheduler` register + schedule.
2. `CashRunwayRootView.init()` (`RootView.swift:27`): constructs `CashRunwayAppModel.live()` which constructs `CashRunwayRepository()` → `DatabaseManager` → opens encrypted DB, runs all migrations.
3. `.task { await model.bootstrap() }` (`RootView.swift:132`): `seedIfNeeded`, `runMaintenance`, `refreshRecurringInstances`, `reloadAll`.
4. On `.active` scene phase: `model.handleForegroundResume()` → `BackgroundWork.refreshForegroundSnapshot` (bank sync + maintenance + snapshot).

## Persistence / data-flow map

- Single `DatabaseQueue` (serialized, WAL). No `DatabasePool`. All access via `databaseManager.dbQueue.read/write`. (`DatabaseManager.swift:268`)
- Encryption: SQLCipher passphrase from Keychain account `database-key`, generated as two concatenated UUIDs. (`DatabaseManager.swift:324`)
- Key migration path: if DB exists but key missing → throws `CashRunwayStartupFailure` (non-destructive). If decrypt fails and `allowsDestructiveRecovery` (DEBUG only) → quarantine + re-key. (`DatabaseManager.swift:347`)
- Aggregates: `monthly_wallet_cashflow`, `monthly_category_spend`, `daily_wallet_balance_delta`, `budget_progress_snapshot` maintained incrementally in `applyContribution` on every transaction write. Dirty-range rebuild via `aggregate_dirty_ranges` + `processPendingAggregateRebuilds`. (`CashRunwayRepository.swift:2867`, `3316`)
- FTS: `transaction_search` (FTS5) synced per-transaction in `syncSearch`; full rebuild in `rebuildFTS`.

## UI state-management flow

- `CashRunwayAppModel` (`AppModel.swift:11`) is `@MainActor @Observable`, holds ~20 published arrays/scalars.
- `reloadAll()` loads everything into an `AppModelSnapshot` via `BackgroundWork` actor, then `apply()` copies into `@Observable` properties.
- Mutations go through `runMutation { try repository.X(...) }` then `Task { await reloadAll() }`. Cache (`overviewSnapshotCache`) is cleared on every mutation.
- Timeline reload uses `TimelineReloadState` to coalesce concurrent reloads (`AppModel.swift:54`, `Models.swift:572`).

## Background-task flow

- `BGProcessingTask` identifier `dev.roman.cash-runway.maintenance`, scheduled 15 min out. (`CashRunwayApp.swift:46`)
- Handler creates a fresh `CashRunwayRepository()` (re-opens DB), runs `runMaintenance()` + `refreshRecurringInstances()`. (`CashRunwayApp.swift:72`)
- Foreground refresh also triggers bank sync via `BackgroundWork.refreshForegroundSnapshot` → `bankSyncPerformer.syncOnForeground()`. (`AppModel.swift:904`)

## Bank-sync / import flow

- `MonobankConnectionService.connectMonobank` validates token, writes to Keychain account `bank-token-monobank-<integrationID>`, saves integration+accounts, triggers sync. (`CashRunwayRepository.swift:355`)
- `BankSyncCoordinator.syncIntegration` builds a `MonobankPersonalAPIClient` per integration, delegates to `BankSyncService.sync`. (`CashRunwayRepository.swift:441`, `233`)
- `BankSyncSerialPerformer` + `BankSyncSerialGate` actor serialize all syncs. (`CashRunwayRepository.swift:35`, `62`)
- Import: `importMonobankExpenseItems` filters UAH expenses, resolves category via `BankCategoryResolver`, writes transaction + `bank_transaction_imports` row with **full `raw_json`**. (`CashRunwayRepository.swift:1176`, `3807`)
- CSV import: `CSVService.importStatement` → `repository.commitCSVImport` atomic write with fingerprint dedup. (`CSVSupport.swift`, `CashRunwayRepository.swift:2429`)

## Recurring-transaction flow

- `refreshRecurringInstances(db)` generates instances for `-7…+60` days for active templates via `generatedDates`. (`CashRunwayRepository.swift:3347`, `3366`)
- `postRecurringInstance` creates a `TransactionDraft` from template/overrides, saves, links. (`CashRunwayRepository.swift:2630`)
- `saveRecurringTemplate` triggers `refreshRecurringInstances` inside the same write. (`CashRunwayRepository.swift:1559`)

## Backup / restore flow

- `BackupService.exportFullBackup` reads all source tables into `CashRunwayBackup` (version 2), encodes pretty JSON. (`Models.swift:1188`, `CashRunwayRepository.swift:1288`)
- `restore` writes a safety backup to `tmp/CashRunwayBackups/`, clears derived + source + bank tables, inserts backup rows, clears Keychain tokens for cleared integrations, rebuilds aggregates + FTS. (`Models.swift:1209`, `CashRunwayRepository.swift:1319`)

## Test architecture map

- 46 files in `Tests/CashRunwayCoreTests/` using Swift Testing (`@Suite`, `@Test`).
- Suites serialized globally (`@Suite(.serialized)`) because they share a filesystem/keychain.
- Categories: CRUD, migrations, backup round-trip, bank sync, CSV idempotency, recurring, concurrency, WAL, crash simulation, key mismatch, performance (1k–150k via `FixtureGenerator`).
- `Tests/CashRunwayUITests/` exists but is not run locally per AGENTS.md; CI runs it only on `workflow_dispatch` with `run_ui_e2e_tests: true`.
- CI: `.github/workflows/ios-ci.yml` — source-membership check, SwiftLint, unit tests (filtered), integration tests (skip perf), app build, optional UI E2E.

---

# Maintainability Findings

| Priority | Finding | Evidence | Impact | Recommendation | Risk | Validation |
|---|---|---|---|---|---|---|
| P0 | God repository mixing DAO, bank sync, resolver, backup, recurring, aggregates | `CashRunwayRepository.swift` 4,029 lines; classes `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator`, `BankCategoryResolver`, `BackupService` all in this file | Any change risks regressions across unrelated features; untestable in isolation; blocks module split | Keep `CashRunwayRepository` as a compatibility facade; extract responsibilities into focused internal types **file/type-level first, not a package split**. Recommended extraction order: (1) `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator`, `BankCategoryResolver` → `Core/BankSync/`; (2) recurring template/instance generation → `Core/Recurring/`; (3) aggregate maintenance, dirty-range, FTS sync, rebuild → `Core/Persistence/Aggregates/`; (4) backup export/restore → `Core/Backup/`; (5) row mappers + persistence helpers → `Core/Persistence/DAOs/`. Keep public behavior stable; avoid broad model moves until the repository is smaller and tests cover the extracted services. | Medium (mechanical, behavior-preserving) | After each extraction: `just check-integration` + targeted `BankSyncImportTests`, `FullBackupTests`, `RecurringIdempotencyTests`, `RepositoryCRUDTests`, `MigrationIntegrityTests` |
| P0 | `CashRunwayAppModel` is a god view model with direct persistence | `AppModel.swift` 1,045 lines; holds `repository`, `csvService`, `backupService`, `bankTokenStore`; 20+ mutation methods call repository directly | UI/persistence/domain all coupled; hard to test UI without a DB; state ownership unclear | Extract per-feature view models (`DashboardViewModel`, `TransactionsViewModel`, `SettingsViewModel`) that depend on repository protocols, not the concrete class. Move shared orchestration into `BackgroundWork`. | Medium | `AppModelTimelineLoadingTests` + new VM unit tests |
| P1 | Migration names imply an order that does not match registration | `DatabaseManager.swift:664` `v3_import_idempotency`, `:671` `v4_import_job_source_format_id`, `:690` `v3_bank_sync` (registered AFTER v4) | A future migration assuming "v3 < v4" ordering by name will break; GRDB runs in registration order, not name order | **Do not rename `v3_bank_sync`** — GRDB tracks applied migrations by identifier; renaming a shipped migration would make existing databases treat it as new and re-run schema changes. Instead: (1) add a code comment that registration order is authoritative, (2) preserve all existing migration names forever, (3) use monotonic names only for *future* migrations (`v6_*`, `v7_*`, …), (4) add a `MigrationIntegrityTests` assertion that the current identifier set is unchanged. | Low | `MigrationIntegrityTests` on empty + upgraded fixture DBs |
| P1 | `Editors.swift` 2,266 lines — monolithic editor file | `Sources/CashRunwayUI/Editors.swift` | Hard to navigate; merge conflicts; untestable views | Split `TransactionEditorView`, `WalletEditorView`, `CategoryEditorView`, `NewWalletCategorySheet` into separate files. | Low | `just build` + `just ui-check` |
| P1 | `DashboardView.swift` 1,658 lines | `Sources/CashRunwayUI/DashboardView.swift` | Same as above | Extract `TimelineOverviewView`, chart cards, feed sections into files. | Low | `just build` |
| P2 | `@unchecked Sendable` on 8 core classes with shared `DatabaseQueue` | `CashRunwayRepository`, `DatabaseManager`, `BankSyncSerialPerformer`, `MonobankDirectTokenValidator`, `MonobankPersonalAPIClient`, `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator`, `BankCategoryResolver` | Concurrency safety is asserted, not proven; `DatabaseQueue` serializes, but the repository's cached `walletsHasCategoryIDColumn` is non-atomic mutable state | Keep `DatabaseQueue` (serialized) unless read concurrency is *measured* to be a bottleneck — moving to `DatabasePool` is a deliberate decision, not an architectural default. Independently: make cached column-existence checks atomic (e.g. move behind a `DatabaseAccess` actor or use `db.schema` lookups), and remove `@unchecked` where the type is genuinely immutable. | High (concurrency) | `DatabaseConcurrencyTests`, `LedgerInvariantPropertyTests` |
| P2 | Repeated row→struct mapping boilerplate (40+ static `Self.X(_ row:)`) | `CashRunwayRepository.swift:3588–4028` | Fragile, no compile-time column checking; force-unwraps `UUID(uuidString:)!` | Adopt GRDB `FetchableRecord`/`PersistableRecord` conformance on models, or generate mappers. Eliminates ~440 lines. | Medium | `ModelSerializationTests`, `RepositoryCRUDTests` |
| P2 | Inconsistent DI — `CashRunwayAppModel.live()` hardcodes `KeychainStore(service:)` | `AppModel.swift:79,90` | Cannot inject test keychain for UI tests; bank token store bound to production service | Introduce a `AppDependencies` struct assembled at the composition root (`CashRunwayAppRuntime`), pass into `AppModel`. | Low | Existing tests already inject via secondary init |
| P2 | Deprecated `appendImportedTransactions`/`finalizeImport` still public | `CashRunwayRepository.swift:2382,2397` marked DEPRECATED | Dead API surface; callers could reintroduce atomic-bypass bugs | Remove after confirming no callers (grep shows only `commitCSVImport` is used). | Low | `CSVIdempotencyTests` |
| P3 | `Models.swift` 1,955 lines mixes domain, backup DTOs, snapshots, errors | `Models.swift` | Hard to locate types | Split `Models.swift` → `DomainModels.swift`, `BackupModels.swift`, `SnapshotModels.swift`, `Errors.swift`. | Low | `ModelSerializationTests` |
| P3 | `overviewSnapshot` aggregates from raw transactions, not from `monthly_category_spend` | `CashRunwayRepository.swift:2063` LEFT JOIN transactions | The aggregate table exists precisely to avoid this; overview re-scans transactions each month view | Rewrite overview category/label queries to use `monthly_category_spend` + a `monthly_label_spend` aggregate (new). | Medium | `OverviewCategoryDistributionTests` + perf benchmark |
| P3 | `existingImportFingerprints` loads ALL fingerprints into memory | `CashRunwayRepository.swift:2540` | At 1M transactions, ~1M strings in a Set | Query for the specific fingerprint with `SELECT 1 ... WHERE import_fingerprint = ?` per row, or batch-check via temp table. | Low | `CSVIdempotencyTests` at scale |
| P3 | No repository protocol — UI depends on the concrete `CashRunwayRepository` | `AppModel.swift:12` `public var repository: CashRunwayRepository` | Cannot mock persistence in UI tests; blocks module separation | Introduce `protocol CashRunwayRepositorying` (or split into `WalletRepository`, `TransactionRepository`, etc.) and depend on protocols in UI. | Medium | `AppModelTimelineLoadingTests` |

---

# Security & Privacy Findings

| Priority | Finding | Evidence | Impact | Recommendation | Risk | Validation |
|---|---|---|---|---|---|---|
| S1 / P0 | Empty entitlements — no Data Protection capability | `AppHost/CashRunway.entitlements` is `<dict/>` | DB file not covered by iOS file-level encryption; backup extraction bypasses SQLCipher if device is unlocked-at-restore | Add `com.apple.developer.default-data-protection` entitlement. Choose `NSFileProtectionComplete` (max privacy) or `NSFileProtectionCompleteUnlessOpen` (if background maintenance must run while locked and the DB has already been opened). Apply via a small `FileProtectionService` to: DB + WAL + SHM, recovery/quarantine files, tmp safety backups, exported backups in-sandbox. | Low (entitlement + attribute) | New `DataProtectionTests`; verify on a **real device** (simulator does not enforce) |
| P1 | `NSLog` in DEBUG-gated UI code | `Editors.swift:624` `NSLog("labels sheet appeared")` (inside `#if DEBUG`); `FeedbackReportScreenshotPicker.swift:164` `NSLog("[Screenshot] %dx%d JPEG...")` (inside `#if DEBUG`) | Not shipping in release, but violates AGENTS.md logging convention and risks future leakage if the guard is dropped | Remove low-value debug `NSLog` calls; replace useful ones with `Logger(...).debug(..., privacy: .public/.private)`. Add a lint/grep check preventing ungated `print`/`NSLog` in production paths. | Low | `just lint` + grep `print(\|NSLog` outside `#if DEBUG` |
| P0 | Raw Monobank JSON stored indefinitely with no TTL/redaction | `DatabaseManager.swift:744` `raw_json TEXT NOT NULL`; `CashRunwayRepository.swift:3807` encodes full `MonobankStatementItem` incl. `balance`, `counter_iban`, `masked_pan` via `masked_pan` | Maximizes PII at rest and survives deletion of the linked transaction. **Note:** the current JSON backup (`exportFullBackup`) does *not* export `bank_transaction_imports`, so the primary exposure is local encrypted-DB retention + device/file-backup extraction, not the user-facing backup format. | (1) Store only fields needed for dedup/audit/reprocess; redact or drop `balance`, `counter_iban`, `counter_name`, `comment`, `receipt_id` unless a product need is documented. (2) Add a `raw_json_expires_at` column + purge job in `runMaintenance`. (3) Keep `bank_transaction_imports` excluded from user-facing exports by default; document this in `BackupValidator`. If full-fidelity export is ever needed, make it explicit, scoped, and encrypted. | Medium (migration + purge) | New `RawPayloadPurgeTests`; `FullBackupTests` proving raw bank imports excluded; regression `BankSyncImportTests`/`CSVIdempotencyTests` |
| P1 | `AppReportingSecrets` placeholder uses trivial XOR obfuscation | `AppHost/AppReportingSecrets.generated.swift:12` XOR with a key embedded in the same file | Not a real secret (placeholder), but the pattern suggests real secrets could ship the same way | Ensure real secrets are **never** compiled in. Use `ReportingKeychainSecretProvider` + Keychain only. CI should fail if `isPlaceholder == false` is committed. | Low | Script `generate-reporting-secrets.swift` should assert placeholder on commit |
| P1 | Debug recovery path writes report to Documents | `CashRunwayApp.swift:239` writes `recovery-attempt-report.txt` to `.documentDirectory` | Could persist transaction counts/wallet counts in an unencrypted location | Write to a `FileManager.default.temporaryDirectory` subpath and delete after read; or protect with `NSFileProtectionComplete`. Gate is already `#if DEBUG`. | Low | `AppLockAndLocationTests` |
| P2 | `AppLockStore` deprecated code remains in release binary | `DatabaseManager.swift:165–222` `AppLockConfiguration`/`AppLockStore` compiled in non-DEBUG | Dead security surface; SHA-256 PIN hash without salt | Remove the types or move behind `#if DEBUG`. If reviving, salt the PIN hash. | Low | `AppLockAndLocationTests` |
| P2 | No file protection on backup/recovery files | `Models.swift:1224` `tmp/CashRunwayBackups/`; `DatabaseManager.swift:398` `Recovery/` | Safety backups are JSON (full financial data) written without `NSFileProtectionComplete` | Set `.complete` file protection on all generated files in `tmp` and `Recovery/`. | Low | New test verifying `resourceValues[.protectionKey]` |
| P2 | `BankExternalExpenseItem.rawJSON` and `BankTransactionImport.rawJSON` flow through backup? | Backup does **not** export `bank_transaction_imports` (`insertBackupSourceData` has no bank imports) | Good — but `raw_json` lives forever in the DB. See P0 above. | Document this exclusion in `BackupValidator`. | Low | `FullBackupTests` |
| P2 | Token validation sends token in `X-Token` header via `URLSession.shared` | `CashRunwayRepository.swift:126,201` | `URLSession.shared` may cache the request/headers in some configurations | Use a dedicated `URLSession` with `.ephemeral` config and no cache. | Low | `BankConnectionServiceTests` |
| P3 | Error messages can include `error.localizedDescription` from GRDB | `AppModel.swift:147,181` `errorMessage = error.localizedDescription` | Could leak SQL/schema details to UI / crash reports | Map known errors to user-safe messages; only log detailed errors via `Logger`. | Low | Manual review |
| P3 | `DebugCSVImportSelfTest` constructs a real `CashRunwayRepository` in DEBUG startup | `CashRunwayApp.swift:254` | Creates a DB in temp; fine, but ensure it cannot run in release | Already `#if DEBUG`. Verify `allowsDestructiveRecovery: true` cannot ship (guarded by `#if !DEBUG fatalError`). ✓ Already guarded. | Low | — |

### Answers to specific security questions

- **Secrets outside Keychain?** No — DB key, bank tokens, reporting secret all use Keychain. The reporting *placeholder* is compiled (XOR), but it is a placeholder.
- **Sensitive data in logs/files/fixtures/crash reports?** `NSLog` is DEBUG-gated (not shipping) — cleanup item. Recovery report writes counts to Documents (P1). Fixtures are synthetic (safe). Backups are unencrypted JSON (P2).
- **DB key generation/rotation/recovery safe?** Generation: two UUIDs concatenated (128-bit equivalent, acceptable). Rotation: **none** — key never rotates. Recovery: destructive only in DEBUG, quarantines old DB. Acceptable for MVP but document.
- **Raw bank payloads necessary?** Useful for re-processing and audit, but should be **redacted + TTL-purged**. See P0.
- **Debug/recovery paths safe in release?** Yes — all gated by `#if DEBUG` or `#if !DEBUG fatalError`.
- **`@unchecked Sendable` risks?** Yes — see Maintainability P2. The `DatabaseQueue` serializes access, but cached mutable state (`walletsHasCategoryIDColumn`) is not protected.
- **Threat model for LLM agents?** See LLM-Agent section.

---

# Performance & Scalability Findings

| Priority | Finding | Evidence | Impact | Recommendation | Risk | Validation |
|---|---|---|---|---|---|---|
| P0 | `overviewSnapshot` scans raw transactions instead of aggregates | `CashRunwayRepository.swift:2063` LEFT JOIN `transactions` for category spend; `:2104` for labels | At 100k+ txns/month this is O(n) per overview open; aggregate table exists for exactly this | Use `monthly_category_spend` for categories. Add `monthly_label_spend` aggregate for labels. | Medium | `OverviewCategoryDistributionTests` + perf at 150k |
| P0 | `rebuildFTS` and `rebuildMonths` rescan ALL transactions | `CashRunwayRepository.swift:3339,3287` | Restore/migration is O(total txns); at 1M this is minutes and blocks the UI | Chunk rebuilds; run in background actor; consider `INSERT INTO transaction_search SELECT ...` bulk SQL instead of per-row `syncSearch`. | Medium | `CashRunwayPerformanceTests` |
| P1 | `listTransactions` default limit 300 but timeline uses `limit: nil` | `CashRunwayRepository.swift:1713,3039` | Timeline month with thousands of txns loads all into memory + maps labels in chunked sub-queries | Add server-style pagination (offset/limit) to timeline; render sections incrementally. | Medium | `PropertyStyleQueryTests` |
| P1 | Label sub-query chunks at 900 but still loads all labels into memory | `CashRunwayRepository.swift:3094–3124` | At 1M txns × avg 2 labels, large dict | Fetch labels lazily per visible section, or precompute `monthly_label_spend`. | Medium | `ChunkedLabelQueryTests` |
| P1 | `existingImportFingerprints` loads all fingerprints into a Set | `CashRunwayRepository.swift:2540` | O(n) memory per import; at 1M txns ~tens of MB | Check fingerprints one-by-one via indexed `SELECT 1`, or use a temp table join. Index already exists (`idx_transactions_import_fingerprint`). | Low | `CSVIdempotencyTests` |
| P2 | `refreshRecurringInstances` inserts with `INSERT OR IGNORE` in a loop | `CashRunwayRepository.swift:3355` | Fine for small template counts; no batching | Batch insert via a single multi-row `INSERT`. | Low | `RecurringIdempotencyTests` |
| P2 | `aggregate_dirty_ranges` never cleans up completed rows | `CashRunwayRepository.swift:3316` marks `done` but never deletes | Table grows unbounded | Delete `done` rows after commit, or TTL-purge in `runMaintenance`. | Low | New test |
| P2 | `BankCategoryResolver` re-reads all categories + rules on every import batch | `CashRunwayRepository.swift:519` init reads DB | Fine per sync, but constructed inside `importMonobankExpenseItems` per call | Construct once per sync session and reuse. | Low | `BankSyncImportTests` |
| P3 | `allBars` computes month range by looping month-by-month | `CashRunwayRepository.swift:1865` | For 30-year history ~360 iterations — negligible | Acceptable. | — | — |
| P3 | `monthEndBalances` uses cumulative scan over `monthly_wallet_cashflow` | `CashRunwayRepository.swift:3196` | O(months) — fine | Acceptable. | — | — |

## Scale answers

- **10k transactions:** Works today (perf tests cover 1k–150k). Overview may feel slow due to raw-scan (P0).
- **100k transactions:** Timeline loading all txns for a month (limit nil) becomes noticeable. FTS rebuild on restore is seconds.
- **1M transactions:** `rebuildFTS`/`rebuildMonths` block for minutes. `existingImportFingerprints` holds ~1M strings. Overview raw scan is the bottleneck. Pagination absent on timeline.
- **Most likely slow screens:** Overview (raw scan), Timeline (unbounded load), Restore (full FTS rebuild).
- **Indexes needed:** Already comprehensive in v1 (`idx_transactions_*`, aggregate indexes). Add `idx_bank_transaction_imports_statement_time` if TTL purge queries by time.
- **Background actor candidates:** FTS rebuild, month rebuild, fingerprint checks, CSV commit for very large files.
- **Caching correctness risk:** `overviewSnapshotCache` is cleared on every mutation (`runMutation`), which is safe but expensive. If made stale-aware, must invalidate by affected month keys, not globally.
- **Performance tests to add:** overview at 150k with raw scan vs aggregate; timeline pagination; restore FTS rebuild timing; fingerprint check at 1M.

---

# LLM-Agent Integration Architecture

## Recommended design: A. Local-only in-app agent service (with E. export-snapshot as a fallback)

**Why:** Cash Runway is offline-first, encrypted, and single-user. A local in-process capability service keeps all data on device, lets the app enforce consent/redaction/audit at the boundary, and avoids opening a network port (option B/C) that increases attack surface. Option E (export-snapshot) is the minimal fallback for one-shot sharing with a remote LLM when the user explicitly exports.

## Rejected alternatives

- **B. Localhost HTTP service:** Opens a port on the device; other apps/processes could reach it; needs auth + TLS; iOS background networking is constrained. Net risk > benefit for a personal finance app.
- **C. MCP server sidecar:** Same port-exposure risk as B; MCP is designed for tool use across processes — overkill for on-device; useful only if the user wants a *remote* MCP client to drive the app, which should go through E instead.
- **D. App Intents / Shortcuts:** Good UX for user-initiated actions ("summarize my spending"), but Shortcuts can be invoked by other automation without per-call consent if granted broadly. Use only for *user-present* triggers, never as the data-access boundary.
- **F. Direct database access:** **Rejected outright.** Bypasses consent, redaction, audit, and schema evolution. A prompt-injection in an LLM response could exfiltrate the entire DB. Violates the core requirement.

## Threat model

| Threat | Mitigation |
|---|---|
| Prompt injection causes agent to read full history | Capability layer enforces limits + redaction; agent never sees raw SQL |
| Agent exfiltrates data via a side channel (URL request) | All agent network calls must go through a user-approved proxy; capability layer logs every read; no raw payload leaves the device unredacted |
| Stale consent grant persists | Short-lived session tokens (e.g. 10 min); re-prompt on app foreground |
| Agent drafts a destructive change | Write capabilities require explicit user confirmation in-app; drafts are never auto-applied |
| Raw bank tokens accessed | Tokens are explicitly excluded from the capability surface |
| Agent reads `raw_json` PII | `read_transactions` redacts `rawJSON`, `counter_iban`, `masked_pan`, `balance` by default |
| Audit tampering | Audit log is append-only in the encrypted DB; agent has no audit-write capability |

## Permission / capability model

```
AgentSession {
  id: UUID
  grantedCapabilities: Set<AgentCapability>   // scoped per session
  walletScope: Set<UUID>?                      // nil = all, else allowlist
  dateRange: ClosedRange<Date>?
  expiresAt: Date                              // short-lived
  revoked: Bool
}
```

Capabilities (read-only by default):
- `read_monthly_summary` → aggregated cashflow, no transactions
- `read_cashflow_forecast` → forecast numbers, no raw txns
- `read_category_spend` → monthly_category_spend rows (redacted merchant)
- `read_transactions` → strict filters, limit ≤ 100, merchant/note redacted unless `include_notes` granted
- `explain_budget_variance` → derived explanation
- `suggest_category_mapping` → suggestion only, no apply
- `generate_financial_insights` → summary text

Write capabilities (require separate grant + confirmation):
- `draft_transaction_changes` → returns a `TransactionDraft` preview, **does not persist**
- `apply_user_confirmed_changes` → only after user taps "Apply" in-app

**Disallowed by default:** unrestricted SQL, raw DB file, Keychain, bank tokens, full history, silent export, persistent access.

## API surface (local Swift protocol, not HTTP)

```swift
protocol AgentAccessService {
  func openSession(capabilities: Set<AgentCapability>, walletScope: Set<UUID>?, dateRange: ClosedRange<Date>?, ttl: TimeInterval) throws -> AgentSession
  func revoke(_ sessionID: UUID) throws
  func monthlySummary(_ req: MonthlySummaryRequest) throws -> MonthlySummary
  func cashflowForecast(_ req: ForecastRequest) throws -> Forecast
  func categorySpend(_ req: CategorySpendRequest) throws -> [CategorySpendRow]
  func transactions(_ req: TransactionReadRequest) throws -> [RedactedTransaction]
  func explainBudgetVariance(_ req: VarianceRequest) throws -> VarianceExplanation
  func suggestCategoryMapping(_ req: MappingSuggestionRequest) throws -> [CategoryMappingSuggestion]
  func draftTransactionChanges(_ req: DraftRequest) throws -> TransactionDraftPreview
  func applyConfirmedChanges(_ draftID: UUID, confirmation: UserConfirmation) throws
  func auditLog(for sessionID: UUID) throws -> [AuditEntry]
}
```

## Redaction rules (default)

| Field | Default |
|---|---|
| `merchant` | Truncate to 32 chars; hash if `include_merchants` not granted |
| `note` | Omit unless `include_notes` granted |
| `amountMinor` | Provided (needed for summaries) |
| `counterName`, `counterIban`, `maskedPAN`, `iban` | Omit |
| `rawJSON` | Never exposed |
| `bankTransactionImports` | Never exposed |
| `wallet.name` | Provided; `walletID` only if `include_wallet_ids` granted |

## Consent UX

1. User triggers "Ask assistant" in Settings.
2. App shows a **scope preview**: capabilities, wallets, date range, TTL.
3. User toggles each capability and confirms.
4. Session token issued; visible in a "Active sessions" list with revoke buttons.
5. Every agent read shows a non-blocking toast ("Assistant read 12 transactions").
6. Write drafts show a full-screen confirmation sheet before applying.

## Audit / revocation

- Every capability call appends to `audit_entries` (existing table) with `entity_type='agent'`, `operation=<capability>`, `diff_json` = redacted request/response summary.
- `revoke` is immediate; in-flight calls check `revoked` before returning.
- Sessions auto-expire; expired tokens cannot be reused.

## Data schemas

Reuse existing domain structs with redaction wrappers:
```swift
struct RedactedTransaction: Sendable {
  let id: UUID
  let amountMinor: Int64
  let kind: TransactionKind
  let occurredAt: Date
  let categoryName: String?      // provided
  let merchantPreview: String?   // truncated/hashed
  // no note, no walletID unless granted
}
```

## Staged roadmap (within Phase 5)

1. Define `AgentCapability`, `AgentSession`, `AgentAccessService` protocol in Core (no impl).
2. Implement read capabilities backed by existing repository queries + redaction.
3. Add audit logging + consent UI.
4. Add `draft_transaction_changes` + `apply_user_confirmed_changes`.
5. Wire a local LLM (on-device) or a user-approved remote proxy behind the same protocol.

## Test strategy (agent)

- **Permission-boundary tests:** every capability refused without the grant; revoked session short-circuits; expired token rejected; out-of-scope wallet/date refused.
- **Redaction tests:** `read_transactions` output never contains `rawJSON`, `counter_iban`, `masked_pan`, `balance`; `note` absent unless `include_notes` granted; `merchantPreview` truncated/hashed.
- **Audit-log tests:** every read and write attempt appends an entry; agent has no audit-write capability; log is append-only.
- **Prompt-injection abuse cases:** model output asking for raw SQL / full history / tokens / file access is refused by the capability layer, not passed to the DB.
- **Draft/apply tests:** `draft_transaction_changes` returns a preview and does not persist; `apply_user_confirmed_changes` requires an in-app confirmation token; replaying an old confirmation is rejected.
- **Consent UX tests:** scope preview lists capabilities + wallets + date range + TTL; revoke is immediate; sessions auto-expire.

---

# Proposed Target Architecture

```
AppHost (composition root)
  └─ assembles AppDependencies { repository, security, agentAccess, ... }

CashRunwayUI (SwiftUI, depends on protocols)
  ├─ View models (per feature) depending on Repository protocols, NOT concrete
  └─ No direct dbQueue access

CashRunwayDomain (future split, currently inside Core)
  ├─ Domain models (Wallet, Transaction, Category, ...)
  ├─ Domain services: ForecastService, RecurringService, CategoryService
  └─ Repository protocols: TransactionRepository, WalletRepository, ...

CashRunwayPersistence (future split)
  ├─ GRDB DatabaseManager, migrations, indexes
  ├─ DAOs implementing repository protocols
  └─ Aggregate maintenance, FTS sync

CashRunwaySecurity (future split)
  ├─ KeychainStore, BankTokenStore, DatabaseKeyLifecycle
  ├─ FileProtection, ConsentGrants
  └─ RedactionService

CashRunwayAgentAccess (future, new)
  ├─ AgentCapability, AgentSession
  ├─ AgentAccessService (read/draft/apply)
  ├─ AuditLog
  └─ Redaction rules
```

**Dependency direction:** AppHost → UI → Domain(protocols) ← Persistence/Security/AgentAccess implement. UI never imports Persistence or Security directly.

## Should these be separate Swift packages now?

**Not yet.** AGENTS.md mandates a single source tree at `Sources/CashRunwayCore/` compiled by both Xcode and SwiftPM. Introducing separate packages now would require either (a) moving files (high churn, risks the pbxproj) or (b) symlinking (fragile). Instead:

- **Phase 2:** Create *logical* subdirectories inside `Sources/CashRunwayCore/` (`Persistence/`, `Domain/`, `Security/`, `BankSync/`, `Recurring/`, `Backup/`) with file-level boundaries and `internal` access where possible. The SwiftPM target stays one.
- **Phase 3+:** Once boundaries are stable and `internal`, promote to separate SwiftPM targets/products with `@_exported` re-exports for backward compatibility. This is reversible and low-risk.

## What to avoid

- Do not create a `Modules/CashRunwayCorePackage/` mirror (the prior duplication that was removed). One source tree only.
- Do not give UI direct access to `dbQueue`.
- Do not expose `BankTransactionImport.rawJSON` to any layer above Persistence.
- Do not add an HTTP server to the app.
- Do not auto-grant agent capabilities.

---

# Roadmap

## Phase 0: Documentation and tests
- Document the single-source-tree invariant and the migration-name-is-identifier rule in `agent_docs/`.
- Add `DataProtectionTests`, `RawPayloadPurgeTests` stubs.
- Add a perf benchmark for `overviewSnapshot` at 150k.
- Verify: `just check-unit-parallel`.

## Phase 1: Low-risk cleanup
- **Do not** rename existing migrations. Preserve `v3_bank_sync` forever; add a code comment that registration order is authoritative; use monotonic names (`v6_*`) only for *new* migrations. Add a `MigrationIntegrityTests` assertion that the identifier set is stable.
- Remove/clean up DEBUG-gated `NSLog` calls; replace with `Logger` + privacy annotations.
- Add a lint/grep check (e.g. a `Scripts/check-no-ungated-logging.sh` wired into CI) preventing ungated `print(`/`NSLog` outside `#if DEBUG`.
- Remove deprecated `appendImportedTransactions`/`finalizeImport` after confirming no callers.
- Split `Editors.swift` and `DashboardView.swift` into per-view files.
- Verify: `just check`, `just build`.

## Phase 2: Persistence/domain separation
- Keep `CashRunwayRepository` as a compatibility facade; extract in this order (file/type-level, behavior-preserving):
  1. `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator`, `BankCategoryResolver` → `Core/BankSync/`
  2. Recurring template/instance generation → `Core/Recurring/`
  3. Aggregate maintenance, dirty-range, FTS sync, rebuild → `Core/Persistence/Aggregates/`
  4. Backup export/restore → `Core/Backup/`
  5. Row mappers + persistence helpers → `Core/Persistence/DAOs/`
- Introduce `protocol CashRunwayRepositorying`; UI depends on protocol.
- **Avoid broad model moves** until the repository is smaller and tests cover the extracted services.
- Verify after each extraction: `just check-integration`, `BankSyncImportTests`, `FullBackupTests`, `RecurringIdempotencyTests`, `RepositoryCRUDTests`, `MigrationIntegrityTests`.

## Phase 3: Performance and benchmark work
- Rewrite `overviewSnapshot` to use aggregates (add `monthly_label_spend`).
- Paginate timeline; chunk FTS/aggregate rebuilds into a background actor.
- Replace `existingImportFingerprints` bulk-load with per-row indexed checks.
- Add `idx_bank_transaction_imports_statement_time` + TTL purge.
- Verify: `just check-perf` at 150k; new overview benchmark.

## Phase 4: Privacy/security hardening
- Add `com.apple.developer.default-data-protection` entitlement + `NSFileProtectionComplete`/`completeUnlessOpen` on DB/WAL/SHM, backups, and recovery files via a `FileProtectionService`. Validate on a real device (simulator does not enforce).
- Redact + TTL-purge `bank_transaction_imports.raw_json`.
- Use ephemeral `URLSession` for Monobank calls.
- Remove or `#if DEBUG`-gate `AppLockStore`.
- Verify: new `DataProtectionTests`, `RawPayloadPurgeTests`; device rehearsal.

## Phase 5: Consent-gated LLM-agent access
- Implement `AgentAccessService` protocol + read capabilities + redaction.
- Add consent UI, session list, audit log.
- Add `draft_transaction_changes` + `apply_user_confirmed_changes`.
- Wire to a local or user-approved remote LLM behind the same protocol.
- Verify: `AgentPermissionBoundaryTests`, `AgentAuditLogTests`.

---

# Open Questions

1. **Data Protection class:** `complete` (locks at sleep) vs `completeUnlessOpen` (keeps DB writable while unlocked)? Finance app → `complete` is safer but may block background tasks. Needs product decision.
2. **Raw bank payload retention:** Keep for N days for re-processing, or drop entirely after linking? Affects audit/re-import capability.
3. **Database key rotation:** Currently none. Should we support rotation on user request or on suspicious activity? Requires re-encrypting the DB.
4. **Backup encryption:** Backups are unencrypted JSON. Should exports be passphrase-encrypted before this is addressed?
5. **Agent LLM host:** On-device (e.g. MLX/llama.swift) vs user-approved remote? Affects whether a network proxy is needed.
6. **`DatabasePool` vs `DatabaseQueue`:** Pool enables concurrent reads but adds complexity for incremental aggregate writes. This should be a *measured* decision (benchmarked read contention), not an architectural default. Keep `DatabaseQueue` until evidence shows read contention.
7. **Budgets feature:** Marked de-prioritized. Should the code/tables be removed or kept frozen? Affects module split scope.

---

# Appendix

## Files inspected
- `README.md`, `AGENTS.md`, `CONTINUITY.md`, `PLAN.md`, `Package.swift`, `.mcp.json`, `justfile`
- `.github/workflows/ios-ci.yml`
- `AppHost/CashRunwayApp.swift` (347), `CashRunway.entitlements`, `AppReportingSecrets.generated.swift`, `Info.plist` (listed)
- `Sources/CashRunwayCore/DatabaseManager.swift` (830, full)
- `Sources/CashRunwayCore/CashRunwayRepository.swift` (4,029, full in chunks)
- `Sources/CashRunwayCore/Models.swift` (1,955, key sections)
- `Sources/CashRunwayCore/CSVSupport.swift` (head), `FeedbackReport.swift` (full), `ReportingSecrets.swift` (full), `Fixtures.swift` (full)
- `Sources/CashRunwayUI/AppModel.swift` (1,045, full), `RootView.swift` (full), `DashboardView.swift` (head), `Editors.swift` (head), `SettingsView.swift` (head)
- `Tests/CashRunwayCoreTests/` directory listing + `MigrationIntegrityTests.swift` (head)
- `Scripts/pre-flight.sh`, `check-core-module-wiring.sh`

## Commands run
- `git worktree list`, `git status --short`, `git rev-parse --abbrev-ref HEAD`
- `ls` of `Modules/`, worktrees (mirror does not exist)
- `wc -l` across all Core/UI/AppHost Swift files
- `grep` for public API surface, `raw_json`, `NSLog`/`Logger`, `@unchecked Sendable`, migration names, file-protection APIs

## Tests run/skipped
- **None run.** Per task instructions ("Do not run UI/E2E tests locally unless explicitly requested") and the investigative nature of this task, no `just`/`swift test`/`xcodebuild` commands were executed.
- Skipped gates: `just check`, `just build`, `just lint`, `just smoke`. Report relies on static review + existing test names as evidence of coverage.

## Assumptions
- The `Modules/CashRunwayCorePackage/` mirror described in the task brief has already been removed on `dev`; the `codex/dedup-core` worktree is detached and also lacks it. Recommendations assume a single source tree.
- `Vendor/GRDB.swift` is a local checkout (not the SPM remote) — version not inspected.
- All `@unchecked Sendable` classes are safe *only because* `DatabaseQueue` serializes access; this is a latent risk if `DatabasePool` is introduced.

## Areas not inspected
- `Sources/CashRunwayUI/Theme.swift`, `TransactionsView.swift`, `BudgetsView.swift`, coordinator files (only listed/grepped).
- `reporting-api/` Node backend (out of scope for iOS architecture, though it receives feedback reports).
- `sidestore/`, `DesignReferences/`, `docs/` content.
- `.swiftlint.yml` rules (only `just lint` referenced).
- `XLSXConverter.swift`, `MCCCategoryMapping.swift`, `BankCategoryNameMapping.swift`, `L10n.swift`, `DateKeys.swift`, `Money.swift` internals.
- `CashRunway.xcodeproj/project.pbxproj` (per AGENTS.md, not hand-edited).
- Nightly/release workflows (`ios-nightly.yml`, `sidestore-release.yml`) beyond confirming their existence.