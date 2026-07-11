# Timeline Screen Redesign Implementation Plan

## Status

**Scope:** planning only. This document does not implement UI, repository, model, localization, or test changes.

**Target:** redesign the existing Timeline tab implemented by `DashboardView`. Do not add a parallel screen or change the root tab structure.

**Reference outcome:**

- top-level **Cash Flow** title with a compact search action;
- one unified summary card;
- net cash flow, income, expenses, and a matched-period expense comparison;
- compact grouped income/expense bars;
- embedded **Spending Overview** action;
- wallet, period, and advanced-filter controls;
- grouped daily transaction cards;
- existing floating add-transaction action.

## Executive recommendation

Implement the redesign by extending the existing Timeline pipeline and preserving current navigation, editing, filtering, async reload protection, and mixed-currency safeguards.

The only new financial capability should be a repository-backed expense comparison against the correct previous comparable period.

Do **not** add a database migration initially. Use existing monthly aggregates for completed periods and bounded transaction sums for partial periods. Add a new daily aggregate only after physical-device profiling proves it necessary.

---

# 1. Verified current architecture

The existing Timeline screen already owns:

1. search;
2. wallet and month/year scope;
3. headline cash flow;
4. grouped income/expense chart;
5. Spending Overview navigation;
6. grouped transaction sections;
7. transaction editing;
8. floating add action.

The current screen is approximately:

```text
hero
filters
chart card
Spending Overview button
transaction feed
floating add button
```

The target hierarchy should be:

```text
Header
  ├─ Cash Flow title
  └─ Search button

Summary card
  ├─ Top row
  │  ├─ Net cash flow
  │  ├─ Expense comparison
  │  └─ Income / expense legend
  ├─ Body
  │  ├─ Income and expense cards
  │  ├─ subtle vertical divider
  │  └─ grouped bar chart
  └─ Spending Overview action

Filter bar
  ├─ Wallet
  ├─ Selected month/year
  └─ Filters + active-count badge

Transaction feed
  └─ Day cards
      ├─ Day header and total
      └─ Transaction rows

Floating add button
```

No root-navigation change should be required.

## Important current-data distinction

The current chart is driven by `model.allBars`, not only by the six-period `TimelineSnapshot.bars` window.

The implementation should preserve this distinction:

- `TimelineSnapshot` supplies the selected-period snapshot, comparison, and transaction sections;
- `model.allBars` remains the source for horizontally navigable historical chart data;
- the chart derives a four-period visible viewport around the selected period while retaining access to older bars.

Do not unintentionally replace the current historical chart with a fixed six-period-only chart unless that product change is explicitly approved.

---

# 2. Product semantics to lock before coding

## 2.1 Expense comparison

The comparison measures **expenses only**.

### Current month

Compare:

```text
first day of selected/current month → today
vs
first day of previous month → same ordinal day, clamped when needed
```

Example on July 11:

```text
Current:  July 1–11
Baseline: June 1–11
```

Formula:

```text
percentageChange = (currentExpense - baselineExpense) / baselineExpense
```

Presentation:

| Condition | First line | Second line |
|---|---|---|
| Current > baseline | `↗ +18%` in red | `Expenses are higher than June 1–11` |
| Current < baseline | `↘ −18%` in green | `Expenses are lower than June 1–11` |
| Equal | neutral indicator | `Expenses are unchanged from June 1–11` |
| Baseline = 0, current > 0 | no percentage | `New spending compared with June 1–11` |
| Both zero | no percentage | `No spending in either period` |
| No valid baseline | no percentage | `No comparable period` |

The percentage appears **only once**, on the first line. Do not repeat it inside the explanatory sentence.

Never display infinity, NaN, or a fabricated percentage.

## 2.2 Historical months

For a completed historical month, compare the full selected month with the full previous month.

```text
June 1–30 vs May 1–31
```

Do not truncate a historical month to today’s ordinal day.

## 2.3 Year mode

- current year: year-to-date versus the same date range in the previous year;
- completed historical year: full year versus previous full year;
- February 29: clamp safely in a non-leap baseline year.

## 2.4 Filter scope

