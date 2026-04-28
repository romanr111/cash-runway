# CONTINUITY

## Snapshot
- 2026-04-26 [USER] Goal: implement the full `PLAN.md` MVP for a Cash Runway iPhone finance app using the provided screenshots as UI reference.
- 2026-04-26 [DECISION] D001 ACTIVE: use a thin iOS host app plus a local Swift package for core/domain/UI modules so most functionality remains testable with `swift test`.
- 2026-04-26 [DECISION] D002 ACTIVE: use host Xcode tooling instead of containers because native iOS simulator builds are the required output.
- 2026-04-26 [DECISION] D003 ACTIVE: approximate screenshot styling with native SwiftUI primitives instead of custom rendering unless specifically needed.
- 2026-04-26 [DECISION] D004 ACTIVE: keep app-target core sources mirrored with `Modules/CashRunwayCorePackage` because the app target compiles local core sources while `swift test` uses the package.
- 2026-04-28T21:56:01+03:00 [DECISION] D005 ACTIVE: `iPhone 17` is the primary simulator validation destination on this machine; if unavailable, use the newest available iPhone simulator and record the exact name.
- 2026-04-28T21:56:01+03:00 [OPEN] UNCONFIRMED manual import on a physical device because validation used simulator app-process e2e import plus generic `iphoneos` build, not an attached real-device picker run.
- 2026-04-27T22:34+03:00 [DECISION] D006 ACTIVE: remove App Group entitlement and default `appGroupIdentifier` to `nil` to enable free-account real-device provisioning.
- 2026-04-28T22:28:05+03:00 [USER] Goal update: implement a minimal review-first CSV import screen that hides unnecessary mapping controls for detected Cash Runway wallet CSVs.
- 2026-04-28T22:28:05+03:00 [CODE] CSV import sheet now presents detected format/row count/behavior summary, fallback wallet, compact 3-row preview, generic-only advanced mapping, and in-sheet import result/skipped-row feedback.
- 2026-04-28T22:53:00+03:00 [USER] Goal update: show CSV data-loading progress and clarify confusing Type/Wallet detected summary copy.
- 2026-04-28T22:53:00+03:00 [CODE] CSV import review sheet now opens immediately after file selection, shows linear progress while file copy/preview runs, hides Format/Rows/mapping until ready, and clarifies Type as `Income / Expense`.
- 2026-04-28T22:53:00+03:00 [CODE] Cash Runway wallet summary now says wallet names come from CSV and unmatched names use the selected fallback wallet; fallback wallet footer explains when it applies.
- 2026-04-28T23:14:00+03:00 [USER] Goal update: rename the app, project, local folder, and GitHub repository to `Cash Runway`.
- 2026-04-28T23:14:00+03:00 [CODE] Renamed app/project identifiers to Cash Runway/CashRunway/cash-runway, including Xcode project, target, bundle id, SwiftPM package/module/test names, app display name, source folders, and debug self-test names.
- 2026-04-28T23:14:00+03:00 [TOOL] GitHub repo renamed to `romanr111/cash-runway`; `origin` now points at `https://github.com/romanr111/cash-runway.git`.
- 2026-04-28T23:19:30+03:00 [TOOL] Primary local checkout folder renamed to `/Users/roman/Documents/Development/Cash Runway`; branch is `codex/cash-runway-rename`.
- 2026-04-28T23:23:00+03:00 [TOOL] Cash Runway rename pushed to both `origin/codex/cash-runway-rename` and `origin/main`; GitHub default branch now points at the renamed app code.

## Done (recent)
- 2026-04-27 [MILESTONE] Core MVP, transaction/category UI, overview labels, wallet CSV import/export, and timing gates completed; see prior continuity/branch notes.
- 2026-04-28 [CODE] Fixed document-provider CSV import boundary and updated simulator validation target to `iPhone 17`.
- 2026-04-27T22:34+03:00 [CODE] Enabled free-account device signing by removing App Group entitlement/default and allowing app target code signing.
- 2026-04-28T22:28:05+03:00 [CODE] Replaced the CSV mapping-first sheet with a review-first import sheet and added row-count/import-result coverage.
- 2026-04-28T22:53:00+03:00 [CODE] Added CSV preparation progress UI and clearer detected Type/Wallet copy.
- 2026-04-28T22:53:00+03:00 [CODE] Fixed the debug CSV import self-test harness to count all imported rows with `limit: nil`.
- 2026-04-28T23:14:00+03:00 [CODE] Renamed project and app branding to Cash Runway across local code, project files, and GitHub repo metadata.

