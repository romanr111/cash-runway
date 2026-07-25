# Continuity Ledger

## Snapshot

**Branch:** `cash-runway-project-skills`
**Worktree:** `/Users/roman/.codex/worktrees/cash-runway-project-skills`
**Task:** Project-local Cash Runway Codex skill packages
**Phase:** Ready to create PR into `main`

## Current State

- Copied six complete global skill packages to `.agents/skills/` with `rsync -a` and verified the complete package trees.
- The copied packages are `cash-runway-localization`, `cash-runway-persistence-change`, `cash-runway-pr-repair`, `cash-runway-release`, `cash-runway-vercel-reporting-api`, and `cash-runway-validation`.
- No copied package has a hard-coded reference to the old global skill directory.
- The six redundant global skill directories were moved to `/Users/roman/.Trash/codex-cash-runway-skills.r0yg5p/`; the project-local copies are now the only active copies.
- Commit `63faa0e` was rebased onto `origin/main`; inherited timeline commits are excluded from the PR.

## Working Set

- `CONTINUITY.md`
- `.agents/skills/cash-runway-localization/`
- `.agents/skills/cash-runway-persistence-change/`
- `.agents/skills/cash-runway-pr-repair/`
- `.agents/skills/cash-runway-release/`
- `.agents/skills/cash-runway-vercel-reporting-api/`
- `.agents/skills/cash-runway-validation/`

## Validation

- `just session-start`: passed in the new worktree; CodeGraph was initialized and pre-flight reported a clean checkout before this task's edits.
- `quick_validate.py`: passed for all six copied packages.
- `diff -qr`: passed for each global source package against its project-local copy.
- `git diff --check`: passed.
- Fresh `codex exec --strict-config` discovery: all six packages appeared as project-local in this worktree and none appeared in the `content_blocker` repository.

## Historical Snapshot - `origin/main` (SUPERSEDED 2026-07-25)

**Branch:** `release/v0.1.4`
**Worktree:** `/Users/roman/.codex/worktrees/cash-runway-pr-92-review-comments`
**PR:** https://github.com/romanr111/cash-runway/pull/92 - Release v0.1.4 into `main`
**Base/head checked:** `main` `82279fc`, `release/v0.1.4` `7722ab1`

- Local no-commit merge of `origin/main` into `release/v0.1.4` had all conflicts resolved and staged; GitHub still reported PR #92 as `DIRTY` / `CONFLICTING` until the resolution was pushed.
- Release decisions retained: version `0.1.4` / build `273`, SwiftUI/UIVM extraction and project references, full-width Settings `moreRow` tap target, month-key date-scope fix, source-currency Agent DTO values, and signed `amount_minor` income in the delete summary.
- Historical validation: `git diff --check`, `git diff --cached --check`, `bash Scripts/verify-pbxproj.sh`, `Scripts/pre-flight.sh`, targeted Agent/bulk-delete tests, `just check-agent`, `just check-isolated`, `just build`, and `just graph-sync` passed. XCUITest/E2E was not run.