| Control | Summary/chart | Transaction feed |
|---|---:|---:|
| Wallet | Yes | Yes |
| Selected month/year | Yes | Yes |
| Text search | No | Yes |
| Category | No | Yes |
| Label | No | Yes |
| Transaction kind | No | Yes |
| Custom date range | No | Yes |

Wallet and period are global financial scope. Search, category, label, kind, and custom date range are feed-exploration filters.

Searching for “Bolt” must not redefine the headline cash-flow KPI.

## 2.5 All-wallet scope prerequisite

Before implementation, verify whether selecting **All Wallets** currently returns a true same-currency aggregate or is normalized to the first active wallet.

If current behavior falls back to one wallet:

- either fix true same-currency all-wallet aggregation as a separate prerequisite;
- or explicitly preserve and document that limitation.

Do not present an “All Wallets” label while silently showing only one wallet’s totals.

---

# 3. Minimal data-model change

Reuse existing:

- `TimelineBarPoint`;
- `TimelineSection`;
- `TimelineSnapshot.heroCashFlowMinor`;
- `model.allBars`;
- existing transaction rows.

Do **not** add a separate `TimelinePeriodSummary` model. It would duplicate income, expenses, cash flow, and selected-period data already represented by the snapshot and selected bar.

Add only the new comparison facts:

```swift
public struct TimelineComparison: Hashable, Sendable {
    public enum Direction: Hashable, Sendable {
        case higher
        case lower
        case unchanged
        case unavailable
    }

    public var direction: Direction
    public var currentExpenseMinor: Int64
    public var baselineExpenseMinor: Int64
    public var percentageChange: Double?
    public var currentRange: ClosedRange<Int>
    public var baselineRange: ClosedRange<Int>
    public var isPartialPeriod: Bool
}
```

Extend `TimelineSnapshot`:

```swift
public var comparison: TimelineComparison?
```

Keep localized strings out of Core.

## Presentation layer

Add a narrow pure formatter/presentation type in `CashRunwayUIVM` or the UI module:

```swift
struct TimelineScreenPresentation {
    let cashFlowText: String
    let incomeText: String
    let expenseText: String
    let comparison: TimelineComparisonPresentation?
    let activeFilterCount: Int
}
```

Resolve the selected `TimelineBarPoint` once and reuse it for:

- income card;
- expense card;
- selected chart state;
- accessibility summary.

Do not introduce another mutable source of financial truth.

---

# 4. Repository implementation

## 4.1 Deterministic comparison window

Add a pure helper:

```swift
struct TimelineComparisonWindow {
    let current: ClosedRange<Int>
    let baseline: ClosedRange<Int>
    let isPartial: Bool
}

static func comparisonWindow(
    selectedMonthKey: Int,
    period: TimelinePeriod,
    now: Date,
    calendar: Calendar
) -> TimelineComparisonWindow?
```

Required edge cases:

- January/December boundary;
- month lengths 28–31;
- leap years;
- February 29 baseline;
- future selected period;
- current partial month;
- completed historical month;
- current year YTD;
- completed historical year;
- local timezone/calendar boundaries.

Clamp the baseline end date to the final valid day when the previous period is shorter.

## 4.2 Inject `now` through the repository contract

The existing protocol has no clock input. Make deterministic testing explicit:

```swift
func timelineSnapshot(
    monthKey: Int,
    walletID: UUID?,
    query: TransactionQuery,
    period: TimelinePeriod,
    now: Date
) throws -> TimelineSnapshot
```

Provide a production convenience wrapper:

```swift
public extension DashboardRepositorying {
    func timelineSnapshot(
        monthKey: Int,
        walletID: UUID?,
        query: TransactionQuery,
        period: TimelinePeriod
    ) throws -> TimelineSnapshot {
        try timelineSnapshot(
            monthKey: monthKey,
            walletID: walletID,
            query: query,
            period: period,
            now: Date()
        )
    }
}
```

This keeps callers simple while allowing deterministic tests without introducing a full clock abstraction.

## 4.3 Hybrid comparison calculation

### Partial current period

Use bounded transaction sums because monthly aggregates include the entire month and may include future-dated manual transactions.

```sql
SELECT COALESCE(SUM(amount_minor), 0)
FROM transactions
WHERE is_deleted = 0
  AND type = 'expense'
  AND local_day_key BETWEEN ? AND ?
  AND (? IS NULL OR wallet_id = ?)
```

