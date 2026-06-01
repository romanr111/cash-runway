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
- Success criteria: Category merge preserves transactions while only updating category references, remap lookups follow active destinations, CI/unit compile blockers are fixed, core mirrors stay identical, current `origin/main` merges cleanly, and required validation passes.
- Current state: The CSV test compile blocker was fixed, chained remap lookup was repaired with focused red/green coverage, and local focused tests passed.
- Next action: Merge current `origin/main`, resolve any continuity conflict, then run the full validation gates.
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
- `Tests/CashRunwayCoreTests/BankCategoryMapperTests.swift`
- `Tests/CashRunwayCoreTests/CSVEdgeCaseTests.swift`
- `Tests/CashRunwayCoreTests/DatabaseTransactionSafetyTests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-06-01 [CODE] Added `ios-release.yml` for tag-triggered IPA builds and automatic `altstore.json` updates pushed to main.
- 2026-06-01 [CODE] Added `sidestore-release.yml` for manual SideStore builds with GitHub Pages deployment.
- 2026-06-01 [CODE] Added `altstore.json` SideStore source manifest and `sidestore/icon.png` app icon.
- 2026-06-01 [REVIEW] Fixed missing icon URL, stale source push to main, tint color inconsistency, Python deprecation, and stale continuity ledger.
- 2026-06-01 [CODE] Published the category merge remap lookup fix on PR `#24`.
- 2026-06-01 [TEST] Added regression coverage for merged built-in MCC fallback and CSV name reuse.
- 2026-06-01 [VALIDATED] Mirror diff and `git diff --check` passed; targeted `swift test` compiled touched files but still hit the unrelated `no such module 'Testing'` failure in `AppLockAndLocationTests.swift`.
- 2026-06-01 [PR] Updated PR `#24` title to `Fix category merge remap lookups` and marked it ready for review.
- 2026-06-01 [TEST] Reproduced the CI compile blocker from `CSVEdgeCaseTests.importReusesMergedDestinationCategoryByName` using the nonexistent `TransactionListItem.categoryID`.
- 2026-06-01 [TEST] Added a failing chained-remap BankCategoryMapper regression for `Restaurants -> Groceries -> Shopping`.
- 2026-06-01 [CODE] Fixed CSV test verification through `transactionDraft(id:)` and made `resolvedCategoryID` follow remap chains to active destinations in both mirrored core trees.
- 2026-06-01 [VALIDATED] `swift test --filter BankCategoryMapperTests`, `swift test --filter CSVEdgeCaseTests/importReusesMergedDestinationCategoryByName`, and core mirror diff passed.

## Receipts

- 2026-06-01 [MERGE] Resolved the only conflict in `CONTINUITY.md` and created merge commit `d8283fd`.
- 2026-06-01 [COMMIT] `d9c269e` — ci: add tag-triggered release workflow and altstore.json source
- 2026-06-01 [COMMIT] `9c3bf28` — Add SideStore release workflow and icon; update agent configs and continuity
- 2026-06-01 [TEST] Red `swift test --filter BankCategoryMapperTests` failed only on `builtInMCCFallbackFollowsChainedMergedDestinationCategory`, resolving archived Groceries instead of active Shopping.
- 2026-06-01 [TEST] Green `swift test --filter BankCategoryMapperTests` passed 6 tests.
- 2026-06-01 [TEST] Green `swift test --filter CSVEdgeCaseTests/importReusesMergedDestinationCategoryByName` passed.
- 2026-06-01 [PR] `#24` — https://github.com/romanr111/cash-runway/pull/24
