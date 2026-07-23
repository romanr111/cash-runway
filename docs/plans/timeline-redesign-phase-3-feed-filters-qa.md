# Timeline Redesign — Phase 3: Filters, Transaction Feed, and Final QA

## Position in the sequence

**Phase 3 of 3.** Start only after the Phase 2 summary card has passed visual review.

Depends on:

1. `timeline-redesign-phase-1-financial-foundation.md`
2. `timeline-redesign-phase-2-summary-chart.md`

## Objective

Complete the redesigned Timeline screen by refining wallet/period controls, reusing the existing search/filter system, grouping transactions into daily cards, and running full production QA.

This phase must preserve the financial semantics and summary-card geometry already validated in Phases 1 and 2.

---

## 1. Final screen order

```text
Header
Summary card
Filter bar
Transaction day cards
Floating add action
Bottom navigation
```

The floating add button must not cover transaction amounts, row chevrons, or the bottom navigation.

---

## 2. Filter scope

Lock the following behavior:

| Control | Summary and chart | Transaction feed |
|---|---:|---:|
| Wallet | Yes | Yes |
| Selected month/year | Yes | Yes |
| Text search | No | Yes |
| Category | No | Yes |
| Label | No | Yes |
| Transaction kind | No | Yes |
| Custom date range | No | Yes |

Wallet and period define the financial scope.

Search and advanced filters are feed-exploration tools only.

Searching for `Bolt` must not change net cash flow, income, expenses, comparison, or chart bars.

---

## 3. Filter bar

At standard width, render three compact controls:

```text
[ wallet ] [ selected month/year ] [ Filters  badge ]
```

Recommended behavior:

- horizontally balanced without text clipping;
- 44 pt minimum interaction height;
- subtle surface/background treatment;
- icons visually secondary to labels;
- use menus or a compact sheet rather than a large permanent picker.

### Wallet control

- preserve Phase 1 truthful All Wallets behavior;
- show explicit wallet name or localized `All Wallets`;
- never silently normalize a valid same-currency all-wallet selection to one wallet;
- for mixed currencies, require a single wallet before showing aggregate summary values.

### Period control

Display the actual selected period, not only `Month` or `Year`:

```text
July 2026
2026
```

The control may open a menu or compact selector.

A full month-grid navigator is optional and must not block completion.

---

## 4. Reuse the existing search/filter sheet

Do not build a second query system.

Extend `TimelineSearchSheet` with an entry mode:

```swift
enum TimelineSearchEntryMode {
    case search
    case filters
}
```

### Search entry

The header search action:

- opens the existing sheet;
- focuses the text field with `@FocusState`;
- preserves existing advanced filters;
- shows a clear-search action when text is non-empty.

### Filter entry

The Filters chip:

- opens the same sheet without forcing text-field focus;
- exposes type, category, label, and date range;
- preserves the current search text.

Both modes edit one draft `TransactionQuery` and perform one reload on Apply.

---

## 5. Reset semantics

Avoid a destructive global reset when the user entered through only one mode.

### Reset in search mode

- clear `searchText`;
- preserve category, label, kind, and date range;
- preserve wallet and Timeline period.

### Reset in filters mode

- reset category;
- reset label;
- reset kinds to all;
- clear date range;
- preserve `searchText`;
- preserve wallet and Timeline period.

A separate explicit `Clear all` action may clear both search and advanced feed filters.

---

## 6. Filter badge

The Filters badge counts **advanced filters only**:

```swift
var activeAdvancedFilterCount: Int {
    var count = 0
    if categoryID != nil { count += 1 }
    if labelID != nil { count += 1 }
    if kinds != Set(TransactionDraft.Kind.allCases) { count += 1 }
    if startDate != nil || endDate != nil { count += 1 }
    return count
}
```

Do not count:

- text search;
- wallet;
- selected Timeline period.

Indicate active text search on the search action itself, for example with a subtle filled state or small status dot.

---

## 7. Date-range behavior

Use the Phase 1 inclusive local-day-key semantics:

```sql
local_day_key >= startDayKey
local_day_key <= endDayKey
```

Requirements:

