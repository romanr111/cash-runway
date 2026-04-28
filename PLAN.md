# PLAN.md — Cash Runway iOS App V1 MVP Implementation Plan

## 1. Document purpose

This document is the **implementation contract** for an autonomous coding agent building the **first minimally working iOS MVP** of a Cash Runway personal finance app.

The goal of V1 is **not** to clone the full product. The goal is to ship a **fast, correct, offline-first iOS app** that allows a user to:

- create wallets
- create/edit/delete manual transactions
- organize transactions by category and labels
- create transfers between wallets
- define recurring transactions
- define simple monthly budgets
- view a dashboard and analytics that remain fast even after many years of data
- import and export CSV files
- protect local data with app lock and encrypted storage

This plan is intentionally opinionated. The agent should follow it unless a design screenshot in the same folder creates a direct UI conflict.

---

## 2. How the agent should use this plan

The folder containing this file may also contain UI screenshots or design references.

Agent rules:

1. **Treat this file as the source of truth for architecture and behavior.**
2. **Treat screenshots in the same folder as the source of truth for visual layout and styling.**
3. If a screenshot conflicts with this file:
   - preserve the architecture and data model from this file
   - adapt the UI structure to the screenshot
   - do not invent new product scope unless the screenshot clearly requires it
4. Build **working software first**, polish second.
5. Prefer boring, deterministic implementations over clever abstractions.

---

## 3. Product definition for V1 MVP

### 3.1 Core product promise

A fast, local-first personal finance app for iPhone that works well with **10 years of transaction history** and stays responsive because analytics are powered by **precomputed aggregates**, not repeated scans of raw rows.

### 3.2 Target user outcome

A single user can:

- record finances manually
- import historical data from CSV
- see monthly spending and cash flow quickly
- manage recurring expenses/income
- track budget progress
- trust that the app remains responsive even with a large dataset

### 3.3 V1 scope (must ship)

#### Included

- iPhone app only
- local database
- single user, local profile only
- UAH only
- multiple wallets
- categories
- labels/tags
- transaction list with filtering/search
- transaction details + edit/delete
- transfers between wallets
- recurring transaction templates + generated instances
- monthly budgets by category
- dashboard with summary cards and simple charts
- analytics by month and category
- CSV import
- CSV export
- encrypted local storage
- PIN + biometric app lock
- benchmark harness and performance tests

#### Explicitly excluded from V1

- bank sync
- shared wallets
- web app
- multi-currency
- crypto
- receipt OCR / AI scan
- cloud sync
- notifications beyond basic local reminders for recurrence if time permits
- debt tracking / subscriptions intelligence / forecasting

### 3.4 V1 design philosophy

- **Correctness before cleverness**
- **Responsiveness before visual complexity**
- **Deterministic state transitions**
- **Local reads first**
- **Minimal feature surface, strong internals**

---

## 4. Non-negotiable technical decisions

The agent must implement these decisions as specified.

### 4.1 Platform / stack

- Minimum deployment target: **iOS 17.0**
- Language: **Swift**
- UI: **SwiftUI**
- Database: **SQLite** via **GRDB**
- Encryption at rest: **SQLCipher**
- Concurrency: **async/await** + structured concurrency
- Background execution: **BGTaskScheduler** for rebuild/import maintenance hooks where applicable
- Secure secrets: **Keychain**
- Charts: native Swift Charts if suitable; otherwise simple custom views. Do not introduce heavy third-party chart dependencies unless necessary.

Implementation rule:
- Use modern iOS 17 APIs consistently
- Use `@Observable` for view models / state holders by default
- Do not mix `ObservableObject` / `@StateObject` patterns unless a specific compatibility wrapper requires it

### 4.2 Money model

- Currency: **UAH only**
- Storage: **integer minor units** (kopiiky)
- Display: format to 2 decimals at presentation time
- Never use floating point for stored amounts

### 4.3 Data model philosophy

- Raw transactions are the **source of historical truth**
- Aggregate tables are the **source of UI speed**
- Aggregate updates happen in the **application layer**, not SQLite triggers
- All interactive reads should prefer indexed queries or aggregate tables

### 4.4 Search

- Full-text search: **SQLite FTS5**
- Tokenizer: **unicode61**
- Searchable fields: merchant, note, wallet name, label text

### 4.5 Database location

