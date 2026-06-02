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
- Run `swiftlint lint` locally when available; otherwise use CI static analysis as the fallback source of truth.
- Run the strongest available validation before completion:
  - package tests if available
  - app/unit test scheme if available
  - iOS simulator build if an app scheme exists
- If validation cannot be run, report what was skipped and why.

### Build and launch verification gates
Every iOS task must pass ALL gates before being marked done, in this order:

1. `swift test` (unit + integration tests only, exclude E2E/UI tests) → all targeted tests pass.
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
| Root view / TabView / onboarding / lock screen | `Sources/CashRunwayUI/RootView.swift` | ~272 |
| Timeline (Dashboard) chart + feed + overview | `Sources/CashRunwayUI/DashboardView.swift` | ~1335 |
| All editors (transaction, wallet, category, recurring, **budget**) | `Sources/CashRunwayUI/Editors.swift` | ~1331 |
| Settings / More screen | `Sources/CashRunwayUI/SettingsView.swift` | ~1832 |
| App state / repository wrapper | `Sources/CashRunwayUI/AppModel.swift` | ~855 |
| DB + Keychain + **AppLockStore** | `Sources/CashRunwayCore/DatabaseManager.swift` | ~724 |
| Repository queries + **budgets/saveBudget** | `Sources/CashRunwayCore/CashRunwayRepository.swift` | ~3490 |
| Models: **Budget**, **BudgetProgress**, transactions, wallets | `Sources/CashRunwayCore/Models.swift` | ~1595 |
| Main app entry + BG tasks | `AppHost/CashRunwayApp.swift` | ~341 |
| UI-test runtime + fixture seeding | `AppHost/UITestRuntime.swift` | ~471 |

Prefer `ReadFile` with `line_offset` over full-file reads for files > 500 lines.

### UI tests — high-cost, low-return
**Do not add, modify, or stabilize UI tests unless the user explicitly asks.**
Historical evidence: XCUITest stabilization consumed multiple sessions with fragile accessibility-tree workarounds (non-hittable labels, toolbar button disambiguation, sheet identifier issues) for marginal coverage gains. Fast unit tests in `CashRunwayCoreTests` provide better ROI.

**E2E/UI tests are exclusively a CI/CD pipeline responsibility; agents must never run them locally.**

If UI tests are explicitly requested:
- Use the existing `UITestLaunchConfiguration` harness in `AppHost/UITestRuntime.swift`.
- Prefer accessibility identifiers on stable SwiftUI views (buttons, list rows) over toolbar/sheet identifiers, which have proven unstable.
- Run only the targeted UI test class; do not run the full UI test suite repeatedly.

### Real-device debugging — approval gate
Real-device builds, forensics, and `devicectl` launches are **slow and token-expensive** (full Xcode builds, symbol downloads, manual trust steps).

**Rule:** Do not initiate real-device debugging, data recovery, or on-device forensics unless the user explicitly requests it or the issue is confirmed device-specific. Simulator verification is the default.

### Development speed rules
- Native iOS tooling is the default for this repo. Use host Swift/Xcode/iOS Simulator workflows; do not create Docker/container workflows for normal Cash Runway work unless explicitly asked.
- Use targeted checks during implementation, then run the full required gates before merge/publish. Core-only changes start with focused `swift test --filter ...`; UI-only changes start with filtered simulator `xcodebuild`; DB/keychain/persistence/security changes require focused unit/integration tests, full unit/integration `swift test`, simulator build, and boot/log check.
- Before broad exploration, use the Code location quick reference above. For large files, use `rg -n` plus line-window reads instead of reading whole files.
- UI tests are opt-in and targeted. When explicitly working on them, use deterministic `CASH_RUNWAY_UI_TEST_MODE` / `UITEST-*` data and inspect the live accessibility tree or logs before changing UI code for a failing selector.
- For confirmed real-device issues, preserve evidence first when data may be at risk, verify device unlock/trust, and prefer plain `devicectl` launch/timing before Xcode/LLDB-heavy debugging.
- Validate new shell scripts with `bash -n` before first execution.

### Worktree hygiene — mandatory cleanup
Historical pattern: worktrees and branches accumulated (`codex/xcuitest-transaction-suite`, `codex/data-loss-investigation`, `codex/keychain-startup-hardening`) and were not always pruned, leaving stale entries.

**Rule:** Immediately after a feature branch is merged and pushed with user approval:
1. `git worktree remove <path>` (or `git worktree prune` if the directory is already gone).
2. `git branch -d <branch>` (local).
3. `git push origin --delete <branch>` (remote) if the branch was pushed.
4. Update `CONTINUITY.md` to reflect the cleaned state.