## Working set
- `/Users/roman/Documents/Development/Cash Runway/CONTINUITY.md`
- `/Users/roman/Documents/Development/Cash Runway/AGENTS.md`
- `/Users/roman/Documents/Development/Cash Runway/AppHost/CashRunway.entitlements`
- `/Users/roman/Documents/Development/Cash Runway/AppHost/CashRunwayApp.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayCore/DatabaseManager.swift`
- `/Users/roman/Documents/Development/Cash Runway/Modules/CashRunwayCorePackage/Sources/CashRunwayCore/DatabaseManager.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayCore/CSVSupport.swift` + `Sources/CashRunwayCore/Models.swift`
- `/Users/roman/Documents/Development/Cash Runway/Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CSVSupport.swift` + `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/Models.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayUI/AppModel.swift`
- `/Users/roman/Documents/Development/Cash Runway/Sources/CashRunwayUI/SettingsView.swift`
- `/Users/roman/Documents/Development/Cash Runway/CashRunway.xcodeproj/project.pbxproj`
- `/Users/roman/Documents/Development/Cash Runway/Tests/CashRunwayCoreTests/CashRunwayCoreTests.swift`

## Receipts
- 2026-04-28T22:24:48+03:00 [TOOL] `swift test` -> 24 tests in 2 suites passed after 68.217s, including new CSV preview row-count and skipped-row result coverage.
- 2026-04-28T22:26:32+03:00 [TOOL] First `xcodebuild ... name=iPhone 17 ... clean build` hit transient Xcode `build.db` lock; immediate retry -> `** BUILD SUCCEEDED **`.
- 2026-04-28T22:27:00+03:00 [TOOL] App-process CSV import self-test on booted iPhone 17 simulator initially failed because CSV was seeded before runtime data container stabilized; rerun after warm launch -> `PASS inserted=2 file=transactions_export_2026-04-27_wallet.csv`.
- 2026-04-28T22:28:05+03:00 [TOOL] `git diff --check`; mirrored `Models.swift` and `CSVSupport.swift` diffs -> clean/matching.
- 2026-04-28T22:29:00+03:00 [TOOL] Final boot check on booted iPhone 17 simulator -> app active as pid `66694`; filtered logs had no app error/fatal/crash/exception/not-entitled/permission entries.
- 2026-04-28T22:45:25+03:00 [TOOL] Pre-harness-fix `swift test` -> 24 tests in 2 suites passed after 87.414s.
- 2026-04-28T22:47:00+03:00 [TOOL] Pre-harness-fix `xcodebuild ... name=iPhone 17 ... clean build 2>&1 | tail -20` -> `** BUILD SUCCEEDED **`.
- 2026-04-28T22:51:52+03:00 [TOOL] Post-harness-fix `swift test` -> 24 tests in 2 suites passed after 79.093s.
- 2026-04-28T22:52:30+03:00 [TOOL] Post-harness-fix `xcodebuild ... name=iPhone 17 ... clean build 2>&1 | tail -20` -> `** BUILD SUCCEEDED **`.
- 2026-04-28T22:53:00+03:00 [TOOL] App-process CSV import self-test on booted iPhone 17 simulator using full attached fixture -> `PASS inserted=13896 file=transactions_export_2026-04-27_wallet.csv`.
- 2026-04-28T22:53:30+03:00 [TOOL] Final boot check on iPhone 17 simulator -> app active as pid `99660`; filtered logs had no app error/fatal/crash/exception/not-entitled/permission entries.
- 2026-04-28T23:10:46+03:00 [TOOL] Renamed `swift test` -> 24 tests in 2 suites passed after 90.006s.
- 2026-04-28T23:12:42+03:00 [TOOL] `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-28T23:13:30+03:00 [TOOL] Renamed app-process CSV import self-test on iPhone 17 simulator -> `PASS inserted=13896 file=transactions_export_2026-04-27_wallet.csv`.
- 2026-04-28T23:14:00+03:00 [TOOL] Renamed app boot check on iPhone 17 simulator -> app active as pid `51321`; filtered logs had no app error/fatal/crash/exception/not-entitled/permission entries.
- 2026-04-28T23:17:00+03:00 [TOOL] After local folder rename and clearing stale SwiftPM `.build`, `swift test` -> 24 tests in 2 suites passed after 74.153s.
- 2026-04-28T23:18:41+03:00 [TOOL] After local folder rename, `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway ... name=iPhone 17 ... clean build` -> `** BUILD SUCCEEDED **`.
- 2026-04-28T23:19:15+03:00 [TOOL] After local folder rename, app-process CSV import self-test -> `PASS inserted=13896 file=transactions_export_2026-04-27_wallet.csv`.
- 2026-04-28T23:19:30+03:00 [TOOL] Final renamed app boot check on iPhone 17 simulator -> app active as pid `62611`; filtered logs had no app error/fatal/crash/exception/not-entitled/permission entries.
- 2026-04-28T23:23:00+03:00 [TOOL] `git ls-remote --heads origin main codex/cash-runway-rename` -> both refs aligned after publication.
