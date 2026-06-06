<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true true.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Make PR `#24` merge-ready while preserving category-merge data safety.
- Success criteria: Category merge preserves transactions while only updating category references, remap lookups follow active destinations, the category merge UI communicates data preservation and success, current `origin/main` merges cleanly, and required validation passes.
- Current state: Category merge now avoids full FTS and aggregate rebuilds, syncing only moved transactions/search rows and source/destination category spend deltas, and local validation passed.
- Next action: Review, commit, and push the category merge progress UI update for PR `#24`.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-category-merge-fix`
- Branch: `codex/category-merge-fix`
- Base branch: `origin/main`
- Worktree reason: review
- Merge status: not-merged

## Working set

- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Sources/CashRunwayUI/AppModel.swift`
- `Sources/CashRunwayUI/Editors.swift`
- `Tests/CashRunwayCoreTests/BankCategoryMapperTests.swift`
- `Tests/CashRunwayCoreTests/CSVEdgeCaseTests.swift`
- `Tests/CashRunwayCoreTests/DatabaseTransactionSafetyTests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-06-01 [CODE] Published PR `#24` category merge remap lookup fixes and regression coverage for built-in MCC fallback and CSV merged-name reuse.
- 2026-06-01 [CODE] Fixed CSV test verification through `transactionDraft(id:)` and made `resolvedCategoryID` follow remap chains to active destinations in both mirrored core trees.
- 2026-06-01 [MERGE] Merged newer `origin/main` through `f5d7ad4` into `codex/category-merge-fix`; only `CONTINUITY.md` conflicted.
- 2026-06-01 [VALIDATED] Focused category merge/import tests, full `swift test`, core mirror diff, `git diff --check`, iPhone 17 clean build, install/launch smoke, and app error/fault log scan passed.
- 2026-06-01 [CI] PR `#24` reported mergeable (`CLEAN`); Static Analysis, Unit Tests, and Integration Tests passed; UI E2E skipped per workflow policy.
- 2026-06-02 [TEST] Added category-merge regression coverage that records source/destination transaction counts and sums before merge, then asserts the destination receives their combined count/sum while global count/sum stay unchanged.
- 2026-06-02 [UI] Replaced the basic category merge form with a designed merge flow showing source/destination category cards, transaction-count preview, data-preservation copy, and an in-sheet success confirmation after merge.
- 2026-06-02 [MERGE] PR `#23` UI refresh landed on `main` at `ca1c3fa`; merging it into PR `#24` auto-merged source/test files and conflicted only in `CONTINUITY.md`.
- 2026-06-02 [VALIDATED] Post-`ca1c3fa` main merge passed focused category merge/import tests, core mirror diff, diff check, full `swift test`, iPhone 17 clean build, install/launch smoke, and app error/fault log scan.

## Receipts

- 2026-06-01 [PR] `#24` — https://github.com/romanr111/cash-runway/pull/24
- 2026-06-01 [MAIN] `fix/side-store-concurrency` was merged into `main` at `db9a1e4`; follow-up continuity update landed at `f5d7ad4`.
- 2026-06-02 [MAIN] PR `#23` UI refresh merged into `main` at `ca1c3fa`.
- 2026-06-02 [COMMIT] `0ea6ddb` — test: verify category merge preserves transaction totals
- 2026-06-02 [COMMIT] `0601948` — feat: add category merge success flow
- 2026-06-02 [TEST] Category merge UI update `swift test --filter 'DatabaseTransactionSafetyTests/categoryMerge|BankCategoryMapperTests|CSVEdgeCaseTests/importReusesMergedDestinationCategoryByName'` passed 14 tests.
- 2026-06-02 [TEST] Category merge UI update `swift test` passed 244 tests in 23 suites.
- 2026-06-02 [BUILD] Category merge UI update iPhone 17 clean build ended with `** BUILD SUCCEEDED **`; SQLCipher strip and AppIntents metadata warnings matched existing build noise.
- 2026-06-02 [SMOKE] Installed and launched latest `dev.roman.cashrunway` on iPhone 17; severity-filtered app log scan found no error/fault entries.
- 2026-06-02 [TEST] Post-`ca1c3fa` `swift test --filter 'DatabaseTransactionSafetyTests/categoryMerge|BankCategoryMapperTests|CSVEdgeCaseTests/importReusesMergedDestinationCategoryByName'` passed 14 tests.
- 2026-06-02 [TEST] Post-`ca1c3fa` `swift test` passed 251 tests in 24 suites.
- 2026-06-02 [BUILD] Post-`ca1c3fa` iPhone 17 clean build ended with `** BUILD SUCCEEDED **`; SQLCipher strip and AppIntents metadata warnings matched existing build noise.
- 2026-06-02 [SMOKE] Post-`ca1c3fa` install and launch returned `dev.roman.cashrunway: 10918`; severity-filtered app log scan found no error/fault entries.
- 2026-06-06 [UI] Added a staged progress panel and disabled in-flight controls when tapping Merge Categories before the existing success confirmation.
- 2026-06-06 [TEST] Category merge progress UI update `swift test --filter 'DatabaseTransactionSafetyTests/categoryMerge'` passed 7 tests.
- 2026-06-06 [BUILD] Category merge progress UI update iPhone 17 clean build ended with `** BUILD SUCCEEDED **`; SQLCipher strip and AppIntents metadata warnings matched existing build noise.
- 2026-06-06 [SMOKE] Installed and launched latest `dev.roman.cashrunway` on iPhone 17; severity-filtered app log scan found no error/fault entries.
- 2026-06-06 [NOTE] Extra broad `swift test` was stopped after hanging with partial output; it is not counted as a passing validation.
- 2026-06-06 [PERF] Removed fixed category merge progress UI waits and replaced full merge-time FTS rebuild with targeted search sync for moved transactions only.
- 2026-06-06 [PERF] Replaced full month aggregate rebuilds during category merge with source/destination category spend deltas plus affected-month budget snapshot recompute.
- 2026-06-06 [TEST] Added category-merge FTS regression coverage for old/destination category search terms after merge.
- 2026-06-06 [VALIDATED] Real category merge speedup passed 15 focused category merge/remap/import tests, core mirror diff, diff check, iPhone 17 clean build, install/launch smoke; launch log showed only Apple app-launch measurement CA Event errors, no crash/fatal entries.
- 2026-06-06 [REVIEW] Detailed code review found no blocking or important findings; full `swift test` passed 252 tests in 24 suites, core mirror diff and diff check passed, and iPhone 17 clean build ended with `** BUILD SUCCEEDED **`.
