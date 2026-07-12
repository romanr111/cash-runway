# Timeline Redesign — Phase 2: Header, Summary Card, and Chart

## Position in the sequence

**Phase 2 of 3.** Start only after Phase 1 financial invariants and tests pass.

Depends on:

- `timeline-redesign-phase-1-financial-foundation.md`

Next:

- `timeline-redesign-phase-3-feed-filters-qa.md`

## Objective

Rebuild the top half of the existing Timeline screen to match the approved reference while preserving correct selected-period data, historical navigation, navigation to Spending Overview, and accessibility.

This phase implements:

- the page header;
- compact search action;
- one unified summary card;
- net, income, expense, and matched-period comparison;
- four-period grouped chart;
- embedded Spending Overview action.

It does not redesign filters or transaction day cards.

---

## 1. Screen hierarchy

Keep `DashboardView` as the Timeline orchestration view.

Target hierarchy:

```text
Header
  ├─ Cash Flow title
  └─ compact Search action

Summary card
  ├─ Top row
  │  ├─ net cash flow
  │  ├─ expense comparison
  │  └─ income/expense legend
  ├─ Main row
  │  ├─ income and expense metric cards
  │  └─ four-period grouped chart
  └─ Spending Overview action

Existing filters
Existing transaction feed
Existing floating add action
```

Do not create a second screen or change the root tab structure.

---

## 2. Data rules

### Summary source

Every selected-period number in the summary card comes from the Phase 1 `TimelineSnapshot`:

- net: `heroCashFlowMinor`;
- income: selected `TimelineBarPoint.incomeMinor` from `snapshot.bars`;
- expense: selected `TimelineBarPoint.expenseMinor` from `snapshot.bars`;
- comparison: `snapshot.comparison`.

Resolve the selected snapshot bar once in a pure presentation adapter and reuse it.

Do not recalculate the headline from `model.allBars`.

### Historical chart source

Use `model.allBars` for historical navigation, but replace the selected period's displayed point with the authoritative snapshot point before rendering.

This keeps current month/year month-to-date or year-to-date while historical completed periods remain full aggregates.

Example merge rule:

```swift
let chartPoints = allBars.map { point in
    point.periodKey == selectedSnapshotPoint.periodKey
        ? selectedSnapshotPoint
        : point
}
```

Do not maintain a second mutable chart-data array in AppModel.

---

## 3. Presentation adapter

Add a pure UI-facing type, for example:

```swift
struct TimelineScreenPresentation {
    let selectedPeriodKey: Int
    let netText: String
    let incomeText: String
    let expenseText: String
    let netStyle: AmountStyle
    let comparison: TimelineComparisonPresentation?
    let chartPoints: [TimelineBarPoint]
}
```

Responsibilities:

- selected-bar resolution;
- signed/unsigned amount formatting;
- comparison text and arrow selection;
- locale-aware compact chart values;
- accessibility summaries.

Keep it deterministic and unit-testable.

Do not put localized strings into Core.

---

## 4. Header specification

### Title

- leading aligned;
- standard SF Pro system typeface, not rounded display type;
- approximately 32–34 pt bold at default Dynamic Type;
- one line on standard widths;
- use semantic primary text color.

### Search action

The action should be visible but subordinate to the title.

Visual geometry:

- visible rounded-square background: **36–38 pt**;
- interaction target: at least **44 × 44 pt**;
- icon: 15–16 pt, medium/semibold;
- subtle accent tint or neutral surface;
- no strong shadow;
- border absent or very low contrast;
- no bright saturated block that competes with the title.

Preserve the existing search accessibility identifier and sheet action.

---

## 5. Summary card geometry

Use a single surface card.

Recommended default-width tokens:

```swift
pageHorizontalPadding = 16
cardCornerRadius = 24
cardPadding = 16
internalSpacing = 12
minimumTouchTarget = 44
```

At a standard 390–393 pt iPhone width:

- card should fill available width;
- target card height is approximately 260–285 pt before Dynamic Type expansion;
- left metrics region is approximately 35–38% of usable width;
- chart region is approximately 62–65%;
- do not compress the entire design with a global scale transform.

The layout must expand vertically when content requires it.

### Top row

Order:

```text
[ net cash flow ] [ comparison ] [ legend ]
```

The net amount is the primary visual anchor.

Recommended default size:

