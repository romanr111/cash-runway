# Timeline Screen Redesign Implementation Plan

## Status

**Scope:** planning only. This document does not implement UI, data-model, repository, localization, or test changes.

**Target screen:** the existing Timeline tab implemented by `DashboardView`.

**Reference design:** a mobile cash-flow screen with:

- a top-level **Cash Flow** title and search action;
- a unified cash-flow summary card;
- income and expense totals;
- a matched-period expense comparison;
- a compact grouped income/expense bar chart;
- an embedded **Spending Overview** action;
- wallet, month, and filter controls;
- grouped daily transaction cards;
- the existing floating add-transaction action.

## Executive recommendation

Implement the design as a focused redesign of the existing Timeline screen, not as a parallel screen or new navigation flow.

Reuse the current:

- `DashboardView` route and tab position;
- Timeline snapshot and monthly/yearly bar data;
- transaction sections and rows;
- transaction editor flow;
- search sheet;
- wallet filter;
- Spending Overview navigation;
- asynchronous stale-result protection;
- mixed-currency safeguards.

The only meaningful new financial capability should be a repository-backed comparison of expenses against the correct previous comparable period.

Do not add a database migration initially. The existing transaction day/month indexes should be sufficient for two bounded expense-sum queries. Add a daily gross cash-flow aggregate only if physical-device profiling demonstrates a real performance problem.

---

# 1. Current architecture and change boundary

The Timeline tab currently routes to `DashboardView`, which owns:

1. the search action;
2. cash-flow hero value;
3. wallet and period filters;
4. the monthly/yearly grouped bar chart;
5. Spending Overview navigation;
6. the grouped transaction feed;
7. the floating add button.

The current screen structure is approximately:

```text
hero
filters
chartCard
overviewButton
transactionFeed
floating add button
```

The redesigned hierarchy should become:

```text
Timeline header
  ├─ Cash Flow title
  └─ Search button

Cash-flow summary card
  ├─ Net cash flow
  ├─ Expense comparison
  ├─ Income / expense legend
  ├─ Income summary
  ├─ Expense summary
  ├─ Grouped monthly/yearly chart
  └─ Spending Overview action

Filter bar
  ├─ Wallet
  ├─ Selected month/year
  └─ Filters + active-count badge

Transaction feed
  └─ Collapsible day cards
      ├─ Day total
      └─ Transaction rows

Floating add button
```

No changes should be required in `CashRunwayRootView` or the tab configuration.

---

# 2. Product rules to decide before implementation

The visual design contains financial semantics that must be explicit and tested rather than inferred inside SwiftUI views.

## 2.1 Expense-comparison meaning

Recommended definition for the current month:

> Compare expenses from the first day of the selected month through the current day against the same ordinal day range in the previous month.

Example on July 11:

```text
Current range:  July 1–11
Baseline range: June 1–11
```

Formula:

```text
percentageChange = (currentExpense - baselineExpense) / baselineExpense
```

Presentation rules:

| Condition | Direction | Presentation |
|---|---|---|
| Current > baseline | Higher | Red upward arrow and “Expenses are higher than …” |
| Current < baseline | Lower | Green downward arrow and “Expenses are lower than …” |
| Current = baseline | Unchanged | Neutral indicator and “Expenses are unchanged from …” |
| Baseline = 0, current > 0 | Unavailable percentage | “New spending compared with …” |
| Baseline = 0, current = 0 | Unchanged/no data | “No spending in either period” |
| Range cannot be formed | Unavailable | Hide percentage and show neutral explanatory text |

Never display infinity, NaN, or a fabricated percentage when the baseline is zero.

## 2.2 Historical months

For a completed historical month, compare the selected full month with the previous full month.

Example:

```text
June 1–30 vs May 1–31
```

Do not compare a historical month only through today’s day number.

## 2.3 Year mode

The app already supports month and year Timeline periods.

Recommended behavior:

- current year: year-to-date versus the same date range in the previous year;
- completed historical year: full year versus the previous full year;
- leap-day ranges: clamp safely when the previous year does not contain February 29.

