# Continuity Ledger

## Snapshot - PR #81 merge with dev

Branch: `codex/csv-import-dedup-category`
Worktree: `~/.codex/worktrees/cash-runway-csv-dedup-category`
Target: merge into `dev` via PR #81 squash merge
Status: merge from `origin/dev` into PR branch resolved locally. Validation passed; commit/push/PR squash merge pending.

## Current Goal

Resolve PR #81 conflicts with `dev`, validate the merged branch, push the conflict-resolution commit, then squash merge PR #81 into `dev`.

## PR #81 Scope

Prevent duplicated transactions when reimporting the same bank/CSV data after category, rule, mapping, or app-version changes, and protect NULL-fingerprint legacy rows.

Key behavior:
- `importFingerprint` no longer hashes resolved category name.
- Fingerprinted CSV imports dedupe by full timestamp precision.
- Semantic fallback is scoped to NULL-fingerprint manual/bank_sync legacy rows.
- Cross-source collapse of fingerprinted import rows is avoided.

Touched PR files:
- `Sources/CashRunwayCore/CSVSupport.swift`
- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Tests/CashRunwayCoreTests/CSVIdempotencyTests.swift`
- `Tests/CashRunwayCoreTests/MigrationIntegrityTests.swift`

## Incoming dev Context

Incoming `origin/dev` includes:
- Bulk delete transactions from PR #75, squash commit `dd941fe`.
- Delete All History UI/success-confirmation polish.
- Architecture audit document at `docs/ARCHITECTURE_AUDIT.md`.

Relevant incoming files:
- `AppHost/Localizable.xcstrings`
- `PLAN.md`
- `Sources/CashRunwayCore/DeletePeriod.swift`
- `Sources/CashRunwayCore/L10n.swift`
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift`
- `Sources/CashRunwayUI/DeleteTransactionsView.swift`
- `Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift`
- `docs/ARCHITECTURE_AUDIT.md`

## Merge Notes

- `CONTINUITY.md` was the only conflicted file during `git merge --no-commit --no-ff origin/dev`.
- `Sources/CashRunwayCore/CashRunwayRepository.swift` auto-merged with incoming `.allHistory` handling in `deletePeriodPredicate`.
- No secrets, generated reporting secrets, project files, lock files, or entitlements were in the conflicted set.

## Validation Receipts

Before this merge, PR #81 had local green targeted gates:
- `swift build --target CashRunwayCore`: passed
- `just test-filter CSVIdempotencyTests`: passed
- `just test-filter MigrationIntegrityTests`: passed

Incoming `dev` receipts recorded by prior sessions:
- `just test-filter BulkDeleteTransactionsTests`: passed
- `just build`: passed
- `swiftlint --strict` on changed files: passed

Validation after this conflict resolution:
- `just test-filter CSVIdempotencyTests`: passed, 32 tests
- `just test-filter MigrationIntegrityTests`: passed, 2 tests
- `just test-filter BulkDeleteTransactionsTests`: passed
- `git diff --check`: passed
- `just build`: passed, BUILD SUCCEEDED

## Skipped Gates

- XCUITest/E2E not run; repo instructions disallow unless explicitly requested.
- Physical-device rehearsal not run; this is not a release/SideStore task.
