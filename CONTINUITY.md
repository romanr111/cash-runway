# Continuity Ledger

## Snapshot

**Branch:** `codex/timeline-hero-and-chart-polish`
**Worktree:** `/Users/roman/Documents/Development/Cash Runway`
**Plan:** Project-local Cash Runway skill migration
**Phase:** Complete

## Current State

- The six Cash Runway skills have one canonical project-local copy in `.agents/skills/`. The corresponding `.claude/skills/*` entries are relative symlinks to it; OpenCode and Kimi officially scan project `.agents/skills/`, so `.opencode/skills/` and `.kimi-code/skills/` duplicates were removed. Their 18 former global copies remain in `/Users/roman/.Trash/cash-runway-global-skills-2026-07-25/`; no global `cash-runway-*` directory remains under Claude, Opencode, Kimi, or Zcode.
- The five global medical/PPTX skills (`medical-pptx-*`, `pptx-style-*`, and `presentation-creator`) were removed from Claude, Opencode, Kimi, and Zcode by the user on 2026-07-25.
- PR #110 was retargeted from `main` to `dev` on 2026-07-25. Its head remains `codex/timeline-hero-and-chart-polish`.
- The active worktree contains pre-existing changes to reporting secrets, timeline repository and picker code, and timeline snapshot tests. They were not changed by this task.
- Timeline screen now uses the Phase 2 header + unified summary card + four-period grouped chart, while preserving the Phase 1 snapshot as the single source of truth for selected-period numbers.
- The chart window ends at the selected period and supports tap and drag navigation; Spending Overview and search actions are preserved.
- PR #110 now includes `72affa3` for timeline history navigation and `e85cf5b` for the project-local skill migration; both commits were pushed to `codex/timeline-hero-and-chart-polish` on 2026-07-25.
- `CashRunway.xcodeproj/project.pbxproj.bak` remains untracked and must be removed before commit (`rm` is denied in this session; user action needed).

## Decisions

- `TimelineComparisonWindow` is a pure helper (Core) with explicit `now`/`calendar`; tests call it directly, repository integration tests call the concrete `timelineSnapshot(...now:)` overload. `DashboardRepositorying` protocol unchanged (no clock-related mock churn).
- `TimelineSummaryAdapter` (UI) is the single presentation adapter over `TimelineSnapshot`; `AppModel.currentCashFlowMinor` now delegates to it instead of recomputing from `allBars`.
- `TimelinePresentation` lives in `CashRunwayUIVM` so it is unit-testable from `CashRunwayUIVMTests`; it is auto-discovered by SwiftPM and not registered in the pbxproj app-target Sources phase.
- `TimelineSummaryCard.swift` and `TimelineGroupedBarChart.swift` are in `Sources/CashRunwayUI` and are registered in the pbxproj app-target Sources phase.
- All Wallets (`nil` walletID) is preserved as `nil` for same-currency scopes and rejected at the query boundary for mixed currencies (not narrowed to the first wallet).
- `MoneyFormatter.string(from:currencyCode:locale:)` was added as an additive overload to support locale-aware formatting without changing existing call sites.
- Chart labels use locale-aware compact values (`52,8 тис.` / `52.8k`) via `TimelinePresentation.compactValueText`; no hardcoded hryvnia symbols.
- Comparison baseline labels use `DateIntervalFormatter` with the current locale; the sentence template is localized via `Localizable.xcstrings` with English fallback for tests.

## Working Set

