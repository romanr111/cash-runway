# Cash Runway - Agent Instructions

Swift/SwiftUI/GRDB iOS app with a Node/TypeScript reporting API.

**Precedence:** This repo `AGENTS.md` overrides `~/.config/opencode/AGENTS.md` for
Cash Runway-specific rules. Where this file is silent, follow global `AGENTS.md`.

## Session start checklist

Run `just session-start` at the beginning of every working session. It prints the
worktree, branch, bootstraps CodeGraph, and runs the pre-flight inventory.

Manual fallback if `just` is unavailable:
1. `git worktree list`
2. `git -C <worktree> rev-parse --abbrev-ref HEAD`
3. `git status --short`
4. `Scripts/pre-flight.sh`
5. `Scripts/codegraph-bootstrap.sh`

## Always Apply

- CashRunwayCore has one canonical source tree at `Sources/CashRunwayCore/`.
  Both Xcode and SwiftPM must compile this tree. Do not create mirrored copies.
- Store credentials and sensitive values only in Keychain or server-side
  environment variables. Never commit or log secrets or sensitive user data.
- Do not use `print()` for production diagnostics.
- Use existing `just` recipes and repository scripts instead of recreating commands.
- Do not add, modify, or run XCUITest/E2E tests locally unless explicitly requested.
- Treat every git worktree as a separate CodeGraph project.
- Report every skipped validation gate and the reason it was skipped. If a command
  times out or fails, report the gate name, command, timeout/limit, failure reason,
  fallback used, and whether the fallback is equivalent or a partial substitute.
- Keep repo validation, runtime smoke tests, backend/API reachability, and
  release readiness as separate status buckets. Green checks do not imply the app
  launched, integrations worked, or release gates are complete.
- Tests that reference `ReportingSecrets`, `ProcessInfo.processInfo.environment`,
  `#if DEBUG`, or any generated/compiled-time state must inject those dependencies
  explicitly. Tests must not silently depend on environment state that differs
  between dev and CI.
- For SideStore or release work, keep the physical-device rehearsal as an
  explicit manual gate. Do not describe release readiness as complete until that
  rehearsal has actually passed.

## CodeGraph

- Run `just graph-bootstrap` once per worktree. It is idempotent and repairs a
  stale or missing worktree marker automatically.
- Run `just graph-sync` after meaningful edits (new files, renamed symbols, moved
  functions) so callers and impact analysis stay accurate.
- Before broad searches for symbols, functions, types, callers, or impact, prefer
  CodeGraph commands:
  - `codegraph query "<name>"`
  - `codegraph callers "<symbol>"`
  - `codegraph callees "<symbol>"`
  - `codegraph impact "<symbol>"`
  - `codegraph affected <files...>`
- Fall back to `grep`/`glob` only when:
  - CodeGraph returns zero results,
  - you need a regex/text pattern that is not a symbol,
  - or CodeGraph is unavailable. Report the fallback explicitly.
- If `just graph-status` still fails after bootstrap, run `just graph-repair`.

## SwiftPM validation

| Goal | First try | If parallel runs hang or stale state is suspected |
|---|---|---|
| AgentAccess changes | `just check-agent` | `just test-isolated --filter Agent` |
| Fast unit feedback (selected suites) | `just check-unit-parallel` | `just test-isolated --filter ...` |
| Broader integration coverage | `just check-integration` | `just check-isolated` |
| Full gate (excludes performance timing) | `just check-isolated` | `just check-isolated-with-perf` |
| Full gate with performance timing | `just check-isolated-with-perf` | — |

- When multiple Cash Runway worktrees are active on the machine, start the full
  gate with `just check-isolated` instead of `just check-integration`. Parallel
  SwiftPM helper processes from other worktrees can cause lock contention.
- If SwiftPM appears blocked by stale build state or lock contention, retry once
  with `just test-isolated` or `just check-isolated`.
- `CashRunwayPerformanceTests` is intentionally excluded from `check-isolated`.
  Run `just check-isolated-with-perf` or `just check-perf` when performance-sensitive
  code changed or before final release sign-off.


## Git Safety

- Before merging, pushing, force-pushing, rebasing, deleting a branch, or closing a PR,
  state the exact operation and branches involved and ask for explicit user confirmation.
- Do not use `--admin`, `--force`, or `--force-with-lease` without explicit user approval.
- When resolving merge/rebase conflicts in source files:
  - Do not use `git checkout --ours` or `git checkout --theirs` on shared `.swift` files.
  - Read both sides of the conflict markers and manually integrate.
  - Run targeted tests for the affected area before continuing.
  - If integration is unsafe, stop and ask.
- Never use `git add -A` unless the user explicitly asks for it and acknowledges
  the risk. Stage files individually or in explicitly named groups.
- Before every commit, run:
  1. `git status --short`
  2. `git diff --cached --stat`
- If any staged file is unexpected, generated, a backup (`.bak`, `.tmp`, `.orig`),
  a lock file, a secret/config file, or an Xcode project file, stop and ask.
- After a successful `project.pbxproj` edit, remove the `.bak` backup or keep it
  untracked; do not commit it.

## Merge Safety

