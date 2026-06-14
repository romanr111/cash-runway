# UI Test History

This file preserves historical XCUITest context. Do not use it as a reason to run
full UI tests locally by default.

## Historical stabilization problems

XCUITest stabilization consumed multiple sessions with fragile accessibility-tree
workarounds for marginal coverage gains. Specific problems included:

- non-hittable labels that passed existence checks but failed tap/scroll actions;
- toolbar buttons requiring disambiguation by position or identifier;
- sheet identifiers that did not resolve reliably across iOS versions;
- general accessibility-tree instability in SwiftUI sheets and toolbars.

Fast unit and integration tests in `CashRunwayCoreTests` provide better return
on investment for most changes.

## Local UI test policy

Only run local XCUITest when explicitly requested. Even then:

- use the existing `UITestLaunchConfiguration` harness in
  `AppHost/UITestRuntime.swift`;
- prefer accessibility identifiers on stable SwiftUI views such as buttons and
  list rows;
- avoid toolbar and sheet identifiers, which have proven unstable;
- run only the targeted UI test class, never the full suite repeatedly.

## CI ownership

Full XCUITest/E2E suites are a CI/CD pipeline responsibility. Agents must not run
them locally unless explicitly asked.

## Deterministic harness data

When local UI tests are explicitly requested, use deterministic data through the
`CASH_RUNWAY_UI_TEST_MODE` / `UITEST-*` environment variables and inspect the live
accessibility tree or logs before changing UI code for a failing selector.

| Variable | Valid values | Consumer |
|----------|--------------|----------|
| `CASH_RUNWAY_UI_TEST_MODE` | `1` | Enables UITest runtime |
| `CASH_RUNWAY_UI_TEST_SCENARIO` | `transaction_core`, `category_merge`, `category_editor`, `monobank_first_start` | `UITestRuntime.swift` |
| `CASH_RUNWAY_UI_TEST_START_SCREEN` | `category_management`, `category_editor` | `RootView.swift` |
| `CASH_RUNWAY_UI_TEST_DB_PATH` | Absolute path to temp `.sqlite` | `UITestRuntime.swift` |
| `CASH_RUNWAY_UI_TEST_RESET` | `1` | Wipes DB + keychain on launch |
| `CASH_RUNWAY_UI_TEST_MONOBANK_MODE` | `happy_path`, `invalid_token`, `first_sync_fails_then_recovers`, `foreground_new_expense` | `UITestRuntime.swift` |

Pass variables to the simulator with the `SIMCTL_CHILD_*` prefix, for example
`SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_MODE=1`.
