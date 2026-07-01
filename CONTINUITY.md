# Continuity Ledger

## Current Snapshot

- Branch: `codex/market-rate-projection`
- Worktree: `/Users/roman/.codex/worktrees/cash-runway-currency-foundation-dev`
- Focus: market-rate foundation and currency-display cleanup for PR #90.
- Local changes this turn:
  - Fixed the remaining failing fallback test to pass `officialClient: nbu`.
  - Added live-shape coverage for Monobank, NBU, and PrivatBank public rate clients.
  - Added a repository seam and UI checks for wallet-currency editability.
  - Wired transaction draft and wallet creation flows to carry the correct default currency.

## Validation

- `just test-filter PublicExchangeRateClientTests` ✅
- `just test-filter CurrencyFoundationTests` ✅
- `just check-unit-parallel` ✅
- `just check-integration` ✅
- `just build` ✅
- `just check` ⚠️ still known-fails on `CashRunwayPerformanceTests.fixturePopulationTimingGate` from the pre-existing >30s benchmark

## Current Snapshot

- Branch: `codex/market-rate-projection`
- Worktree: `/Users/roman/.codex/worktrees/cash-runway-currency-foundation-dev`
- Focus: finish the market-rate foundation work with the explicit official-client fallback test contract.
- Local change made in this turn: `CompositeBankMidpointRateProviderTests.missingPublicBankRatesFallBackToNbuOfficial` now passes `officialClient: nbu`.

## Validation

- `just test-filter CompositeBankMidpointRateProviderTests` ✅
- `just check-unit-parallel` ✅
- `just check-integration` ✅ on rerun after one transient failure
- `just check` ⚠️ failed only on `CashRunwayPerformanceTests.fixturePopulationTimingGate` because elapsed time exceeded 30 seconds
- `just check` simulator build fallback ✅

## Snapshot — `codex/market-rate-projection` branch

