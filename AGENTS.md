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
- Use the project’s existing logging mechanism.
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
