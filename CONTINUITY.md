# Continuity Ledger

## Session: Testing roadmap — persistence and idempotency regression tests

Branch: `testing-roadmap-priority-tests`
Worktree: `~/.codex/worktrees/cash-runway-testing-roadmap-priority-tests`
<<<<<<< Updated upstream
PR: https://github.com/romanr111/cash-runway/pull/71 (ready for review)
Commits: 4e7345f, 3060e0b

## Validation
- swift test: 398 tests, 0 failures
- just check-perf: 14 tests, 0 failures
- just build: BUILD SUCCEEDED
- diff -rq: core trees identical

## Changed files (13)
- Sources/CashRunwayCore/DatabaseManager.swift + mirror
- Sources/CashRunwayCore/CashRunwayRepository.swift + mirror
- Tests/CashRunwayCoreTests/MigrationIntegrityTests.swift
- Tests/CashRunwayCoreTests/DatabaseKeyMismatchTests.swift
- Tests/CashRunwayCoreTests/DatabaseKeyStartupMatrixTests.swift
- Tests/CashRunwayCoreTests/RecurringIdempotencyTests.swift
- Tests/CashRunwayCoreTests/RecurringCalendarBoundaryTests.swift
- Tests/CashRunwayCoreTests/MonobankImportRollbackTests.swift
- Tests/CashRunwayCoreTests/ImportConcurrencyRecoveryTests.swift
- .github/workflows/ios-ci.yml
- CONTINUITY.md

## Excluded
- Forecasting (no production code)
- Immutable historical fixtures (follow-up)
- CI coverage policy (follow-up)