- 30–34 pt bold;
- standard system design;
- `.monospacedDigit()`;
- one line where possible;
- controlled smaller breakpoint for very large values;
- do not rely primarily on aggressive `.minimumScaleFactor`.

Color:

- negative → semantic negative;
- positive → semantic positive;
- zero → primary neutral.

### Income and expense metric cards

Each metric has:

```text
thin vertical semantic indicator
label
formatted amount
```

Rules:

- income amount displays positive magnitude;
- expense amount displays negative sign in the UI even though Core stores a positive magnitude;
- use monospaced digits;
- keep card styling subtle;
- maintain consistent internal alignment between both cards.

### Comparison block

Display:

```text
↗ +18%
Expenses are higher than June 1–11
```

or the equivalent lower/unchanged/unavailable state.

Rules:

- percentage appears only once;
- explanatory line must state that it compares expenses;
- use a complete localized sentence;
- color is not the only signal: retain arrow and wording;
- do not show infinity, NaN, or `+0%` for unavailable states.

### Legend

- compact income and expense dots with labels;
- align near the chart rather than the net amount;
- keep it visually secondary;
- use semantic colors from `CashRunwayTheme`.

---

## 6. Four-period chart behavior

### Deterministic viewport

At standard width, display exactly four period groups.

The selected period must be the **trailing/rightmost** group:

```text
April  May  June  July(selected)
```

For an older selection, the window ends at that selection:

```text
February  March  April  May(selected)
```

If fewer than four earlier periods exist, show available periods without inventing data before history begins.

### Navigation

Retain full historical access without an unbounded layout:

- keep full data in `model.allBars`;
- render a four-point window ending at the selected period;
- horizontal drag shifts the selected period/window by one or more periods;
- tapping a visible group selects that period;
- selecting a period triggers the existing stale-result-protected Timeline reload;
- provide light haptic feedback for a committed period change.

Do not render a fixed six-period-only chart.

### Proposed API

```swift
struct TimelineGroupedBarChart: View {
    let points: [TimelineBarPoint]
    let selectedPeriodKey: Int
    let period: TimelinePeriod
    let currencyCode: CurrencyCode
    let onSelect: (Int) -> Void
}
```

The component derives its visible four-point window from `points` and `selectedPeriodKey`.

### Scaling

Calculate the chart scale from the four displayed points only:

```text
maximum = max(displayed income/expense magnitude)
usableHeight = chartHeight - valueLabelReserve - periodLabelReserve
barHeight = value / maximum × usableHeight
```

Rules:

- zero → dash, no colored bar;
- non-zero values receive a 3–4 pt minimum visible bar;
- reserve explicit space above bars for values;
- selected period may use stronger opacity/weight, not a large background block;
- bars must not be inverted below a baseline;
- expense remains a positive-height red bar because the chart compares magnitudes.

### Value labels

Use locale-aware compact values without hardcoded hryvnia symbols.

Examples:

```text
52,8 тис.
61,3 тис.
78,5 тис.
```

or English equivalents.

Collision rule:

- each label is centered over its own bar;
- if paired labels would overlap because bar heights are nearly equal, raise the leading label by one label line;
- never let a label overlap the next period group;
- expose the full unabridged value through accessibility.

### Period labels

Month mode:

```text
Квіт.
2026
```

Year mode:

```text
2026
```

Use two-line month/year labels and fixed group widths so four groups fit predictably.

---

## 7. Spending Overview action

Move the existing action into the bottom of the summary card.

Requirements:

- preserve the existing navigation destination;
- preserve the existing accessibility identifier;
- full-width 44–48 pt row;
- icon and chevron remain secondary;
- do not duplicate Overview calculations or state inside Timeline.

---

## 8. Responsive behavior

### Standard width

Use the reference composition:

```text
Top row: net | comparison | legend
Main row: metric cards | chart
Bottom: Spending Overview
```

### Narrow width or accessibility Dynamic Type

Switch layout rather than shrinking everything:

```text
net
comparison + legend
income and expense cards
full-width chart
Spending Overview
```

Use `ViewThatFits`, a custom `Layout`, or an explicit Dynamic Type branch.

Do not hide essential comparison wording at large text sizes.

---

## 9. Typography and formatting

