# Session Start Reference

Run `just session-start` at the beginning of every Cash Runway working session.

The recipe performs the following steps:

1. Prints the current worktree path.
2. Prints the current branch name.
3. Runs `git worktree list`.
4. Runs `Scripts/pre-flight.sh` to print git status, diff stat, untracked files,
   and the CashRunwayCore module-wiring check.

If `just` is unavailable, run the equivalent commands manually:

```bash
git worktree list
git -C <worktree> rev-parse --abbrev-ref HEAD
git status --short
Scripts/pre-flight.sh
```

## Manual recovery

- If a full SwiftPM gate hangs, kill stale `swiftpm-testing-helper` processes
  from other worktrees and retry with `just check-isolated`.
- If `just session-start` itself fails, fix the underlying issue before editing
  source files.

## Related documents

- `AGENTS.md` — project rules and precedence.
- `CONTINUITY.md` — current branch state and validation.
- `agent_docs/reference/ledger-archive.md` — historical phases.
