# Timeline Redesign — Phase 1: Financial Semantics and Repository Foundation

## Position in the sequence

**Phase 1 of 3.** Complete and validate this phase before starting the visual redesign.

Next:

1. `timeline-redesign-phase-2-summary-chart.md`
2. `timeline-redesign-phase-3-feed-filters-qa.md`

## Objective

Make the Timeline financial data internally consistent and deterministic so the redesigned screen can render one trustworthy selected-period snapshot.

This phase changes data semantics, repository behavior, and tests. It does **not** redesign the screen.

## Non-goals

- no new root tab or parallel Timeline screen;
- no database migration in the first implementation;
- no duplicate period-summary model;
- no currency conversion;
- no broad clock abstraction;
- no visual transaction-card work.

---

## 1. Verified current architecture

The existing implementation already has the required foundation:

- `DashboardView` is the Timeline screen;
- `TimelineSnapshot` contains selected-period bars, cash flow, and grouped transactions;
- `model.allBars` contains the full historical chart series;
- `TimelineSearchSheet` owns the shared transaction query;
- `DashboardRepositorying` exposes `timelineSnapshot` and `allBars` separately;
- GRDB serializes database reads and writes.

Preserve these boundaries.

### Source-of-truth rule

Use the two data paths for different purposes:

- `TimelineSnapshot` is authoritative for the selected period and summary card;
- `model.allBars` is historical navigation data only.

Do not compute headline values independently from `model.allBars` after this phase.

---

## 2. Product semantics to lock

### 2.1 Selected current month

For the current calendar month, all selected-period facts must use **month-to-date** data:

```text
month start ... current local day
```

The following values must use the same bounded range:

- net cash flow;
- income;
- expenses;
- selected chart point;
- current side of the expense comparison.

Transactions after the current local day must not be included in these current-period actuals.

This prevents a future-dated transaction from appearing in the expense card while being absent from the comparison.

### 2.2 Selected current year

For the current year, use **year-to-date** consistently for the same five values.

### 2.3 Completed historical periods

- historical month: full selected month;
- historical year: full selected year;
- comparison baseline: full immediately preceding period.

Do not truncate a completed historical period to today's ordinal day.

### 2.4 Future selected periods

If the app can select a future period because future-dated records exist:

- retain the stored selected-period totals;
- mark comparison as unavailable;
- do not label the values month-to-date or year-to-date;
- do not fabricate a percentage.

### 2.5 Expense comparison

The comparison measures **expenses only**.

Current month example on July 11:

```text
Current:  July 1–11
Baseline: June 1–11
```

Current year example on July 11:

```text
Current:  January 1–July 11, 2026
Baseline: January 1–July 11, 2025
```

Clamp safely when the baseline period has no equivalent date, including February 29.

Formula when `baselineExpenseMinor > 0`:

```text
percentageChange =
    (currentExpenseMinor - baselineExpenseMinor)
    / baselineExpenseMinor
```

Direction is based on the unrounded amounts, not the displayed rounded percentage.

### 2.6 Zero and unavailable states

| Condition | Direction | Percentage | Message intent |
|---|---|---:|---|
| current > baseline > 0 | higher | value | expenses are higher than baseline range |
| current < baseline | lower | value | expenses are lower than baseline range |
| current = baseline | unchanged | `0%` or neutral | expenses are unchanged |
| baseline = 0, current > 0 | unavailable | none | new spending versus baseline |
| both are zero | unchanged | none | no spending in either period |
| future/invalid baseline | unavailable | none | no comparable period |

Never produce infinity, NaN, or a made-up percentage.

---

## 3. Minimal Core model change

Reuse:

- `TimelineBarPoint`;
- `TimelineSection`;
- `TimelineSnapshot.heroCashFlowMinor`;
- `TimelineSnapshot.bars`;
- existing transaction rows.

Do not add a second model that duplicates income, expense, and net values.