## 2.4 Filter scope

Recommended scope separation:

| Control | Summary/chart | Transaction feed |
|---|---:|---:|
| Wallet | Yes | Yes |
| Selected month/year | Yes | Yes |
| Text search | No | Yes |
| Category | No | Yes |
| Label | No | Yes |
| Transaction kind | Prefer no | Yes |

A text search such as “Bolt” should not silently redefine the top-level cash-flow KPI. Wallet and selected period are global financial scope. Search, category, label, and kind are feed-exploration filters.

This distinction should be represented explicitly instead of relying on incidental `TransactionQuery` behavior.

---

# 3. Existing data that should be reused

The current Timeline data model already contains most required values:

- `TimelineBarPoint`
  - period key;
  - income amount;
  - expense amount;
  - chart label.
- `TimelineSection`
  - day key;
  - localized period label;
  - day total;
  - transactions.
- `TimelineSnapshot`
  - selected anchor period;
  - wallet scope;
  - hero cash flow;
  - bars;
  - sections;
  - selected Timeline period.

The repository already:

1. normalizes wallet scope;
2. rejects invalid mixed-currency aggregate scopes;
3. loads monthly or yearly bars;
4. applies period scope to the transaction query;
5. loads transactions;
6. groups transactions by local day;
7. computes income minus expenses for the selected period.

The redesign should extend this snapshot rather than introduce a separate UI-only calculation path.

---

# 4. Target data model

## 4.1 Add `TimelineComparison`

Add a Core model similar to:

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

Use local day keys for ranges to remain consistent with the database and existing date-key utilities.

Extend `TimelineSnapshot` with:

```swift
public var comparison: TimelineComparison?
```

Do not place localized strings in Core. Core should return facts; the UI/presentation layer should construct localized sentences.

## 4.2 Add an explicit selected-period summary

The current UI can locate the selected bar and derive values, but a normalized summary reduces duplicate logic:

```swift
public struct TimelinePeriodSummary: Hashable, Sendable {
    public var periodKey: Int
    public var incomeMinor: Int64
    public var expenseMinor: Int64
    public var cashFlowMinor: Int64
}
```

Add it to `TimelineSnapshot`:

```swift
public var selectedPeriodSummary: TimelinePeriodSummary
```

This should become the single source for:

- main cash-flow amount;
- income card;
- expense card;
- comparison context;
- accessibility summary.

## 4.3 Add a narrow presentation model

Prefer a pure Timeline presentation type in `CashRunwayUIVM` or the UI module:

```swift
struct TimelineScreenPresentation {
    let cashFlowText: String
    let incomeText: String
    let expenseText: String
    let amountStyle: AmountStyle
    let comparison: TimelineComparisonPresentation?
    let chartPoints: [TimelineChartPointPresentation]
    let activeFilterCount: Int
}
```

This layer may handle:

- signed amount display;
- compact chart labels;
- comparison direction and icon;
- active filter count;
- accessibility summaries.

It should not perform repository access or own mutable app state.

---

# 5. Repository implementation

## 5.1 Add a comparison-window helper

Create a deterministic pure helper:

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

Inject `now` rather than calling `Date()` deep inside repository logic so tests remain deterministic.

Required edge cases:

- January to December year boundary;
- February and leap years;
- day 29–31 when the previous month is shorter;
- selected future month;
- selected completed month;
- current year YTD;
- historical full year;
- February 29 comparison against a non-leap year;
- local timezone/calendar boundaries.

When the comparable period is shorter, clamp to its final valid day.

## 5.2 Add the expense-sum query

Add a private repository method similar to:

```swift
private static func loadExpenseComparison(
    _ db: Database,
    monthKey: Int,
    walletID: UUID?,
    period: TimelinePeriod,
    now: Date
) throws -> TimelineComparison?
```

Use two bounded sums over `transactions`:

```sql
SELECT COALESCE(SUM(amount_minor), 0)
FROM transactions
WHERE is_deleted = 0
  AND type = 'expense'
  AND local_day_key BETWEEN ? AND ?
  AND (? IS NULL OR wallet_id = ?)
```

Rules:

- include expense transactions only;
- exclude income;
- exclude both transfer directions;
- exclude soft-deleted transactions;
- respect the normalized selected wallet;
- preserve mixed-currency aggregate rejection;
- compute the percentage from integer money values only after both sums are available.

## 5.3 Avoid a migration initially

The schema already indexes transaction day and month/wallet access. Start with direct bounded queries.

Do not introduce `daily_wallet_cashflow` unless profiling on a representative physical device shows a material regression, for example a p95 comparison-query duration above roughly 20–30 ms on a large fixture.

A new aggregate table would require:

- a permanent append-only migration;
- historical backfill;
- transaction mutation updates;
- CSV/import updates;
- bank-sync updates;
- backup/restore implications;
- migration-integrity tests;
- aggregate consistency tests.

That cost is not justified before measurement.

## 5.4 Keep one consistent database read

The selected summary, comparison, bars, and transaction sections should be constructed in the same repository read transaction where practical. This prevents the UI from showing values from different moments during sync/import/mutation activity.

---

# 6. SwiftUI decomposition

`DashboardView.swift` is already large. Do not continue expanding it indefinitely.

Recommended final component structure:

```text
DashboardView.swift
TimelineHeaderView.swift
TimelineSummaryCard.swift
TimelineGroupedBarChart.swift
TimelineFilterBar.swift
TimelineDayCard.swift
TimelinePresentation.swift
```

Optional:

```text
TimelineTransactionRow.swift
TimelinePeriodPickerSheet.swift
```

## Safe extraction sequence

Because the Xcode project uses explicit source-file references:

1. build the first visual iteration using private subviews in `DashboardView.swift`;
2. validate composition and behavior;
3. extract stable components into separate files;
4. add files through Xcode/project tooling;
5. verify `project.pbxproj` immediately;
6. remove any temporary project backup from staged changes;
7. run CodeGraph sync after symbol/file extraction.

This minimizes risky project-file churn while the layout is still changing.

---

# 7. Header design

Replace the current centered search/hero arrangement with a conventional title row:

```swift
HStack(alignment: .center) {
    Text(L10n.string("Cash Flow"))
        .font(.system(size: 32, weight: .bold, design: .rounded))

    Spacer()

    TimelineSearchButton(...)
}
```

Search button requirements:

- visual size around 40–44 points;
- interaction area at least 44 × 44 points;
- subtle rounded-rectangle surface;
- subdued secondary icon color;
- light border;
- reuse the current search sheet;
- preserve `timelineSearchButton` accessibility identifier.

---

# 8. Cash-flow summary card

## 8.1 Hierarchy

```text
TimelineSummaryCard
├─ summary header
│  ├─ net cash flow
│  ├─ comparison
│  └─ legend
├─ summary body
│  ├─ income card
│  ├─ expense card
│  └─ grouped bar chart
└─ Spending Overview button
```

## 8.2 Responsive behavior

Normal iPhone widths may use a two-column card body:

```text
metrics: approximately 35%
chart:   approximately 65%
```

For accessibility Dynamic Type or insufficient width, switch to a vertical layout:

```text
cash flow
comparison
legend
income / expense cards
full-width chart
overview button
```

Use `ViewThatFits`, an adaptive custom `Layout`, or an explicit `dynamicTypeSize` branch.

Do not solve layout pressure primarily with aggressive `.minimumScaleFactor`; financial values must remain readable.

## 8.3 Net amount

Rules:

- negative cash flow → negative semantic color;
- positive cash flow → positive semantic color;
- zero → primary/neutral text;
- use `.monospacedDigit()`;
- use the selected wallet/aggregate currency formatter;
- never hardcode the hryvnia sign;
- allow a controlled fallback layout for very large values.

## 8.4 Income and expense cards

Each card should contain:

```text
colored vertical indicator
label
formatted amount
```

Recommended styling:

