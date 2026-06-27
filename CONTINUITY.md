# Continuity Ledger

## Snapshot — CSV import dedup hardening (category-independent identity + semantic fallback)

Branch: `codex/csv-import-dedup-category`
Worktree: `~/.codex/worktrees/cash-runway-csv-dedup-category`
Base: `origin/dev` @ dd941fe
Status: implemented, all local gates green. Not committed/pushed (awaiting user instruction).

## Goal
Prevent duplicated transactions when reimporting the same bank/CSV data after
category/rule/mapping/app-version changes, and protect NULL-fingerprint legacy
rows. TDD-first: failing tests added, then smallest robust fix.

## Root cause
`importFingerprint` hashed `resolvedCategoryName` (mutable/import-derived:
user edits, bank rules, MCC mapping, localization, source-format detection).
A reimport that resolved the same financial event to a different category
produced a different fingerprint → duplicate insert.

## Fix (3 source edits)
- `Sources/CashRunwayCore/CSVSupport.swift`
  - Removed `categoryName` from `ImportFingerprintInput` + `importFingerprint`
    computation + all 3 call sites. Fingerprint now: source|wallet|kind|date|
    amount|merchant|note|currency (currency kept as a stable bank-fact
    differentiator per user decision).
  - `parseDate`: try full ISO8601 (with time) BEFORE date-only `[.withFullDate]`.
    The old order truncated ISO timestamps (e.g. Cash Runway exports) to
    date-only, which broke timestamp equality and made export reimports insert
    duplicates. Existing tests use `T00:00:00Z` (midnight) — no behavior change.
- `Sources/CashRunwayCore/CashRunwayRepository.swift`
  - `commitCSVImport`: loads `existingImportSemanticKeys` (all non-deleted
    transactions, regardless of source) and checks each prepared row against
    this set in addition to the fingerprint. New inserts also register their
    semantic key in the batch set (mirrors `seenFingerprints.insert`).
  - Semantic key: `walletID|kind|local_day_key|amountMinor|normalizedMerchant|
    normalizedNote`. Day-granularity (uses stored `local_day_key` / computed
    `DateKeys.dayKey`) to survive the export date-round-trip and timezone shifts.
    Excludes currency (no `transactions.currency` column to backfill from).

## Decisions (locked with user)
- Keep `currency` in the fast fingerprint; semantic fallback excludes it
  (covers algorithm-change + NULL-fingerprint cases; two rows identical except
  currency collapse only via the rare fallback path).
- Semantic fallback only, no backfill migration (avoids unique-index collisions
  on old rows differing only by category).
- Semantic key spans ALL non-deleted transactions (not just `source='import_csv'`)
  so export reimports of manual/bank-sync transactions also dedup.

## Tests (`Tests/CashRunwayCoreTests/CSVIdempotencyTests.swift`)
New: `importingSameCSVTwiceIsIdempotent`, `reimportAfterCategoryChangedIsIdempotent`,
`reimportCashRunwayExportIsIdempotent`, `oldTransactionsWithNullFingerprintProtectedBySemanticFallback`,
`duplicateRowsInSameCSVDoNotMultiplyWhenOnlyCategoryDiffers`,
`legitimateRepeatedPaymentsAreNotCollapsed` (guard against over-collapse),
`reimportAfterSoftDeleteReInserts` (guard: deleted rows don't permanently suppress reimport),
`crossSourceReimportCollapsesViaSemanticFallback` (characterizes intentional cross-source collapse),
`reimportMonobankCSVIsIdempotent`, `reimportPrivatBankCSVIsIdempotent` (format coverage).
Integration: `MigrationIntegrityTests.reimportAfterMigrationDedupesNullFingerprintLegacyRows`
(simulates old-schema DB with NULL fingerprint, full migration, reimport dedup).
Updated: removed 2 `withKnownIssue` wrappers (dedup now works); flipped
`legacyGenericCSVEmptyCategoryDoesNotMatchMappedCategoryRow` →
`...MatchesMappedCategoryRow` (new policy: category no longer distinguishes);
fixed `csvImportReportsDuplicateRows` first-import count (3 identical rows now
correctly collapse to 1 per requirement #5); flipped
`importStatementMatchesLegacyGenericCSVEmptyCategoryNoCurrency` precondition
`!=` → `==`; updated private `historicalImportFingerprint` helper to drop
category (matches new production algorithm).

## Validation (all ran successfully)
- `swift build --target CashRunwayCore`: passed
- `just check-unit-parallel`: 58/58 passed
- `just check-integration`: 413/413 passed
- `just check-perf`: 14/14 passed (incl. import timing gate)
- `just lint`: 0 violations (91 files)
- `just build` (iPhone 17 simulator): BUILD SUCCEEDED
- `CSVIdempotencyTests` (30 tests): all passed
- `MigrationIntegrityTests` (2 tests): all passed

## Skipped gates
- None skipped. No XCUITest/E2E per AGENTS.md. No physical-device rehearsal
  (not a release/SideStore task).

## Open / follow-ups
- Semantic fallback uses day-granularity: two legitimate same-day same-amount
  same-merchant transactions where BOTH have NULL fingerprints would collapse.
  Narrow edge case (NULL fingerprints only for pre-v3 imports or manual txns
  being re-imported). The fingerprint path protects all post-v3 imports at full
  timestamp precision. Documented as accepted trade-off.

## Freshness check (verify before next session)
- [ ] `git status --short` is clean (currently 3 modified files, uncommitted).
- [ ] Validation counts reflect the latest test run.

## Note
- The `origin/dev` ledger snapshots for other branches belong to separate
  worktrees and are intentionally not duplicated here.