- complete selected end date is included;
- start later than end is prevented or validated before Apply;
- clearing the date-range toggle clears both dates;
- custom feed range is intersected with the selected month/year;
- summary and chart remain scoped only by wallet and selected period.

Test local midnight and DST boundaries.

---

## 8. Transaction day cards

Wrap each existing `TimelineSection` in one surface card.

### Day header

Structure:

```text
calendar icon
localized weekday/date
spacer
day total
expand/collapse chevron
```

Requirements:

- entire header is one accessible button;
- minimum height 44–48 pt;
- total uses a fixed trailing alignment;
- negative and positive totals use semantic amount color;
- VoiceOver announces date, total, and expanded/collapsed state.

### Collapse state

Suggested local state:

```swift
@State private var collapsedDayKeys: Set<Int> = []
```

Behavior:

- expanded by default;
- preserve state while the user remains on Timeline;
- reset on wallet or selected-period change;
- do not persist to the database.

### Transaction rows

Reuse the existing editor action and transaction row data.

Target layout:

```text
category glyph | title / metadata | amount | chevron
```

Rules:

- glyph approximately 42–46 pt;
- merchant/category title and amount remain on one line where possible;
- secondary metadata remains one concise line;
- fixed trailing amount column;
- inset separators;
- preserve transaction accessibility identifiers;
- do not invent card network, bank, or provider logos absent from the model;
- retain display-only masked-card-title behavior already approved elsewhere;
- phone numbers, IBANs, and order IDs must not be transformed into card masks.

### Day total correctness

Day totals must use signed displayed transaction amounts:

- expenses negative;
- income positive;
- transfer handling remains consistent with existing feed semantics;
- mixed-currency day totals show unavailable state rather than an invalid sum.

---

## 9. Empty and loading states

### Loading

Do not cover the entire screen with an opaque loading blanket for every period/chart change.

Preferred behavior:

- keep previous valid content visible during reload;
- show a small progress indicator in the summary/filter area;
- disable only interactions that could create conflicting selection changes;
- preserve request-ID stale-result protection.

An initial bootstrap loading state may remain broader.

### Empty selected period

Keep the structural screen visible:

- zero net/income/expense;
- empty or zero chart point;
- unavailable comparison;
- visible filter bar;
- clear empty-feed message;
- floating add action remains available.

### Filtered empty feed

Distinguish:

- no transactions in selected period;
- no transactions matching active search/filters.

Offer a clear-filters action only in the second case.

---

## 10. Localization

Add complete English and Ukrainian strings through the repository localization workflow.

Required groups:

- Cash Flow;
- Income;
- Expenses;
- Spending Overview;
- All Wallets;
- Filters;
- period names and month labels;
- comparison sentences;
- unavailable/mixed-currency states;
- search/filter reset actions;
- expand/collapse actions;
- empty-feed messages;
- chart accessibility labels.

Comparison copy must be complete sentences, not concatenated fragments.

Examples of intent:

```text
Витрати вищі, ніж за 1–11 червня
Витрати нижчі, ніж за 1–11 червня
Витрати не змінилися порівняно з 1–11 червня
```

The percentage remains on the separate first line and is not repeated in the sentence.

Validate Ukrainian grammar manually.

---

## 11. Accessibility

Add or preserve identifiers for:

```swift
timelineWalletMenu
timelineMonthPicker
timelineFilterButton
timelineFilterBadge
timelineDayHeader(_ dayKey: Int)
timelineDayToggle(_ dayKey: Int)
transactionRow(_ item: TransactionListItem)
```

Validate:

- all controls have at least 44 × 44 hit areas;
- correct VoiceOver reading order;
- day headers announce expanded/collapsed state;
- filter badge has a spoken count;
- color is not the only indicator;
- accessibility Dynamic Type;
- Bold Text;
- Reduce Motion;
- light and dark mode;
- keyboard/focus behavior in search sheet.

---

## 12. Year-mode performance

The current Timeline can load a full year of transactions without an explicit limit.

Do not add speculative pagination before measurement.

Create a representative fixture with approximately 5,000–10,000 transactions and measure on a physical device:

- repository snapshot load time;
- time to first usable screen;
- scrolling frame stability;
- expand/collapse responsiveness;
- search/filter Apply latency;
- memory use.