- Before merging any branch (including `origin/dev`) into the active PR branch:
  1. Run `git merge --no-commit --no-ff <target-branch>`.
  2. Run `git status --short` and `git diff --cached --stat`.
  3. If any of these changed, inspect the diff explicitly before committing:
     - `*Secret*`, `*secret*`, `*Config*`, `*config*`, `*Token*`, `*Key*`,
       `*Credential*`, `*.p8`, `*.p12`, `*.mobileprovision`
     - `*.pbxproj`, `Info.plist`, `*.entitlements`, `Podfile.lock`,
       `Package.resolved`, `*.generated.swift`
     - `CONTINUITY.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`
  4. Never commit a file with `isPlaceholder: false` in any `*Secrets*.swift`.
     Revert it to `isPlaceholder: true` or ask the user.
- Only commit the merge after all high-risk items are resolved or explicitly accepted.

## Xcode Project Safety
- Do not hand-edit `CashRunway.xcodeproj/project.pbxproj` unless the task
  explicitly requires it. When editing is unavoidable:
  1. Always back up first: `cp CashRunway.xcodeproj/project.pbxproj{,.bak}`.
  2. Make the smallest possible change (remove or add a single block).
  3. Verify immediately: `Scripts/verify-pbxproj.sh` (or `xcodebuild -list -project CashRunway.xcodeproj`).
  4. If verification fails, restore from backup and retry.
- When CashRunwayCore is compiled as a SwiftPM package (Phase 2B+), the Xcode
  app target must NOT include `Sources/CashRunwayCore/*.swift` in its Sources
  build phase. `Scripts/pre-flight.sh` validates this invariant.
- Before debugging Xcode access-level errors (`internal` protection level),
  run `swift build --target CashRunwayCore` first. It surfaces module-boundary
  issues in seconds, avoids minutes-long Xcode rebuilds, and gives clearer
  diagnostics.
- After removing `#if canImport(CashRunwayCore)` guards from UI/AppHost
  files, do not assume only files that had the guard need the import. Use
  `grep` to find any remaining references to Core symbols in files that do not
  yet `import CashRunwayCore`, and add the import to all of them.

## Token Efficiency
- Use Headroom by default for bulky command output, logs, code search, and
  cross-agent handoff memory.
- Keep routine progress updates to at most two sentences unless more detail is
  requested.
- Do not emit recurring environment, completed-task, or current-focus recaps.
- For SwiftUI concurrency patterns (`.task(id:)`, `Task.detached`, async state
  driving irreversible actions), verify: cancellation handling, request-token
  guards against stale results, consumer re-validation of async state, and
  awaiting downstream refresh/mutation before reporting success.
- Detailed command references:
  `agent_docs/reference/headroom-commands.md`,
  `agent_docs/reference/codegraph-commands.md`,
  `agent_docs/reference/token-efficiency.md`,
  `agent_docs/reference/verification-strategies.md`, and
  `agent_docs/reference/code-review.md`.
- For files over 500 lines, locate the relevant symbol first and read a narrow
  line range. Do not read the complete file unless necessary.
- Batch related reads in one response; emit multiple `Read` calls in parallel
  instead of reading one file per turn.
- Always use existing `just` recipes for repository tasks. Do not run raw
  `xcodebuild`, `swift test`, `swiftlint`, or validation scripts directly unless
  the justfile recipe is clearly insufficient for the specific case.
- For iOS builds use `just build`. For Swift tests use `just test` or
  `just test-filter <pattern>`. For full validation use `just check`.
- MCP Xcode tools (`mcp__xcode__*`) are available for screenshots and quick
  Xcode operations. They require session defaults to be set
  (`session_set_defaults`) and may time out on the first call or on long
  operations. Pre-warm with `session_show_defaults` or `list_sims`, boot the
  simulator first, then retry. If an MCP tool times out, fall back to the
  equivalent `just` / Bash command rather than retrying repeatedly.
- For long-running builds, prefer `Bash` with `run_in_background=true` and
  inspect the result when notified.
- Use `Scripts/localize-xcstrings.py` to modify
  `AppHost/Localizable.xcstrings`; do not rewrite the complete catalog manually.
- Batch related edits to the same file. Re-read only when the target or
  resulting state is uncertain.
- Prefer targeted tests during implementation and repository validation scripts
  for completion. Preserve complete raw logs outside model context.
- Do not paste complete build logs, test logs, JSON catalogs, or large diffs
  into the conversation. Report the outcome, the first relevant failure, and
  the retained log location.
- For visual verification, prefer MCP Xcode screenshots. If using raw simulator
  screenshots, downsample before reading them back. Take screenshots only at
  milestones, not after every build.
- Before changing a helper or shared component signature, check at least one
  caller/site to confirm the change is safe and to avoid silent regressions
  (e.g., `LocalizedStringKey` vs. `String`).
- Do not mutate `RootView` or other core app routing just to take screenshots.
  For visual verification, build and install normally, then navigate to the
  screen or use SwiftUI previews.
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

### Pre-task diff inventory
Before editing files in a worktree:
1. Run `git status --short` and `git diff --stat`.
2. Flag generated, secret, or unrelated dirty files and ask the user before proceeding.
3. Never silently revert files you did not modify.

Cash Runway generated/secrets files to flag:
- `AppHost/AppReportingSecrets.generated.swift`
- `DerivedData/`, `.build/`, `.codegraph`, coverage output

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
- Session start, environment bootstrap, or worktree health:
  `agent_docs/reference/session-start.md`

Historical and troubleshooting material is under `agent_docs/reference/`.