**Base:** `codex/currency-foundation-dev` (PR #87, stashed uncommitted worktree edits preserved).  
**Branch:** `codex/market-rate-projection` adds wallet-native currency selection UI and market-rate projection on top of PR #87's currency foundation.

## What was implemented

- Added `ExchangeRateBasis`, `MarketRatePolicy`, `WalletValueProjection`, `WalletValueProjectionProvider` in `Sources/CashRunwayCore/ExchangeRateBasis.swift`.
- Added `SupportedCurrency` enum in `Sources/CashRunwayCore/SupportedCurrency.swift`.
- Implemented public rate clients conforming to PR #87's `PublicExchangeRateClient`:
  - `MonobankPublicRateClient`
  - `PrivatBankPublicRateClient`
  - `NBUOfficialRateClient`
- Implemented `CompositeBankMidpointRateProvider` conforming to PR #87's `ExchangeRateProviding`.
- Implemented `WalletValueProjectionService` for UAH-pivot cross-currency wallet balance projection.
- Ported UI:
  - `WalletEditorView` currency picker (disabled when balance is non-zero; repository still enforces hard block).
  - `WalletManagementView` uses `model.defaultCurrencyCode` for new wallets.
  - `SettingsView` Main Currency row opens a new `CurrencySettingsView` (embedded in `SettingsView.swift` to avoid `pbxproj` edits).
  - `Editors.swift` inherits transaction currency from selected wallet and filters transfer destinations to same-currency wallets.
- Added `AppModel.defaultCurrencyCode`, `reportingCurrencyCode`, and `saveCurrencyPreferences(_:)`.
- Added tests:
  - `WalletValueProjectionServiceTests` (6 tests)
  - `CompositeBankMidpointRateProviderTests` (4 tests)
- Extended `WalletBuilder` with `with(currencyCode:)`.

## Validation

| Gate | Result |
|---|---|
| `swift build --target CashRunwayCore` | ✅ |
| `just build` | ✅ BUILD SUCCEEDED |
| `just lint` | ✅ 0 violations / 122 files |
| `swift test --filter "WalletValueProjectionServiceTests\|CompositeBankMidpointRateProviderTests\|CurrencyFoundationTests"` | ✅ 35/35 |
| `swift test --filter "WalletCategoryTests"` | ✅ 14/14 |
| `just check-unit-parallel` | ⚠️ timed out (>15 min); aborted to avoid blocking |
| `just check-integration` | ⏭️ skipped (unit gate timeout) |

## Stash

`git stash` contains PR #87 uncommitted worktree edits stashed before the market-rate layer was applied. To restore: `git stash pop` on `codex/market-rate-projection`.

## Next steps

1. Restore/pop PR #87 stash and integrate if those edits are still needed.
2. Re-run full `just check-unit-parallel` and `just check-integration` when time permits.
3. Decide whether to open a PR from `codex/market-rate-projection` into `codex/currency-foundation-dev` or wait until PR #87 lands.
4. Consider adding a `CurrencyConverter` conforming to `CurrencyConverting` for non-wallet conversions in a follow-up.

## Architecture improvements — all phases integrated (legacy)

### Phase 1: cleanup & foundation — DONE
- Branch: `codex/arch-phase-1-cleanup`
- Split `Editors.swift` (2266→937) and `DashboardView.swift` (1658→638) into per-view files
- Removed deprecated `appendImportedTransactions`/`finalizeImport` CSV APIs
- Replaced DEBUG-gated `NSLog` with `OSLog Logger` + privacy annotations
- Added `Scripts/check-no-ungated-logging.sh` CI gate
- Documented migration-identifier permanence invariant; added `MigrationIntegrityTests.migrationIdentifierSetIsStable`

### Phase 2: persistence/domain separation — DONE
- Branch: `codex/arch-phase-2-extraction`
- Split `CashRunwayRepository.swift` (4204→2263 lines, 46% reduction) into focused files
- Introduced `protocol CashRunwayRepositorying` (57 methods)
- `AppModel.repository`, `BackgroundWork`, `BankSyncService`, `MonobankConnectionService`, `BankSyncCoordinator` depend on `any CashRunwayRepositorying`
- Added `CashRunwayRepositoryingTests` — mock conformance without `DatabaseManager`

### Phase 3: privacy/security hardening — DONE
- Branch: `codex/arch-phase-3-security-hardening`
- Added `com.apple.developer.default-data-protection` entitlement with `NSFileProtectionComplete`
- Added `FileProtectionService`, `ProtectedDataMonitor`, protected-data gating for DB/bank sync/CSV/backup operations
- Added `v6_bank_raw_json_ttl` migration: nullable `raw_json`, redacted audit payload, 30-day TTL purge
- Switched Monobank validator and `FeedbackReport` to ephemeral `URLSession`
- Removed `AppLockStore`, updated `PLAN.md` reference
- Added `DataProtectionTests` and `RawPayloadPurgeTests`
- **Release gate:** physical-device rehearsal required before shipping Phase 3 security behavior

### Phase 3.5: protocol cleanup — DONE
- Branch: `codex/arch-phase-3.5-protocol-cleanup`
- Added `CSVImportServicing` protocol; `CSVService: CSVImportServicing` and `BackupService: BackupServicing`
- Updated `CashRunwayAppModel` and `BackgroundWork` to depend on `any CSVImportServicing` / `any BackupServicing`
- Narrowed `AppModel.repository` from `public var` to `private let`
- Extracted `ProtectedDataCache`, fixed cold-cache issue, added `@unchecked Sendable` guard checks

### Phase 4: performance — DONE
- Branch: `codex/arch-phase-4-performance` (rebuilt on top of `codex/arch-improvements`, replacing the stale Phase-2-based branch)
- Added wallet-scoped v7 aggregate migrations:
  - `v7_monthly_category_spend_wallet_kind_income`
  - `v7_monthly_label_spend_wallet`
- Updated `overviewSnapshot` and dashboard top-categories to filter by `wallet_id`
- Added `offset` to `TransactionQuery` for timeline pagination
- Implemented per-row import fingerprint/semantic duplicate checks
- Implemented chunked `rebuildFTS` and bulk `rebuildMonths`
- Extracted `PersistenceHelpers.swift` for shared `tableExists`/`columnExists`
- **Bug fix:** `rebuildMonths` now calls `recomputeWalletBalances(_:)` so backup restore preserves `current_balance_minor`

## Validation on `codex/arch-improvements`

| Gate | Result |
|---|---|
| `Scripts/pre-flight.sh` | ✅ |
| `just build` | ✅ BUILD SUCCEEDED |
| `just check-unit-parallel` | ✅ 58/58 |
| `just check-integration` | ✅ 434/434 |
| `just lint` | ✅ 0 violations / 111 files |
| `FullBackupTests` | ✅ 29/29 |
| `just check-perf` | ⚠️ 13/14; `fixturePopulationTimingGate` is a known pre-existing bottleneck (fails locally on clean `dev` too) |

## CI status

PR #86 full `iOS CI` workflow is now green (run `28397532095`).

Earlier run `28396573815` failed because `FileProtectionService.protect` called
`setAttributes([.protectionKey: .complete])` on macOS SwiftPM tests, where
`NSFileProtectionComplete` is unsupported and returns `EINVAL`; the DEBUG
`assertionFailure` then crashed the test runner. Fixed in commit `b6c6cc7` by
wrapping the attribute application in `#if canImport(UIKit)` and no-oping on
non-UIKit platforms. iOS behavior and loud DEBUG failure are unchanged.

## Next steps

1. Merge PR #86 into `dev`.
2. Close the superseded stacked PRs (#80, #82, #84) if not already closed.
3. Schedule physical-device rehearsal before releasing Phase 3 security changes.
4. Delete stale worktrees after merge:
   - `/Users/roman/.codex/worktrees/cash-runway-arch-phase-1` (was `codex/arch-phase-3.5-protocol-cleanup`)
   - `/Users/roman/.codex/worktrees/cash-runway-arch-phase-4` (now `backup/codex-arch-phase-4-performance-before-restack` exists; can be removed after merge)
5. Begin Phase 5 (consent-gated LLM-agent access) design/scoping.

## Open questions for product/security

See `docs/ARCHITECTURE_AUDIT.md`.
