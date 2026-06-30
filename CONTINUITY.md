## Snapshot — Cash Runway persistence rules and skill updates

Branch: `codex/cash-runway-persistence-change`
Worktree: `/Users/roman/.codex/worktrees/cash-runway-persistence-change`
Merge status: not-merged
Worktree reason: isolated-feature

Goal: update local Cash Runway AGENTS guidance and local skills for persistence, migration, and review workflows.

## Current state

- `AGENTS.md` updated with SwiftPM silent-hang fallback, safe test-filter quoting, CodeGraph narrow-window reads, and persistence-change notes.
- `~/.codex/skills/cash-runway-validation/SKILL.md` updated with the same validation rules plus log-first routing for `just check-integration` and `just check`.
- `~/.codex/skills/self-review/SKILL.md` and `~/.codex/skills/code-review/SKILL.md` now call out new repository or protocol seams that lack direct behavioral tests.
- New local skill `cash-runway-persistence-change` created for migrations, repository seams, and backup/export/restore compatibility.

## Validation

- `git diff --check`: passed.
- No build or test run; this was a documentation and skill-metadata update only.

## Receipts

- Separate worktree used because the primary checkout was dirty with unrelated files.
- Local skills live outside the repo and are not tracked by git.

## Snapshot — Two-tap category detail navigation

Branch: `codex/two-tap-category-detail`
Worktree: `/Users/roman/.codex/worktrees/cash-runway-two-tap-category-detail`
PR: https://github.com/romanr111/cash-runway/pull/83 (draft, base `dev`)

Goal: Overview category rows use a two-tap state machine. First user tap selects
and arms a row; second tap on the same selected row opens
`CategoryDetailOverviewView` for the active month and wallet filter.

## Current state

- `Sources/CashRunwayUI/DashboardView.swift`
  - Adds item-driven `CategoryDetailRoute` navigation.
  - Tracks `categoryDetailArmedCategoryID`.
  - Keeps donut chart taps selection-only.
  - Resets arming when category kind, month, wallet, category identity list, donut selection,
    or Show More/Less context changes.
- `Tests/CashRunwayUITests/TransactionOverviewUITests.swift`
  - Existing Overview drilldown test taps Groceries once, asserts detail does not open,
    then taps again and asserts detail opens with the created note.

## Latest update

- Merged `origin/dev` into this branch to resolve PR conflicts.
  - `CONTINUITY.md` was the only manual conflict; auto-merged files:
    `Sources/CashRunwayCore/CSVSupport.swift`,
    `Sources/CashRunwayCore/CashRunwayRepository.swift`,
    `Tests/CashRunwayCoreTests/CSVIdempotencyTests.swift`,
    `Tests/CashRunwayCoreTests/MigrationIntegrityTests.swift`.
  - No secrets, generated reporting secrets, project files, lock files, or entitlements were touched.
- Fixed review issue: Show More/Less now clears the armed category before changing
  the displayed category context.
- Recreated this worktree because it was missing locally while the branch still existed.
- Repaired partial `.codegraph` by removing the generated directory and rerunning bootstrap.

## Validation

- `git diff --check`: passed.
- `Scripts/pre-flight.sh`: passed.
- `just build`: passed on iPhone 17 simulator.
  - Existing warnings only: duplicate `AppHost/uk.lproj/InfoPlist.strings` project reference,
    signed SQLCipher binary not stripped, AppIntents metadata skipped.
- `just graph-bootstrap`: passed after `.codegraph` repair.
- `just graph-sync`: passed.
- `just check-unit-parallel`: passed, 58 tests in 5 suites.

## Skipped / blocked

- XCUITest not run locally per repo policy.
- Physical-device rehearsal not run; this is not a release/SideStore task.

## Git safety notes

- `dev` worktree was dirty but was not modified by this merge.
- Only this isolated feature worktree was edited.

## Snapshot - Dev build SQLCipher artifact repair (`dev`)

Branch: `dev` @ `1860608` with pre-existing dirty files.
Goal: investigate Xcode dev build failure showing missing `SQLCipher` package product / missing `SQLCipher.xcframework`.
Status: fixed local Xcode package artifact state by resolving packages; no source patch required.

## Validation

- `swift package resolve`: passed.
- `xcodebuild -resolvePackageDependencies -project CashRunway.xcodeproj -scheme CashRunway`: passed; log `/tmp/cash-runway-agent-validation/xcode-resolve-packages-20260628-131144.log`.
- `xcodebuild -scheme CashRunway -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build`: passed; log `/tmp/cash-runway-agent-validation/xcode-generic-ios-build-20260628-131217.log`.
- `just build`: attempted simulator build, stopped after idle/no final result; partial log `/tmp/cash-runway-agent-validation/dev-build-20260628-130556.log`.
- Build regenerated `AppHost/AppReportingSecrets.generated.swift`; restored generated file to committed placeholder state.

