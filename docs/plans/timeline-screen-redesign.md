# Timeline Screen Redesign — Implementation Index

## Purpose

This PR contains an implementation-ready, repository-grounded plan for redesigning the existing Timeline tab in `DashboardView` to match the approved cash-flow reference.

The work is split into three sequential documents so an AI coding agent can complete and validate one bounded phase before moving to the next:

1. [`timeline-redesign-phase-1-financial-foundation.md`](timeline-redesign-phase-1-financial-foundation.md) — financial semantics, deterministic comparison logic, truthful All Wallets behavior, date-boundary correctness, repository integration, and tests.
2. [`timeline-redesign-phase-2-summary-chart.md`](timeline-redesign-phase-2-summary-chart.md) — header, unified summary card, consistent selected-period KPIs, four-period chart viewport, typography, responsive layout, and visual tests.
3. [`timeline-redesign-phase-3-feed-filters-qa.md`](timeline-redesign-phase-3-feed-filters-qa.md) — wallet/period controls, search and filters, transaction day cards, localization, accessibility, screenshot QA, performance gates, and final validation.

Do not implement Phase 2 until Phase 1 acceptance criteria pass. Do not implement Phase 3 until Phase 2 visual and behavioral criteria pass.

## Locked corrections

These decisions resolve the material ambiguities and inconsistencies in the original monolithic plan.

### One current-period financial truth

For the current month or current year, all primary KPI values use the same partial-period boundary:

- current month: first day of month through the current local day;
- current year: January 1 through the current local day;
- future-dated transactions are excluded from current-period actual KPIs;
- completed historical months and years use full-period aggregates.

The following values must agree with the authoritative selected `TimelineSnapshot`:

- net cash flow;
- income;
- expenses;
- expense-comparison current value;
- selected chart point.

`model.allBars` remains the long-history source, but its selected point must be replaced or reconciled with the authoritative snapshot point before rendering. The headline must not be independently recalculated from `model.allBars`.

### Expense comparison

The comparison measures expenses only.

- current partial month: month-to-date versus the same ordinal date range in the previous month, clamped safely;
- completed month: full month versus previous full month;
- current year: year-to-date versus the equivalent prior-year range;
- completed year: full year versus previous full year;
- percentage appears once;
- zero baseline never produces infinity or NaN.

### Truthful All Wallets

`nil` wallet scope means a true all-wallet aggregate when all active wallets share one currency. It must not silently normalize to the first active wallet.

- stale non-`nil` wallet ID may fall back safely;
- same-currency `nil` scope remains `nil` and includes every active wallet;
- mixed-currency `nil` scope produces an aggregate-unavailable state or requires one wallet;
- unlike currencies are never summed without conversion.

This is mandatory, not an optional documentation-only limitation.

### Minimal clock injection

Keep the existing `DashboardRepositorying.timelineSnapshot(...)` requirement stable. Add a deterministic `now:` overload on the concrete repository or internal test surface rather than forcing unrelated mocks and conformers to implement a new protocol requirement.

### Complete-day filtering

Date-only feed filters use inclusive `local_day_key` boundaries. This includes the entire selected end date and avoids accidental next-period expansion from applying `startOfNextDay` to an already scoped period end.

### Filter semantics

Wallet and visible Timeline period affect summary, chart, and feed.

Text search, category, label, transaction kind, and custom date range affect the transaction feed only. They do not redefine financial KPIs.

The Filters badge counts category, label, kind, and date range. It does not count wallet, visible period, or text search. Search state is indicated on the search action itself.

### Reference composition

At standard iPhone width, the intended composition is:

```text
Header: [Cash Flow title]                         [compact search]

Unified summary card
  top:  [net cash flow] [expense comparison] [legend]
  body: [income/expense cards] | [four grouped periods]
  bottom: [Spending Overview]

[wallet] [explicit month/year] [Filters + badge]

[day card]
[day card]
...
```

The selected chart period is the trailing/rightmost group, preceded by the three immediately previous periods when available.

### Search-button styling

- visible background: approximately 36–38 pt;
- interactive target: at least 44 × 44 pt;
- glyph approximately 15–16 pt;
- subdued tint or neutral surface;
- no prominent shadow or saturated block competing with the title.

### Typography and locale

Use standard system typography for title and primary monetary values, with `.monospacedDigit()` for numbers. Do not hardcode `₴`, decimal separators, or currency-symbol position.

Required formatting examples include:

```text
uk_UA: −79 471,22 ₴
en_US: −₴79,471.22
de_DE: −79.471,22 €
```

## Repository boundaries

Preserve:

- the existing Timeline tab and `DashboardView` route;
- transaction editing and add flows;
- `TimelineSearchSheet` as the shared query surface;
- request-ID stale-result protection;
- `model.allBars` historical navigation;
- Spending Overview navigation;
- mixed-currency safeguards.

Do not add a database migration initially. Add a new aggregate only after measured physical-device profiling proves bounded queries materially too slow.

## Cross-phase execution rule

Every phase must:

1. inspect current branch code before editing;
2. implement only its declared scope;
3. add focused tests;
4. run its listed repository validation commands;
5. report skipped gates and reasons;
6. avoid speculative cleanup unrelated to the redesign.

The final screen is accepted only after deterministic screenshot QA against the approved Ukrainian reference fixture at standard iPhone width.