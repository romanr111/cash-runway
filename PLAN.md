# PLAN.md - Cash Runway current-state spec

## What this file is for

This file is a compact snapshot of what Cash Runway already is, what is intentionally deferred, and what should be done next if work resumes.

It is no longer a historical MVP implementation checklist.

## Current situation

Cash Runway is a local-first iPhone finance app built with SwiftUI, GRDB, SQLite, SQLCipher, async/await, and Keychain-backed secrets.

The active product focuses on:

- wallets
- manual transactions
- transfers between wallets
- categories and labels
- recurring transaction templates and generated instances
- CSV import and export
- dashboard and analytics backed by precomputed aggregates
- encrypted local storage

The codebase is already past the bootstrap phase. Core data flow, persistence, search, aggregates, and the main UI surfaces exist.

## Already done

- iPhone app shell and navigation
- local encrypted database stack
- wallets and transaction CRUD
- transfer handling
- category and label management
- recurring templates and instance generation
- CSV import and export flows
- dashboard analytics and summary views
- aggregate-backed reads for speed
- FTS-based transaction search
- unit tests and performance checks for core behavior
- simulator-based validation with current repo rules centered on `swift test`, iPhone 17 simulator build, and boot checks

## Intentionally deferred

The following are present in the repo or legacy plan history, but are not the current focus:

- budgets as an active shipping priority
- app lock as an active shipping priority
- App Group as a required day-one database location
- the old phase-by-phase MVP rollout narrative
- the old iPhone 12 performance baseline

## What could be done next

If work continues, the highest-value next steps are:

1. Tighten the active flows that users already touch most: transaction entry, search, dashboard, CSV import/export, and recurring posting.
2. Keep performance work focused on the current hot paths, using aggregate reads and targeted benchmarks instead of broad rescans.
3. Revisit budgets and app lock only if they become a real product priority again.
4. Keep the repo documentation aligned with current code reality so stale MVP language does not come back.

## Operating notes

- Raw transactions remain the source of truth.
- Aggregates exist so the UI stays fast.
- Interactive reads should stay indexed or aggregate-backed.
- Validation should stay simulator-first unless a bug is confirmed device-specific.
- Keep mirrored core sources in sync when editing `Sources/CashRunwayCore/`.

## Short summary

The app is already a working local finance product, not a greenfield MVP. The useful cleanup now is to keep the documentation centered on current behavior and on the next incremental improvements, rather than on the original rollout plan.