- Store the database in an **App Group container path** from day one
- Even if widgets are not shipped in V1, this avoids painful relocation later

---

## 5. Information architecture / screens

The exact visual hierarchy may follow attached screenshots, but the functional screen map for V1 should be:

1. **Onboarding / App Lock Setup**
2. **Main Tab Bar** with:
   - Dashboard
   - Transactions
   - Budgets
   - Settings
3. Modal / push flows:
   - Wallet list / wallet management
   - Add/Edit transaction
   - Transaction details
   - Transfer flow
   - Recurring templates
   - Budget create/edit
   - Category management
   - Label management
   - CSV import wizard
   - CSV export action sheet
   - App lock settings

### 5.1 Dashboard screen

Purpose: quick overview of current financial state.

Show at minimum:

- total balance across wallets
- current month income
- current month expense
- current month net
- top spending categories for selected month
- recent transactions preview
- period selector (default current month)

Performance rule:
- dashboard must be powered from aggregate tables, `wallet.current_balance_minor`, and top-N indexed queries

### 5.2 Transactions screen

Purpose: history browsing and fast entry.

Show at minimum:

- paginated or incremental transaction list
- grouped by date
- search bar
- filters: wallet, category, label, income/expense/transfer, date range
- add transaction button

### 5.3 Add/Edit transaction screen

Required fields:

- type: expense / income / transfer
- wallet
- amount
- date
- category (required for income/expense, not for transfer)
- labels (0..n)
- note
- merchant / title field
- recurring toggle (optional shortcut to create from transaction)

### 5.4 Budgets screen

V1 budgets are **monthly category budgets only**.

Show at minimum:

- current month budget cards
- spent / limit / remaining / percentage
- over-budget state
- create/edit budget
- archive/delete budget

### 5.5 Settings screen

Show at minimum:

- wallet management
- category management
- label management
- recurring templates
- import CSV
- export CSV
- app lock settings
- database diagnostics (debug/dev build only)

---

## 6. UX behavior rules

### 6.1 Transaction UX rules

- Saving a transaction updates the list immediately
- Saving a transaction updates dashboard/budget totals immediately
- Deleting a transaction updates aggregates immediately
- Editing a transaction must correctly move its contributions across month/category/wallet buckets

### 6.2 Error handling rules

- Never fail silently
- Import errors should show row-level reasons where possible
- Validation errors must be inline and human-readable
- Corruption or impossible states should fail loudly in debug builds

### 6.3 Empty states

Provide empty states for:

- no wallets
- no transactions
- no budgets
- no recurring templates
- no search results

### 6.4 Accessibility baseline

- Dynamic Type should not break layout
- Support VoiceOver labels for buttons and summary cards
- Touch targets should be at least standard iOS comfortable sizes

---

## 7. Canonical domain model

The agent must implement the following core entities.

### 7.1 Wallet

Represents a user-defined container such as cash, card, or account.

Fields:

- `id: UUID`
- `name: String`
- `kind: String` (`cash`, `card`, `account`, `other`)
- `color_hex: String?`
- `icon_name: String?`
- `starting_balance_minor: Int64`
- `current_balance_minor: Int64`
- `is_archived: Bool`
- `sort_order: Int`
- `created_at: Date`
- `updated_at: Date`

Implementation rule:
- `current_balance_minor` is the authoritative O(1) source for current wallet balance in interactive UI
- It must be updated atomically inside the same DB transaction as any transaction create/edit/delete affecting that wallet
- `starting_balance_minor` remains the seed value for rebuilds and integrity verification
- `daily_wallet_balance_delta` remains the source for time-series analytics, not current-balance rendering

### 7.2 Category

V1 uses a flat category model, but reserve hierarchy support.

Fields:

- `id: UUID`
- `name: String`
- `kind: String` (`expense`, `income`)
- `icon_name: String?`
- `color_hex: String?`
- `parent_id: UUID?`  // reserved for future subcategories
- `is_system: Bool`
- `is_archived: Bool`
- `sort_order: Int`
- `created_at: Date`
- `updated_at: Date`

### 7.3 Label

Fields:

- `id: UUID`
- `name: String`
- `color_hex: String?`
- `created_at: Date`
- `updated_at: Date`

### 7.4 Transaction

This is the most important table.

Fields:

