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

- Goal: Add SideStore release automation for Cash Runway — tag-triggered IPA releases with source metadata updates on main, and manual SideStore builds deployed to GitHub Pages.
- Success criteria: Tag push produces IPA + updated source JSON committed to main; manual workflow produces unsigned IPA + Pages-deployed SideStore source; icon asset exists and is referenced correctly.
- Current state: PR `#26` merged to `main`; `ios-release.yml` and `sidestore-release.yml` are on `main`; `altstore.json` and `sidestore/icon.png` present; branch and remote cleaned up.
- Next action: Enable GitHub Pages (GitHub Actions source) in repo settings if not already done, then trigger a manual SideStore release to verify E2E flow.
- Open questions: None.
- Merge status: merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- Base branch: `origin/main`
- Merge status: merged

## Working set

- `.github/workflows/ios-release.yml`
- `.github/workflows/sidestore-release.yml`
- `altstore.json`
- `sidestore/icon.png`
- `CONTINUITY.md`

## Done (recent)

- 2026-06-01 [MERGE] PR `#26` (`side_store_integration`) merged to `main`. Branch deleted locally and remotely.
- 2026-06-01 [CODE] Added `ios-release.yml` for tag-triggered IPA builds and automatic `altstore.json` updates pushed to main.
- 2026-06-01 [CODE] Added `sidestore-release.yml` for manual SideStore builds with GitHub Pages deployment.
- 2026-06-01 [CODE] Added `altstore.json` SideStore source manifest and `sidestore/icon.png` app icon.
- 2026-06-01 [REVIEW] Fixed missing icon URL, stale source push to main, tint color inconsistency, Python deprecation, and stale continuity ledger.

## Receipts

- 2026-06-01 [MERGE] `0d31943` — Merge pull request #26 from romanr111/side_store_integration
- 2026-06-01 [COMMIT] `20a9c48` — fix(release): review fixes for SideStore automation
- 2026-06-01 [COMMIT] `d9c269e` — ci: add tag-triggered release workflow and altstore.json source
- 2026-06-01 [COMMIT] `9c3bf28` — Add SideStore release workflow and icon; update agent configs and continuity