- white or lightly tinted surface;
- green income indicator;
- red expense indicator;
- restrained border;
- clear trailing amount alignment;
- monospaced digits;
- no strong gradients.

Keep the distinction explicit between:

- aggregate `expenseMinor` as a positive magnitude;
- displayed expense amount as a negative signed value where required by UI convention.

## 8.5 Comparison block

Use complete localized sentences rather than concatenating fragments.

Required localization forms:

- `Expenses are %d%% higher than %@`
- `Expenses are %d%% lower than %@`
- `Expenses are unchanged from %@`
- `New spending compared with %@`
- `No spending in either period`
- `No comparable period`

Display:

- arrow and percentage on the first line;
- comparison sentence below;
- red for higher spending;
- green for lower spending;
- neutral treatment for unchanged/unavailable.

Color must not be the only indicator; direction must also be conveyed by icon and text.

---

# 9. Grouped bar chart

Retain a custom SwiftUI grouped-bar implementation for the initial redesign. The target requires predictable placement of:

- paired income/expense bars;
- exact compact values above each bar;
- zero placeholders;
- two-line period labels;
- selected-period emphasis.

Proposed API:

```swift
struct TimelineGroupedBarChart: View {
    let points: [TimelineBarPoint]
    let selectedPeriodKey: Int
    let currencyCode: CurrencyCode
    let onSelect: (Int) -> Void
}
```

## 9.1 Visible range

Recommended behavior:

- normal phone width: show approximately four period groups;
- retain up to six bars from existing repository data;
- horizontal scrolling when needed;
- center the selected period on appearance and after selection.

No data-layer change is needed for this range because the repository already supplies a six-period monthly/yearly window.

## 9.2 Scaling

```text
maximum = maximum visible income/expense magnitude
usableHeight = total height - value-label reserve - period-label reserve
barHeight = value / maximum × usableHeight
```

Rules:

- zero value: show a dash and no colored bar;
- non-zero tiny value: minimum visible bar height around 3–4 points;
- reserve vertical space for amount labels;
- prevent labels from overlapping adjacent groups;
- compact values using locale-aware formatting;
- expose full values through accessibility.

## 9.3 Interaction

Preserve current behavior:

- light haptic feedback;
- update `selectedMonthKey`;
- reload Timeline data;
- scroll selected bar into view;
- maintain the existing request-ID guard against stale asynchronous results.

---

# 10. Spending Overview action

Move the existing separate action into the bottom of the summary card.

Recommended appearance:

- full card width;
- 48–52-point height;
- subtle border;
- small green analytics icon;
- centered label;
- trailing chevron.

Preserve:

- current navigation to `TimelineOverviewView`;
- `overviewOpenButton` accessibility identifier;
- no duplication of Overview logic in the Timeline screen.

---

# 11. Filter bar

The target filter bar contains:

1. wallet scope;
2. explicit selected month/year;
3. advanced filters with a count badge.

## 11.1 Wallet chip

Reuse current wallet selection and asynchronous reload behavior.

Preserve mixed-currency rules: when an all-wallet aggregate cannot be represented in one currency, require selection of a single wallet rather than summing incompatible currencies.

## 11.2 Period chip

Display an explicit label such as:

```text
July 2026
```

Recommended MVP interaction: a sheet with:

- previous/next month controls;
- year selector;
- month grid;
- current-period shortcut;
- month/year Timeline mode control where appropriate.

A menu-based implementation is acceptable for the first iteration but scales poorly for long history.

## 11.3 Filters chip and badge

The badge should count only advanced feed filters:

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

Do not count wallet or selected Timeline period because they have dedicated controls.

## 11.4 Search and Filters integration

Use one shared query state and one shared sheet.

- Header search button: open the sheet focused on the text field.
- Filters chip: open the same sheet in its default filter state.
- Apply: perform one feed reload.
- Reset: clear all advanced feed filters.

Do not create independent search and filter query states.

---

# 12. Transaction day cards

Wrap each `TimelineSection` in a visual card.

Proposed component:

```swift
TimelineDayCard(
    section: section,
    isCollapsed: ...,
    onToggle: ...,
    onOpenTransaction: ...
)
```

## 12.1 Header

Contents:

```text
calendar icon
localized weekday/date
spacer
day total
expand/collapse chevron
```

The entire header should be one accessible button with a full-width content shape and minimum 44–48-point height.

Suggested local state:

```swift
@State private var collapsedDayKeys: Set<Int> = []
```

Recommended behavior:

- all sections expanded by default;
- preserve collapsed state while remaining on the screen;
- reset collapsed state when wallet or selected period changes.

## 12.2 Transaction rows

Reuse the existing `TransactionRow` behavior and model.

Refinements:

- category glyph around 44–48 points where density requires;
- merchant and amount on one line;
- secondary metadata on one line;
- fixed trailing amount column;
- trailing chevron;
- inset separators beginning after the glyph;
- keep existing row tap → load draft → open editor;
- preserve transaction-row accessibility identifiers.

Do not invent card-network or bank logos when the model does not provide them. Use existing category, wallet, source, label, and merchant data.

---

# 13. Theme and visual tokens

Reuse `CashRunwayTheme` semantic colors and typography.

Potential Timeline-specific layout tokens:

```swift
static let timelinePageHorizontalPadding: CGFloat = 16
static let timelineSectionSpacing: CGFloat = 14
static let timelineCardRadius: CGFloat = 24
static let timelineInnerRadius: CGFloat = 16
static let timelineCardPadding: CGFloat = 16
static let minimumTouchTarget: CGFloat = 44
```

Visual principles:

- near-white page background and white surfaces;
- very subtle card border and shadow;
- green reserved for income, positive direction, selected state, and key actions;
- red reserved for expenses and negative direction;
- normal body text remains neutral;
- consistent radius family;
- trailing-aligned monospaced money values;
- avoid heavy gradients, thick borders, and multiple competing accent colors.

---

# 14. Loading, empty, and error states

## 14.1 Loading

Initial implementation may preserve the current loading behavior, but the desired follow-up behavior is:

- initial load: redacted/skeleton summary and feed;
- wallet/period change: preserve previous content while loading;
- show a small progress indicator within the summary area;
- avoid blanketing the entire screen for every period tap.

## 14.2 Empty selected period

Keep the summary structure visible:

- zero net amount;
- zero income and expense values;
- empty chart bars;
- unavailable comparison;
- clear empty transaction-feed state.

The selected wallet and period still provide useful context even when no transactions exist.

## 14.3 Mixed currencies

Never add unlike currencies without conversion.

Continue to either:

- require a single wallet;
- or show the existing mixed-currency unavailable state.

## 14.4 Large-number cases

At minimum, verify:

```text
₴0.00
-₴864.00
-₴79,471.22
₴9,999,999.99
-$1,234,567.89
€1,234,567.89
```

The main amount should avoid wrapping where possible. Chart values should compact safely.

---

# 15. Localization

The app supports system language, English, and Ukrainian.

Add complete localization entries for:

- Cash Flow;
- Income;
- Expenses;
- Spending Overview;
- All Wallets;
- Filters;
- Current Month;
- comparison sentences;
- no-comparison states;
- chart accessibility labels;
- day expand/collapse labels.

Use the repository localization script to modify `AppHost/Localizable.xcstrings`; do not manually rewrite the complete catalog.

Avoid composing grammatically dependent sentences from separately localized fragments.

---

# 16. Accessibility

Add identifiers for new elements, for example:

```swift
static let timelineSummaryCard = "timeline.summaryCard"
static let timelineIncomeValue = "timeline.incomeValue"
static let timelineExpenseValue = "timeline.expenseValue"
static let timelineComparison = "timeline.comparison"
static let timelineMonthPicker = "timeline.monthPicker"
static let timelineFilterButton = "timeline.filterButton"
static let timelineFilterBadge = "timeline.filterBadge"
```

Add helpers for:

```swift
timelineDayHeader(_ dayKey: Int)
timelineDayToggle(_ dayKey: Int)
timelineChartPoint(_ periodKey: Int)
```

Preserve existing identifiers for:

- search;
- wallet menu;
- cash-flow value;
- Spending Overview;
- transaction rows;
- add transaction.

Recommended VoiceOver order in the summary card:

1. selected period and wallet;
2. net cash flow;
3. income;
4. expenses;
5. comparison;
6. chart summary;
7. Spending Overview action.

Each chart point should announce a complete summary, for example:

```text
April 2026. Income 52,800 hryvnias. Expenses 45,700 hryvnias.
```

Also verify:

- minimum 44 × 44-point controls;
- Bold Text;
- Reduce Motion;
- accessibility Dynamic Type;
- light and dark appearance;
- status understandable without color.

---

# 17. Test strategy

## 17.1 Pure comparison-window tests

Cover:

1. current partial month;
2. completed historical month;
3. January/December boundary;
4. March 31 compared with February;
5. leap-year February;
6. current year YTD;
7. historical full year;
8. future selected period;
9. baseline zero/current positive;
10. both periods zero;
11. timezone/calendar boundary behavior.

## 17.2 Repository integration tests

Verify:

- expenses included;
- income excluded;
- transfers excluded;
- deleted transactions excluded;
- wallet scope respected;
- single-currency all-wallet scope supported;
- mixed currencies rejected;
- current/baseline amounts correct;
- percentage direction correct;
- existing section grouping unchanged;
- summary, comparison, bars, and sections remain internally consistent.

## 17.3 Presentation tests

Verify:

- negative/positive/zero cash-flow style;
- higher/lower/unchanged/unavailable comparison presentation;
- zero baseline never produces infinity/NaN;
- active filter count;
- compact chart formatting;
- selected chart point state;
- localized date-range labels;
- signed expense display.

## 17.4 Visual QA matrix

| Dimension | Cases |
|---|---|
| Language | Ukrainian, English |
| Appearance | Light, dark |
| Width | Small, standard, large iPhone |
| Dynamic Type | Default, XL, accessibility sizes |
| Cash flow | Positive, negative, zero |
| Data density | Empty, one day, many days |
| Currency | UAH, USD, EUR, mixed |
| Chart | Zero income, zero expense, large values |
| Text | Long merchant/category/wallet names |

Existing UI-test identifiers and flows should be preserved even if XCUITest changes are deferred according to repository policy.

---

# 18. File-by-file implementation map

| File | Planned change |
|---|---|
| `Sources/CashRunwayCore/Models.swift` | Add Timeline comparison and selected-period summary models |
| `Sources/CashRunwayCore/CashRunwayRepository.swift` | Add comparison-window query and enrich Timeline snapshot |
| Repository protocol declarations | Update snapshot contract where required |
| `Sources/CashRunwayUI/AppModel.swift` | Consume enriched snapshot without duplicating calculations |
| `Sources/CashRunwayUI/DashboardView.swift` | Replace current hero/chart/feed hierarchy |
| `Sources/CashRunwayUI/Theme.swift` | Add reusable Timeline layout/formatting tokens |
| `Sources/CashRunwayUI/AccessibilityIdentifiers.swift` | Add summary, filter, chart, and day identifiers |
| `Sources/CashRunwayUI/TimelineSearchSheet.swift` | Support search-focused and filter-focused entry modes |
| `AppHost/Localizable.xcstrings` | Add English/Ukrainian strings through approved script |
| Core test files | Date-window and repository comparison tests |
| UIVM/presentation test files | Formatting, trend, badge, and chart tests |
| `CashRunway.xcodeproj/project.pbxproj` | Update only when stable new Swift files are extracted |

---

# 19. Implementation phases

## Phase 0 — Specification lock

Confirm:

- partial-month comparison semantics;
- historical-month semantics;
- year-mode semantics;
- filter scope;
- zero-baseline wording;
- collapsible day behavior;
- number of visible chart periods.