- `id: UUID`
- `wallet_id: UUID`
- `type: String` (`expense`, `income`, `transfer_out`, `transfer_in`)
- `linked_transfer_id: UUID?`
- `amount_minor: Int64`
- `occurred_at: Date`
- `local_day_key: Int`      // YYYYMMDD integer for grouping/indexing
- `local_month_key: Int`    // YYYYMM integer for rollups
- `category_id: UUID?`
- `merchant: String?`
- `note: String?`
- `is_deleted: Bool`
- `source: String` (`manual`, `recurring`, `import_csv`)
- `recurring_template_id: UUID?`
- `recurring_instance_id: UUID?`
- `created_at: Date`
- `updated_at: Date`

### 7.5 TransactionLabel

Join table.

Fields:

- `transaction_id: UUID`
- `label_id: UUID`

### 7.6 Budget

Monthly category budget.

Fields:

- `id: UUID`
- `category_id: UUID`
- `month_key: Int`
- `limit_minor: Int64`
- `is_archived: Bool`
- `created_at: Date`
- `updated_at: Date`

Constraint:
- one active budget per `(category_id, month_key)`

Validation rules:
- `limit_minor` must be greater than zero in V1
- zero-limit budgets are invalid and must be rejected at validation time

### 7.7 RecurringTemplate

Defines the recurrence rule.

Fields:

- `id: UUID`
- `kind: String` (`expense`, `income`, `transfer`)
- `wallet_id: UUID`
- `counterparty_wallet_id: UUID?`   // for transfers only
- `amount_minor: Int64`
- `category_id: UUID?`
- `merchant: String?`
- `note: String?`
- `rule_type: String` (`daily`, `weekly`, `monthly`, `yearly`)
- `rule_interval: Int`
- `day_of_month: Int?`
- `weekday: Int?`
- `start_date: Date`
- `end_date: Date?`
- `is_active: Bool`
- `created_at: Date`
- `updated_at: Date`

### 7.8 RecurringInstance

Tracks generated occurrences and their state.

Fields:

- `id: UUID`
- `template_id: UUID`
- `due_date: Date`
- `day_key: Int`
- `status: String` (`scheduled`, `posted`, `skipped`, `postponed`)
- `linked_transaction_id: UUID?`
- `override_amount_minor: Int64?`
- `override_category_id: UUID?`
- `override_note: String?`
- `override_merchant: String?`
- `created_at: Date`
- `updated_at: Date`

Constraint:
- unique `(template_id, day_key)`

### 7.9 CategoryRemap

Needed for future-safe analytics even in V1.

Fields:

- `id: UUID`
- `old_category_id: UUID`
- `new_category_id: UUID`
- `remapped_at: Date`

### 7.10 AuditEntry

Even though V1 is single-user, define the audit table now.

Fields:

- `id: UUID`
- `entity_type: String`
- `entity_id: UUID`
- `operation: String` (`create`, `update`, `delete`, `remap`, `rebuild`)
- `diff_json: String`
- `created_at: Date`

### 7.11 ImportJob

Tracks CSV import lifecycle.

Fields:

- `id: UUID`
- `source_name: String`
- `file_name: String`
- `status: String` (`created`, `parsed`, `validated`, `committed`, `failed`, `cancelled`)
- `total_rows: Int`
- `valid_rows: Int`
- `invalid_rows: Int`
- `started_at: Date`
- `finished_at: Date?`
- `error_summary: String?`

### 7.12 Aggregate tables

#### `monthly_wallet_cashflow`

Fields:

- `wallet_id: UUID`
- `month_key: Int`
- `income_minor: Int64`
- `expense_minor: Int64`
- `transfer_in_minor: Int64`
- `transfer_out_minor: Int64`
- `txn_count: Int`
- `updated_at: Date`

Constraint:
- unique `(wallet_id, month_key)`

#### `monthly_category_spend`

Fields:

- `category_id: UUID`
- `month_key: Int`
- `expense_minor: Int64`
- `txn_count: Int`
- `updated_at: Date`

Constraint:
- unique `(category_id, month_key)`

#### `daily_wallet_balance_delta`

Fields:

- `wallet_id: UUID`
- `day_key: Int`
- `net_delta_minor: Int64`
- `updated_at: Date`

Constraint:
- unique `(wallet_id, day_key)`