Run once for the current range and once for the baseline range.

### Completed historical period

Use the same aggregate source as the chart:

- `monthly_wallet_cashflow` for months;
- yearly totals derived from monthly aggregates for years.

This keeps the comparison consistent with the displayed bars and avoids unnecessary full transaction scans.

Use a bounded direct-query fallback only when an expected aggregate is missing.

### Invariants

- include expenses only;
- exclude income;
- exclude both transfer directions;
- exclude soft-deleted rows;
- respect normalized wallet scope;
- preserve mixed-currency rejection;
- build summary, comparison, bars, and feed within one consistent database read where practical.

## 4.4 No migration initially

Do not add `daily_wallet_cashflow` in the first implementation.

Consider a daily aggregate only if a representative physical-device fixture demonstrates a material regression, for example p95 comparison-query time above roughly 20–30 ms.

A new aggregate would require migration, backfill, mutation-path updates, import/bank-sync updates, restore handling, and integrity tests.

---

# 5. Chart behavior

Retain a custom SwiftUI grouped-bar chart for predictable placement of:

- paired income/expense bars;
- compact values above bars;
- zero placeholders;
- two-line month/year labels;
- selected-period emphasis.

Proposed API:

```swift
struct TimelineGroupedBarChart: View {
    let points: [TimelineBarPoint]       // from model.allBars
    let selectedPeriodKey: Int
    let currencyCode: CurrencyCode
    let onSelect: (Int) -> Void
}
```

## Visible viewport

- show approximately four period groups at normal iPhone width;
- retain horizontal access to the full `allBars` history;
- initially center or trailing-align the selected period;
- recenter after a period selection;
- calculate scale from the visible viewport, not from a distant historical outlier.

## Scaling

```text
maximum = max visible income/expense magnitude
usableHeight = chart height - value-label reserve - period-label reserve
barHeight = value / maximum × usableHeight
```

Rules:

- zero → dash, no colored bar;
- tiny non-zero → minimum visible height around 3–4 points;
- reserve space above bars for labels;
- prevent adjacent label collisions;
- use locale-aware compact formatting;
- expose complete values through accessibility.

## Interaction

Preserve current behavior:

- light haptic feedback;
- update selected period;
- reload Timeline;
- scroll selection into view;
- retain request-ID stale-result protection.

---

# 6. SwiftUI composition

`DashboardView` should remain the orchestration view, not become a larger rendering monolith.

Recommended final files:

```text
DashboardView.swift
TimelineHeaderView.swift
TimelineSummaryCard.swift
TimelineGroupedBarChart.swift
TimelineFilterBar.swift
TimelineDayCard.swift
TimelinePresentation.swift
```

Optional after the first stable iteration:

```text
TimelinePeriodPickerSheet.swift
TimelineTransactionRow.swift
```

## Safe extraction order

1. Build the first visual iteration as private subviews in `DashboardView.swift`.
2. Validate geometry and interaction.
3. Extract only stable components.
4. Add files through Xcode/project tooling.
5. Verify `project.pbxproj` immediately.
6. Keep `.bak` files untracked.
7. Run CodeGraph sync after extraction.

## Responsive summary card

Primary normal-width layout:

```text
Top:
[ net cash flow ] [ comparison ] [ legend ]

Body:
[ income + expense cards ] | [ grouped chart ]

Bottom:
[ Spending Overview ]
```

For accessibility Dynamic Type or insufficient width, switch to:

```text
net cash flow
comparison
legend
income / expense cards
full-width chart
Spending Overview
```

Use `ViewThatFits`, an adaptive custom `Layout`, or an explicit `dynamicTypeSize` branch.

Do not solve pressure primarily with aggressive `.minimumScaleFactor`.

---

# 7. Header and summary details

## Header

- large leading **Cash Flow** title;
- compact search button in the upper-right;
- visual size approximately 40–44 points;
- interaction target at least 44 × 44;
- subdued icon and light border;
- preserve the existing search accessibility identifier.

## Net amount

- negative → semantic negative color;
- positive → semantic positive color;
- zero → neutral primary text;
- monospaced digits;
- wallet/aggregate currency formatter;
- no hardcoded `₴`;
- controlled fallback layout for very large values.

## Income and expense cards

Each card contains:

