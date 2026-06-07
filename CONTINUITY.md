<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true true.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Implement English/Ukrainian localization with system default and an in-app language selector.
- Success criteria: App supported English and Ukrainian UI strings, defaulted to iOS language when set to System, offered a More > Settings language selector, display-localized built-in categories without renaming stored data, and focused validation passed without local UI/E2E execution.
- Current state: Localization implementation was completed locally on `codex/localization-en-uk` with simulator build, test-build compile, seeded English/Ukrainian launch, and Ukrainian category-screen screenshot checks passing.
- Next action: Review diff and decide whether to commit/push/open PR.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-localization-en-uk`
- Branch: `codex/localization-en-uk`
- Base branch: `origin/main`
- Worktree reason: isolated-feature
- Merge status: not-merged

## Working set

- `AppHost/Localizable.xcstrings`
- `CashRunway.xcodeproj/project.pbxproj`
- `Sources/CashRunwayUI/Localization.swift`
- `Sources/CashRunwayUI/RootView.swift`
- `Sources/CashRunwayUI/SettingsView.swift`
- `Sources/CashRunwayUI/DashboardView.swift`
- `Sources/CashRunwayUI/Editors.swift`
- `Sources/CashRunwayUI/TransactionsView.swift`
- `Sources/CashRunwayUI/CSVImportView.swift`
- `Sources/CashRunwayUI/BackupView.swift`
- `Sources/CashRunwayUI/MonobankWizardView.swift`
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift`
- `Sources/CashRunwayUI/Theme.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-06-06 [SETUP] Created localization worktree `/Users/roman/.codex/worktrees/cash-runway-localization-en-uk` on branch `codex/localization-en-uk` from `origin/main`.
- 2026-06-06 [CODE] Added `AppHost/Localizable.xcstrings` with English/Ukrainian entries and added `uk` to the Xcode project known regions/resources.
- 2026-06-06 [CODE] Added app language preference support with `system`, `en`, and `uk`, stored as `cashRunway.languagePreference`.
- 2026-06-06 [UI] Added a compact More > Settings language selector using existing row/surface styling and SF Symbols.
- 2026-06-06 [UI] Localized active timeline, More/settings, editors, CSV/backup import, Monobank wizard, date labels, plural counts, and dynamic helper labels.
- 2026-06-06 [DATA] Added UI-only built-in category display-name localization via stable seed UUIDs; stored category names, wallet names, CSV data, backups, and import matching stayed unchanged.
- 2026-06-06 [DESIGN] Checked Ukrainian timeline and category-management screenshots for compact text fit; long category merge button fit in the existing bottom action capsule.

## Receipts

- 2026-06-06 [SETUP] Localization worktree `codex/localization-en-uk` created at `/Users/roman/.codex/worktrees/cash-runway-localization-en-uk`.
- 2026-06-06 [VALIDATED] `ruby -rjson -e 'JSON.parse(...)' AppHost/Localizable.xcstrings` passed.
- 2026-06-06 [VALIDATED] `Scripts/validate-ui-only.sh` passed, including core mirror diff, `git diff --check`, iPhone 17 clean simulator build, and category icon catalog check.
- 2026-06-06 [VALIDATED] `xcodebuild ... -derivedDataPath /tmp/cash-runway-localization-build-for-testing build-for-testing` ended with `** TEST BUILD SUCCEEDED **`; UI/E2E tests were not executed.
- 2026-06-06 [SMOKE] English seeded `transaction_core` launch passed log scan; screenshot `/tmp/cash-runway-agent-validation/20260606-194417-13243/screenshot.png`.
- 2026-06-06 [SMOKE] Ukrainian seeded `transaction_core` launch passed log scan; screenshot `/tmp/cash-runway-agent-validation/20260606-194945-uk-final/screenshot.png`.
- 2026-06-06 [SMOKE] Ukrainian seeded `category_management` launch passed log scan; screenshot `/tmp/cash-runway-agent-validation/20260606-195252-uk-category-final/screenshot.png`.
- 2026-06-06 [NOTE] Known existing build warnings remained: AppIcon size warnings, SQLCipher signed-binary strip warning, AppIntents metadata warning, and UI-test main-actor compile warnings.
