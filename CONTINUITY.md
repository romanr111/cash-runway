# Continuity Ledger

## Session: Testing roadmap — persistence and idempotency regression tests

Branch: `testing-roadmap-priority-tests`
Worktree: `~/.codex/worktrees/cash-runway-testing-roadmap-priority-tests`
PR: https://github.com/romanr111/cash-runway/pull/71

## Changed files (9)

### Production (canonical + mirror)
- `Sources/CashRunwayCore/DatabaseManager.swift` — migration refactor + test-only init
- `Modules/.../DatabaseManager.swift` — mirror
- `Sources/CashRunwayCore/CashRunwayRepository.swift` — recurring post idempotency guard
- `Modules/.../CashRunwayRepository.swift` — mirror

### Tests
- `Tests/CashRunwayCoreTests/MigrationIntegrityTests.swift` — generated encrypted previous-schema migration test
- `Tests/CashRunwayCoreTests/DatabaseKeyMismatchTests.swift` — wrong-key non-destructive failure test
- `Tests/CashRunwayCoreTests/RecurringIdempotencyTests.swift` — sequential double-post idempotency test
- `Tests/CashRunwayCoreTests/MonobankImportRollbackTests.swift` — batch rollback + corrected retry + idempotency test

### CI
- `.github/workflows/ios-ci.yml` — source-consistency + app-build preflight job

### Docs
- `CONTINUITY.md`

## Validation
- 384 tests (removed RunwayForecastTests which tested a non-production RunwayCalculator; merged correctedImport into monobank rollback test)
- swift test: 384 tests, 0 failures
- just check-perf: 14 tests, 0 failures
- just build: BUILD SUCCEEDED
- diff -rq: core trees identical