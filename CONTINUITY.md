## Snapshot — Two-tap category detail navigation

Branch: `codex/two-tap-category-detail`
Worktree: `/Users/roman/.codex/worktrees/cash-runway-two-tap-category-detail`
PR: https://github.com/romanr111/cash-runway/pull/83 (draft, base `dev`)

Goal: Overview category rows use a two-tap state machine. First user tap selects
and arms a row; second tap on the same selected row opens
`CategoryDetailOverviewView` for the active month and wallet filter.

## Current state

- `Sources/CashRunwayUI/DashboardView.swift`
  - Adds item-driven `CategoryDetailRoute` navigation.
  - Tracks `categoryDetailArmedCategoryID`.
  - Keeps donut chart taps selection-only.
  - Resets arming when category kind, month, wallet, category identity list, donut selection,
    or Show More/Less context changes.
- `Tests/CashRunwayUITests/TransactionOverviewUITests.swift`
  - Existing Overview drilldown test taps Groceries once, asserts detail does not open,
    then taps again and asserts detail opens with the created note.

## Latest update

- Fixed review issue: Show More/Less now clears the armed category before changing
  the displayed category context.
- Recreated this worktree because it was missing locally while the branch still existed.
- Repaired partial `.codegraph` by removing the generated directory and rerunning bootstrap.

## Validation

- `git diff --check`: passed.
- `Scripts/pre-flight.sh`: passed.
- `just build`: passed on iPhone 17 simulator.
  - Existing warnings only: duplicate `AppHost/uk.lproj/InfoPlist.strings` project reference,
    signed SQLCipher binary not stripped, AppIntents metadata skipped.
- `just graph-bootstrap`: passed after `.codegraph` repair.
- `just graph-sync`: passed.

## Skipped / blocked

- XCUITest not run locally per repo policy.
- PR #83 remains `CONFLICTING` against `origin/dev`.
- Merging or rebasing `origin/dev` into this branch still needs explicit user confirmation.

## Git safety notes

- `dev` worktree is dirty and was not modified.
- Only this isolated feature worktree was edited.
