:

Use this reference when reviewing changes in this project. It complements the
general code-review skill with Cash-Runway-specific checks.

## Review checklist

| Check | Why it matters |
|-------|----------------|
| Does the change solve the stated task? | Avoid solving an adjacent, easier problem. |
| Are there TODOs, stubs, mocks, or hard-coded values where production behavior was required? | Stubs should be intentional and temporary. |
| Are realistic failure paths handled? | Network errors, invalid state, empty data, lifecycle changes. |
| Are secrets, tokens, or PII logged or exposed? | Follow `security-privacy.md`. |
| Do tests cover behavior, not implementation details? | Tests should survive refactoring. |
| Does the diff stay within scope? | Avoid unrelated changes in the same PR. |

---

## Signature-change checklist

Before changing the signature of a helper, shared component, or public method,
verify the impact:

1. **Find all call sites.** Use CodeGraph or grep:
   ```bash
   mcp__codegraph__codegraph_callers symbol:moreRow
   rg "moreRow\\(" Sources/
   ```
2. **Check at least one caller** to confirm the parameter type is compatible.
   Example: changing `LocalizedStringKey` to `String` breaks SwiftUI
   localization for string literals passed to `Text(...)`.
3. **Run the narrowest gate** that exercises the changed code, e.g.:
   ```bash
   just build
   just test-filter SettingsViewTests
   ```
4. **Update callers if needed**, or choose a different change that doesn't
   require broad updates.

---

## SwiftUI-specific checks

- Avoid mutating `RootView` or app routing for screenshots. Use
  `CASHRUNWAY_DEBUG_ROOT_SCREEN` instead.
- Prefer `just build` over raw `xcodebuild`.
- Preserve `Localizable.xcstrings` formatting by using
  `Scripts/localize-xcstrings.py`.
- Verify localization strings with `plutil -p` before relying on screenshots.

---

## Severity calibration

Use these labels in review comments:

- **BLOCKING**: task requirement not met, realistic runtime failure, security or
  data-loss issue, broken declared gate.
- **IMPORTANT**: clear correctness/maintainability/test issue with concrete cost.
- **SUGGESTION**: useful improvement, safe to defer.

Drop comments based only on taste, naming preference, or line layout unless a
project rule explicitly requires them.
