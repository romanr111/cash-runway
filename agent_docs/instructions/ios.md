# iOS and Swift Instructions

## Architecture

- Match existing architecture, naming, formatting, and test conventions.
- Prefer the smallest complete implementation.
- Use the UI framework already used by the feature.
- Use SwiftUI for standalone new UI only when that fits the surrounding code.
- Do not rewrite UIKit to SwiftUI unless explicitly requested.
- Use native Swift, Xcode, and iOS Simulator workflows.
- Do not introduce Docker or container workflows for normal iOS development
  unless requested.

## Builds

This repo contains both `Package.swift` and `CashRunway.xcodeproj`.

- Use focused Swift package tests during implementation.
- Use repository validation scripts for completion gates.
- For build failures, summarize warnings, errors, and the retained log path
  instead of pasting full xcodebuild output.

## Concurrency

- Prefer `async/await` for new asynchronous Swift code.
- Preserve callbacks, delegates, closures, or Combine APIs when changing them is
  unnecessary.

## Dependencies

- Do not add dependencies unless required.
- Prefer Swift Package Manager when a dependency is necessary.
- Commit `Package.resolved` when package dependencies change.
- Do not vendor dependency source unless explicitly requested.

## Mirrored Core Sources

Core source files exist in both:

- `Sources/CashRunwayCore/`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/`

Any edit to one mirrored core file must be applied to the corresponding file in
the same change batch. `Scripts/agent-validate.sh` checks for drift.

## Swift Testing

- Use Swift Testing conventions already present in the repo.
- Use `@Suite(.serialized)` for tests that use the filesystem or Keychain.
- Disable tests with `@Test(.disabled("reason"))`; do not comment them out.
- Prefer existing `TestSupport.makeRepository()` and
  `TestSupport.makeLocation()` helpers.
- Use `TestKeychainStore` instead of the global Keychain implementation.
- Avoid broad UI coverage where package-level tests provide equivalent
  confidence.

## Persistence and Keychain

- Preserve migration compatibility.
- Do not delete persisted models, migrations, or repository methods merely
  because a UI feature is temporarily hidden.
- Use isolated temporary databases in tests.
- Do not allow tests to share global Keychain or filesystem state.

## Feature Deprecation

When temporarily removing or hiding a feature:

1. Hide UI entry points.
2. Preserve implementation, models, repository methods, and migrations.
3. Add a clear `DEPRECATED` comment describing status and reactivation intent.
4. Disable affected tests with an explicit reason.
5. Do not delete stored-data support.

## Localization Catalog

When changing `AppHost/Localizable.xcstrings`:

1. Prepare a small JSON update file.
2. Run `Scripts/localize-xcstrings.py`.
3. Review only the changed strings.

Do not rewrite or regenerate the complete catalog manually.

## Large-File Exploration

- Use CodeGraph before broad repository searches.
- Use `rg -n` to locate exact symbols or text when CodeGraph is insufficient.
- Read narrow line ranges for large files.
- Do not read entire multi-thousand-line files unless explicitly justified.
- Use `agent_docs/reference/code-location-guide.md` only when location guidance
  is needed.

## Real-Device Work

Do not initiate real-device debugging, data recovery, `devicectl` forensics, or
device builds unless the issue is confirmed to be device-specific or the user
explicitly requests it. Simulator verification is the default.

When data may be at risk, preserve evidence before changing or deleting device
data.

## Shell Scripts

Validate materially changed shell scripts with:

```bash
bash -n <script>
```

Avoid `status` as a shell variable name; it conflicts with the zsh `status`
special parameter.
