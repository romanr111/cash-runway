# Timeline Screen Redesign — Implementation Index

## Purpose

This PR contains an implementation-ready, repository-grounded plan for redesigning the existing Timeline tab in `DashboardView` to match the approved cash-flow reference.

The work is intentionally split into three sequential documents so an AI coding agent can complete and validate one bounded phase before moving to the next:

1. [`timeline-redesign-phase-1-financial-foundation.md`](timeline-redesign-phase-1-financial-foundation.md) — financial semantics, repository contract, deterministic comparison logic, truthful All Wallets behavior, and tests.
2. [`timeline-redesign-phase-2-summary-and-chart.md`](timeline-redesign-phase-2-summary-and-chart.md) — header, unified summary card, consistent current-period KPIs, four-period chart viewport, typography, and responsive layout.
3. [`timeline-redesign-phase-3-feed-filters-and-qa.md`](timeline-redesign-phase-3-feed-filters-and-qa.md) — search/filter behavior, day cards, localization, accessibility, screenshot QA, performance gates, and final validation.

Do not implement Phase 2 until Phase 1 acceptance criteria pass. Do not implement Phase 3 until Phase 2 visual and behavioral criteria pass.

## Locked product decisions

These rules supersede ambiguous behavior in the previous monolithic plan.

### Current-period semantics

For the current month or current year, all primary KPIs use the same partial-period boundary:

- current month: first day of month through `now`;
- current year: January 1 through `now`;
- future-dated transactions are excluded from current-period actual KPIs;
- completed historical months and years use full-period aggregates.

The following values must agree with the same selected-period snapshot:

- net cash flow;
- income;
- expenses;
- expense comparison current value;
- selected chart point.

`model.allBars` remains the long-history source, but the selected point rendered in the chart must be replaced or reconciled with the selected snapshot point so the screen never presents two financial truths.

### Expense comparison

The comparison measures expenses only.

- current partial month: month-to-date versus the same ordinal date range in the previous month, clamped safely;
- completed month: full month versus previous full month;
- current year: year-to-date versus equivalent prior-year range;
- completed year: full year versus previous full year;
- percentage appears once;
- zero baseline never produces infinity or NaN.

### All Wallets

`nil` wallet scope means a true all-wallet aggregate when all active wallets share one currency. It must not silently normalize to the first active wallet.

- stale non-`nil` wallet ID may fall back safely;
- same-currency `nil` scope must remain `nil`;
- mixed-currency `nil` scope must show an unavailable state or require one wallet;
- unlike currencies are never summed without conversion.

### Filters

Wallet and visible Timeline period affect summary, chart, and feed.

Text search, category, label, transaction kind, and custom date range affect the transaction feed only. They must not redefine the headline financial KPIs.

The filter badge counts category, label, kind, and date-range filters. It does not count wallet, visible period, or text search.

### Reference layout

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

The current/selected chart period is trailing, with the three immediately preceding periods visible when available.

### Search-button styling

- visible circle/background: approximately 36–38 pt;
- interactive target: at least 44 × 44 pt;
- subdued accent or neutral fill;
- no prominent shadow;
- glyph approximately 15–16 pt.

## Repository boundaries

Preserve:

- the existing Timeline tab and `DashboardView` route;
- transaction editing and add flows;
- `TimelineSearchSheet` as the shared search/filter surface;
- request-ID stale-result protection;
- `model.allBars` historical navigation;
- Spending Overview navigation;
- mixed-currency safety.

Do not add a database migration initially. Add a new aggregate only after measured physical-device profiling proves the bounded queries are materially too slow.

## Cross-phase validation rule

Every phase must:

1. inspect current branch code before editing;
2. implement only its declared scope;
3. add focused tests;
4. run the relevant repository validation commands;
5. report skipped gates and reasons;
6. avoid speculative cleanup unrelated to the redesign.

The final screen is accepted only after deterministic screenshot QA against the approved reference fixture in Ukrainian locale at standard iPhone width.