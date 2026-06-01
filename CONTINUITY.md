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

- Goal: Keep the category merge remap lookup fix published while preserving the current mainline release-automation continuity.
- Success criteria: PR `#24` stays ready for review on top of current `origin/main`, category lookup reuses merged categories, and the ledger stays synchronized after the branch is reconciled.
- Current state: The category merge remap lookup fix was published on PR `#24`, the PR was marked ready for review, and the branch hit a merge conflict while being brought up to current `origin/main`.
- Next action: Resolve the remaining merge conflict in `CONTINUITY.md`, repush the branch, and recheck mergeability.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/openclaw/Development/Cash_Runway`
- Working directory: `/Users/openclaw/.codex/tmp/cash-runway-pr24-review-fix`
- Branch: `codex/pr24-review-fix-2`
- Base branch: `origin/main`
- Worktree reason: review
- Merge status: not-merged

## Working set

- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Tests/CashRunwayCoreTests/BankCategoryMapperTests.swift`
- `Tests/CashRunwayCoreTests/CSVEdgeCaseTests.swift`
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

## Receipts

- 2026-06-01 [MERGE] Resolved the only conflict in `CONTINUITY.md` and created merge commit `d8283fd`.
- 2026-06-01 [COMMIT] `d9c269e` — ci: add tag-triggered release workflow and altstore.json source
- 2026-06-01 [COMMIT] `9c3bf28` — Add SideStore release workflow and icon; update agent configs and continuity
- 2026-06-01 [PR] `#24` — https://github.com/romanr111/cash-runway/pull/24