```text
colored vertical indicator
label
formatted amount
```

Keep explicit that aggregate `expenseMinor` is a positive magnitude while the displayed expense value may use a negative sign.

## Comparison block

Use complete localized sentences without percentage duplication:

```text
Expenses are higher than %@
Expenses are lower than %@
Expenses are unchanged from %@
New spending compared with %@
No spending in either period
No comparable period
```

Ukrainian forms must also be complete sentences rather than concatenated fragments.

Color must not be the only directional signal; use arrow and text.

## Spending Overview

Move the current action into the bottom of the summary card.

Preserve existing navigation and accessibility identifier. Do not duplicate Overview logic in Timeline.

---

# 8. Period and advanced filters

## Wallet chip

Reuse current selection and async reload behavior.

Do not sum unlike currencies without conversion.

## Period chip

Display an explicit label such as:

```text
July 2026
```

For the first implementation, restyle the existing control and use a `Menu` or compact selection sheet. A full month-grid navigator is optional and should not block the redesign.

## Existing search sheet

The app already has one shared draft query with:

- search text;
- type;
- category;
- label;
- date range;
- apply/reset.

Do not rebuild this system. Extend it with an entry mode:

```swift
enum TimelineSearchEntryMode {
    case search
    case filters
}
```

- header search opens the existing sheet and focuses the search field;
- Filters chip opens the same sheet in its normal state;
- both edit the same `TransactionQuery`;
- Apply performs one reload;
- Reset clears advanced feed filters.

Use `@FocusState` for search focus.

## Filter badge

Count only advanced feed filters:

```swift
extension TransactionQuery {
    var activeFilterCount: Int {
        var count = 0
        if !searchText.isEmpty { count += 1 }
        if categoryID != nil { count += 1 }
        if labelID != nil { count += 1 }
        if kinds != Set(TransactionDraft.Kind.allCases) { count += 1 }
        if startDate != nil || endDate != nil { count += 1 }
        return count
    }
}
```

Do not count wallet or the visible Timeline period.

## Date-range correctness fix

The current end-date filter should be changed to a half-open interval:

```text
occurred_at >= startOfStartDay
occurred_at < startOfDayAfterEndDate
```

Do not use `occurred_at <= selectedDateAtMidnight`, which can omit transactions later on the chosen end date.

---

# 9. Transaction day cards

Wrap each existing `TimelineSection` in a card.

Header:

```text
calendar icon
localized weekday/date
spacer
day total
expand/collapse chevron
```

The whole header should be one accessible full-width button with minimum 44–48-point height.

Suggested local state:

```swift
@State private var collapsedDayKeys: Set<Int> = []
```

Behavior:

- expanded by default;
- preserve collapsed state while the user remains on the screen;
- reset on wallet or selected-period change.

Reuse the existing transaction row and editor flow.

Refinements:

- glyph approximately 44–48 points;
- merchant and amount on one line;
- secondary metadata on one line;
- fixed trailing amount column;
- trailing chevron;
- inset separators;
- preserve transaction-row accessibility identifiers;
- do not invent card-network or bank logos absent from the model.

---

# 10. Year-mode performance

The current Timeline snapshot can load a full year of transactions with no explicit limit.

For the first implementation:

1. preserve existing year behavior;
2. test with a fixture containing roughly 5,000–10,000 transactions;
3. measure repository load time and scroll responsiveness on a physical device;
4. introduce pagination or month-grouped lazy expansion only if measured performance is unacceptable.

Do not add pagination speculatively without profiling, but do not mark year mode complete without this large-data gate.

---

# 11. Theme, localization, and accessibility

## Theme

Reuse `CashRunwayTheme` semantic colors and typography.

Potential layout tokens:

```swift
static let timelinePageHorizontalPadding: CGFloat = 16
static let timelineSectionSpacing: CGFloat = 14
static let timelineCardRadius: CGFloat = 24
static let timelineInnerRadius: CGFloat = 16
static let timelineCardPadding: CGFloat = 16
static let minimumTouchTarget: CGFloat = 44
```

Use subtle borders/shadows, consistent radii, neutral body text, and trailing-aligned monospaced money values.

## Localization

Add complete English and Ukrainian entries for:

