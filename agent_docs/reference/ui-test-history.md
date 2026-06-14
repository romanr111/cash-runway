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
