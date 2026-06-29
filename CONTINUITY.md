## Snapshot — Two-tap category detail navigation

## Architecture Audit — Phases 1 & 2 complete

### Phase 1: cleanup & foundation — DONE
- Branch: `codex/arch-phase-1-cleanup` (PR #80 → `dev`)
- Split `Editors.swift` (2266→937) and `DashboardView.swift` (1658→638) into 8 per-view files
- Removed deprecated `appendImportedTransactions`/`finalizeImport` CSV APIs
- Replaced DEBUG-gated `NSLog` with `OSLog Logger` + privacy annotations
- Added `Scripts/check-no-ungated-logging.sh` CI gate (depth-aware awk, `#else`/`#elseif` handling, `--self-test` 5 fixtures)
- Documented migration-identifier permanence invariant; added `MigrationIntegrityTests.migrationIdentifierSetIsStable`
- Verified: build, integration (425/425), lint (0/98), pre-flight, pbxproj, logging

### Phase 2: persistence/domain separation — DONE
- Branch: `codex/arch-phase-2-extraction` (PR #82 → `codex/arch-phase-1-cleanup`)
- Split `CashRunwayRepository.swift` (4204→2263 lines, 46% reduction) into:
  - `BankSync/BankSyncTypes.swift` (715 lines) — protocols, API clients, sync services, category resolver
  - `Recurring/RecurringGeneration.swift` (79 lines) — recurring instance generation
  - `Persistence/Aggregates/AggregateMaintenance.swift` (509 lines) — aggregate maintenance + FTS sync
  - `Backup/BackupService.swift` (231 lines) — backup export/restore
  - `Persistence/DAOs/RowMappers.swift` (425 lines) — row mappers + persistence helpers
- Introduced `protocol CashRunwayRepositorying` (57 methods, no `databaseManager`) — clean domain abstraction
- `AppModel.repository`, `BackgroundWork`, `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator` depend on `any CashRunwayRepositorying`
- Protocol-extension default-arg wrappers preserve call-site ergonomics
- `BackupService`/`CSVService`/`BankCategoryResolver` retain concrete `CashRunwayRepository` dependency (need internal DB methods)
- `AppModel` mock init accepts injected `csvService` + `backupService` for testability
- Added `CashRunwayRepositoryingTests` — mock conformance without `DatabaseManager` (2/2 pass)
- Verified: build, integration (427/427), lint (0/105), pre-flight, pbxproj, logging

### Pending phases
- **Phase 3:** privacy/security hardening (Data Protection entitlement, `NSFileProtectionComplete`, `raw_json` TTL purge, ephemeral URLSession, `AppLockStore` gating)
- **Phase 4:** performance/benchmarks (overview aggregate rewrite, timeline pagination, FTS rebuild chunking, fingerprint per-row checks)
- **Phase 5:** consent-gated LLM-agent access (`AgentAccessService` protocol + read capabilities + redaction + consent UI + audit log)

See `docs/ARCHITECTURE_AUDIT.md` for the full roadmap.

### Follow-ups from Phase 2 review (not blocking)
- `BackupServicing` protocol for full `CashRunwayAppModel` DB-free mockability — Phase 3+
- Split `CashRunwayRepositorying` (57 methods) into per-feature protocols (`DashboardRepositorying`/`TransactionRepositorying`/etc.) — Phase 3+
- Narrow `AppModel.repository` from `public var` to `private let` — Phase 3+
- Split `RowMappers.swift` (pure mappers vs query helpers) — next extraction pass
- `BankCategoryResolver` → split into `SnapshotLoader` + pure `Resolver` — Phase 3+

## Key audit findings (top risks, still open)
1. God repository — **resolved by Phase 2** (4204→2263 lines, 6 focused files)
2. Empty `AppHost/CashRunway.entitlements` — no Data Protection capability — **Phase 3**
3. `bank_transaction_imports.raw_json` stored indefinitely — **Phase 3**
4. `NSLog` in DEBUG-gated UI code — **resolved by Phase 1**
5. God view model `AppModel` (1045 lines) — **partially addressed by Phase 2 protocol; full split is Phase 3+**

## Open questions for product/security
1. Data Protection class: `complete` (safer, blocks BG tasks when locked) vs `completeUnlessOpen`?
2. `raw_json` retention: N days for reprocessing, or drop after linking?
3. Database key rotation: support on user request?
4. Backup encryption: passphrase-encrypt exports?
5. Agent LLM host: on-device vs user-approved remote?
6. Budgets feature: remove frozen code/tables, or keep?

## PR status
- PR #80 (Phase 1 → `dev`): MERGEABLE, CI green
- PR #82 (Phase 2 → Phase 1): MERGEABLE, CI green
- Merge order: PR #80 first, then retarget PR #82 to `dev`, then merge

## Areas not inspected (audit baseline)
- `Theme.swift`, `TransactionsView.swift`, `BudgetsView.swift`, coordinator files (listed/grepped only)
- `reporting-api/` Node backend, `sidestore/`, `DesignReferences/`, `docs/` content
- `.swiftlint.yml` rules; `XLSXConverter`, `MCCCategoryMapping`, `BankCategoryNameMapping`, `L10n`, `DateKeys`, `Money` internals
- `CashRunway.xcodeproj/project.pbxproj` (not hand-edited per AGENTS.md)
- Nightly/release workflows beyond confirming existence