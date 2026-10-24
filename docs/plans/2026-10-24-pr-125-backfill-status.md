# Backfill-status indicator on the dashboard (retrospective USD lines)

**Ticket:** follow-up to #121 (rendered data), spawned from #124 review discussion.
**Scope:** UI-only status surface; no exporter changes, no schema changes.
**Deliverable:** while the USD-snapshot backfill runs (bootstrap full pass, or
foreground dirty-month refresh), the dashboard shows an honest "in progress"
state instead of silently-missing USD lines; a stale/failed month reads differently
from "still computing".

## Problem

USD secondary lines (`≈ $X` under income/expenses/saved) render only when a
persisted snapshot row exists (`TimelinePresentation.usdSecondaryLine` returns
`nil` → `metricCard` just omits the line). During a backfill the user cannot
distinguish:

1. backfill actually running (seconds–minutes — bootstrap full pass),
2. rate fetch failed / not yet fetched for a month (until next foreground pass),
3. month not complete (current month — normal).

## Design decisions

- NOT a percentage progress bar: store-once backfill proceeds in chunks
  (month → NBU fetch), percentages would jump and lie.
- Status label under the summary card, not per-card spinners: the backfill is
  global, not per-metric.
- Distinct copy for the three states above; "in progress" only for (1).
- The flag is set around the two real trigger points only; passive paths
  (`reloadStoredRetrospectiveUSDMetrics`) never show "in progress".

## Plan (bite-sized tasks, each with gate + commit)

### T1 — AppModel state flag

Files: `Sources/CashRunwayUI/AppModel.swift`

1. Add `public private(set) var isRetrospectiveBackfilling = false` near the
   other published state (line ~68 region).
2. In `refreshRetrospectiveUSDSnapshots()` (line ~285): set `true` before
   `await repository.refreshRetrospectiveUSDSnapshots(monthKeys: nil)`, reset
   `false` in a `defer`.
3. In `refreshForegroundSnapshot(...)` (line ~1062): same around
   `await repository.refreshDirtyUSDSnapshots()`.
4. Note: `refreshForegroundSnapshot` throws — the `defer` must be inside a
   scoped block so early throws still reset the flag (wrap the await in
   `do/defer` pattern or set flag in a nested func).

Gate: `swiftc -parse Sources/CashRunwayUI/AppModel.swift` with the swift.org
toolchain swiftc; `swift test --filter CashRunwayRepositoryingTests` unchanged
(2/2).
Commit: `feat(ui): expose retrospective backfill-in-progress state on AppModel`

### T2 — Presentation carries the flag

Files: `Sources/CashRunwayUIVM/TimelinePresentation.swift`, tests.

1. Add `public let usdBackfillInProgress: Bool` (default `false` via both
   inits; the legacy init passes `false`).
2. Add it as a trailing parameter (defaulted) so the 6 existing
   `TimelinePresentation(` call sites in tests compile unchanged; only the
   DashboardView call site passes it.
3. Update `TimelinePresentationTests`: one new test asserting the field
   round-trips and that Equatable includes it.

Gate: toolchain `swift test --filter TimelinePresentationTests` — all pass
including the new one.
Commit: `feat(uivm): carry USD backfill status in TimelinePresentation`

### T3 — Dashboard renders the status

Files: `Sources/CashRunwayUI/DashboardView.swift`,
`Sources/CashRunwayUI/TimelineSummaryCard.swift`.

1. `TimelineSummaryCard` gains `let usdBackfillInProgress: Bool` and, when
   `true`, renders a one-line status under the card body:
   `localizedSummaryString("dashboard.usd.backfilling", fallback: "Оновлюємо історичні курси…")`
   with `CashRunwayTheme.textSecondary` + small progress glyph (SF Symbol
   `clock.arrow.circlepath`), `.accessibilityElement` + identifier
   `dashboard.retrospectiveBackfillStatus`.
2. DashboardView call site passes `usdBackfillInProgress:
   model.isRetrospectiveBackfilling`.
3. New a11y identifier in `AccessibilityIdentifiers.swift`
   (next to the existing retrospective row ID).
4. Localization: three new keys via `Scripts/localize-xcstrings.py`
   (`dashboard.usd.backfilling`, `dashboard.usd.pendingRates`,
   `dashboard.usd.currentMonth`) — uk translations,
   `docs/plans/pr-125-strings.json` stays untracked.

Gate: `swiftc -parse` both changed files; `DYLD_FRAMEWORK_PATH=… swiftlint
lint --strict` on them (0 violations). UI compile proof only in CI (Xcode App
Build job) — same as the rest of the PR stack.
Commit: `feat(ui): show USD backfill status on the dashboard summary card`

### T4 — PR/issue plumbing

1. Post the plan digest as a comment on the tracking issue (when created).
2. Branch `feature/issue-125-backfill-status` off `origin/dev` (NOT the #124
   branch) to avoid coupling; #124 merges first independently.
3. CI gates on the PR: full `iOS CI` green.

Commit: n/a (repo bookkeeping).

## Acceptance table (requirement → evidence)

| Requirement | Evidence |
|---|---|
| Backfill running → status visible | T1 flag set around both trigger points; T3 renders when flag true — TimelinePresentationTests new case + CI Xcode App Build |
| Not-running → no status, layout unchanged | flag defaults false; existing TimelinePresentationTests suites stay green (no snapshot diff) |
| Stale/failed ≠ in progress | copy keys separated: pendingRates vs backfilling; T2 test pins the field, T3 uses distinct strings per state |
| Localizable | strings.json via script; `Localizable.xcstrings` diff inspected |
| No exporter/schema changes | `git diff` touches only AppModel/Dashboard/SummaryCard/Presentation/A11y/xcstrings |

## Risks

- `refreshForegroundSnapshot` early-throw leaking the flag stuck `true` →
  mitigated by scoped defer (T1.4).
- UI compile only provable in CI → T3 must keep `swiftc -parse` + lint local,
  CI Xcode App Build is the real gate (same stack as #124).
- Timing races: flag flips fast on incremental passes; status line may
  flicker — acceptable for v1 (bootstrap pass is the real case, minutes-long).