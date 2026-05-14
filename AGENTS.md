## Agent-specific behavioral guidelines
- **Kimi / Kimi-based LLMs only:** Also apply `.kimi/AGENTS.md` project-wide for behavioral, git safety, continuity ledger, and workflow rules.

## iOS agent rules

### Preserve existing structure
- Follow the existing project structure, architecture, naming, formatting, and test style.
- Do not introduce new modules, packages, dependencies, architectural patterns, formatters, or linters unless the task requires it.
- Prefer the smallest change that solves the task.

### UI
- For new UI, prefer the UI framework already used in the surrounding feature.
- Use SwiftUI for new standalone UI when there is no existing precedent.
- Use UIKit when integrating with existing UIKit code or when SwiftUI is insufficient.
- Do not rewrite UIKit to SwiftUI unless explicitly asked.

### Concurrency
- Prefer async/await for new asynchronous Swift code.
- Preserve existing callback, Combine, delegate, or closure-based APIs unless changing them is necessary.

### Security
- Store tokens, credentials, secrets, and sensitive user data in Keychain only.
- Never store sensitive values in UserDefaults, logs, source files, fixtures, or plain-text local files.

### Logging
- Do not use `print()` for production diagnostics.
- Use the project's existing logging mechanism.
- If none exists, use Apple unified logging.
- Never log secrets, tokens, credentials, or sensitive personal data.

### Dependencies
- Do not add dependencies unless necessary.
- Prefer Swift Package Manager when a dependency is required.
- Commit `Package.resolved` when package dependencies change.
- Do not vendor source unless explicitly required.

### Tests and validation
- Add or update tests for changed business logic, parsing, persistence, networking, or security-sensitive behavior.
- Prefer fast unit tests over broad UI tests.
- Do not add UI tests unless the project already has them or the task asks for them.
- Run the strongest available validation before completion:
  - package tests if available
  - app/unit test scheme if available
  - iOS simulator build if an app scheme exists
- If validation cannot be run, report what was skipped and why.

### Build and launch verification gates
Every iOS task must pass ALL gates before being marked done, in this order:

1. `swift test` → all tests pass.
2. `xcodebuild -scheme <scheme> -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     clean build 2>&1 | tail -5`
   → last line must be `** BUILD SUCCEEDED **`.
   If `iPhone 17` is unavailable on the local machine, use the newest available
   iPhone simulator as the primary destination and record the exact name.
3. Boot check (must be last):
   - App launches successfully on simulator
   - No runtime crashes or warnings in Xcode console
   - Core features accessible within 3 seconds of launch

---

## Project-specific rules (Cash Runway)

### Mirrored core sources (D004)
Core sources live in **two places** and must stay identical:
- `Sources/CashRunwayCore/` — compiled by the app target
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/` — compiled by `swift test`

**Rule:** Any edit to a file in `Sources/CashRunwayCore/` must be mirrored to the same relative path under `Modules/CashRunwayCorePackage/` **in the same commit/change batch**. Do not leave them out of sync.

**Quick sync check:**
```bash
diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore
```
If the diff reports any differences, mirror the missing changes before finishing.

### Code location quick reference
To avoid expensive exploration of large files, use this reference before grepping:

| Concern | Primary file | Approx. lines |
|---------|-------------|---------------|
| Root view / TabView / onboarding / lock screen | `Sources/CashRunwayUI/RootView.swift` | ~260 |
| Timeline (Dashboard) chart + feed + overview | `Sources/CashRunwayUI/DashboardView.swift` | ~1270 |
| All editors (transaction, wallet, category, recurring, **budget**) | `Sources/CashRunwayUI/Editors.swift` | ~1280 |
| Settings / More screen | `Sources/CashRunwayUI/SettingsView.swift` | ~990 |
| App state / repository wrapper | `Sources/CashRunwayUI/AppModel.swift` | ~620 |
| DB + Keychain + **AppLockStore** | `Sources/CashRunwayCore/DatabaseManager.swift` | ~550 |
| Repository queries + **budgets/saveBudget** | `Sources/CashRunwayCore/CashRunwayRepository.swift` | ~1940 |
| Models: **Budget**, **BudgetProgress**, transactions, wallets | `Sources/CashRunwayCore/Models.swift` | ~650 |
| Main app entry + BG tasks | `AppHost/CashRunwayApp.swift` | ~295 |
| UI-test runtime + fixture seeding | `AppHost/UITestRuntime.swift` | ~245 |

Prefer `ReadFile` with `line_offset` over full-file reads for files > 500 lines.

### UI tests — high-cost, low-return
**Do not add, modify, or stabilize UI tests unless the user explicitly asks.**
Historical evidence: XCUITest stabilization consumed multiple sessions with fragile accessibility-tree workarounds (non-hittable labels, toolbar button disambiguation, sheet identifier issues) for marginal coverage gains. Fast unit tests in `CashRunwayCoreTests` provide better ROI.

If UI tests are explicitly requested:
- Use the existing `UITestLaunchConfiguration` harness in `AppHost/UITestRuntime.swift`.
- Prefer accessibility identifiers on stable SwiftUI views (buttons, list rows) over toolbar/sheet identifiers, which have proven unstable.
- Run only the targeted UI test class; do not run the full UI test suite repeatedly.

### Real-device debugging — approval gate
Real-device builds, forensics, and `devicectl` launches are **slow and token-expensive** (full Xcode builds, symbol downloads, manual trust steps). 

**Rule:** Do not initiate real-device debugging, data recovery, or on-device forensics unless the user explicitly requests it or the issue is confirmed device-specific. Simulator verification is the default.

### Feature deprecation / temporary disable pattern
When hiding a feature temporarily (as done for Budgets and App Lock):
1. **Hide UI entry points** only (remove from `TabView`, remove settings row, skip onboarding).
2. **Preserve all code** — add `// DEPRECATED — <feature> is <status>. <action>.` comments on affected types/methods.
3. **Disable related tests** with Swift Testing: `@Test(.disabled("<reason>. Re-enable when work resumes."))`.
4. **Do not** delete data models, repository methods, or migration code.

This pattern avoids re-implementing the feature later and keeps the app buildable.

### Build output filtering
`xcodebuild` emits thousands of lines. Always filter output to essentials:
```bash
xcodebuild -scheme CashRunway -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  clean build 2>&1 | grep -E "(warning:|error:|BUILD SUCCEEDED|BUILD FAILED)"
```
For a final success confirmation, `tail -5` is sufficient.

### Swift Testing conventions
- Use `@Suite(.serialized)` for tests that touch the filesystem or keychain.
- Disable tests with `@Test(.disabled("reason"))`, not by commenting out.
- Prefer `TestSupport.makeRepository()` and `TestSupport.makeLocation()` for isolated DBs.
- Use `TestKeychainStore` instead of the global keychain to avoid cross-test collisions.
