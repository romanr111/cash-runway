# Continuity Ledger

## Architecture Audit — Phase 1 (cleanup & foundation)

Status: Phase 1 complete on `codex/arch-phase-1-cleanup` (worktree `cash-runway-arch-phase-1`), rebased onto `dev` @ `f46f838`; verified (sim build + integration pass, 2 known CSV idempotency issues CI-excluded). Phases 2 (persistence/domain separation), 3 (privacy/security hardening), 4 (performance & benchmarks), and 5 (consent-gated LLM-agent access) pending. See `docs/ARCHITECTURE_AUDIT.md`.

> **Note:** Audit was generated from `dev` @ `fed7859`; rebased onto `dev` @ `dd941fe`. Audit findings reflect the codebase at the earlier baseline (the one intervening commit `dd941fe` added the bulk-delete-transactions feature, which does not materially affect the audit's findings).

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
- `.swiftlint.yml` rules; `XLSXConverter`, `MCCCategoryMapping`, `BankCategoryNameMapping`, `L10n`, `DateKeys`, `Money` internals.
- `CashRunway.xcodeproj/project.pbxproj` (not hand-edited per AGENTS.md).
- Nightly/release workflows beyond confirming existence.
