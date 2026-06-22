Goal: Deduplicate and Modularize CashRunwayCore — Phase 2B (in progress)

Branch: `codex/core-reporting-config-extraction`
Worktree: `/Users/roman/.codex/worktrees/cash-runway-dedup-core`

PR 2A (extract reporting configuration) — completed and pushed:
- `ReportingKeychainSecretProvider` now accepts injected `bundledSecret`.
- Generated file moved from `Sources/CashRunwayCore/` to `AppHost/`.
- Enum renamed `ReportingSecrets` -> `AppReportingSecrets`.
- Xcode build phase, `.swiftlint.yml`, and `reporting-api/README.md` updated.
- 5 new tests covering precedence, persistence, and nil/empty handling.
- 385 Swift tests pass; Xcode build passes.
- Draft PR #69 created targeting PR #66 branch.

PR 2B (consume CashRunwayCore package product) — in progress:
- `Package.swift` now exposes `CashRunwayCore` library product.
- Xcode app target:
  - Removed all direct `Sources/CashRunwayCore/*.swift` entries from Sources build phase.
  - Removed direct CoreXLSX dependency from app target.
  - Kept GRDB directly linked (AppHost debug recovery code uses GRDB symbols).
  - Added `CashRunwayCore` local package product dependency to Frameworks.
- Removed `#if canImport(CashRunwayCore)` guards; normalized to explicit imports.
- Made narrow access-control fixes for module boundary:
  - `DatabaseManager.init(keychain:)` → `public`
  - `ReportIssueResponse` gained explicit `public init`
  - `CSVImportPreview` gained explicit `public init`
- Fixed type-ambiguity (`CashRunwayCore.Category`/`Label`, `Date.now`, `CategoryKind.expense`).
- Xcode Debug simulator build **BUILD SUCCEEDED**.
- `Scripts/pre-flight.sh` and `.github/workflows/ios-ci.yml` updated to validate
  the Phase 2B invariants (no direct Core compilation + CashRunwayCore linked).
- Added `Scripts/verify-pbxproj.sh` for fast pbxproj corruption detection.
- `AGENTS.md` updated with Xcode Project Safety section.

Still to complete:
- Reconcile root SPM `Package.resolved` (SQLCipher 4.15.0) with Xcode workspace
  `Package.resolved` (SQLCipher 4.14.0).
- Run `swift test` and `just lint` validation.
- Run Release configuration Xcode build.
- Commit remaining changes and create/update draft PR.
