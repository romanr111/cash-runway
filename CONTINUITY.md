# Continuity Ledger

## Snapshot

**Branch:** `release/v0.1.4`
**Worktree:** `/Users/roman/.codex/worktrees/cash-runway-pr-92-review-comments`
**PR:** https://github.com/romanr111/cash-runway/pull/92 — Release v0.1.4 into `main`
**Base/head checked:** `main` `82279fc`, `release/v0.1.4` `7722ab1`

## Current State

- Local no-commit merge of `origin/main` into `release/v0.1.4` has all conflicts resolved and staged.
- No commit or push has been made.
- GitHub still reports PR #92 as `DIRTY` / `CONFLICTING` because the local merge resolution is uncommitted and unpushed.
- Review-fix patch is preserved at `/tmp/cash-runway-pr92/review-fixes-before-main-merge.patch`.
- Project-file conflict backup is preserved at `/tmp/cash-runway-pr92/project.pbxproj.conflicted.bak`.

## Decisions

- Resolve release-vs-main conflicts to the release-side v0.1.4 content because `main` contains v0.1.3 plus the Settings row tap-target fix, and the release branch already supersedes those changes.
- Keep `AppHost/Info.plist` release metadata: `CFBundleShortVersionString` `0.1.4`, `CFBundleVersion` `273`.
- Keep the release-side SwiftUI/UIVM extraction and project references.
- Preserve the full-width Settings `moreRow` tap target via `.contentShape(.interaction, Rectangle())`.
- Preserve review fixes:
  - monthly overview month key must start inside the approved date scope,
  - Agent wallet and transaction DTO money values preserve source currency codes,
  - transaction deletion summary income uses signed `amount_minor`.
- Signed income impact must remain visible in the delete preview and accessibility summary even when `incomeMinor` is negative.

## Working Set

- `CONTINUITY.md`
- `Sources/CashRunwayCore/AgentAccess/AgentAccessService.swift`
- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Sources/CashRunwayCore/DeletePeriod.swift`
- `Sources/CashRunwayUI/DeleteTransactionsView.swift`
- `Tests/CashRunwayCoreTests/AgentAbuseBoundaryTests.swift`
- `Tests/CashRunwayCoreTests/AgentPermissionBoundaryTests.swift`
- `Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift`

## Validation

- `git diff --check`: passed.
- `git diff --cached --check`: passed.
- `Scripts/verify-pbxproj.sh`: skipped direct execution, file is not executable in this worktree.
- `bash Scripts/verify-pbxproj.sh`: passed.
- `Scripts/pre-flight.sh`: passed.
- `just test-filter AgentAbuseBoundaryTests`: passed.
- `just test-filter AgentPermissionBoundaryTests`: passed.
- `just test-filter BulkDeleteTransactionsTests`: passed after signed-income UI impact follow-up.
- `just test-filter FullBackupTests`: passed.
- `just test-filter MigrationIntegrityTests`: passed.
- `just test-filter WalletCategoryTests`: passed.
- `just check-agent`: passed.
- `just check-isolated`: passed.
- `just build`: passed.
- `just graph-sync`: passed after signed-income UI impact follow-up.
- `gh pr view 92 --json mergeStateStatus,mergeable,headRefOid,baseRefOid`: remote still `DIRTY` / `CONFLICTING` until local resolution is committed and pushed.

## Notes

- Known build warnings only: duplicate `AppHost/uk.lproj/InfoPlist.strings` project reference, signed SQLCipher binary not stripped, AppIntents metadata skipped.
- XCUITest/E2E was not run per repo policy.
