# Ledger Archive

Historical architecture phases and resolved incidents. See `CONTINUITY.md` for
the current snapshot.

## Canonical integration branch

- **PR:** https://github.com/romanr111/cash-runway/pull/86
- **Branch:** `codex/arch-improvements`
- **Status:** merged into `dev` as `9f3ca21`

## Phase 1: cleanup & foundation — DONE

- **Branch:** `codex/arch-phase-1-cleanup`
- Split `Editors.swift` (2266→937) and `DashboardView.swift` (1658→638) into per-view files.
- Removed deprecated `appendImportedTransactions`/`finalizeImport` CSV APIs.
- Replaced DEBUG-gated `NSLog` with `OSLog Logger` + privacy annotations.
- Added `Scripts/check-no-ungated-logging.sh` CI gate.
- Documented migration-identifier permanence invariant; added `MigrationIntegrityTests.migrationIdentifierSetIsStable`.

## Phase 2: persistence/domain separation — DONE

- **Branch:** `codex/arch-phase-2-extraction`
- Split `CashRunwayRepository.swift` (4204→2263 lines, 46% reduction) into focused files.
- Introduced `protocol CashRunwayRepositorying` (57 methods).
- `AppModel.repository`, `BackgroundWork`, `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator` depend on `any CashRunwayRepositorying`.
- Added `CashRunwayRepositoryingTests` — mock conformance without `DatabaseManager`.

## Phase 3: privacy/security hardening — DONE

- **Branch:** `codex/arch-phase-3-security-hardening`
- Added `com.apple.developer.default-data-protection` entitlement with `NSFileProtectionComplete`.
- Added `FileProtectionService`, `ProtectedDataMonitor`, protected-data gating for DB/bank sync/CSV/backup operations.
- Added `v6_bank_raw_json_ttl` migration: nullable `raw_json`, redacted audit payload, 30-day TTL purge.
- Switched Monobank validator and `FeedbackReport` to ephemeral `URLSession`.
- Removed `AppLockStore`, updated `PLAN.md` reference.
- Added `DataProtectionTests` and `RawPayloadPurgeTests`.
- **Release gate:** physical-device rehearsal required before shipping Phase 3 security behavior.

## Phase 3.5: protocol cleanup — DONE

- **Branch:** `codex/arch-phase-3.5-protocol-cleanup`
- Added `CSVImportServicing` protocol; `CSVService: CSVImportServicing` and `BackupService: BackupServicing`.
- Updated `CashRunwayAppModel` and `BackgroundWork` to depend on `any CSVImportServicing` / `any BackupServicing`.
- Narrowed `AppModel.repository` from `public var` to `private let`.
- Extracted `ProtectedDataCache`, fixed cold-cache issue, added `@unchecked Sendable` guard checks.

## Phase 4: performance — DONE

- **Branch:** `codex/arch-phase-4-performance` (rebuilt on top of `codex/arch-improvements`, replacing the stale Phase-2-based branch)
- Added wallet-scoped v7 aggregate migrations:
  - `v7_monthly_category_spend_wallet_kind_income`
  - `v7_monthly_label_spend_wallet`
- Updated `overviewSnapshot` and dashboard top-categories to filter by `wallet_id`.
- Added `offset` to `TransactionQuery` for timeline pagination.
- Implemented per-row import fingerprint/semantic duplicate checks.
- Implemented chunked `rebuildFTS` and bulk `rebuildMonths`.
- Extracted `PersistenceHelpers.swift` for shared `tableExists`/`columnExists`.
- **Bug fix:** `rebuildMonths` now calls `recomputeWalletBalances(_:)` so backup restore preserves `current_balance_minor`.

## Resolved incidents

### CI crash on macOS SwiftPM tests (`NSFileProtectionComplete`)

- **Run:** `28396573815`
- **Cause:** `FileProtectionService.protect` called `setAttributes([.protectionKey: .complete])` on macOS, where `NSFileProtectionComplete` is unsupported and returns `EINVAL`; the DEBUG `assertionFailure` then crashed the test runner.
- **Fix (commit `b6c6cc7`):** wrapped attribute application in `#if canImport(UIKit)` and no-oped on non-UIKit platforms. iOS behavior and loud DEBUG failure are unchanged.
- **Resolved run:** `28397532095`.

### NSLock deadlock in AgentAccess fake

- A re-entrant `NSLock` deadlock in `FakeDashboardRepository.transactions` (called `walletName(for:)` while already holding the lock) caused Swift Testing to hang on any `readTransactions` call scoped to a single wallet.
- Fixed by computing the target wallet name before entering the locked region.

## Validation on `codex/arch-improvements`

| Gate | Result |
|---|---|
| `Scripts/pre-flight.sh` | ✅ |
| `just build` | ✅ BUILD SUCCEEDED |
| `just check-unit-parallel` | ✅ 58/58 |
| `just check-integration` | ✅ 434/434 |
| `just lint` | ✅ 0 violations / 111 files |
| `FullBackupTests` | ✅ 29/29 |
| `just check-perf` | ⚠️ 13/14; `fixturePopulationTimingGate` is a known pre-existing local bottleneck (fails locally on clean `dev` too) |

## Post-merge cleanup

- Closed superseded stacked PRs (#80, #82, #84).
- Deleted stale worktrees:
  - `/Users/roman/.codex/worktrees/cash-runway-arch-phase-1` (`codex/arch-phase-1-cleanup`)
  - `/Users/roman/.codex/worktrees/cash-runway-arch-phase-4` (`backup/codex-arch-phase-4-performance-before-restack`)
