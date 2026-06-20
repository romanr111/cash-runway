# Worktree and CodeGraph Instructions

## Worktree Isolation

Treat each Git worktree as an independent development environment.

Before meaningful work, run:

```bash
Scripts/pre-flight.sh
```

Review the current branch, modified files, untracked files, existing diff, and
mirrored-core drift. If drift is caused by your core edits, run
`just mirror-core`. Do not overwrite or discard unrelated work.

## CodeGraph Lifecycle

Each worktree must have its own:

```text
.codegraph/codegraph.db
.codegraph/worktree-root
```

Never copy or share `.codegraph/` between worktrees.

After creating or entering a worktree, run:

```bash
just graph-bootstrap
just graph-status
```

After meaningful source changes, run:

```bash
just graph-sync
```

Use this only when normal synchronization is insufficient:

```bash
just graph-reindex
```

Multiple agents may share one CodeGraph daemon only when they operate in the
same worktree. Different worktrees require separate indexes.

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
