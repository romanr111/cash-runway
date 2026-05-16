# CONTINUITY

## Snapshot
- 2026-05-16T23:31:30+0300 [ACTIVE] Primary checkout `/Users/roman/Documents/Development/Cash Runway` is on branch `codex/primary-checkout-cleanup`, tracking `origin/codex/primary-checkout-cleanup`.
- 2026-05-16T23:31:30+0300 [ACTIVE] `origin/main` is `7d23d4a`. Current branch contains the continuity cleanup/update work intended for PR into `origin/main`.
- 2026-05-16T23:31:30+0300 [ACTIVE] Remaining worktrees: primary checkout plus `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data` on unmerged branch `codex/stop-fake-data`.
- 2026-05-16T23:22:30+0300 [DONE] Primary checkout conflicts were resolved by backing up the dirty state, aligning `main` to `origin/main`, and removing stale merged worktrees/branches.
- 2026-05-16T23:22:30+0300 [BACKUP] Recoverable conflicted-state backup: `/Users/roman/.codex/backups/cash-runway-primary-conflicts-20260516-232230`.

## Current Remote State
- `origin/main` includes the merged Monobank/bank-sync work, GitHub Actions workflow, SwiftLint CI integration, full backup/restore, CSV import hardening, database safety work, and performance/test expansion.
- `codex/primary-checkout-cleanup` is the only branch currently being prepared for merge into `origin/main` from the primary checkout.
- `codex/stop-fake-data` is intentionally preserved because it is not merged into `origin/main`.

## Latest Validation
- 2026-05-16T23:26:24+0300 [VERIFY] `swift test` passed 215 tests in 21 suites after 138.757s.
- 2026-05-16T23:26:24+0300 [VERIFY] `xcodebuild -project CashRunway.xcodeproj -scheme CashRunway -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build` ended `** BUILD SUCCEEDED **`.
- 2026-05-16T23:26:xx+0300 [VERIFY] iPhone 17 simulator launch succeeded for `dev.roman.cashrunway` as pid `33259`; Timeline UI loaded with filters, empty chart state, tab bar, and add button visible.
- 2026-05-16T23:26:xx+0300 [VERIFY] Recent app log check found no crash/fatal/exception/error entries for the launch window.

## Durable Decisions
- Core sources are mirrored between `Sources/CashRunwayCore/` and `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/`; keep edits synchronized in the same change batch.
- Native iOS tooling is the default for this repo. Do not create Docker/container workflows for normal Cash Runway work unless explicitly requested.
- UI tests are high-cost and opt-in. Prefer targeted unit tests unless the user explicitly asks for UI-test work.
- Real-device debugging is approval-gated unless the issue is confirmed device-specific. Simulator verification is the default.
- When hiding deferred features, preserve code and disable UI/tests with explicit deprecation comments rather than deleting data models or migrations.

## Recent Milestones
- GitHub Actions workflow was split into dedicated CI stages and SwiftLint configuration was added to `origin/main`.
- Monobank settings integration and bank sync phases 1-2 merged into `origin/main`.
- Full backup and replace-mode restore merged into `origin/main`.
- Atomic/idempotent CSV import merged into `origin/main`.
- Database/keychain crash-resilience hardening and performance regression gates are present on `origin/main`.
