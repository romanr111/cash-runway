# Continuity Ledger

## Snapshot

**Branch:** `codex/timeline-phase-1-financial-foundation`
**Worktree:** `/Users/roman/.codex/worktrees/cash-runway-timeline-phase-1`
**Plan:** `docs/plans/timeline-redesign-phase-2-summary-chart.md`
**Phase:** 2 of 3 (Header, Summary Card, and Chart) - COMPLETE

## Current State

- Phases 1 and 2 both complete in the same worktree; all validation gates green.
- Timeline screen now uses the Phase 2 header + unified summary card + four-period grouped chart, while preserving the Phase 1 snapshot as the single source of truth for selected-period numbers.
- The chart window ends at the selected period and supports tap and drag navigation; Spending Overview and search actions are preserved.
- No commit or push has been made; changes are staged in the worktree only.
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

- `CashRunway.xcodeproj/project.pbxproj.bak` is untracked and must be removed before commit (rm denied in this session).
- Pre-existing build warnings are unrelated (duplicate `AppHost/uk.lproj/InfoPlist.strings` project reference, signed SQLCipher binary not stripped, AppIntents metadata skipped).
- Phase 3 (`timeline-redesign-phase-3-feed-filters-qa.md`) can now start; Phase 2 acceptance criteria 1-10 are satisfied.