- Cash Flow;
- Income;
- Expenses;
- Spending Overview;
- All Wallets;
- Filters;
- current-period labels;
- comparison sentences;
- unavailable states;
- chart accessibility summaries;
- expand/collapse labels.

Modify `AppHost/Localizable.xcstrings` through the repository localization script.

## Accessibility

Add identifiers for:

```swift
timelineSummaryCard
timelineIncomeValue
timelineExpenseValue
timelineComparison
timelineMonthPicker
timelineFilterButton
timelineFilterBadge
timelineDayHeader(_ dayKey: Int)
timelineDayToggle(_ dayKey: Int)
timelineChartPoint(_ periodKey: Int)
```

Preserve existing search, wallet, cash-flow, Overview, add, and transaction-row identifiers.

VoiceOver order:

1. selected period and wallet;
2. net cash flow;
3. income;
4. expenses;
5. comparison;
6. chart summary;
7. Spending Overview.

Also validate:

- 44 × 44 minimum targets;
- Bold Text;
- Reduce Motion;
- accessibility Dynamic Type;
- light/dark appearance;
- meaning understandable without color.

---

# 12. Loading and edge states

## Loading

Initial implementation may preserve current behavior. Preferred follow-up:

- initial redacted/skeleton state;
- keep previous content during wallet/period reload;
- small progress indicator inside summary area;
- no full-screen loading blanket for every chart tap.

## Empty period

Keep the summary visible with:

- zero net;
- zero income/expenses;
- empty bars;
- unavailable comparison;
- clear empty-feed state.

## Mixed currencies

Either require one wallet or show aggregate-unavailable state. Never add unlike currencies.

## Large values

Verify at least:

```text
₴0.00
-₴864.00
-₴79,471.22
₴9,999,999.99
-$1,234,567.89
€1,234,567.89
```

---

# 13. Test strategy

## Pure date-window tests

- current partial month;
- completed historical month;
- January/December boundary;
- March 31 versus February;
- leap-year February;
- February 29 versus non-leap baseline;
- current year YTD;
- completed historical year;
- future selected period;
- timezone/calendar boundaries.

## Repository integration tests

- expense included;
- income excluded;
- transfers excluded;
- deleted rows excluded;
- wallet scope respected;
- true same-currency all-wallet behavior verified or limitation documented;
- mixed currencies rejected;
- current/baseline amounts correct;
- zero baseline safe;
- historical aggregate path consistent with chart values;
- partial-period bounded-query path excludes future-dated transactions;
- snapshot fields internally consistent.

## Presentation tests

- positive/negative/zero cash-flow style;
- higher/lower/unchanged/unavailable states;
- percentage appears only once;
- no infinity/NaN;
- signed expense display;
- active-filter count;
- localized compact chart labels;
- selected chart state;
- localized date-range text.

## Visual QA matrix

| Dimension | Cases |
|---|---|
| Language | Ukrainian, English |
| Appearance | Light, dark |
| Width | Small, standard, large iPhone |
| Dynamic Type | Default, XL, accessibility |
| Cash flow | Positive, negative, zero |
| Data density | Empty, one day, many days, 5k–10k year fixture |
| Currency | UAH, USD, EUR, mixed |
| Chart | Zero income, zero expense, large outlier, long history |
| Text | Long merchant/category/wallet names |

---

# 14. Exact file map

| File | Planned change |
|---|---|
| `Sources/CashRunwayCore/Models.swift` | Add `TimelineComparison`; extend `TimelineSnapshot` |
| `Sources/CashRunwayCore/CashRunwayRepositorying.swift` | Add `now`-aware `DashboardRepositorying.timelineSnapshot` requirement and convenience wrapper |
| Timeline repository implementation file | Add comparison-window and hybrid comparison calculation |
| `Sources/CashRunwayUI/AppModel.swift` | Consume enriched snapshot without new duplicate financial state |
| `Sources/CashRunwayUI/DashboardView.swift` | Replace current visual hierarchy; preserve orchestration |
| `Sources/CashRunwayUI/TimelineSearchSheet.swift` | Add search/filter entry mode, focus handling, and date-range boundary fix |
| `Sources/CashRunwayUI/Theme.swift` | Add reusable Timeline layout tokens if needed |
| `Sources/CashRunwayUI/AccessibilityIdentifiers.swift` | Add summary/filter/chart/day identifiers |
| `AppHost/Localizable.xcstrings` | Add English/Ukrainian strings via approved script |
| `Tests/CashRunwayCoreTests/TimelineComparisonTests.swift` | Pure comparison-window and percentage tests |
| `Tests/CashRunwayCoreTests/TimelineSnapshotTests.swift` | Repository comparison/snapshot integration tests |
| `Tests/CashRunwayUIVMTests/TimelinePresentationTests.swift` | Formatting, trend, filter badge, and localization tests |
| `CashRunway.xcodeproj/project.pbxproj` | Update only after stable new Swift files are extracted |

