# Cash Runway - Agent Instructions

Swift/SwiftUI/GRDB iOS app with a Node/TypeScript reporting API.

## Always Apply
- Keep `Sources/CashRunwayCore/` and
  `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/` identical.
  After modifying either tree, update the mirror and verify the two trees are
  identical before finishing.
- Store credentials and sensitive values only in Keychain or server-side
  environment variables. Never commit or log secrets or sensitive user data.
- Do not use `print()` for production diagnostics.
- Use existing `just` recipes and repository scripts instead of recreating
  commands.
- Do not add, modify, or run XCUITest/E2E tests locally unless explicitly
  requested.
- Treat every git worktree as a separate CodeGraph project.
- Report every skipped validation gate and the reason it was skipped.
- Keep repo validation, runtime smoke tests, backend/API reachability, and
  release readiness as separate status buckets. Green checks do not imply the
  app launched, integrations worked, or release gates are complete.
- For SideStore or release work, keep the physical-device rehearsal as an
  explicit manual gate. Do not describe release readiness as complete until that
  rehearsal has actually passed.

## Token Efficiency
- Use Headroom by default for bulky command output, logs, code search, and
  cross-agent handoff memory.
- Keep routine progress updates to at most two sentences unless more detail is
  requested.
- Do not emit recurring environment, completed-task, or current-focus recaps.
- Run `Scripts/pre-flight.sh` before meaningful feature or bug-fix work.
- Use CodeGraph before broad code searches or repeated raw file reads. Run
  `just graph-bootstrap` before CodeGraph operations in each worktree.
- Detailed command references:
  `agent_docs/reference/headroom-commands.md`,
  `agent_docs/reference/codegraph-commands.md`,
  `agent_docs/reference/token-efficiency.md`, and
  `agent_docs/reference/verification-strategies.md`.
- For files over 500 lines, locate the relevant symbol first and read a narrow
  line range. Do not read the complete file unless necessary.
- Batch related reads in one response; emit multiple `Read` calls in parallel
  instead of reading one file per turn.
- Always use existing `just` recipes for repository tasks. Do not run raw
  `xcodebuild`, `swift test`, `swiftlint`, or validation scripts directly unless
  the justfile recipe is clearly insufficient for the specific case.
- For iOS builds use `just build`. For Swift tests use `just test` or
  `just test-filter <pattern>`. For full validation use `just check`.
- For long-running builds, prefer `Bash` with `run_in_background=true` and
  inspect the result when notified.
- Use `Scripts/localize-xcstrings.py` to modify
  `AppHost/Localizable.xcstrings`; do not rewrite the complete catalog manually.
- Batch related edits to the same file. Re-read only when the target or
  resulting state is uncertain.
- Prefer targeted tests during implementation and repository validation scripts
  for completion. Preserve complete raw logs outside model context.
- Do not paste complete build logs, test logs, JSON catalogs, or large diffs
  into the conversation. Report the outcome, the first relevant failure, and the
  retained log location.
- For visual verification, prefer MCP Xcode screenshots. If using raw simulator
  screenshots, downsample before reading them back. Take screenshots only at
  milestones, not after every build.
- Before changing a helper or shared component signature, check at least one
  caller/site to confirm the change is safe and to avoid silent regressions
  (e.g., `LocalizedStringKey` vs. `String`).
- Do not mutate `RootView` or other core app routing just to take screenshots.
  Use the `CASHRUNWAY_DEBUG_ROOT_SCREEN` environment variable (DEBUG builds)
  documented in `agent_docs/reference/verification-strategies.md`.
- Before context compaction, a major task switch, or transfer to a fresh
  session, update the `CONTINUITY.md` Snapshot. Keep it fresh.
- Use subagents only for parallel evidence gathering or isolated review tasks
  with clear inputs and expected outputs.
- Escalate reasoning effort after one concrete failed attempt, an ambiguous
  requirement, a security/privacy decision, or an architectural tradeoff.

## Generated and Heavy Files
- Do not hand-edit generated files, lock files, coverage output, `.build`,
  `DerivedData`, `.codegraph`, or Xcode project files unless the task explicitly
  requires it. Use the approved generator or project tool instead.
- Do not read generated, vendored, artifact, snapshot, coverage, `.build`,
  `DerivedData`, or `.codegraph` files unless the task requires them.

## Load Only When Relevant
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

Historical and troubleshooting material is under `agent_docs/reference/`.
