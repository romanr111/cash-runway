# CONTINUITY

## Snapshot
- 2026-04-26 [USER] Goal: implement the full `PLAN.md` MVP for a Spendee-like iPhone finance app using the provided screenshots as UI reference.
- 2026-04-26 [DECISION] D001 ACTIVE: use a thin iOS host app plus a local Swift package for core/domain/UI modules so most functionality remains testable with `swift test`.
- 2026-04-26 [DECISION] D002 ACTIVE: use host Xcode tooling instead of containers because native iOS simulator builds are the required output.
- 2026-04-26 [DECISION] D003 ACTIVE: approximate screenshot styling with native SwiftUI primitives instead of custom rendering unless specifically needed.
- 2026-04-26 [DECISION] D004 ACTIVE: keep app-target core sources mirrored with `Modules/LedgerCorePackage` because the app target compiles local core sources while `swift test` uses the package.
- 2026-04-27T13:11:16+03:00 [TOOL] Primary checkout `/Users/roman/Documents/Development/spendee_v2_ledger` is on `main` synced with `origin/main`; non-shipping screenshot PNGs are preserved under `DesignReferences/` in that checkout.
- 2026-04-27T21:07:46+03:00 [USER] Goal update: implement transaction composer/category fixes, remove success notifications, improve overview chart/category UI, and add labels decomposition.
- 2026-04-27T21:07:46+03:00 [TOOL] Isolated implementation worktree created at `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux` on branch `codex/transaction-overview-ux`.
- 2026-04-27T21:07:46+03:00 [CODE] Current implementation changes are in the isolated worktree only; the dirty primary checkout was left untouched.
- 2026-04-27T21:07:46+03:00 [CODE] Composer now commits expense/income category taps immediately, closes the sheet, focuses the amount field, opens category management from the gear button, removes the composer Merchant row, and uses Today/Yesterday date shortcuts.
- 2026-04-27T21:07:46+03:00 [CODE] Success alert plumbing was removed; errors still surface through the root error alert.
- 2026-04-27T21:07:46+03:00 [CODE] Overview snapshots now include label totals; overview UI now uses compact currency y-axis labels, explicit category legend rows, and a labels section.
- 2026-04-27T21:34:00+03:00 [USER] Goal update: verify business logic/performance and implement first-class import/export compatibility for `/Users/roman/Downloads/transactions_export_2026-04-27_wallet.csv`.
- 2026-04-27T21:34:00+03:00 [CODE] CSV import/export now defaults to wallet CSV headers `Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author`; import handles row-level type, wallet, currency, signed amount, category, labels, quoted fields, UTF-8/CP1251, and delimiter detection.
- 2026-04-27T21:34:00+03:00 [CODE] `CSVService.exportCSV` exports all matching rows in the user-facing wallet format instead of the prior internal/source-column format.
- 2026-04-27T21:34:00+03:00 [CODE] CSV/import/performance regression tests now cover attached-format mapping, signed import, round-trip totals, the real 13,896-row fixture when present, aggregate truth, FTS rebuild, and measured timing gates.
- 2026-04-27T21:54:00+03:00 [TOOL] Self-review found no blocking correctness findings; noted that the wallet CSV shape is expense/income-only like the attached file, while transfer logic remains covered by repository tests.
- 2026-04-27T21:07:46+03:00 [OPEN] UNCONFIRMED no runtime warnings in Xcode console because verification used CLI build/install/launch plus simulator screenshot, not an attached Xcode console.
- 2026-04-27T21:07:46+03:00 [OPEN] Exact `iPhone 16` simulator destination is unavailable; validation used booted `iPhone 17` fallback.

## Done (recent)
- 2026-04-26 [CODE] Implemented core schema, repositories, aggregates, recurrence, CSV import/export, SQLCipher setup, app lock, and fixture generation.
- 2026-04-26 [CODE] Implemented SwiftUI app shell: timeline, wallets, budgets, settings, full-screen transaction composer, category management, labels, recurring, import, and overview screens.
- 2026-04-27 [CODE] Published public GitHub repo `romanr111/spendee-ledger-ios`, set `main` as default, and added repo-local `AGENTS.md`.
- 2026-04-27T21:07:46+03:00 [CODE] Added `OverviewLabelRow` and `OverviewSnapshot.labels` in both mirrored core source trees.
- 2026-04-27T21:07:46+03:00 [CODE] Added label aggregation to `overviewSnapshot(monthKey:walletID:)` and regression coverage for expense/income label totals.
- 2026-04-27T21:07:46+03:00 [CODE] Updated transaction composer/category sheet behavior and removed user-facing success notifications.
- 2026-04-27T21:07:46+03:00 [CODE] Improved overview chart formatting, category donut/list mapping, and label decomposition UI.
- 2026-04-27T21:34:00+03:00 [CODE] Added first-class Spendee wallet CSV import/export support plus guarded integration coverage for the attached real file.
- 2026-04-27T21:34:00+03:00 [CODE] Replaced timing scaffold assertions with measured gates for dashboard, transaction query, FTS search, and CSV import/aggregate rebuild.

