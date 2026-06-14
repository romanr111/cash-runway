# iOS and Swift Instructions

## Architecture and scope

- Preserve surrounding architecture, naming, formatting, and test conventions.
- Prefer the smallest complete implementation.
- Use the UI framework already used by the surrounding feature.
- Use SwiftUI for standalone new UI only when no contrary project precedent exists.
- Do not rewrite UIKit to SwiftUI unless explicitly requested.
- Use native Swift/Xcode/iOS Simulator workflows.
- Do not introduce Docker or container workflows for normal iOS development
  unless explicitly requested.

## Concurrency

- Prefer `async/await` for new asynchronous Swift code.
- Preserve callbacks, delegates, closures, or Combine APIs when changing them is
  unnecessary for the requested work.

## Dependencies

- Do not add dependencies unless required.
- Prefer Swift Package Manager when a dependency is necessary.
- Commit `Package.resolved` when package dependencies change.
- Do not vendor dependency source unless explicitly requested.

## Mirrored core sources

Core source files exist in both:

- `Sources/CashRunwayCore/`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/`

Any edit to one mirrored core file must be applied to the corresponding file in
the same change batch.

Do not finish with mirror drift.

Use the existing validation implementation in:

- `Scripts/agent-validate.sh`

## Swift Testing conventions

- Add or update tests for changed business logic, parsing, persistence,
  networking, imports, exports, and security-sensitive behavior.
- Prefer focused package tests during implementation.
- Use `@Suite(.serialized)` for tests that use the filesystem or Keychain.
- Disable tests with `@Test(.disabled("reason"))`; do not comment them out.
- Prefer existing `TestSupport.makeRepository()` and
  `TestSupport.makeLocation()` helpers.
- Use `TestKeychainStore` instead of the global Keychain implementation.
- Avoid broad UI coverage where package-level tests provide equivalent confidence.

## Persistence and Keychain

- Preserve migration compatibility.
- Do not delete persisted models, migrations, or repository methods merely
  because a UI feature is temporarily hidden.
- Use isolated temporary databases in tests.
- Do not allow tests to share global Keychain or filesystem state.

## Feature deprecation

When temporarily hiding a feature:

1. hide UI entry points;
2. preserve implementation, models, repository methods, and migrations;
3. add a clear `DEPRECATED` comment describing status and reactivation intent;
4. disable affected tests with an explicit reason;
5. do not delete stored-data support.

## Localization catalog

When changing `AppHost/Localizable.xcstrings`:

- use `Scripts/localize-xcstrings.py`;
- provide a small JSON update file;
- do not rewrite or regenerate the complete catalog manually;
- review only the affected catalog entries where practical.

## Large-file exploration

- Use CodeGraph before broad repository searches.
- Use `rg -n` to locate exact symbols or text when CodeGraph is insufficient.
- Read narrow line ranges for large files.
- Do not read entire multi-thousand-line files unless the task genuinely requires
  complete-file context.
- Use `agent_docs/reference/code-location-guide.md` only when location guidance is
  needed.

## Real-device work

Do not initiate real-device debugging, data recovery, `devicectl` forensics, or
device builds unless:

- the user explicitly requests it; or
- the issue is confirmed to be device-specific.

Simulator verification is the default.

When data may be at risk, preserve evidence before changing or deleting device data.

## Shell scripts

Validate every new or materially changed shell script with:

```bash
bash -n <script>
```