## Snapshot - Delete All History icon review (`dev`)

Branch: `dev` @ `09a5190` with uncommitted review fixes.
Goal: Detailed review of the all-history delete icon change and current dirty diff; fix important issues only.
Status: one blocking issue fixed: `AppHost/AppReportingSecrets.generated.swift` was regenerated with `isPlaceholder = false`; restored it to the committed placeholder state and kept it out of the final diff.

## Validation

- `just build`: BUILD SUCCEEDED on 2026-06-27; local build regenerated reporting secrets from local config, then placeholder file was restored.
- `just lint`: passed, 0 violations.
- `python3 -m json.tool AppHost/Localizable.xcstrings`: passed.
- `git diff --check -- Sources/CashRunwayUI/DeleteTransactionsView.swift AppHost/Localizable.xcstrings CONTINUITY.md`: passed.

## Snapshot - Delete All History icon fallback (`dev`)

Branch: `dev` @ `09a5190` with uncommitted UI fix.
Goal: Restore the missing icon for the "All History" delete-period row.
Status: implemented; build gate passed.

## Changes

- `Sources/CashRunwayUI/DeleteTransactionsView.swift` - changed `.allHistory` period icon from `skull.fill` to `trash.fill` because the skull SF Symbol rendered as a blank glyph on the target device.

## Validation

- `just build`: BUILD SUCCEEDED on 2026-06-27.

## Skipped Gates

- Interactive device/simulator visual verification was not exercised; XCUITest/E2E is disallowed locally unless explicitly requested.

## Snapshot - Delete All History + UI polish (`dev`)

Branch: `dev` @ `a07f25f` (audit commit).
Goal: Add "All History" option to Delete Transactions sheet, plus UI polish.
Status: implemented, all gates green, uncommitted.

## Changes

- `Sources/CashRunwayCore/DeletePeriod.swift`
- `Sources/CashRunwayCore/CashRunwayRepository.swift` - `deletePeriodPredicate` handles `.allHistory` with `1 = 1`.
- `Sources/CashRunwayCore/L10n.swift`
- `Sources/CashRunwayUI/DeleteTransactionsView.swift`
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift`
- `AppHost/Localizable.xcstrings`
- `Tests/CashRunwayCoreTests/BulkDeleteTransactionsTests.swift`

## Validation

- `swift build --target CashRunwayCore`: passed
- `just test-filter BulkDeleteTransactionsTests`: 36/36 passed
- `swiftlint --strict` on changed files: 0 violations
- `just build`: BUILD SUCCEEDED

## Skipped Gates

- Interactive sheet navigation (open, select All History, type DELETE, success card, Done): manual gate, not exercised locally because XCUITest is disallowed per AGENTS.md unless explicitly requested.

## Open / Performance

- Row-by-row aggregate reversal for very large histories. Consider optimizing to drop/rebuild aggregate tables only if reported slow.

## Snapshot - Bulk delete transactions feature

Branch: `codex/bulk-delete-transactions` (merged via PR #75, squash commit `dd941fe`)
Worktree: `~/.codex/worktrees/cash-runway-bulk-delete-transactions`
Base: `dev` @ d903f61
Status: MERGED into `dev`.

Feature adds Delete Transactions counts plus total four-step destructive flow:
open sheet, select period, backup prompt, type DELETE/VIDALYTY to enable the destructive CTA.

Decisions:
- Hard-deletes transaction rows for manual, Monobank, CSV, and recurring instances.
- Recurring templates are preserved.
- Transfer pairs delete only the in-period half.
- Preview creates immutable `TransactionDeletionPlan` values.
- `deleteTransactions(plan:)` awaits `reloadAll()` and returns `TransactionDeletionResult`.
- `transactionDeletionSummary(for:)` uses SQL aggregate counts and sums.
- `deletePeriodPredicate` excludes tombstoned rows with `is_deleted = 0`.

## Previous Architecture Audit

Branch: `dev` @ `fed7859`
Goal: Deep architecture audit of Cash Runway covering maintainability, security/privacy, performance, and future LLM-agent integration.
Status: complete. Deliverable saved to `docs/ARCHITECTURE_AUDIT.md`.

Key findings:
- `Sources/CashRunwayCore/CashRunwayRepository.swift` is a large repository/facade containing DAO, bank sync, resolver, backup, recurring, and aggregate responsibilities.
- `AppHost/CashRunway.entitlements` was empty; no default data protection entitlement was present in the audit snapshot.
- `bank_transaction_imports.raw_json` stores full Monobank payload data.

Recommendations:
- Split repository responsibilities behind focused internal services while preserving `CashRunwayRepository` compatibility.
- Add file protection support and validate on device.
- Redact or TTL-purge raw bank import payloads.
- Keep migration identifiers stable and protect them with tests.
