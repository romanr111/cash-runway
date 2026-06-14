# Cash Runway — Agent Instructions

Swift/SwiftUI/GRDB iOS app with a Node/TypeScript reporting API.

## Always apply

- Follow existing architecture, naming, formatting, and test style.
- Prefer the smallest complete change. Do not add dependencies, modules,
  architectural patterns, formatters, or linters unless required.
- Keep `Sources/CashRunwayCore/` and
  `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/` identical.
- Store credentials and sensitive values only in Keychain or server-side
  environment variables. Never commit or log secrets or sensitive user data.
- Do not use `print()` for production diagnostics.
- Use existing `just` recipes and repository scripts instead of recreating commands.
- Do not add, modify, or run XCUITest/E2E tests locally unless explicitly requested.
- Treat every git worktree as a separate CodeGraph project.
- Report skipped validation and its reason.

## Token efficiency

- Keep this file concise and do not repeat its rules in status messages.
- Keep routine progress updates to at most two sentences unless more detail is requested.
- Do not emit recurring environment, completed-task, or current-focus recaps.
  Track active work with the agent's task or todo mechanism.
- Run `Scripts/pre-flight.sh` before meaningful feature or bug-fix work.
- Use CodeGraph before broad text searches or repeated raw file reads. Run
  `just graph-bootstrap` before CodeGraph operations in each worktree.
- For files over 500 lines, locate the relevant symbol first and read a narrow
  line range. Do not read the complete file unless necessary.
- Use `Scripts/localize-xcstrings.py` to modify
  `AppHost/Localizable.xcstrings`; do not rewrite the complete catalog manually.
- Batch related edits to the same file. Re-read only when the target or resulting
  state is uncertain.
- Prefer targeted tests during implementation and repository validation scripts
  for completion. Preserve complete raw logs outside model context.
- Do not paste complete build logs, test logs, JSON catalogs, or large diffs into
  the conversation. Report the outcome, the first relevant failure, and the
  retained log location.
- Before context compaction, a major task switch, or transfer to a fresh session,
  update the `CONTINUITY.md` Snapshot.

## Load only when relevant

Before editing matching areas, read:

- Swift, SwiftUI, GRDB, app, or core code:
  `agent_docs/instructions/ios.md`
- `reporting-api/**`:
  `agent_docs/instructions/reporting-api.md`
- Keychain, secrets, authentication, diagnostics, or PII:
  `agent_docs/instructions/security-privacy.md`
- Validation or task completion:
  `agent_docs/instructions/validation.md`
- Branches, worktrees, CodeGraph, or cleanup:
  `agent_docs/instructions/worktrees.md`

Do not load unrelated instruction or reference files.

Historical and troubleshooting material is under `agent_docs/reference/`.
