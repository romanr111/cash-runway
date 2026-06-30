# Continuity Ledger

## Snapshot — `codex/arch-improvements` integration branch

**Canonical integration PR:** https://github.com/romanr111/cash-runway/pull/86 (`codex/arch-improvements → dev`)

All architecture phases are now stacked on this branch and pushed to origin.

## Architecture improvements — all phases integrated

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

1. ~~Merge PR #86 into `dev`.~~ **DONE** — merged as `9f3ca21`.
2. Close the superseded stacked PRs (#80, #82, #84) if not already closed.
3. Schedule physical-device rehearsal before releasing Phase 3 security changes.
4. Delete stale worktrees after merge:
   - `/Users/roman/.codex/worktrees/cash-runway-arch-phase-1` (was `codex/arch-phase-3.5-protocol-cleanup`)
   - `/Users/roman/.codex/worktrees/cash-runway-arch-phase-4` (now `backup/codex-arch-phase-4-performance-before-restack` exists; can be removed after merge)
5. Begin Phase 5.0 (AgentAccess foundation) on `codex/arch-phase-5-agent-access-design`.

## Phase 5.0: AgentAccess foundation — COMPLETE (local only)

**Branch:** `codex/arch-phase-5-agent-access-design` (local only; not pushed, no PR)
**Base:** `dev` after PR #86 merge (`9f3ca21`)

### What landed
- `Sources/CashRunwayCore/AgentAccess/` with the full foundation:
  - `AgentCapability.swift` — read-only v1 capability set
  - `AgentScope.swift` — explicit `AgentWalletScope`/`AgentDateScope`/`AgentScope` (conservative defaults)
  - `AgentSession.swift` — short-lived, revocable, fail-closed session
  - `AgentConsentGrant.swift` — user-approved grant with 15-min TTL clamp and `v1.0` consent version
  - `AgentAccessError.swift` — safe-to-surface typed errors
  - `AgentDTOs.swift` — dedicated `Agent*DTO` response types with opaque `tx_NNN` handles
  - `AgentRedactionService.swift` — hard-blocks forbidden fields and redacts IBAN/card/account patterns
  - `AgentAuditLog.swift` — `AgentAuditEntry` + `AgentAuditLogging` + in-memory fake
  - `AgentSessionStoring.swift` — session store contract + in-memory fake
  - `AgentAccessService.swift` — concrete `AgentAccessServicing` using only narrow repository protocols
- `Tests/CashRunwayCoreTests/`:
  - `AgentPermissionBoundaryTests.swift` (7 tests)
  - `AgentRedactionTests.swift` (8 tests)
  - `AgentRedactionServiceUnitTests.swift` (3 tests)
  - `AgentAuditContractTests.swift` (3 tests)
  - `AgentTestMocks.swift` (fakes + helpers)

### Design notes
- No LLM, no UI, no DB migration, no write capabilities, no `DatabaseManager`/`dbQueue` access.
- Service depends only on `DashboardRepositorying`, `BankSyncRepositorying`, plus session/audit/redaction collaborators.
- Redaction uses deterministic string scanning (no `NSRegularExpression`) to be concurrency-safe and backtracking-free.
- Session store and audit log use `@unchecked Sendable` + `NSLock` with justification comments.
- In-memory fakes are intentionally non-isolated classes (not actors) to avoid actor hops in tests.

### Validation gates (all green)
| Gate | Result |
|---|---|
| `swift build --target CashRunwayCore` | BUILD SUCCEEDED |
| Targeted AgentAccess tests | 21/21 passed |
| `just check-unit-parallel` | 58/58 passed (includes new AgentAccess suites) |
| `just lint` | 0 violations / 126 files |
| `Scripts/check-no-ungated-logging.sh` | passed |
| `Scripts/check-unchecked-sendable.sh` | passed |
| `Scripts/pre-flight.sh` | OK (module wiring correct) |

### Bug found and fixed during implementation
A re-entrant `NSLock` deadlock in `FakeDashboardRepository.transactions` (called `walletName(for:)` while already holding the lock) caused Swift Testing to hang on any `readTransactions` call scoped to a single wallet. Fixed by computing the target wallet name before entering the locked region.

## Open questions for product/security

See `docs/ARCHITECTURE_AUDIT.md`.