#### `budget_progress_snapshot`

Fields:

- `budget_id: UUID`
- `month_key: Int`
- `spent_minor: Int64`
- `remaining_minor: Int64`
- `percent_used_bp: Int`   // basis points to avoid float
- `updated_at: Date`

Constraint:
- unique `(budget_id, month_key)`

### 7.13 AggregateDirtyRange

Tracks rebuild work.

Fields:

- `id: UUID`
- `kind: String` (`month`, `wallet_month`, `category_month`, `budget_month`, `full`)
- `wallet_id: UUID?`
- `category_id: UUID?`
- `budget_id: UUID?`
- `month_key: Int?`
- `status: String` (`pending`, `running`, `done`, `failed`)
- `created_at: Date`
- `updated_at: Date`

---

## 8. Stable system categories

The agent must seed default categories with **hardcoded stable UUIDs** in source control. They must not be generated at runtime.

Minimum default expense categories:

- Groceries
- Restaurants
- Transport
- Housing
- Utilities
- Health
- Shopping
- Entertainment
- Education
- Travel
- Gifts
- Other Expense

Minimum default income categories:

- Salary
- Bonus
- Gift Income
- Refund
- Other Income

Implementation rule:
- category names may be localized later
- UUIDs remain constant forever

---

## 9. Database indexes and query strategy

The agent must create indexes for the main interactive paths.

Required indexes:

- `transactions(wallet_id, occurred_at DESC)`
- `transactions(local_day_key DESC, id)`
- `transactions(local_month_key, wallet_id)`
- `transactions(category_id, local_month_key)`
- `transactions(recurring_template_id)`
- `transactions(source)`
- `transaction_labels(label_id, transaction_id)`
- `budgets(month_key, category_id)`
- `monthly_wallet_cashflow(month_key, wallet_id)`
- `monthly_category_spend(month_key, category_id)`
- `daily_wallet_balance_delta(day_key, wallet_id)`
- `recurring_instances(template_id, day_key)`

FTS requirements:

- FTS5 virtual table indexing:
  - merchant
  - note
  - wallet name
  - label text (via denormalized searchable text if needed)

Important rule:
- no interactive screen should require a full scan of the transaction table

---

## 10. Aggregate invalidation and rebuild rules

This section is **mandatory**. The agent must implement exactly this principle: **incremental updates for normal writes, rebuilds only for exceptional operations**.

### 10.1 General rule

Whenever a transaction changes, calculate:

- the **old contribution** (before mutation)
- the **new contribution** (after mutation)

Then:

- subtract old contribution from affected aggregate rows
- add new contribution to affected aggregate rows

Do not recompute globally for ordinary CRUD.

### 10.2 CRUD rules for transactions

#### Create transaction

On insert:

- update `monthly_wallet_cashflow`
- if expense with category: update `monthly_category_spend`
- update `daily_wallet_balance_delta`
- update `wallet.current_balance_minor`
- if budget exists for that category/month: update `budget_progress_snapshot`

#### Delete transaction

On delete:

- reverse the exact previous contributions
- update `wallet.current_balance_minor` by reversing the prior wallet effect
- mark transaction deleted or hard-delete depending on final implementation, but aggregates must be decremented deterministically

#### Edit transaction

If any of the following changes:

- amount
- wallet
- date/month
- type
- category

then:

1. remove old contribution from old buckets
2. apply new contribution to new buckets

This includes month migration (e.g. March -> April) and category migration.

Also update `wallet.current_balance_minor` atomically if the edit changes:

- amount
- wallet
- type
- transfer linkage

### 10.3 Transfers

Transfers must generate two rows:

- `transfer_out` in source wallet
- `transfer_in` in destination wallet

They are linked by `linked_transfer_id`.

Aggregate behavior:

- transfer rows affect wallet cashflow and daily balance deltas
- transfer rows must also update both affected wallets' `current_balance_minor` atomically
- transfer rows do **not** affect category spend
- transfer rows do **not** affect budgets

### 10.4 Budget snapshots

Budget snapshot values are derived from:

- budget limit
- category spend in the matching month

For ordinary transaction writes, update affected snapshots incrementally if a matching budget exists.

When a `Budget` is created, edited, archived, or unarchived:

