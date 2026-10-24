# PR #124 — Conflict Resolution & Retarget Plan

**PR:** https://github.com/romanr111/cash-runway/pull/124 — `feat: export retrospective monthly totals as CSV/XLSX`
**Date:** 2026-10-24 · **Status:** planning only (no repo changes yet)

---

## Goal

Make PR #124 mergeable again and retarget its base from the now-merged
`feature/issue-121-usd-retrospective` branch to `origin/dev`, **without losing any
of the export feature work or the five post-review fixes**.

## Verified current state (git, 2026-10-24)

| Fact | Evidence |
|---|---|
| PR state: `OPEN`, mergeable `CONFLICTING`, mergeState `DIRTY` | `gh pr view 124` |
| Head: `origin/feature/issue-122-retrospective-export` @ `52803eb` | gh pr view |
| Base: `origin/feature/issue-121-usd-retrospective` @ `1e4052c` | gh pr view |
| **Base branch was already merged as PR #122 → `dev`** (merge commit `9738df0`, 2026-10-22) | gh pr list 122 |
| dev tip `9738df0` = base tip `1e4052c` + only the merge commit | `git log origin/feature/issue-121..origin/dev` |
| Merge-base of PR head with dev is stale (`7dd5353`, PR #117 merge — pre-#105) | `git merge-base` |
| `git merge-tree --write-tree dev…head` → 10 conflicted files; **same set for current base and for dev** → retarget alone fixes nothing | merge-tree runs `23afbc8`, `32c5577` |
| Conflict class: 10 of 18 PR files conflict; 15 of 17 PR files are `ADDED` files (Export sources/tests/evidence) that merge cleanly | merge-tree |

## Root cause

The PR branch contains the **entire #121 feature stack in its pre-review-fix
form**: 12 duplicate commits (`b8e4368..f6d2a6e` equivalents, i.e.
`54b6653…79afac6` on the head) were cherry-picked as `017c8b3…1a0b3d8` copies
and later superseded on `dev` by review-fix rewrites (`8333671`, `0f3d9af`,
`3a7615e`, `1e4052c`) merged via #122. GitHub therefore sees 10 files with
two genuinely different versions of the same #121 code:

- `Sources/…/CashRunwayRepository.swift`, `CashRunwayRepositorying.swift`,
  `DatabaseManager.swift`, `MonthlyRetrospectiveUSDSnapshotService.swift` (add/add),
  `Persistence/CurrencyRepository.swift`, `Persistence/DAOs/MonthlyUSDSnapshot.swift` (add/add)
- `Sources/CashRunwayUI/AppModel.swift`
- `Tests/…/CashRunwayRepositoryingTests.swift`, `MigrationIntegrityTests.swift`,
  `MonthlyUSDSnapshotTests.swift` (add/add)

**Critical:** the 15 real export commits (`0348bb8…52803eb`) never touch any of
these 10 files except `AppModel.swift` (commit map below). So 9 of 10 conflicts
resolve to *dev's version verbatim* (it is the review-fixed superset); only
`AppModel.swift` needs real integration.

### Export-commit → file map (what must survive on the rebuilt head)

| Commits | Files (all ADDED or clean auto-merge) |
|---|---|
| `0348bb8` | `Sources/CashRunwayCore/Export/MonthlyRetrospectiveExport.swift`, `Tests/…/MonthlyRetrospectiveExportTests.swift` |
| `d41385f` | `Package.swift` (ZIPFoundation), `…/Export/MonthlyRetrospectiveXLSX.swift`, `Tests/…/MonthlyRetrospectiveXLSXTests.swift` |
| `d824f22`, `0ae7b62` | `Sources/CashRunwayUI/AppModel.swift` (export pipeline func) |
| `5144c4b` | `Sources/CashRunwayUI/SettingsView.swift`, `AccessibilityIdentifiers.swift` |
| `07c8e0d`, `e602b13`, `acfd490`, `7cb96d8`, `7a595b6`, `52803eb` | exporter + the two export test files (style/fixes incl. inlineStr, formula-injection, mixed-base guard) |
| `3ee7efa`, `a89cdd1`, `35f6ab1` | `.github/workflows/ios-ci.yml`, `AppHost/UITestRuntime.swift`, `Tests/CashRunwayUITests/*` |
| `67a9f2c` | `docs/evidence/pr-124/*` (logs, generated artifacts, tooling) |
| auto-merge by #122 | `TimelineSummaryCard.swift`, `TimelinePresentation.swift`, `DashboardView.swift` — take dev's versions, identical content |

## Recommended approach: rebuild the head on top of `dev`

Squash-merge the PR head onto a fresh branch from `dev`, drop the 12 duplicate
commits, keep the 15 export commits' content. Retarget the PR to `dev` and
point it at the rebuilt branch. One conflict-resolution session, no rebase
history surgery, old branch untouched (natural backup).

### Step-by-step

**T0 — Tooling (setup)**
- `brew install just` (missing on this machine today), verify `just --version`,
  then `just session-start` in `~/projects/cash-runway`.
- Gate: recipes resolve; session-start inventory clean.

**T1 — Rebuild branch (all git-mechanical)**
- `git switch -c fix/pr-124-rebuild origin/dev`
- `git merge --squash origin/feature/issue-122-retrospective-export` → 10 conflicts.
- Resolve 9 verbatim-to-dev files ( reasoned, not blind — see guard below),
  integrate `AppModel.swift` by hand (keep dev's refresh/backfill changes +
  PR's `exportMonthlyRetrospective(format:)` pipeline + BackgroundWork actor path).
- Commit: `merge: rebuild PR 124 head onto dev; drop duplicate pre-image (#121) commits`
- No push yet (Git Safety: push needs explicit user confirmation).

Resolution playbook per conflict class:
1. Core + Core test files (9 files): take **ours (=dev)**.
   Guard check before each: grep the conflict region for dev-side review-fix
   signatures — `monthKeys:` explicit-parameter call-sites, closed
   `v9_masked` migration block, `isPlaceholder: true` secret invariant,
   wallet-scoped `monthlyUSDSnapshots(monthKeys:)` + `monthlyUSDMonthAggregates`.
   If any signature is missing from the dev side: **stop and ask** (do not resolve).
2. `AppModel.swift` (1 file): manual integrate; PR adds `exportMonthlyRetrospective(format:)`,
   BackgroundWork actor func, `allMonthlyUSDSnapshots()` call → point it at
   dev's identical `allMonthlyUSDSnapshots()` (`CashRunwayRepositorying.swift:154`,
   repository impl `CurrencyRepository.swift:289`).
   Forbidden: `git checkout --ours/--theirs` without prior manual read (AGENTS.md).

**T2 — Local verification gates**
- `just check-unit-parallel` (fast) → green.
- `just test-filter MonthlyRetrospective` → both export suites pass (19+ tests).
- `just lint` → expect 0 violations / ~174 files (matches `52803eb` evidence).
- `just check-integration` (or `check-isolated` since multiple worktrees are active).
- Simulate GitHub's merge: on the rebuilt branch `git merge --no-commit --no-ff origin/dev`
  → expect trivial/no-op → abort. Confirms mergeable.
- History hygiene assert (programmatic): of the 27 duplicate commit subjects
  (`feat: retrospective monthly USD snapshot via historical month-end rates`,
  `fix: store unconverted snapshot on rate failure; …`, etc.), each appears ≤1
  time in `fix/pr-124-rebuild` log (dev already carries the fixed ones);
  all 15 export commit subjects present.
- Diff assert: `git diff 52803eb fix/pr-124-rebuild -- Sources/CashRunwayCore/Export Tests/CashRunwayCoreTests/MonthlyRetrospective*`
  → empty (export feature bits byte-identical).

**T3 — Push, retarget, verify (needs user YES per repo Git Safety)**
- Push: `git push -u origin fix/pr-124-rebuild`.
- `gh pr edit 124 --head fix/pr-124-rebuild --base dev`
  (non-destructive: keeps old head branch as backup; alternative — force-push
  the rebuilt history to the existing branch, needs `--force-with-lease` approval).
- Comment on the PR documenting the rebuild (use `just pr-comment`).
- Verify (programmatic): `gh pr view 124 --json mergeable,mergeStateStatus,baseRefName,headRefName,files,commits`
  → `MERGEABLE`; file list no longer contains the 6 Core conflict files,
  `MonthlyRetrospectiveUSDSnapshotService.swift`, the 2 dup DAO/test files,
  `DashboardView.swift`, `TimelineSummaryCard.swift`, `TimelinePresentation.swift`;
  commits ≈ 16 (15 + merge).
- CI: expect green on Unit + Integration + Xcode App Build + Static Analysis;
  UI E2E stays label-gated.

**T4 — Post-merge housekeeping (separate confirmation)**
- After #124 merges: delete `origin/feature/issue-121-usd-retrospective` (merged)
  and `origin/feature/issue-122-retrospective-export` (superseded).
- Prune local worktrees when no longer needed: `-ev124`, `-fix122`, `-fix124`, `-shots`
  (contents already in history — verify each with `git log --contains` first).

## Requirements self-check

| Requirement | Evidence anchor |
|---|---|
| Conflicts resolved, review fixes not lost | grep guard signatures T1 + `just test-filter MonthlyRetrospective` green |
| Retargeted into `dev` | `gh pr view 124` → `baseRefName: dev`, `mergeable: MERGEABLE` |
| No duplicate commits in history | programmatic ≤1-count assert (T2) |
| Export feature content identical | `git diff 52803eb rebuild -- Export*` empty |
| CI green | `gh pr checks 124` all pass |
| AGENTS.md merge-safety scan | high-risk path grep (`*Secret*`, pbxproj, plist, Package.resolved…) before commit |

## Assumptions (defaults; veto any)

- **A1** New branch `fix/pr-124-rebuild` + `gh pr edit --head` instead of force-push
  (non-destructive, old branch stays as rollback).
- **A2** Retarget base → `dev` (confirmed necessary: base branch already merged; conflicts
  identical either way, so retarget is semantics-only).
- **A3** Squash-merge rebuild (single conflict session). Alternative on request:
  cherry-pick the 15 export commits one-by-one for granular history (~only 2 commits
  would conflict).
- **A4** `just` installed via Homebrew; if unavailable, fall back to
  `Scripts/pre-flight.sh` + documented skipped gates.
- **A5** No `.pbxproj` edits involved (PR doesn't touch Xcode project files — verified).
- **A6** Every push/PR-mutation step waits for explicit user confirmation.

## Risks / trade-offs

- **R1** UI behavior drift: `TimelineSummaryCard`/`DashboardView` now ship from dev's
  #122 versions — same content the PR had post-merge; CI gates UI only in the
  Xcode App Build job (by design).
- **R2** `AppHost/UITestRuntime.swift`: rebuild must leave exactly the `3ee7efa` +
  `a89cdd1` delta vs dev (verified in advance via merge-tree; re-assert after build).
- **R3** `docs/evidence/pr-124/README.md` describes pre-rebuild head hashes — history
  doc, still valid; optionally append a post-rebuild note.
- **R4** If PR #126 (savings wallets) merges into `dev` first, `CashRunwayRepository.swift`
  may conflict again — re-run the merge-tree simulation (2 min) before pushing.
- **R5** Squash merge commit makes `git blame` on AppModel export code land on the merge
  commit; acceptable, noted.

## Open questions

- Q1: Prefer force-push rebuild onto the existing head branch over the new-branch default?
- Q2: Squash (default) or 15-commit cherry-pick?
- Q3: Approve branch deletions after merge (T4), or keep as archive?