Add only comparison facts:

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
    public var currentStartDayKey: Int
    public var currentEndDayKey: Int
    public var baselineStartDayKey: Int
    public var baselineEndDayKey: Int
    public var isPartialPeriod: Bool
}
```

Extend `TimelineSnapshot`:

```swift
public var comparison: TimelineComparison?
```

Keep localized copy out of Core.

---

## 4. Deterministic comparison windows without protocol churn

### 4.1 Pure date helper

Add a pure helper that can be unit-tested directly:

```swift
struct TimelineComparisonWindow: Equatable {
    let currentStartDayKey: Int
    let currentEndDayKey: Int
    let baselineStartDayKey: Int
    let baselineEndDayKey: Int
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

- current partial month;
- completed historical month;
- January/December boundary;
- 28–31 day month lengths;
- leap years and February 29;
- current year-to-date;
- completed historical year;
- future selected period;
- local timezone boundaries.

### 4.2 Keep `DashboardRepositorying` stable

Do **not** replace the existing protocol requirement with a new `now:` requirement. That would force unrelated mocks and conformers to change.

Keep:

```swift
func timelineSnapshot(
    monthKey: Int,
    walletID: UUID?,
    query: TransactionQuery,
    period: TimelinePeriod
) throws -> TimelineSnapshot
```

Add a deterministic overload on the concrete repository:

```swift
func timelineSnapshot(
    monthKey: Int,
    walletID: UUID?,
    query: TransactionQuery,
    period: TimelinePeriod,
    now: Date
) throws -> TimelineSnapshot
```

The protocol-conforming production method delegates with `Date()`.

Repository integration tests call the concrete overload with a fixed date. Pure window tests call the helper directly.

---

## 5. Build one consistent selected-period snapshot

Inside one `dbQueue.read` where practical:

1. resolve truthful wallet scope;
2. calculate selected-period bounds;
3. load the normal six-period snapshot bars;
4. for a current partial period, replace the selected bar with bounded transaction sums;
5. calculate comparison current and baseline expenses;
6. derive `heroCashFlowMinor` from the same selected bar;
7. load and group the transaction feed.

### Partial-period bounded sums

Use day keys rather than timestamps:

```sql
SELECT
    COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE 0 END), 0) AS income_minor,
    COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor ELSE 0 END), 0) AS expense_minor
FROM transactions
WHERE is_deleted = 0
  AND local_day_key BETWEEN ? AND ?
  AND (? IS NULL OR wallet_id = ?)
```

Transfers are excluded by the conditional sums.

For the comparison baseline, query expenses only over its bounded day-key range.

### Completed periods

Use `monthly_wallet_cashflow` for completed months and yearly totals derived from those monthly aggregates.

Use a direct transaction-query fallback only if an expected aggregate is missing or integrity checks show it is stale.

### Snapshot invariants

For the selected period:

```text
heroCashFlowMinor == selectedBar.incomeMinor - selectedBar.expenseMinor
comparison.currentExpenseMinor == selectedBar.expenseMinor
```

The second invariant applies when comparison is available for the selected actual period.

---

## 6. Truthful All Wallets behavior is mandatory

The current normalization path can turn `nil` into the first active wallet. The redesign must not display **All Wallets** while silently showing one wallet.

Required behavior:

- valid explicit wallet ID → keep that wallet;
- stale explicit wallet ID → fall back to the first active wallet;
- `nil` and all active wallets use one currency → preserve `nil` and aggregate all wallets;
- `nil` and active wallets use different currencies → preserve `nil`, reject aggregate totals, and show the existing unavailable state until conversion exists.

Do not mutate `selectedWalletID` from `nil` to the first wallet for a valid same-currency all-wallet scope.

Update both:

- repository helper/default behavior;
- AppModel normalization behavior.

Add regression tests proving that two same-currency wallets are both included.

---

## 7. Complete-day date filtering

`TransactionQuery.startDate` and `endDate` come from date-only UI controls. Filter them using local day keys:

```sql
local_day_key >= startDayKey
local_day_key <= endDayKey
```

This includes the complete selected end date and avoids midnight/DST bugs.

Do not convert every `endDate` to `startOfNextDay` because internal period scoping already supplies end-of-period dates; adding another day can extend the query into the next period.

`applyPeriodScope` may continue intersecting UI dates with month/year bounds, but the final SQL predicate must use inclusive day keys.

---

## 8. AppModel integration

After this phase:

- remove `currentCashFlowMinor` dependence on `model.allBars`;
- expose selected summary values from `timelineSnapshot` or a pure UI presentation adapter;
- keep `model.allBars` only for Phase 2 historical chart navigation;
- preserve request-ID stale-result protection;
- preserve asynchronous background loading.

Do not introduce another mutable financial state in AppModel.

---

## 9. Tests

### Pure window tests

- July 1–11 versus June 1–11;
- March 1–31 versus February 1–28/29;
- January versus previous December;
- leap-day year-to-date comparison;
- completed month and completed year;
- future selected period;
- timezone boundary around local midnight.

### Repository integration tests

- income and expense selected bar are month-to-date for current month;
- future-dated records are excluded from current actuals;
- completed historical month uses full aggregate;
- comparison excludes income and both transfer directions;
- soft-deleted rows are excluded;
- selected wallet scope is respected;
- same-currency All Wallets includes every active wallet;
- mixed-currency All Wallets is rejected;
- zero baseline never emits NaN/infinity;
- snapshot invariants hold;
- date-only end date includes transactions late in that local day.

### Regression tests

- historical `allBars` remains available;
- search/category/label filters do not alter summary values;
- wallet and selected period do alter summary values.

---

## 10. Files expected to change

Likely files:

```text
Sources/CashRunwayCore/Models.swift
Sources/CashRunwayCore/CashRunwayRepositorying.swift
Sources/CashRunwayCore/CashRunwayRepository.swift
Sources/CashRunwayUI/AppModel.swift
Tests/CashRunwayCoreTests/TimelineComparisonTests.swift
Tests/CashRunwayCoreTests/TimelineSnapshotTests.swift
```

The protocol file may only need documentation/helper corrections; do not add a new required method solely for clock injection.

---

## 11. Validation gates

Run at minimum:

```bash
just session-start
just test-filter TimelineComparisonTests
just test-filter TimelineSnapshotTests
just check-isolated
just lint
just build
just graph-sync
```

Report any skipped command and reason.

---

## 12. Phase 1 acceptance criteria

Phase 1 is complete only when:

1. current month/year summary values are bounded to today;
2. selected net, income, expense, chart point, and comparison share one data snapshot;
3. completed historical periods retain full-period totals;
4. same-currency All Wallets genuinely aggregates all wallets;
5. mixed currencies are never added without conversion;
6. comparison is deterministic and safe for zero/missing baselines;
7. complete-day date filters are correct;
8. `DashboardRepositorying` has not gained unnecessary clock-related mock churn;
9. focused, isolated, lint, and build gates pass.

Do not start Phase 2 until these invariants are green.