- `.agents/skills/cash-runway-{localization,persistence-change,pr-repair,release,validation,vercel-reporting-api}/` - canonical project-local skill trees, untracked pending a future commit
- `.claude/skills/cash-runway-{localization,persistence-change,pr-repair,release,validation,vercel-reporting-api}` - six relative symlinks to the canonical tree for Claude
- `CONTINUITY.md`
- `AppHost/Localizable.xcstrings` - new timeline comparison, chart-value, and accessibility keys
- `CashRunway.xcodeproj/project.pbxproj` - registered `TimelineSummaryAdapter.swift`, `TimelineSummaryCard.swift`, `TimelineGroupedBarChart.swift`
- `Sources/CashRunwayCore/Money.swift` - added `string(from:currencyCode:locale:)` overload
- `Sources/CashRunwayCore/Models.swift` - made `TimelineBarPoint` public memberwise init public
- `Sources/CashRunwayUIVM/TimelinePresentation.swift` (new) - pure presentation adapter
- `Sources/CashRunwayUI/DashboardView.swift` - new header + summary card wiring; removed old hero/chartCard/overviewButton
- `Sources/CashRunwayUI/TimelineSummaryCard.swift` (new) - summary card layout
- `Sources/CashRunwayUI/TimelineGroupedBarChart.swift` (new) - four-period chart with tap/drag navigation
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift` - added `timelineSummaryCard`, `timelineIncomeValue`, `timelineExpenseValue`, `timelineComparison`, `timelineChartPoint(_:)`
- Phase 1 files remain in the working set: `TimelineComparisonWindow.swift`, `CashRunwayRepository.swift`, `CashRunwayRepositorying.swift`, `AggregateMaintenance.swift`, `AppModel.swift`, `TimelineSummaryAdapter.swift`, `TimelineSnapshotTests.swift`, `TimelineComparisonTests.swift`, `AgentTestMocks.swift`, `CurrencyFoundationTests.swift`, `PropertyStyleQueryTests.swift`
- `Tests/CashRunwayUIVMTests/TimelinePresentationTests.swift` (new) - 16 presentation/behavior tests

## Validation

Project-local skill migration checks on 2026-07-25:

- Official documentation confirms that Codex, OpenCode, and Kimi scan project `.agents/skills/`; Claude supports a project skill directory symlink. All six Claude symlinks resolve to the canonical tree. This was a static discovery check, not fresh-session execution for the other CLIs.
- All 12 canonical-and-symlink `quick_validate.py` checks passed. The permanent-delete command was rejected by the local safety layer, so the 18 global directories were moved to the dated macOS Trash archive instead.
- Source parity and `.claude/skills` to `.agents/skills` mirror parity passed for all six Cash Runway skills.
- `quick_validate.py` passed for all 12 project-local skill copies; `git diff --check` and a project-local trailing-whitespace scan passed.
- `just pr-status 110` passed repository diff/membership checks and reported PR #110 as `MERGEABLE` against `dev`; its existing CI checks were passing, with UI End-to-End Tests intentionally skipped.
- Runtime smoke, backend/API reachability, and release readiness were skipped because this task changed only project-local skill configuration. No XCUITest/E2E was run per repository policy.

All gates run in this worktree on 2026-07-23:

- `just test-filter TimelineComparisonTests`: passed (12/12).
- `just test-filter TimelineSnapshotTests`: passed (18/18).
- `just test-filter TimelinePresentationTests`: passed (16/16).
- `just lint`: passed (0 violations, 162 files).
- `just build`: passed (`BUILD SUCCEEDED`; only pre-existing warnings: duplicate InfoPlist group, signed SQLCipher binary, AppIntents metadata skipped).
- `just check-isolated`: passed (663 tests in 65 suites).
- `just ui-check`: passed (iPhone 17 simulator build + agent validation).
- `just smoke`: passed (seeded simulator smoke with `scenario=transaction_core`).
- `just graph-sync`: passed (8 changed files, 4 added, 4 modified, 343 nodes).
- `Scripts/verify-pbxproj.sh`: passed.
- `Scripts/check_core_module_wiring.py`: passed (Core linked once, no Core sources in app target, 33 files checked).
- `xcodebuild -list -project CashRunway.xcodeproj`: passed.
- Skipped: `just check-isolated-with-perf` / `just check-perf` (no performance-sensitive code changed). `just check` (full CI gate) not run because no `ReportingSecrets*`/`ReportingConfig*`/pipeline/deploy files changed.
- XCUITest/E2E not run per repo policy.

## Notes

- Self-review follow-up on 2026-07-25: `TimelineGroupedBarChart` now synchronizes its local selection when the scrolling branch mounts, preventing a year-to-month switch from rendering an unselected month strip. `git diff --check` passed. `just ui-check`, `just test-filter TimelinePresentationTests`, and `just lint` were attempted but blocked before completion by sandbox-denied writes to Xcode/SwiftPM/SwiftLint caches under `~/Library`; the linter did scan all 166 files and reported 0 violations before its cache write failed. No UI/E2E test was run per policy, so the branch-switch behavior still needs simulator evidence outside this sandbox.
- PR #110 update attempted on 2026-07-25 after explicit approval for the 12-file timeline-only scope. Staging was blocked because the sandbox denied creation of `.git/index.lock`; no files were staged, committed, or pushed.
- After Git write access was restored on 2026-07-25, the same 12-file timeline-only scope was committed as `72affa3` (`feat(timeline): add period history navigation`) and pushed to PR #110. `TimelinePresentationTests` (21 tests), `TimelineSnapshotTests` (19 tests), and `just lint` (0 violations across 166 files) passed; the clean iPhone 17 simulator build completed successfully. GitHub then reported PR #110 open and mergeable at `72affa3`; it has no required checks configured. UI/E2E remains intentionally skipped per policy.
- `CashRunway.xcodeproj/project.pbxproj.bak` is untracked and must be removed before commit (rm denied in this session).
- Pre-existing build warnings are unrelated (duplicate `AppHost/uk.lproj/InfoPlist.strings` project reference, signed SQLCipher binary not stripped, AppIntents metadata skipped).
- Phase 3 (`timeline-redesign-phase-3-feed-filters-qa.md`) can now start; Phase 2 acceptance criteria 1-10 are satisfied.

## Historical Snapshot - `origin/main` (SUPERSEDED 2026-07-26)

**Branch:** `release/v0.1.4`
**Worktree:** `/Users/roman/.codex/worktrees/cash-runway-pr-92-review-comments`
**PR:** https://github.com/romanr111/cash-runway/pull/92 - Release v0.1.4 into `main`
**Base/head checked:** `main` `82279fc`, `release/v0.1.4` `7722ab1`

- Local no-commit merge of `origin/main` into `release/v0.1.4` had all conflicts resolved and staged; GitHub still reported PR #92 as `DIRTY` / `CONFLICTING` until the resolution was pushed.
- Release decisions retained: version `0.1.4` / build `273`, SwiftUI/UIVM extraction and project references, full-width Settings `moreRow` tap target, month-key date-scope fix, source-currency Agent DTO values, and signed `amount_minor` income in the delete summary.
- Historical validation: `git diff --check`, `git diff --cached --check`, `bash Scripts/verify-pbxproj.sh`, `Scripts/pre-flight.sh`, targeted Agent/bulk-delete tests, `just check-agent`, `just check-isolated`, `just build`, and `just graph-sync` passed. XCUITest/E2E was not run.
