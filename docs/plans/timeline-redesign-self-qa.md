# Timeline Redesign — Self-QA and Coverage Audit

## Status

This audit compares the original monolithic Timeline redesign plan with the three sequential phase documents in this PR.

**Conclusion:** no material product, data-integrity, interaction, accessibility, or validation requirement was intentionally dropped. The split preserves the original scope while correcting several unsafe or ambiguous decisions.

The approved visual reference is stored at:

- [`assets/timeline-screen-reference.jpg`](assets/timeline-screen-reference.jpg)

This is an optimized repository copy of the user-provided portrait screenshot. The reference image is the visual source of truth for Phase 2 and the final Phase 3 screenshot comparison. Written dimensions and spacing are implementation guidance, not permission to override a clearly visible reference relationship.

---

## 1. Coverage map

| Original plan area | Preserved in |
|---|---|
| existing `DashboardView` and navigation boundary | index, Phases 1–3 |
| selected-period financial semantics | Phase 1 |
| expense-comparison windows and zero-baseline behavior | Phase 1 |
| `TimelineComparison` Core facts | Phase 1 |
| current-period MTD/YTD repository calculation | Phase 1 |
| historical completed-period aggregate path | Phase 1 |
| truthful same-currency All Wallets aggregation | Phase 1 |
| mixed-currency rejection | Phase 1 |
| complete-day date filtering | Phases 1 and 3 |
| `TimelineSnapshot` versus `model.allBars` responsibilities | Phases 1 and 2 |
| header and subdued search action | Phase 2 |
| unified summary card | Phase 2 |
| income, expense, net, comparison, and legend | Phase 2 |
| four-period chart and historical navigation | Phase 2 |
| chart scaling, zero states, value labels, and collision rules | Phase 2 |
| responsive layout and Dynamic Type | Phase 2 |
| Spending Overview navigation | Phase 2 |
| wallet, period, and advanced-filter controls | Phase 3 |
| shared search/filter sheet | Phase 3 |
| mode-specific Reset semantics | Phase 3 |
| filter badge excluding text search | Phase 3 |
| transaction day cards and collapse state | Phase 3 |
| row editing and add-transaction flows | Phase 3 |
| loading and empty states | Phase 3 |
| localization and VoiceOver | Phases 2 and 3 |
| year-mode large-data profiling | Phase 3 |
| deterministic visual fixture and overlay QA | Phases 2 and 3 |
| repository-specific commands and acceptance gates | every phase |

---

## 2. Important corrections that are intentional, not lost scope

### One current-period truth

The original plan allowed the comparison to use month-to-date transactions while headline and chart values could still use full monthly aggregates. The revised Phase 1 requires current net, income, expenses, selected chart point, and comparison current value to share one MTD/YTD boundary.

### Minimal clock injection

The original plan proposed adding `now:` to the `DashboardRepositorying` requirement. The split deliberately keeps that protocol stable and uses a concrete/internal deterministic overload so unrelated mocks and conformers are not forced to change.

### All Wallets is mandatory

The original plan allowed documenting the current first-wallet fallback. The revised plan requires a real same-currency all-wallet aggregate and treats silent fallback as a blocker.

### Date-only filtering uses day keys

The original half-open timestamp proposal could conflict with an already computed end-of-period timestamp. The revised plan uses inclusive `local_day_key` boundaries for date-only feed filters.

### Deterministic chart composition

The original plan allowed the selected point to be centered or trailing. The approved reference clearly places it on the right. Phase 2 now requires a four-period window ending at the selected period.

### Search badge semantics

The original sample counted search text inside the Filters badge despite saying the badge represented advanced filters. Phase 3 excludes text search and indicates search state on the search action itself.

---

## 3. Clarifications recovered during this audit

These details must remain part of implementation even when an agent works from only one phase document.

### 3.1 Period control must preserve both concepts

The visible control displays the selected period, for example `July 2026` or `2026`, but the existing ability to switch between month and year Timeline modes must remain available.

