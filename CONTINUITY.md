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
- 2026-04-29T10:05:57+03:00 [CODE] Implementation lives in worktree `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes` on branch `codex/overview-import-category-fixes`.
- 2026-04-29T10:05:57+03:00 [CODE] Timeline income and expense bars now both plot positive magnitudes; cash-flow totals remain signed as income minus expenses.
- 2026-04-29T10:05:57+03:00 [CODE] CSV import now trims/case-insensitively matches category names by transaction kind and creates missing non-system categories using `Other Expense` / `Other Income` icon-color defaults.
- 2026-04-29T10:05:57+03:00 [CODE] Overview category rows now navigate to a category detail screen with wallet/month filters, total, per-day bar chart, and tappable filtered transaction rows.
- 2026-04-29T10:21:14+03:00 [TOOL] Double-check before merge: feature branch retested, rebuilt, and relaunched on iPhone 17 simulator successfully.

## Done (recent)
- 2026-04-27 [MILESTONE] Core MVP, transaction/category UI, overview labels, wallet CSV import/export, and timing gates completed.
- 2026-04-28 [CODE] Fixed document-provider CSV import boundary and updated simulator validation target to `iPhone 17`.
- 2026-04-28T22:28:05+03:00 [CODE] Replaced the CSV mapping-first sheet with a review-first import sheet and added row-count/import-result coverage.
- 2026-04-28T22:53:00+03:00 [CODE] Added CSV preparation progress UI and clearer detected Type/Wallet copy.
- 2026-04-28T23:14:00+03:00 [CODE] Renamed project and app branding to Cash Runway across local code, project files, and GitHub repo metadata.
- 2026-04-29T10:05:57+03:00 [CODE] Added CSV category auto-create tests, exact-match/no-duplicate tests, and positive bar-facing assertions.

## Working set
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/CONTINUITY.md`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Sources/CashRunwayCore/CSVSupport.swift`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CSVSupport.swift`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Sources/CashRunwayCore/Models.swift`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Modules/CashRunwayCorePackage/Sources/CashRunwayCore/Models.swift`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Sources/CashRunwayUI/DashboardView.swift`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Sources/CashRunwayUI/SettingsView.swift`
- `/Users/roman/.codex/worktrees/cash-runway-overview-import-category-fixes/Tests/CashRunwayCoreTests/CashRunwayCoreTests.swift`

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
