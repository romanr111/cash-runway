# CONTINUITY

## Snapshot
- 2026-04-26 [USER] Goal: implement the full `PLAN.md` MVP for a Cash Runway iPhone finance app using screenshot references.
- 2026-04-26 [DECISION] D001 ACTIVE: use a thin iOS host app plus a local Swift package for core/domain/UI modules so most functionality remains testable with `swift test`.
- 2026-04-26 [DECISION] D002 ACTIVE: use host Xcode tooling instead of containers because native iOS simulator builds are the required output.
- 2026-04-26 [DECISION] D003 ACTIVE: approximate screenshot styling with native SwiftUI primitives unless a task requires custom rendering.
- 2026-04-26 [DECISION] D004 ACTIVE: keep app-target core sources mirrored with `Modules/CashRunwayCorePackage` because the app target compiles local core sources while `swift test` uses the package.
- 2026-04-28T21:56:01+03:00 [DECISION] D005 ACTIVE: `iPhone 17` is the primary simulator validation destination on this machine; if unavailable, use the newest available iPhone simulator and record the exact name.
- 2026-04-27T22:34+03:00 [DECISION] D006 ACTIVE: remove App Group entitlement and default `appGroupIdentifier` to `nil` to enable free-account real-device provisioning.
- 2026-04-28T21:56:01+03:00 [OPEN] UNCONFIRMED manual import on a physical device because validation used simulator app-process e2e import plus generic `iphoneos` build, not an attached real-device picker run.
- 2026-04-28T23:23:00+03:00 [TOOL] Cash Runway rename was pushed to both `origin/codex/cash-runway-rename` and `origin/main`; GitHub default branch points at the renamed app code.
- 2026-04-29T10:05:57+03:00 [USER] Goal update: fix Timeline monthly bar direction, create/match CSV categories on import, and make Overview category rows drill into category transaction details.
- 2026-04-29T10:05:57+03:00 [CODE] Implementation was developed in worktree `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes` on branch `codex/overview-import-category-fixes`.
- 2026-04-29T10:05:57+03:00 [CODE] Timeline income and expense bars now both plot positive magnitudes; cash-flow totals remain signed as income minus expenses.
- 2026-04-29T10:05:57+03:00 [CODE] CSV import now trims/case-insensitively matches category names by transaction kind and creates missing non-system categories using `Other Expense` / `Other Income` icon-color defaults.
- 2026-04-29T10:05:57+03:00 [CODE] Overview category rows now navigate to a category detail screen with wallet/month filters, total, per-day bar chart, and tappable filtered transaction rows.
- 2026-04-29T10:21:14+03:00 [TOOL] Double-check before merge: feature branch retested, rebuilt, and relaunched on iPhone 17 simulator successfully.
- 2026-04-29T10:25:19+03:00 [TOOL] Branch `codex/overview-import-category-fixes` was committed as `5a82e18`, fast-forward merged into primary `main`, and verified from `/Users/roman/Documents/Development/Cash Runway`.
- 2026-04-29T10:47:00+03:00 [USER] Goal update: Timeline rows must show imported category names instead of generic `Expense`, and CSV-created categories should get approximate icons from English/Russian/Ukrainian category context.
- 2026-04-29T10:47:00+03:00 [CODE] Implementation is in worktree `/Users/roman/.codex/worktrees/cash-runway-timeline-category-icons` on branch `codex/timeline-category-icons`.
- 2026-04-29T10:47:00+03:00 [CODE] Timeline transaction rows now use category-first `displayTitle`; CSV-created categories keep exact-name creation/matching but choose icon/color by deterministic localized keyword rules when possible.
- 2026-04-29T10:51:00+03:00 [TOOL] Branch `codex/timeline-category-icons` was committed as `b25ae9d`, fast-forward merged into primary `main`, and verified from `/Users/roman/Documents/Development/Cash Runway`.
- 2026-04-29T11:05:00+03:00 [TOOL] Draft PR `https://github.com/romanr111/cash-runway/pull/2` was opened from `codex/cash-runway-overview-timeline-fixes` into `main`.
- 2026-04-29T19:12:00+03:00 [USER] Goal update: investigate and fix a brief freeze when switching between iOS apps.
- 2026-04-29T19:12:00+03:00 [CODE] Implementation is in worktree `/Users/roman/.codex/worktrees/cash-runway-app-switch-freeze-fix` on branch `codex/app-switch-freeze-fix`.
- 2026-04-29T19:12:00+03:00 [CODE] Foreground resume no longer runs maintenance, recurring refresh, and full model reload synchronously on the main actor; it loads a snapshot on a utility task and applies it only if the current filters still match.
- 2026-04-29T19:17:00+03:00 [TOOL] Branch `codex/app-switch-freeze-fix` was committed as `9eaa45e`, fast-forward merged into primary `main`, and pushed to PR branch `codex/cash-runway-overview-timeline-fixes`.
- 2026-04-29T23:02:00+03:00 [USER] Goal update: implement wallet removal with a minimum-one active wallet constraint.
- 2026-04-29T23:39:00+03:00 [CODE] Added `deleteWallet(id:)` to repository and AppModel; UI supports swipe-to-delete in wallet list and delete button in wallet editor with confirmation.
- 2026-04-29T23:39:00+03:00 [CODE] Added tests for wallet deletion (cascade removes transactions/transfers) and last-wallet guard.
- 2026-04-29T23:39:00+03:00 [TOOL] `swift test` → 33 tests in 2 suites passed; xcodebuild iPhone 17 simulator clean build → ** BUILD SUCCEEDED **; app launched without crashes.

