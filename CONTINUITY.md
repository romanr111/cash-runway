## Snapshot

- Goal: Enforce repo-local CodeGraph worktree isolation.
- Success criteria: CodeGraph bootstrap runs from the current worktree root, initializes that worktree's own `.codegraph/codegraph.db`, rejects mismatched CodeGraph project roots, `just` recipes use the bootstrap guard, and guidance documents the required flow.
- Current state: CodeGraph worktree isolation guard is implemented and validated on `codex/codegraph-worktree-isolation`.
- Next action: Report branch status and validation results.
- Open questions: None.
- Merge status: not-merged.

## Git Context

- Repo root: `/Users/roman/.codex/worktrees/cash-runway-codegraph-isolation`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-codegraph-isolation`
- Branch: `codex/codegraph-worktree-isolation`
- Base branch: `origin/main`
- Worktree reason: dirty-primary
- Merge status: not-merged.

## Working Set

- `Scripts/codegraph-bootstrap.sh`
- `Scripts/test-codegraph-bootstrap.sh`
- `justfile`
- `AGENTS.md`
- `CONTINUITY.md`

## Receipts

- 2026-06-13 [TEST] `bash Scripts/test-codegraph-bootstrap.sh` failed before implementation because `Scripts/codegraph-bootstrap.sh` was missing.
- 2026-06-13 [CODE] Added CodeGraph bootstrap guard and wired `graph-bootstrap`, `graph-status`, `graph-sync`, and `graph-reindex` through `just`.
- 2026-06-13 [VALIDATED] Focused bootstrap tests passed with fake `codegraph` for initialization, subdirectory rejection, and mismatched project rejection.
- 2026-06-13 [VALIDATED] Real `just graph-bootstrap` initialized this worktree's CodeGraph index and `just graph-status` ran through the guard.
- 2026-06-13 [VALIDATED] Disposable detached worktree from commit `c139762` ran `just graph-bootstrap`, created its own `.codegraph/codegraph.db`, reported the disposable worktree path, and was removed.