- recompute `budget_progress_snapshot` for the matching `(budget_id, month_key)`
- recompute `remaining_minor = limit_minor - spent_minor`
- recompute `percent_used_bp = (spent_minor * 10000) / limit_minor` using integer arithmetic
- because V1 disallows zero-limit budgets, division-by-zero must never be possible in valid persisted data

### 10.5 Exceptional rebuild cases

Full or scoped rebuild is allowed only for:

- CSV import finalization
- migration that changes aggregate semantics
- category remap / merge
- detected corruption / repair action

Category remap execution semantics:

- executing a remap is a real write operation in V1, not a read-time translation only
- batch-update all matching `Transaction.category_id` rows from `old_category_id` to `new_category_id`
- write an `AuditEntry` with operation = `remap`
- mark affected month/category buckets dirty in `AggregateDirtyRange`
- rebuild affected `monthly_category_spend` rows and any affected `budget_progress_snapshot` rows for those months
- remap is not automatically reversible in V1

Rebuild rules:

- mark dirty range rows in `AggregateDirtyRange`
- rebuild in chunks by month or month+wallet
- do not block all UI reads
- UI may show last known values while rebuild is running

### 10.6 Validation requirement

After implementing aggregate updates, create property-style tests that verify:

- aggregate totals equal totals derived from raw transactions
- after random create/edit/delete sequences, rollups remain correct
- transfer edits preserve double-entry balance behavior

---

## 11. Recurring engine specification

V1 recurrence must be deterministic and limited.

### 11.1 Authority

For V1 local-only MVP:

- recurrence generation happens on device
- `RecurringInstance` unique constraint prevents duplicate instances

### 11.2 Generation horizon

On app launch, foreground resume, and recurring management changes:

- generate instances from `today - 7 days` through `today + 60 days`
- do **not** backfill unlimited history

### 11.3 Instance lifecycle

Statuses:

- `scheduled`: instance exists, no transaction posted yet
- `posted`: generated into actual transaction(s)
- `skipped`: intentionally skipped
- `postponed`: due date moved by user

### 11.4 User actions

Support the following actions in V1:

- mark scheduled instance as posted now
- skip this occurrence
- edit this occurrence only
- edit template for future occurrences

If time pressure exists, `edit this and future` may be simplified to modifying the template and leaving already-generated past/future instances unchanged beyond the regeneration window.

### 11.5 Posting behavior

When a scheduled occurrence is posted:

- create transaction with `source = recurring`
- link transaction to template + instance
- update aggregates as normal transaction write
- set instance `status = posted`

### 11.6 Transfer recurrence

If recurring template is a transfer:

- posting creates both transfer rows linked together
- instance references the primary logical occurrence; both transaction rows reference the instance

---

## 12. CSV import / export specification

CSV import is required in V1 because it is the fastest way to create a large realistic dataset.

### 12.1 Import pipeline stages

1. file select
2. encoding detection
3. delimiter detection
4. header parse
5. mapping preview
6. row validation
7. commit in batches
8. aggregate rebuild for affected months
9. FTS rebuild

### 12.2 Supported parsing capabilities

Must support:

- UTF-8
- Windows-1251
- semicolon/comma/tab delimiters
- `DD.MM.YYYY` and ISO-like dates
- signed amount column
- debit/credit split columns
- comma decimal separator

### 12.3 Import mapping model

User or preset maps source columns to:

- date
- amount or debit/credit
- merchant/title
- note
- category (optional)
- wallet target
- labels (optional)

### 12.4 Import presets

Define parser presets for at least:

- PrivatBank
- Monobank
- generic CSV

If additional Ukrainian banks are easy to support, add them behind a simple preset interface.

### 12.5 Import commit rules

- commit rows in chunks, e.g. 500-1000 rows per batch
- do not update FTS row-by-row during large import
- do not try to incrementally patch all aggregates row-by-row if a large import spans many months; instead mark affected months dirty and rebuild them after commit
- import must remain resumable enough that a crash does not corrupt DB

### 12.6 Export

Provide CSV export for:

- all transactions
- filtered transactions (if easy)

Required exported columns:

- date
- wallet
- type
- amount
- category
- labels
- merchant
- note
- source

---

## 13. Security and privacy baseline

The app handles sensitive financial data. V1 must meet a serious baseline.

### 13.1 Local encryption

- Use SQLCipher for database encryption
- Store the database key in Keychain
- Do not store any sensitive material in UserDefaults