**Exit criterion:** no unresolved financial rule remains inside visual-design comments.

## Phase 1 — Core models and date logic

Implement:

- `TimelineComparison`;
- selected-period summary;
- comparison-window helper;
- percentage calculation;
- pure unit tests.

**Exit criterion:** all date and zero-baseline edge cases pass without database access.

## Phase 2 — Repository integration

Implement:

- bounded expense queries;
- wallet/mixed-currency behavior;
- enriched `TimelineSnapshot`;
- repository integration tests.

**Exit criterion:** one snapshot returns summary, comparison, bars, and transaction sections consistently.

## Phase 3 — Summary card and chart

Implement:

- new header;
- cash-flow summary card;
- income/expense cards;
- comparison block;
- grouped chart;
- embedded Spending Overview action.

Keep early subviews private in `DashboardView.swift` until the design stabilizes.

**Exit criterion:** normal-size Ukrainian light-mode screen matches the intended hierarchy and information density.

## Phase 4 — Period and filters

Implement:

- wallet chip restyle;
- explicit period picker;
- filter badge;
- unified search/filter sheet;
- filter-scope separation.

**Exit criterion:** global summary scope and feed exploration filters behave predictably.

## Phase 5 — Day-card feed

Implement:

- daily card containers;
- collapse/expand;
- row chevrons and inset separators;
- preservation of transaction-editor navigation.

**Exit criterion:** all existing transaction open/edit/add flows remain functional.

## Phase 6 — Component extraction

After visual stability:

- extract subviews;
- add files safely to the Xcode project;
- verify project integrity;
- run CodeGraph sync.

**Exit criterion:** `DashboardView` is an orchestration layer rather than a large rendering monolith.

## Phase 7 — Localization, accessibility, and QA

Complete:

- English and Ukrainian localization;
- dark mode;
- Dynamic Type;
- VoiceOver;
- empty/mixed-currency/large-value states;
- visual screenshot matrix;
- full validation.

---

# 20. Validation gates

Use existing repository workflows:

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

Additional requirements:

- use the isolated SwiftPM gate when multiple worktrees are active;
- run performance tests if comparison-query performance or chart rendering is changed materially;
- verify `project.pbxproj` immediately after any project-file edit;
- report every skipped gate and the reason;
- treat build, unit tests, smoke launch, and physical-device readiness as separate status categories.

---

# 21. Acceptance criteria

The redesign is complete when:

1. The existing Timeline tab adopts the supplied visual hierarchy.
2. Net cash flow, income, expenses, and chart values come from one selected-period snapshot.
3. Expense comparison follows a documented matched-period algorithm.
4. Zero-baseline cases never display infinity, NaN, or a misleading percentage.
5. Wallet and period controls affect both summary and feed.
6. Search/category/label filters affect the feed without silently redefining the headline KPI.
7. Mixed currencies are never summed without conversion.
8. Chart labels do not collide on supported phone widths.
9. Accessibility Dynamic Type switches layout rather than shrinking values excessively.
10. Day cards display correct signed totals and support the approved collapse behavior.
11. Transaction rows still open the current editor.
12. Search, wallet selection, Spending Overview, and add-transaction flows remain intact.
13. Ukrainian and English wording is grammatically correct.
14. VoiceOver communicates values and comparison direction without relying on color.
15. Focused tests, full isolated tests, lint, UI validation, build, and smoke checks pass.

---

# 22. Estimated effort

| Work | Estimate |
|---|---:|
| Product/data-rule decisions | 0.5 day |
| Core models, date logic, unit tests | 1–1.5 days |
| Repository query and integration tests | 0.5–1 day |
| Summary card and grouped chart | 1.5–2 days |
| Period picker and filters | 0.75–1 day |
| Day-card transaction feed | 0.5–1 day |
| Localization, accessibility, visual QA | 1–1.5 days |
| **Total** | **5–8 engineering days** |

A shorter implementation can reproduce the static appearance, but production quality requires explicit comparison semantics, mixed-currency safety, responsive layout, accessibility, localization, and regression validation.