---

# 15. Implementation phases

## Phase 0 — Specification and prerequisite verification

Confirm:

- comparison semantics;
- year semantics;
- filter scope;
- zero-baseline wording;
- All Wallets behavior;
- four-period chart viewport;
- collapse behavior.

## Phase 1 — Core comparison logic

- add `TimelineComparison`;
- add comparison-window helper;
- add deterministic `now` contract;
- add pure unit tests.

## Phase 2 — Repository integration

- implement partial-period bounded queries;
- implement historical aggregate comparison;
- preserve mixed-currency behavior;
- enrich `TimelineSnapshot`;
- add integration tests.

## Phase 3 — Summary card and chart

- new header;
- exact top/body/bottom card geometry;
- net, income, expense, comparison;
- four-period viewport over `allBars`;
- embedded Spending Overview.

Keep early subviews private until stable.

## Phase 4 — Period and filters

- restyle wallet and period chips;
- add filter badge;
- extend existing search sheet with entry mode and focus;
- correct date-range end semantics.

## Phase 5 — Day-card feed

- day card containers;
- collapse/expand;
- row chevrons and inset separators;
- preserve editor/add flows.

## Phase 6 — Extraction and QA

- extract stable components;
- verify project integrity;
- localization;
- Dynamic Type, VoiceOver, dark mode;
- large-data year fixture;
- full validation.

---

# 16. Validation gates

Use repository workflows:

```bash
just session-start
just test-filter <focused-test-suite>
just check-unit-parallel
just check-isolated
just lint
just ui-check
just build
just smoke
just graph-sync
```

Additionally:

- use isolated SwiftPM validation when multiple worktrees are active;
- run performance checks when query or large-feed behavior changes;
- verify `project.pbxproj` immediately after editing it;
- report skipped gates and reasons;
- keep unit, build, smoke, and physical-device readiness as separate status categories.

---

# 17. Acceptance criteria

The redesign is complete when:

1. The existing Timeline tab adopts the approved hierarchy.
2. Net, income, expenses, and comparison use one consistent selected-period snapshot.
3. The chart preserves historical `allBars` navigation with a four-period visible viewport.
4. Comparison follows documented partial/historical month and year rules.
5. The percentage appears once and is never infinity/NaN.
6. Wallet and period affect summary and feed.
7. Advanced filters affect the feed only.
8. All Wallets behavior is truthful and tested.
9. Mixed currencies are never summed without conversion.
10. Date-range end dates include the complete selected day.
11. Chart labels do not collide on supported widths.
12. Dynamic Type switches layout instead of shrinking values excessively.
13. Day totals and signed transaction amounts remain correct.
14. Existing search, wallet, Overview, transaction editing, and add flows remain intact.
15. Ukrainian and English text is grammatically correct.
16. VoiceOver communicates values and direction without relying on color.
17. Year mode passes the large-data performance gate.
18. Focused tests, isolated tests, lint, UI validation, build, and smoke checks pass.

---

# 18. Estimated effort

| Work | Estimate |
|---|---:|
| Specification and All Wallets verification | 0.5 day |
| Core comparison/date logic and tests | 1 day |
| Repository integration and tests | 0.75–1 day |
| Summary card and chart | 1.5–2 days |
| Period/filter refinements | 0.5–0.75 day |
| Day-card feed | 0.5–1 day |
| Localization, accessibility, large-data and visual QA | 1–1.5 days |
| **Total** | **5–7.5 engineering days** |

A faster implementation can reproduce the static appearance, but production quality requires explicit comparison semantics, truthful wallet scope, responsive layout, localization, accessibility, and measured year-mode performance.