### 13.2 App lock

Support:

- PIN lock
- Face ID / Touch ID unlock if available
- auto-lock after app backgrounding (configurable if easy; otherwise fixed timeout acceptable for V1)

### 13.3 Data handling

- No network transmission in V1 unless analytics/crash reporting is explicitly enabled in debug or later configuration
- No third-party analytics SDK in the first minimal build unless required by the development process

### 13.4 Logging rules

- Never log full transaction notes or amounts in production logs unless redacted
- Do not log DB encryption keys
- Debug logs should be guarded by build flags

---

## 14. Project structure recommendation

The agent should keep the project modular, but avoid unnecessary micro-modules.

Recommended folder/module layout:

```text
App/
  CashRunwayApp.swift
  AppCoordinator.swift
  DependencyContainer.swift

Core/
  Money/
  Dates/
  Extensions/
  Logging/
  Security/

Data/
  Database/
    DatabaseManager.swift
    Migrations/
    SQL/
  Models/
  Repositories/
  Aggregates/
  Search/
  Import/
  Export/
  Recurring/

Features/
  Dashboard/
  Transactions/
  Budgets/
  Wallets/
  Categories/
  Labels/
  Settings/
  ImportFlow/
  AppLock/

UI/
  Components/
  Theme/
  Charts/

Tests/
  Unit/
  Integration/
  Performance/
  Fixtures/
```

Architectural recommendation:

- keep feature screens isolated
- keep DB write logic in repositories/services, not in views
- keep aggregate logic in dedicated services, not scattered across screens

---

## 15. State management guidance

Use a simple, testable pattern.

Recommended approach:

- SwiftUI views with `@Observable`-based view models / state holders
- repositories injected via dependency container
- async load methods for screen hydration
- explicit screen state enums where useful (`idle`, `loading`, `loaded`, `error`)

Avoid:

- business logic in views
- hidden singleton DB access
- unbounded reactive chains that are hard to reason about

---

## 16. Implementation phases for the agent

This is the required execution order.

## Phase 0 — bootstrap

Deliverables:

- Xcode project targeting iOS 17.0
- App Group setup
- SQLCipher + GRDB wiring
- Keychain wrapper
- base theme / navigation shell

Acceptance:

- app launches
- encrypted DB can be opened and migrated
- debug build runs on simulator/device

## Phase 1 — schema and migrations

Deliverables:

- schema creation
- all tables from this plan
- indexes
- stable seed categories
- repository interfaces

Acceptance:

- migration tests pass on empty DB
- migration can reopen existing DB cleanly

## Phase 2 — synthetic dataset and benchmark harness

Deliverables:

- generator for 1k / 10k / 50k / 150k transactions
- seeded wallets, categories, labels, recurrence samples
- performance tests scaffolding

Acceptance:

- dataset generation deterministic by seed
- performance fixture can populate local DB repeatedly

## Phase 3 — transaction engine and aggregates

Deliverables:

- create/edit/delete transactions
- transfer creation/edit/delete
- aggregate update service
- validation tests for aggregate correctness

Acceptance:

- dashboard totals always match raw transaction truth in tests
- transfer edits remain balanced

## Phase 4 — transaction UI

Deliverables:

- transaction list
- add/edit forms
- details screen
- search/filter basics
- wallet management
- category management
- label management

Acceptance:

- end-to-end manual usage works
- list remains responsive with large seeded dataset

## Phase 5 — budgets and recurrence

Deliverables:

- monthly category budgets
- budget list/progress UI
- recurring templates
- scheduled instance list
- post/skip/edit occurrence flows

Acceptance:

- changing transaction/category/date updates budget progress correctly
- recurrence posting creates correct transaction rows

## Phase 6 — import/export

Deliverables:

- CSV import wizard
- parser presets
- validation preview
- batched commit
- rebuild pipeline
- CSV export

Acceptance:

- large CSV import completes without freezing UI
- imported totals equal exported totals for the same selection where applicable

## Phase 7 — security hardening and polish

Deliverables:

- PIN + biometric lock
- background lock handling
- debug diagnostics panel
- error states / empty states / accessibility pass

Acceptance:

- app can be locked/unlocked reliably
- no sensitive values appear in production logs

## Phase 8 — release candidate stabilization