## Working set
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/CONTINUITY.md`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Sources/LedgerCore/Models.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Sources/LedgerCore/LedgerRepository.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Modules/LedgerCorePackage/Sources/LedgerCore/Models.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Modules/LedgerCorePackage/Sources/LedgerCore/LedgerRepository.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Sources/LedgerCore/CSVSupport.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Modules/LedgerCorePackage/Sources/LedgerCore/CSVSupport.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Sources/LedgerUI/Editors.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Sources/LedgerUI/DashboardView.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Sources/LedgerUI/SettingsView.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Tests/LedgerCoreTests/LedgerCoreTests.swift`
- `/Users/roman/Documents/Development/spendee_v2_ledger_transaction_overview_ux/Tests/LedgerCoreTests/LedgerPerformanceTests.swift`

## Receipts
- 2026-04-27T21:07:46+03:00 [TOOL] `git worktree add -b codex/transaction-overview-ux ../spendee_v2_ledger_transaction_overview_ux main` -> created isolated worktree at commit `8c86ca0`.
- 2026-04-27T21:04:22+03:00 [TOOL] `swift test` -> 19 tests in 2 suites passed, including `overviewSnapshotSeparatesExpenseIncomeAndLabels`.
- 2026-04-27T21:04:00+03:00 [TOOL] `xcrun simctl list devices available` -> no exact `iPhone 16`; available fallback includes booted `iPhone 17`.
- 2026-04-27T21:04:00+03:00 [TOOL] Requested `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 16' ... | tail -5` returned available destination alternatives and no `** BUILD SUCCEEDED **` footer.
- 2026-04-27T21:05:00+03:00 [TOOL] `xcodebuild -project SpendeeLedger.xcodeproj -scheme SpendeeLedger -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -5` -> `** BUILD SUCCEEDED **`.
- 2026-04-27T21:06:00+03:00 [TOOL] `xcrun simctl install booted .../SpendeeLedger.app && xcrun simctl launch booted dev.roman.spendeeledger` -> launched as pid `51894`.
- 2026-04-27T21:06:00+03:00 [TOOL] `xcrun simctl io booted screenshot /tmp/spendee-ledger-transaction-overview-ux.png` -> screenshot captured after launch.
- 2026-04-27T21:07:46+03:00 [TOOL] `git diff --check` -> no whitespace errors.
- 2026-04-27T21:31:40+03:00 [TOOL] `swift test` -> 23 tests in 2 suites passed; guarded real CSV fixture imported 13,896 rows without parser row loss.
- 2026-04-27T21:32:00+03:00 [TOOL] `git diff --check` and `diff -u` across mirrored `CSVSupport.swift`, `LedgerRepository.swift`, and `Models.swift` -> clean.
- 2026-04-27T21:33:00+03:00 [TOOL] Required `xcodebuild ... name=iPhone 16 ... | tail -5` failed with code 70 because no exact `iPhone 16` destination exists; available destinations include booted `iPhone 17`.
- 2026-04-27T21:33:30+03:00 [TOOL] `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -5` -> `** BUILD SUCCEEDED **`.
- 2026-04-27T21:34:00+03:00 [TOOL] `xcrun simctl install 46833F60... SpendeeLedger.app && xcrun simctl launch 46833F60... dev.roman.spendeeledger` -> launched as pid `92081`; host `ps -p 92081` confirmed process alive after 3 seconds.
- 2026-04-27T21:49:26+03:00 [TOOL] Rerun `swift test` -> 23 tests in 2 suites passed in 65.439s, including the attached real CSV fixture.
- 2026-04-27T21:52:00+03:00 [TOOL] Rerun required `xcodebuild ... name=iPhone 16 ... | tail -5` -> failed code 70 because only iPhone 16e and iPhone 17-family simulators are available.
- 2026-04-27T21:53:00+03:00 [TOOL] Rerun fallback `xcodebuild ... name=iPhone 17 ... | tail -5` -> `** BUILD SUCCEEDED **`.
- 2026-04-27T21:54:00+03:00 [TOOL] Rerun simulator install/launch on booted iPhone 17 -> launched as pid `6235`; host `ps -p 6235` confirmed process alive after 3 seconds.