The control or its compact sheet must support:

1. changing month/year mode;
2. navigating/selecting the concrete month or year;
3. keeping the selected chart period, summary, and feed synchronized;
4. preventing selection beyond the supported future boundary unless future-dated data intentionally makes it selectable.

### 3.2 Visual reference must be opened before Phase 2

An implementation agent must inspect:

```text
docs/plans/assets/timeline-screen-reference.jpg
```

before choosing geometry. The reference locks the following relationships:

- search action is visually subordinate to the title;
- summary is one card, not several unrelated cards;
- left metrics column is narrower than the chart region;
- selected/current chart period is rightmost;
- Spending Overview sits inside the summary card;
- filter controls appear below the summary;
- transaction groups read as compact day cards;
- the floating add action must not cover transaction values or bottom navigation.

### 3.3 Repository and project-file hygiene

For every phase:

- start from current branch code rather than relying only on the plan;
- keep first-pass SwiftUI subviews private until geometry stabilizes;
- after extracting files, update and immediately validate `CashRunway.xcodeproj/project.pbxproj`;
- do not leave `.bak`, temporary screenshots, generated reports, or local fixture databases tracked accidentally;
- run `just graph-sync` after structural extraction;
- report skipped validation gates explicitly.

### 3.4 Large-value fixtures

At minimum, presentation and screenshot QA should exercise locale-correct equivalents of:

```text
0
−864.00
−79,471.22
9,999,999.99
−1,234,567.89 USD
1,234,567.89 EUR
```

For `uk_UA`, use localized decimal/group separators and currency-symbol placement rather than the English strings above.

### 3.5 Visual matrix

The final visual matrix must include:

- Ukrainian and English;
- light and dark appearance;
- small, standard, and large iPhone widths;
- default, XL, and accessibility Dynamic Type;
- positive, negative, and zero net cash flow;
- zero income and zero expenses;
- long wallet, category, merchant, and label names;
- mixed-currency unavailable state;
- four chart periods with a large outlier and near-equal paired labels;
- empty period, one-day period, dense month, and large year feed.

### 3.6 Performance decision gate

Do not add a daily cash-flow aggregate or pagination speculatively.

Use a representative physical-device fixture and record measurements. As a practical signal, a bounded comparison query with p95 materially above roughly **20–30 ms**, or a clearly perceptible Timeline reload/scroll regression, justifies investigating an aggregate or feed optimization. This is diagnostic guidance, not a substitute for end-to-end profiling.

Preferred feed optimizations remain:

1. lazy day-card rendering;
2. month-grouped lazy expansion;
3. stable pagination only if necessary.

### 3.7 Loading behavior

A period or chart selection must not replace the entire screen with an opaque loading blanket. Keep the previous valid summary/feed visible where safe, show localized progress near the affected area, and preserve request-ID stale-result protection.

---

## 4. Approximate effort retained from the original plan

These are planning ranges, not deadlines:

| Phase | Scope | Estimate |
|---|---|---:|
| Phase 1 | financial semantics, repository, All Wallets, date correctness, tests | 1.5–2.5 engineering days |
| Phase 2 | header, summary, chart, responsive/accessibility and visual iteration | 1.5–2.5 engineering days |
| Phase 3 | filters, day feed, localization, performance and final QA | 2–3 engineering days |
| **Total** | production-quality implementation | **5–8 engineering days** |

A static visual imitation may be faster, but it does not satisfy the data-integrity, accessibility, localization, or regression gates.

---

## 5. Final go/no-go checklist

The plan is safe to hand to an AI coding agent only if the agent follows this order:

1. Phase 1 passes all financial invariants and focused tests.
2. Phase 2 opens the committed reference image and passes visual approval.
3. Phase 3 preserves the accepted Phase 2 geometry while completing feed/filter behavior.
4. The final deterministic `uk_UA` fixture is compared against the reference with an overlay.
5. All skipped tests, device checks, or performance gates are reported before merge.

No phase may silently defer a failed acceptance criterion to the next phase.