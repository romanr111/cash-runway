# Plan: Settings Navigation UI Test Coverage

## Goal
Add a targeted XCUITest smoke suite that verifies every Settings row opens its destination and returns cleanly — the one manual test not already covered by the 235 existing unit/integration/performance tests.

## Why this is doable now
- UITest runtime harness (`UITestRuntime.swift`) already provides deterministic fixture seeding and isolated DB/keychain.
- Base class (`CashRunwayUITestCase`) has launch helpers, `returnToRoot()`, and identifier constants.
- Monobank wizard is already fully instrumented; we only need to catch up Settings + its sub-views.

## Implementation steps

### 1. Instrument SettingsView.swift
Add `accessibilityIdentifier(...)` to every tappable row in Settings:
- `settingsCategoriesRow`
- `settingsLabelsRow`
- `settingsScheduledTransactionsRow`
- `settingsMainCurrencyRow`
- `settingsWalletsRow`
- `settingsImportCSVRow`
- `settingsExportCSVRow`
- `settingsBackupRow`
- `settingsMonobankRow` (already exists — verify)

### 2. Instrument sub-view navigation anchors
Add identifiers to the elements a test needs to confirm "this screen opened":
- **WalletManagementView.swift**: `walletManagementHeader` or first list row
- **LabelManagementView.swift**: `labelManagementHeader` or first list row
- **BackupView.swift**: `backupExportButton`
- **CSVImportView.swift**: `csvImportChooseFileButton`

Keep it minimal — one "proof of life" identifier per destination is enough for a smoke test.

### 3. Sync test-side identifier enum
Mirror every new identifier string in `CashRunwayUITestIdentifiers` inside `Tests/CashRunwayUITests/CashRunwayUITestCase.swift`.

### 4. Create `SettingsNavigationUITests.swift`
New test class, per-test launch (not class-shared), `transaction_core` scenario:
- `testOpenSettingsFromMoreTab()` — tap More, assert Settings visible
- `testSettingsToWalletsAndBack()` — tap Wallets row, assert destination, dismiss, assert back on Settings
- `testSettingsToLabelsAndBack()` — same pattern
- `testSettingsToCategoriesAndBack()` — same pattern
- `testSettingsToBackupAndBack()` — same pattern
- `testSettingsToCSVImportAndBack()` — same pattern
- `testSettingsToMonobankAndBack()` — same pattern (reuses existing wizard identifiers)

Use `returnToRoot()` between tests. Keep each test under 10 seconds.

### 5. Add file to Xcode target
Register `SettingsNavigationUITests.swift` in `CashRunwayUITests` target via `project.pbxproj`.

### 6. Validate
Run only the new class: `xcodebuild test -scheme CashRunwayUITests -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:CashRunwayUITests/SettingsNavigationUITests`

## Files touched
| File | Change |
|------|--------|
| `Sources/CashRunwayUI/SettingsView.swift` | +8 accessibility identifiers on rows |
| `Sources/CashRunwayUI/WalletManagementView.swift` | +1 identifier |
| `Sources/CashRunwayUI/LabelManagementView.swift` | +1 identifier |
| `Sources/CashRunwayUI/BackupView.swift` | +1 identifier |
| `Sources/CashRunwayUI/CSVImportView.swift` | +1 identifier |
| `Tests/CashRunwayUITests/CashRunwayUITestCase.swift` | +8 enum cases |
| `Tests/CashRunwayUITests/SettingsNavigationUITests.swift` | New (~80 lines) |
| `CashRunway.xcodeproj/project.pbxproj` | +1 source file reference |

## Effort & risk
- **Effort:** Small. ~1 hour. No logic changes; only additive identifiers and a focused test class.
- **Risk:** Near-zero. Worst case: identifier collisions with existing strings (avoided by namespacing prefix).
- **CI policy:** Per AGENTS.md, UI tests are run in CI/CD only; local validation is class-targeted only.
