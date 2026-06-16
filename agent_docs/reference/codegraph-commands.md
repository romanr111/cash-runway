# CodeGraph command reference

Use CodeGraph before broad code searches or repeated raw file reads.

## Bootstrap

Run once per worktree before any CodeGraph operations:

```bash
just graph-bootstrap
# or, if the repo has no justfile:
Scripts/codegraph-bootstrap.sh
```

## MCP tools

Primary:
- `mcp__codegraph__codegraph_explore` — first tool for almost any codebase question: how does X work, architecture, bugs, locating symbols, or surveying an area.
- `mcp__codegraph__codegraph_search` — quick symbol search by name; returns locations only (no code).
- `mcp__codegraph__codegraph_node` — get one symbol in full: location, signature, callers/callees trail, and verbatim body.

Analysis:
- `mcp__codegraph__codegraph_impact` — list symbols affected by changing a symbol; use before refactoring.
- `mcp__codegraph__codegraph_files` — indexed file tree with language + symbol counts; faster than Glob for layout.

Call graph:
- `mcp__codegraph__codegraph_callers` — list functions that call a symbol.
- `mcp__codegraph__codegraph_callees` — list functions that a symbol calls.
- For full call flows, prefer `codegraph_explore`.

Debug:
- `mcp__codegraph__codegraph_status` — index health check; skip unless debugging.

## Rules of thumb

- For files over ~500 lines, locate the relevant symbol first and read a narrow line range.
- Fall back to `rg -n` or `Grep` only when CodeGraph is unavailable or insufficient.
- Verify any path or line number against the current checkout before editing.
