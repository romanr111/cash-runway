# CodeGraph command reference

Follow `~/.codex/references/codegraph.md` to decide whether a task warrants
CodeGraph. This reference applies only after that global selector chooses it.

## Bootstrap

For a selected high-value task with a healthy worktree-local index, query it
directly. If it has no index, run `just graph-bootstrap` to initialize the
active worktree. Otherwise run it only for owner-marker repair or an index
warning that requires recovery, because the wrapper runs `codegraph status`.
Never copy or share graph directories between worktrees; separate worktrees
require separate indexes.

```bash
just graph-bootstrap
# or, if the repo has no justfile:
Scripts/codegraph-bootstrap.sh
```

## Exploration

Prefer `mcp__codegraph__codegraph_explore`. CLI fallbacks are:

- `codegraph explore "<question>"`
- `codegraph callers "<symbol>"`
- `codegraph callees "<symbol>"`
- `codegraph impact "<symbol>"`

Use `just graph-status` and `just graph-reindex` only for diagnostics or an
old-engine migration. Run `just graph-sync` only when the watcher is disabled
or an actual stale-index warning appears. Verify any path or line number against
the current checkout before editing.
