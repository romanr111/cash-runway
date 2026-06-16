# Headroom command reference

Use Headroom first for bulky command output, logs, code search, diffs, and
cross-agent handoff memory.

## MCP tools

- `mcp__headroom__headroom_compress` — compress bulky text and get a retrieval hash.
- `mcp__headroom__headroom_retrieve` — get the original content back by hash; filter with an optional query.
- `mcp__headroom__headroom_stats` — show compression savings for the session.

## CLI commands

When working outside the agent (Codex example — wrapper invocation differs by agent):

```bash
headroom wrap codex --memory --no-context-tool
headroom proxy --host 127.0.0.1 --port 8787
headroom stats
```

## Rules of thumb

- Prefer Headroom over command-specific token filters for routine work.
- Use targeted shell commands and narrow reads when exact output matters.
- Preserve complete raw logs outside the model context, then compress the summary.
- Do not paste complete build logs, JSON catalogs, or large diffs into the conversation.
- Do not default to RTK; use it only when explicitly requested or when a one-off RTK filter is the narrowest safe way to inspect noisy output.