A clean workspace has **one** worktree (the primary checkout) and **one** local branch (`main`), except intentionally retained legacy branches.

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

### Test execution policy
- **Never run full regression** (unfiltered `swift test`, full UI/E2E suite) locally.
- **Allowed locally**: Full unit tests, full integration tests, individual failed tests, or `--filter` targeted runs.
- **E2E/UI tests**: Only run in CI/CD nightly pipelines; agents must never run them locally.
- Re-run only failing targeted tests locally to verify fixes — not full suites.

### Self-review proportionality
Full self-code-review (re-read every changed file, grep for orphans, verify logic) is required for:
- Multi-file changes (> 3 files)
- Architectural or API changes
- Security-sensitive changes (Keychain, DB encryption, auth)

**Skip the full second pass for:**
- Single-file comment-only changes
- Simple test disables (`@Test(.disabled(...))`)
- Adding deprecation comments with no logic changes

For these, a quick `git diff --stat` + `grep` for typos is sufficient.

### Validation Matrix

Choose validation by change type.

- UI-only SwiftUI presentation/catalog changes:
  Run `Scripts/validate-ui-only.sh`.
  Do not run unfiltered `swift test` unless the user explicitly asks or the change touches business logic, persistence, parsing, imports, security, mirrored core sources, merge/conflict resolution, or publish-readiness validation.

- Core/business/persistence/import/export/security changes:
  Run targeted `swift test --filter ...` during implementation, then run full allowed unit/integration validation before completion.

- PR publish/readiness, merge conflict resolution, or main-merge updates:
  Run the full required gates: core mirror diff, `git diff --check`, unit/integration tests, clean simulator build, simulator launch/log smoke, and PR checks after push.

- E2E/UI tests:
  Never run locally unless explicitly requested. CI owns UI/E2E execution.

### Simulator Smoke Limitation

XcodeBuildMCP runtime snapshots may return no element refs for this app. If a settled seeded launch still returns an empty runtime snapshot once, do not keep retrying tap/type navigation.

Use screenshot evidence plus runtime/os log scan, report that interactive smoke was blocked by empty runtime snapshots, and do not run local UI/E2E tests.

### Xcode / Package-Root Build Guidance

This repo contains both a `Package.swift` and a `.xcodeproj`; `xcodebuild` from the repo root resolves the project automatically. If XcodeBuildMCP build/scheme tools require an explicit project/workspace path, use shell `xcodebuild` from the repo root instead.

Prefer repo scripts for validation instead of rediscovering commands:
- `Scripts/validate-ui-only.sh` for UI-only changes.
- `Scripts/agent-validate.sh` for focused/full validation.
- `Scripts/smoke-seeded-simulator.sh` for deterministic launch/log smoke.

For long full package test runs, capture the summary in a log:

```bash
swift test > /tmp/cash-runway-swift-test.log 2>&1; rc=$?; tail -60 /tmp/cash-runway-swift-test.log; exit $rc
```

Do not use `status` as a zsh variable name.

- **Stale build artifact warning:**
  A legacy `$PROJECT_DIR/DerivedData/` directory may contain old simulator builds. If simulator smoke tests behave unexpectedly (missing new UI, empty seeded data, or sheets not presenting), verify the installed `.app` is fresh. The smoke script resolves the true build path via `xcodebuild -showBuildSettings`.

### UITest Environment Variables (DEBUG only)

| Variable | Valid values | Consumer |
|----------|--------------|----------|
| `CASH_RUNWAY_UI_TEST_MODE` | `1` | Enables UITest runtime |
| `CASH_RUNWAY_UI_TEST_SCENARIO` | `transaction_core`, `category_merge`, `category_editor`, `monobank_first_start` | `UITestRuntime.swift` |
| `CASH_RUNWAY_UI_TEST_START_SCREEN` | `category_management`, `category_editor` | `RootView.swift` |
| `CASH_RUNWAY_UI_TEST_DB_PATH` | Absolute path to temp `.sqlite` | `UITestRuntime.swift` |
| `CASH_RUNWAY_UI_TEST_RESET` | `1` | Wipes DB + keychain on launch |
| `CASH_RUNWAY_UI_TEST_MONOBANK_MODE` | `happy_path`, `invalid_token`, `first_sync_fails_then_recovers`, `foreground_new_expense` | `UITestRuntime.swift` |

All variables are passed to the simulator via `SIMCTL_CHILD_*` prefix (e.g. `SIMCTL_CHILD_CASH_RUNWAY_UI_TEST_MODE=1`).