## Done (recent)
- 2026-04-27 [MILESTONE] Core MVP, transaction/category UI, overview labels, wallet CSV import/export, and timing gates completed.
- 2026-04-28 [CODE] Fixed document-provider CSV import boundary and updated simulator validation target to `iPhone 17`.
- 2026-04-28T22:28:05+03:00 [CODE] Replaced the CSV mapping-first sheet with a review-first import sheet and added row-count/import-result coverage.
- 2026-04-28T22:53:00+03:00 [CODE] Added CSV preparation progress UI and clearer detected Type/Wallet copy.
- 2026-04-28T23:14:00+03:00 [CODE] Renamed project and app branding to Cash Runway across local code, project files, and GitHub repo metadata.
- 2026-04-29T10:05:57+03:00 [CODE] Added CSV category auto-create tests, exact-match/no-duplicate tests, and positive bar-facing assertions.
- 2026-04-29T10:47:00+03:00 [CODE] Added tests for Timeline category-first titles and localized contextual icons for CSV-created categories.
- 2026-04-29T19:12:00+03:00 [CODE] Added `TransactionQuery: Equatable` so async foreground refreshes can avoid applying stale snapshots after filter changes.

## Working set
- `/Users/roman/Documents/Development/Cash Runway/CONTINUITY.md`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayCore/CSVSupport.swift`
- `/Users/roman/Documents/Development/Cash Runway/Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CSVSupport.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayCore/Models.swift`
- `/Users/roman/Documents/Development/Cash Runway/Modules/CashRunwayCorePackage/Sources/CashRunwayCore/Models.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayUI/DashboardView.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayUI/SettingsView.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayUI/AppModel.swift`
- `/Users/roman/Documents/Development/Cash Runway/Tests/CashRunwayCoreTests/CashRunwayCoreTests.swift`

## Receipts
- 2026-04-28T23:17:00+03:00 [TOOL] After local folder rename and clearing stale SwiftPM `.build`, `swift test` -> 24 tests in 2 suites passed after 74.153s.
- 2026-04-28T23:18:41+03:00 [TOOL] After local folder rename, `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway ... name=iPhone 17 ... clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-28T23:19:15+03:00 [TOOL] After local folder rename, app-process CSV import self-test -> `PASS inserted=13896 file=transactions_export_2026-04-27_wallet.csv`.
- 2026-04-28T23:19:30+03:00 [TOOL] Final renamed app boot check on iPhone 17 simulator -> app active as pid `62611`; filtered logs had no app error/fatal/crash/exception/not-entitled/permission entries.
- 2026-04-28T23:23:00+03:00 [TOOL] `git ls-remote --heads origin main codex/cash-runway-rename` -> both refs aligned after publication.
- 2026-04-29T10:04:00+03:00 [TOOL] `git diff --check` -> clean.
- 2026-04-29T10:19:00+03:00 [TOOL] Double-check `swift test` in `codex/overview-import-category-fixes` -> 26 tests in 2 suites passed after 87.695s.
- 2026-04-29T10:19:17+03:00 [TOOL] Double-check `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T10:20:52+03:00 [TOOL] Double-check iPhone 17 simulator boot/install/launch -> `dev.roman.cashrunway: 85949`; filtered logs had no fatal/crash/exception/not-entitled entries.
- 2026-04-29T10:22:51+03:00 [TOOL] Post-merge `swift test` from primary `main` -> 26 tests in 2 suites passed after 85.939s.
- 2026-04-29T10:24:47+03:00 [TOOL] Post-merge `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T10:25:00+03:00 [TOOL] Post-merge iPhone 17 simulator install/launch from primary checkout -> `dev.roman.cashrunway: 96224`; filtered logs had no fatal/crash/exception/not-entitled entries.
- 2026-04-29T10:43:41+03:00 [TOOL] `swift test` in `codex/timeline-category-icons` -> 27 tests in 2 suites passed after 74.068s.
- 2026-04-29T10:45:20+03:00 [TOOL] `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` in `codex/timeline-category-icons` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T10:46:50+03:00 [TOOL] iPhone 17 simulator install/launch in `codex/timeline-category-icons` -> `dev.roman.cashrunway: 35648`; filtered app logs had no fatal/crash/exception/not-entitled/permission/error entries.
- 2026-04-29T10:47:46+03:00 [TOOL] Post-merge `swift test` from primary `main` -> 27 tests in 2 suites passed after 82.483s.
- 2026-04-29T10:49:41+03:00 [TOOL] Post-merge `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T10:50:20+03:00 [TOOL] Post-merge iPhone 17 simulator install/launch from primary checkout -> `dev.roman.cashrunway: 42199`; filtered app logs had no fatal/crash/exception/not-entitled/permission/error entries.
- 2026-04-29T19:09:18+03:00 [TOOL] `swift test` in `codex/app-switch-freeze-fix` -> 27 tests in 2 suites passed after 85.059s.
- 2026-04-29T19:11:10+03:00 [TOOL] `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` in `codex/app-switch-freeze-fix` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T19:11:45+03:00 [TOOL] iPhone 17 simulator install/launch plus app-switch smoke check -> `dev.roman.cashrunway: 96309`; fatal/crash/exception/not-entitled log filter empty.
- 2026-04-29T19:13:44+03:00 [TOOL] Post-merge `swift test` from primary `main` -> 27 tests in 2 suites passed after 90.488s.
- 2026-04-29T19:15:37+03:00 [TOOL] Post-merge `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T19:16:10+03:00 [TOOL] Post-merge iPhone 17 simulator install/launch plus app-switch smoke check -> `dev.roman.cashrunway: 3069`; fatal/crash/exception/not-entitled log filter empty.
- 2026-04-29T18:58:20+03:00 [TOOL] Final verification from primary checkout: `swift test` -> 27 tests in 2 suites passed after 69s.
- 2026-04-29T18:58:20+03:00 [TOOL] Final verification: `xcodebuild -scheme CashRunway -sdk iphonesimulator -destination 'name=iPhone 17' clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-29T18:58:20+03:00 [TOOL] Final boot check on iPhone 17 simulator -> `dev.roman.cashrunway: 9806`; fatal/crash/exception/not-entitled log filter empty.
- 2026-04-29T23:31:00+03:00 [USER] Goal update: replace Dashboard "By months" dropdown with Period Size selector (Day/Week/Month/Year); chart and transaction feed must adapt to selected period.
- 2026-04-29T23:31:00+03:00 [CODE] DateKeys extended with weekKey, yearKey, periodKey, periodLabel, and weekDateRange helpers.
- 2026-04-29T23:31:00+03:00 [CODE] Models generalized: TimelinePeriod enum added; TimelineBarPoint uses periodKey/xLabel; TransactionDaySection renamed to TimelineSection with periodLabel.
- 2026-04-29T23:31:00+03:00 [CODE] Repository timelineSnapshot now accepts a period parameter and generates daily/weekly/monthly/yearly bars plus appropriately-grouped sections.
- 2026-04-29T23:31:00+03:00 [CODE] Dashboard filters replaced month-list dropdown with Period Size selector; prev/next arrow buttons navigate months; chart uses xLabel; feed uses periodLabel.
- 2026-04-29T23:31:00+03:00 [CODE] 33 tests pass including new DateKeys round-trip, period label, and timeline snapshot grouping tests for all periods.
- 2026-04-29T23:31:00+03:00 [TOOL] `swift test` -> 33 tests passed; `xcodebuild` -> BUILD SUCCEEDED; iPhone 17 simulator boot check -> `dev.roman.cashrunway: 24558`; no fatal/crash/exception entries.