Deliverables:

- bug fixes
- crash fixes
- performance optimization
- screenshots/design alignment

Acceptance:

- meets performance and correctness gates defined below

---

## 17. Performance and scale requirements

The app must be built for long-lived data from day one.

### 17.1 Target dataset

V1 must remain usable with:

- 50 wallets max
- 150,000 transactions
- 10 years of monthly aggregates
- 2,000 labels associations on top of raw transactions
- 500 recurring instances generated in active window

### 17.2 Device baseline

Use **iPhone 12** as the minimum performance reference device for measurement.

### 17.3 Measured targets

Targets should be measured in XCTest performance tests where possible.

- warm app open to dashboard data visible: **< 200 ms p95** from local DB
- transaction list initial render for recent month: **< 150 ms p95**
- month switch on dashboard/analytics: **< 80 ms p95**
- add transaction save to UI reflect: **< 80 ms p95**
- text search first results: **< 150 ms p95**

### 17.4 Measurement rules

- define cold vs warm open in test comments
- run `measure {}` tests on seeded DB
- profile with Instruments for slow paths if targets are missed
- any query > 16 ms in debug instrumentation should be considered suspicious and logged

---

## 18. Testing strategy

The agent must not rely only on manual testing.

### 18.1 Unit tests

Cover:

- money formatting/parsing
- month/day key generation
- category remap logic
- recurring schedule generation
- CSV parsing and mapping
- import row validation

### 18.2 Integration tests

Cover:

- transaction create/edit/delete with aggregate verification
- transfer flows
- budget updates after transaction mutation
- recurring posting
- import commit and aggregate rebuild
- FTS rebuild/search

### 18.3 Property-style / randomized tests

Generate random mutation sequences and assert:

- aggregate truth equals raw-scan truth
- no negative impossible states from normal flows unless semantically valid
- linked transfers remain paired

### 18.4 Performance tests

Measure:

- dashboard month load
- transaction query pagination
- FTS search
- import batch commit
- aggregate rebuild by month

---

## 19. Design integration rules for screenshots in this folder

When screenshots are added to the same folder as this `PLAN.md`, the agent should:

1. Inspect every screenshot before implementing UI polish
2. Derive:
   - color palette
   - typography hierarchy
   - card structure
   - icon style
   - spacing rhythm
   - nav/tab layout
3. Preserve the functional screen list from this plan unless a screenshot clearly requires an additional lightweight screen
4. Do not let visuals compromise performance rules
5. If a design element is expensive to build and non-essential for MVP, approximate it with native SwiftUI components first

---

## 20. Definition of done for V1 MVP

V1 is done when all of the following are true:

### Functional

- user can create at least two wallets
- user can create/edit/delete income and expense transactions
- user can transfer money between wallets
- user can assign categories and labels
- user can create monthly category budgets
- user can create recurring templates and post occurrences
- user can import CSV history and export transactions
- dashboard reflects totals correctly

### Correctness

- aggregate tables match raw transaction truth in test suite
- wallet `current_balance_minor` matches rebuild truth in test suite
- budget progress updates correctly after edits/deletes/category changes and budget limit edits
- recurring posting does not duplicate instances within the active horizon
- transfer rows remain linked and balanced

### Security

- database is encrypted
- app lock works with PIN and biometrics if available
- no sensitive information is leaked in production logs

### Performance

- app remains responsive with 150k transaction fixture
- main views use aggregate/indexed queries rather than raw full scans
- performance tests pass or are within acceptable threshold after review

### Maintainability

- project structure is understandable
- migrations are versioned and tested
- core services are covered by tests
- screenshots in this folder have been used to align UI where provided

---

## 21. Final instruction to the implementing agent

Build **the smallest serious version** of the product.

That means:

- do not overbuild sync
- do not add speculative features
- do not spend days on animations before correctness is proven
- do not sacrifice aggregate correctness for UI speed hacks
- do not sacrifice UI responsiveness by scanning the full transaction table on each screen load

The highest-priority outcome is a **trustworthy, fast, local-first finance app** whose architecture still makes sense after years of usage.

If time is limited, preserve in this order:

1. encrypted local DB
2. correct transaction CRUD
3. correct aggregate engine
4. responsive transaction list/dashboard
5. budgets
6. recurring
7. CSV import/export
8. UI polish

