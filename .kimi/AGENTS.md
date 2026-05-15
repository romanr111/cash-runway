## Git safety
- For major feature development - new branch.
- If local edits exist - separate git worktree.
- If an asset should not ship, move it to `Docs/`, `DesignReferences/`, or equivalent.

1. Behavioral guidelines, these guidelines bias toward caution over speed. For trivial tasks, use judgment.

   1.1 Think before coding
   Don't assume. Don't hide confusion. Surface tradeoffs.
   Before implementing:
   - State your assumptions explicitly. If uncertain, ask.
   - If multiple interpretations exist, present them - don't pick silently.
   - If a simpler approach exists, say so.
   - Push back when warranted.
   - If something is unclear, stop. Name what's confusing. Ask.

   1.2 Simplicity first
   Minimum code that solves the problem. Nothing speculative.
   - No features beyond what was asked.
   - No abstractions for single-use code.
   - No "flexibility" or "configurability" that wasn't requested.
   - No error handling for impossible scenarios.
   - If you write 200 lines and it could be 50, rewrite it.
   Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

   1.3 Surgical changes
   Touch only what you must. Clean up only your own mess.
   When editing existing code:
   - Don't "improve" adjacent code, comments, or formatting.
   - Don't refactor things that aren't broken.
   - Match existing style, even if you'd do it differently.
   - If you notice unrelated dead code, mention it - don't delete it.
   - After making changes, run the project’s standard checks when feasible (format/lint, unit tests, build/typecheck).
   When your changes create orphans:
   - Remove imports/variables/functions that YOUR changes made unused.
   - Don't remove pre-existing dead code unless asked.
   The test: Every changed line should trace directly to the user's request.

   1.4 Goal-driven execution
   Define success criteria. Loop until verified.
   Transform tasks into verifiable goals:
   - "Add validation" -> "Write tests for invalid inputs, then make them pass"
   - "Fix the bug" -> "Write a test that reproduces it, then make it pass"
   - "Refactor X" -> "Ensure tests pass before and after"
   For multi-step tasks, state a brief plan:
   1. [Step] -> verify: [check]
   2. [Step] -> verify: [check]
   3. [Step] -> verify: [check]

A task is done when:
- the requested change is implemented or the question is answered,
  - build attempted (when source code changed),
  - errors/warnings addressed (or explicitly listed and agreed as out-of-scope),
- documentation is updated only for impacted areas,
- impact is explained (shortly what changed, where, why),
- follow-ups are listed if anything was intentionally left out.
- Deliver a runnable app first, then deepen architecture.

For product/MVP/app/completion of PLAN.md tasks:
- Verify early and repeatedly.
  1. project builds
  2. app launches without crashes
  3. seed/demo data renders
  4. main navigation works
  5. one core create/edit/delete flow works
  6. persistence survives relaunch
  7. only then deepen secondary features




### Context7 MCP
- Use Context7 when you need library/API docs.
- Fetch minimal targeted docs; summarize (no large dumps).

### Container-first policy for .git projects
- Codex must **never** install system packages on the host unless explicitly instructed.
- Prefer container images to supply all tooling used by the project.
- For code projects and dependencies: **use containers by default**.
- If the repo has an existing container workflow (Dockerfile/compose/Makefile targets), follow it.
- If the repo has no container workflow, create a minimal one.
- Keep repo-specific container details in the repo’s `AGENTS.md`.
- Cash Runway exception: native iOS tooling is the default here. Use host Swift/Xcode/iOS Simulator workflows; do not create Docker/container workflows for normal Cash Runway work unless explicitly asked.

### Secrets and sensitive data
- Never print secrets (tokens, private keys, credentials) to terminal output.
- Do not request users paste secrets.
- Avoid commands that might expose secrets (e.g., dumping env vars broadly, `cat ~/.ssh/*`).
- Prefer existing authenticated CLIs; redact sensitive strings in any displayed output.

## Baseline workflow
- Start every task by determining:
  1. Goal + acceptance criteria.
  2. Constraints (time, safety, scope).
  3. If requirements are ambiguous, ask targeted clarifying questions before making irreversible changes.




## Continuity Ledger

- State lives in CONTINUITY.md. Read it before acting when present. Create it for long-running or multi-step work.
- Update CONTINUITY.md after every meaningful change: file modified, decision made, blocker hit/resolved, verification result changed.
- Snapshot must reflect current truth. Rewrite it, don't append stale state.

## Git Session Start

Before editing files, reporting repo status, removing worktrees, pulling, pushing, or committing in a git repo:
- Run `git worktree list`.
- Run `git -C <active-worktree> rev-parse --abbrev-ref HEAD`.
- Run `git -C <active-worktree> status --short`.
- If reality differs from CONTINUITY.md, update CONTINUITY.md first.

## CONTINUITY.md Location

- For git repos, keep CONTINUITY.md in the primary checkout.
- Do not duplicate CONTINUITY.md across worktrees.
- When multiple worktrees exist, use absolute paths and identify primary checkout, active worktree, branch, base branch, and merge status.

---

## Cash Runway speed rules

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

### Validation tiers
Use targeted checks during implementation, then run the full required gates before merge/publish.
- Core-only changes start with focused `swift test --filter ...`.
- UI-only changes start with filtered simulator `xcodebuild`.
- DB/keychain/persistence/security changes require focused tests, full `swift test`, simulator build, and boot/log check.

### Worktree hygiene — mandatory cleanup
Historical pattern: worktrees and branches accumulated (`codex/xcuitest-transaction-suite`, `codex/data-loss-investigation`, `codex/keychain-startup-hardening`) and were not always pruned, leaving stale entries.

**Rule:** Immediately after a feature branch is merged and pushed with user approval:
1. `git worktree remove <path>` (or `git worktree prune` if the directory is already gone).
2. `git branch -d <branch>` (local).
3. `git push origin --delete <branch>` (remote) if the branch was pushed.
4. Update `CONTINUITY.md` to reflect the cleaned state.

A clean workspace has **one** worktree (the primary checkout) and **one** local branch (`main`), except intentionally retained legacy branches.

### Exploration cost ceiling
Before broad exploration, use the Code location quick reference in the root `AGENTS.md`. For large files, use `rg -n` plus line-window reads instead of reading whole files.

### UI tests
UI tests are opt-in and targeted. When explicitly working on them, use deterministic `CASH_RUNWAY_UI_TEST_MODE` / `UITEST-*` data and inspect the live accessibility tree or logs before changing UI code for a failing selector.

### Real-device debugging
Simulator is the default validation target. Real-device work requires explicit user approval or a confirmed device-specific bug. For confirmed real-device issues, preserve evidence first when data may be at risk, verify device unlock/trust, and prefer plain `devicectl` launch/timing before Xcode/LLDB-heavy debugging.