If performance is unacceptable, prefer in order:

1. lazy day-card rendering;
2. month-grouped lazy expansion;
3. pagination with stable ordering.

Do not change financial summary semantics to improve feed performance.

---

## 13. Final visual QA fixture

Use one deterministic reference fixture for the full screen:

```text
Locale: uk_UA
Date: 2026-07-11
Device width: 390–393 pt
Wallet scope: All Wallets, one currency
Income: 0
Expenses: 79 471,22 ₴
Net: −79 471,22 ₴
Comparison: +18% versus June 1–11
Visible periods: April–July 2026
Selected period: July 2026
Active advanced filters: 1
Feed: multiple days and transaction types
```

Capture screenshots for:

- standard light mode;
- dark mode;
- small iPhone width;
- large iPhone width;
- XL Dynamic Type;
- accessibility Dynamic Type;
- long merchant/category/wallet names;
- very large monetary values;
- zero income;
- zero expense;
- mixed-currency unavailable state.

Use overlay comparison against the approved reference for the standard fixture.

---

## 14. Test plan

### Filter tests

- search affects feed only;
- category/label/kind/date affect feed only;
- wallet and selected period affect summary, chart, and feed;
- filter badge excludes search text;
- search-mode reset preserves advanced filters;
- filter-mode reset preserves search;
- Apply triggers one reload;
- complete end date is included;
- invalid date range cannot apply.

### Feed tests

- day sections sort newest first;
- signed day totals are correct;
- rows keep editor action;
- collapse state resets on wallet/period change;
- mixed-currency total is unavailable;
- empty unfiltered and empty filtered states differ;
- masked-card display logic does not alter persisted merchant/note values.

### UI regression tests

- search opens in focused mode;
- Filters opens without forced focus;
- Spending Overview still navigates;
- add transaction still opens composer;
- row tap still opens editor;
- bottom navigation remains usable;
- add button does not cover the final row.

### Full regression suite

- Phase 1 snapshot/comparison tests remain green;
- Phase 2 presentation/chart tests remain green;
- imports, bank sync, editing, deletion, and restore behavior remain unaffected.

---

## 15. Likely files

```text
Sources/CashRunwayUI/DashboardView.swift
Sources/CashRunwayUI/TimelineSearchSheet.swift
Sources/CashRunwayUI/TimelineFilterBar.swift
Sources/CashRunwayUI/TimelineDayCard.swift
Sources/CashRunwayUI/Theme.swift
Sources/CashRunwayUI/AccessibilityIdentifiers.swift
AppHost/Localizable.xcstrings
Tests/CashRunwayUIVMTests/TimelineFilterPresentationTests.swift
Tests/CashRunwayUITests/TimelineScreenTests.swift
```

Keep components private until geometry and behavior are stable. Update `project.pbxproj` only when extracting new files.

---

## 16. Validation gates

Run the repository workflows:

```bash
just session-start
just test-filter Timeline
just check-unit-parallel
just check-isolated
just lint
just ui-check
just build
just smoke
just graph-sync
```

Also run the large-year physical-device profile.

Report separately:

- unit status;
- integration status;
- build status;
- simulator UI status;
- physical-device performance status;
- skipped checks and reasons.

---

## 17. Final acceptance criteria

The three-phase redesign is complete only when:

1. the existing Timeline tab uses the approved hierarchy;
2. Phase 1 financial invariants remain true;
3. summary and chart match the approved reference at standard width;
4. search is compact and visually subordinate;
5. exactly four periods are visible with selection trailing;
6. wallet and period control summary/chart/feed;
7. search and advanced filters control only the feed;
8. filter badge excludes text search;
9. All Wallets is truthful and mixed currencies are never invalidly summed;
10. complete-day date ranges are correct;
11. transaction day cards preserve totals, editing, and accessibility;
12. existing Overview, add, search, wallet, and transaction flows remain intact;
13. Ukrainian and English localization is correct;
14. Dynamic Type, VoiceOver, dark mode, and large values are supported;
15. chart labels and transaction amounts do not collide or clip;
16. year mode passes the measured large-data gate;
17. focused tests, isolated tests, lint, UI validation, build, smoke, and graph sync pass.

Any failed gate must be documented before merge.