- use standard system font for title, net, and monetary values;
- use `.monospacedDigit()` for money and chart numbers;
- use rounded design only where the existing product intentionally requires it;
- never hardcode `₴`;
- use `MoneyFormatter`/`NumberFormatter` with locale-specific symbol position and separators.

Expected examples:

```text
uk_UA: −79 471,22 ₴
en_US: −₴79,471.22
de_DE: −79.471,22 €
```

Use a true minus sign where the formatter supports it.

---

## 10. Theme and dark mode

Reuse semantic theme colors:

- `background`;
- `surface`;
- `textPrimary`/`textSecondary`/`textMuted`;
- `positive`;
- `negative`;
- `line`;
- `pill`.

Add layout tokens only when they are reused or improve consistency.

Avoid copying literal light-mode reference colors into dark mode.

---

## 11. Accessibility

Add or preserve identifiers for:

```swift
timelineSummaryCard
timelineIncomeValue
timelineExpenseValue
timelineComparison
timelineChartPoint(_ periodKey: Int)
```

Preserve existing identifiers for:

- search;
- cash flow;
- Spending Overview;
- add transaction.

VoiceOver reading order:

1. selected period and wallet;
2. net cash flow;
3. income;
4. expenses;
5. comparison;
6. chart summary;
7. Spending Overview.

Chart points are buttons with a combined label containing period, full income, full expense, and selected state.

Validate:

- 44 × 44 touch targets;
- Bold Text;
- Reduce Motion;
- accessibility Dynamic Type;
- light and dark appearance;
- meaning without color.

---

## 12. Implementation structure

Keep the first geometry iteration as private subviews in `DashboardView.swift`.

Extract only after the reference layout is stable.

Likely final files:

```text
Sources/CashRunwayUI/DashboardView.swift
Sources/CashRunwayUI/TimelineSummaryCard.swift
Sources/CashRunwayUI/TimelineGroupedBarChart.swift
Sources/CashRunwayUI/TimelinePresentation.swift
Sources/CashRunwayUI/Theme.swift
Sources/CashRunwayUI/AccessibilityIdentifiers.swift
Tests/CashRunwayUIVMTests/TimelinePresentationTests.swift
```

Immediately verify `project.pbxproj` after adding Swift files.

---

## 13. Tests

### Presentation tests

- positive, negative, and zero net styling;
- selected snapshot bar overrides the same period in `allBars`;
- income and expense signs;
- higher/lower/unchanged/unavailable comparison copy;
- percentage appears once;
- zero baseline is safe;
- compact values respect locale;
- four-point window ends at selected period;
- first-history edge contains fewer than four valid points without placeholders before history.

### Interaction tests

- tapping a chart period updates selection once;
- dragging shifts the selected trailing period;
- stale reload results cannot overwrite a newer selection;
- Spending Overview navigation still works;
- search button still opens the existing sheet.

### Visual checks

Use a deterministic seeded fixture matching the approved reference:

```text
Locale: uk_UA
Date: 2026-07-11
Width: 390–393 pt
Income: 0
Expenses: 79 471,22 ₴
Net: −79 471,22 ₴
Comparison: +18%
Visible periods: April–July 2026
Selected period: July 2026
```

Capture simulator screenshots and compare against the reference with a semi-transparent overlay.

Check:

- card proportions;
- search-button visual prominence;
- title and number typography;
- four visible period groups;
- chart-label collision;
- selected period trailing alignment;
- no clipping at large values.

---

## 14. Validation gates

Run at minimum:

```bash
just test-filter TimelinePresentationTests
just check-isolated
just lint
just ui-check
just build
just smoke
just graph-sync
```

Record the simulator/device and locale used for visual QA.

---

## 15. Phase 2 acceptance criteria

Phase 2 is complete only when:

1. the existing Timeline top area matches the approved hierarchy;
2. the search control is compact and subdued while retaining a 44 pt target;
3. net, income, expense, comparison, and selected chart point use the Phase 1 snapshot;
4. exactly four periods appear at standard width with the selected period trailing;
5. older history remains navigable;
6. chart labels do not collide on supported widths;
7. large values use controlled responsive typography rather than global scaling;
8. currency and compact values are locale-correct;
9. Spending Overview behavior is preserved;
10. Dynamic Type, VoiceOver, dark mode, UI checks, build, and smoke validation pass.

Do not begin the final feed/filter polish until the summary screenshot is visually accepted.