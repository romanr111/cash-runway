# PLAN.md - Cash Runway current status

## What this file is for

This file is the current implementation status for Cash Runway. The old phase-specific Monobank plan files have been folded into this summary so the repo root has one source of truth.

## Current product state

Cash Runway is a local-first iPhone finance app built with SwiftUI, GRDB, SQLite, SQLCipher, async/await, and Keychain-backed secrets.

The active product includes:

- wallets, manual transactions, transfers, categories, and labels
- recurring transaction templates and generated instances
- CSV import/export and full JSON backup import/export
- dashboard, timeline, search, and analytics backed by aggregate reads
- encrypted local storage
- Monobank local-first expense sync

## Monobank implementation status

Monobank phases 1, 2, and 3 are implemented in the current feature branch.

Completed behavior:

- Bank sync schema for integrations, accounts, import metadata, and category rules.
- Monobank API client and sync service for statement windows, idempotent imports, token-invalid handling, retry-safe sync, and UAH expense-only filtering.
- Keychain-only token storage.
- Settings flow for token validation, account selection, wallet mapping, confirmation, status, manual sync, account management, and disconnect.
- Foreground sync wiring through the app model.
- Category learning prompt for edited bank-sync expenses.
- Deterministic debug Monobank UI-test harness for first-start coverage without live API calls.

Important product rules:

- Only selected UAH card expenses are imported.
- Old bank history before connection time is not imported.
- Income is not imported.
- Existing manual, CSV, and recurring transactions are not modified by bank sync.
- Disconnect disables future sync and removes the local token, but keeps imported transactions.

## Verification status

Verified locally:

- Focused bank SwiftPM suite: 27 tests passed across bank connection, sync service, import, schema, and category mapper tests.
- Mirrored core sources are in sync.
- Xcode project file parses.
- Git diff whitespace check passes.

Environment limitations:

- Full `swift test` currently hangs in the active Command Line Tools Swift Testing runner.
- `xcodebuild` and XCUITest cannot run in this shell because full Xcode is not selected; active developer directory is Command Line Tools.

## Deferred or inactive

The following remain intentionally inactive unless product priority changes:

- budgets as an active shipping priority
- app lock as an active shipping priority
- App Group as a required day-one database location
- live Monobank API tests in CI

## Operating notes

- Raw transactions remain the source of truth.
- Aggregates exist so the UI stays fast.
- Interactive reads should stay indexed or aggregate-backed.
- Store tokens, credentials, and sensitive values only in Keychain.
- Keep mirrored core sources in sync when editing `Sources/CashRunwayCore/`.
- Prefer fast unit/integration tests; UI tests should stay targeted and deterministic.
