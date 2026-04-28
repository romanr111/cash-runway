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




## Continuity Ledger (compaction-safe)

Maintain a single continuity file for this workspace: `CONTINUITY.md`.
`CONTINUITY.md` is the canonical briefing designed to survive compaction; do not rely on earlier chat/tool output unless it's reflected there.

### Operating rule
- At the start of each assistant turn: read `CONTINUITY.md` before acting.
- Update `CONTINUITY.md` only when there is a meaningful delta in: Goal/success criteria, Invariants/constraints, Decisions, State (Done/Now/Next), Open questions, Working set, or important tool outcomes.

### Keep it bounded (anti-bloat)
- Keep `CONTINUITY.md` short and high-signal:
  - `Snapshot`: ≤ 25 lines.
  - `Done (recent)`: ≤ 7 bullets.
  - `Working set`: ≤ 12 paths.
  - `Receipts`: keep last 10–20 entries.
- If sections exceed caps, compress older items into milestone bullets with pointers (commit/PR/log path/doc path). Do not paste raw logs.

### Anti-drift rules
- Facts only, no transcripts.
- Every entry must include:
  - a date or ISO timestamp (e.g., `2026-01-13` or `2026-01-13T09:42Z`)
  - a provenance tag: `[USER]`, `[CODE]`, `[TOOL]`, `[ASSUMPTION]`
- If unknown, write `UNCONFIRMED` (never guess). If something changes, supersede it explicitly (don't silently rewrite history).

### Decisions and incidents
- Record durable choices in `Decisions` as ADR-lite entries (e.g., `D001 ACTIVE: …`).
- For recurring weirdness, create a small, stable incident capsule (Symptoms / Evidence pointers / Mitigation / Status).

### Plan tool vs ledger
- Use `update_plan` for short-term execution scaffolding (3–7 steps).
- Use `CONTINUITY.md` for long-running continuity ("what/why/current state"), not micro task lists.
- Keep them consistent at the intent/progress level.

### In replies
- Start with a brief "Ledger Snapshot" (Goal + Now + Next + Open Questions).
- Print the full ledger only when it materially changed or the user requests it
