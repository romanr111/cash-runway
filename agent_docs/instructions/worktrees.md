# Worktree and CodeGraph Instructions

## Worktree Isolation

Treat each Git worktree as an independent development environment.

Before meaningful work, run:

```bash
Scripts/pre-flight.sh
```

Review the current branch, modified files, untracked files, and existing diff.
Do not overwrite or discard unrelated work.

## CodeGraph Lifecycle

Each worktree must have its own:

```text
.codegraph/codegraph.db
.codegraph/worktree-root
```

Never copy or share `.codegraph/` between worktrees. Different worktrees require
separate indexes.

Bootstrap only when the global CodeGraph selector chooses it for a high-value
task. If that selected task has no index, bootstrap initializes this worktree's
separate index:

```bash
just graph-bootstrap
```

Run this only when a required rebuild or old-engine migration is needed:

```bash
just graph-reindex
```

Multiple agents may share one CodeGraph daemon only when they operate in the
same worktree.

## Branch Management

- Use one feature branch per isolated task.
- Do not mix unrelated changes.
- Do not delete or reset work you did not create.
- Do not merge, publish, or delete branches without the required user approval.

## Cleanup

After a branch is merged and cleanup is approved, run only applicable steps:

```bash
git worktree remove <path>
git branch -d <branch>
git push origin --delete <branch>
git worktree prune
```

Do not delete an unmerged branch or a worktree containing uncommitted changes.

## Continuity

Follow the update contract in `CONTINUITY.md`. Update its Snapshot when:

- repository state materially changes;
- a decision is made;
- validation status changes;
- a blocker appears or is resolved;
- the task is completed or abandoned;
- context is about to be compacted;
- work is transferred to another session or agent.

Do not create an additional arbitrary handoff threshold.

## Worktree-local `CONTINUITY.md`

`CONTINUITY.md` is a per-worktree working log, not a shared source-of-truth file.

- Maintain and update `CONTINUITY.md` inside the active worktree directory.
- Let it diverge from `dev`, `main`, or other worktrees; each branch/worktree
  records its own context, decisions, and validation history.
- Do not attempt to keep `CONTINUITY.md` identical across worktrees or base branches.
- When merging a feature branch/worktree into `dev` (or another shared branch),
  resolve `CONTINUITY.md` conflicts by preserving both histories: keep the incoming
  worktree snapshot(s) and the target branch snapshot(s) in the resulting file.
