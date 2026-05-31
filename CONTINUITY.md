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

- Goal: Fix category merging so duplicate categories such as `Restaurant` can be merged into `Restaurants` safely.
- Success criteria: Merge moves transactions and relevant category references, hides the source category, keeps the destination active, preserves aggregate/search consistency, mirrors core changes, and passes required iOS validation gates.
- Current state: Category merge was fixed and draft PR `#24` was opened from `codex/category-merge-fix` with required unit/build/boot validation passing.
- Next action: Monitor PR `#24` CI and address any review feedback.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-category-merge-fix`
- Branch: `codex/category-merge-fix`
- Base branch: `origin/main`
- Worktree reason: isolated-feature
- Merge status: not-merged

## Working set

- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Tests/CashRunwayCoreTests/DatabaseTransactionSafetyTests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-31 [PLAN] Category merge repair plan selected: move all references, archive the source category, and use TDD.
- 2026-05-31 [SETUP] Created isolated worktree `/Users/roman/.codex/worktrees/cash-runway-category-merge-fix` on branch `codex/category-merge-fix`.
- 2026-05-31 [TEST] Added failing category merge tests for duplicate transaction merge, recurring/bank rule references, invalid pairs, and hidden destinations; then made them pass.
- 2026-05-31 [TEST] Added review follow-up coverage for category remap and audit persistence.
- 2026-05-31 [IMPLEMENTED] `mergeCategory(oldCategoryID:into:)` now validates category pairs, moves transaction/recurring/bank-rule references, archives the source category, records remap/audit entries, and rebuilds derived data.
- 2026-05-31 [VALIDATED] Focused merge tests, mirror diff, `git diff --check`, full `swift test`, required iPhone 17 clean build, and simulator boot/log smoke passed.
- 2026-05-31 [SMOKE] Booted app on iPhone 17 and opened Timeline, Wallets, More, Categories, and the Merge Categories sheet without crash.
- 2026-05-31 [PR] Opened draft PR `#24` from `codex/category-merge-fix` into `main`.

## Receipts

- 2026-05-31 [DECISION] Source categories should be hidden after merge; category references should move beyond transactions where active runtime behavior depends on them.
- 2026-05-31 [TEST] `swift test` passed 236 tests in 22 suites.
- 2026-05-31 [BUILD] `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -5` ended with `** BUILD SUCCEEDED **`.
- 2026-05-31 [LOG] Simulator runtime log scan found no crash/error/warning matches; XcodeBuildMCP reported the existing SQLCipher signed-binary strip warning during build-run.
- 2026-05-31 [PR] `#24` — https://github.com/romanr111/cash-runway/pull/24
