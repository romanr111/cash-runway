## Snapshot

- Goal: Make Cash Runway issue screenshot upload work end to end, merge the PR,
  and update local `main`.
- Success criteria: Met. Production reporting API uses GitHub Contents uploads,
  app-submitted Xcode MCP E2E report created GitHub issue `#54` with a visible
  `raw.githubusercontent.com` screenshot image, PR `#48` was merged, and the
  primary checkout is fast-forwarded to `origin/main`.
- State: Merged to `main`.
- Next action: None for reporting upload. Do not create or print reporting
  secrets.
- Handoff trigger: Rewrite this Snapshot before context compaction, a major task
  switch, or task completion.

## Git Context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- HEAD: `ce55427` (merge commit for PR `#48`)
- Reporting worktree: `/Users/roman/.codex/worktrees/cash-runway-reporting-e2e`
  on `codex/reporting-e2e-enable`, left in place.

## Working Set

- `CONTINUITY.md` modified only to resolve the primary-checkout ledger conflict
  after preserving the pre-existing local snapshot.
- Untracked reporting secret/env files must stay uncommitted.

## Receipts

- 2026-06-14: Restored `reporting-api/src/github/createGitHubIssue.ts` from
  data URI workaround back to `GitHubClient.uploadFile`, embedding returned raw
  file URLs in issue Markdown.
- 2026-06-14: Redeployed production reporting API:
  `dpl_AZN87SyJnMBNzSLC3VR7qc9ygkP2`.
- 2026-06-14: Direct backend screenshot POST smoke created GitHub issue `#53`;
  body had `raw.githubusercontent.com` screenshot URL and `hasDataUri=false`.
- 2026-06-14: Xcode MCP app E2E created GitHub issue `#54`; verification:
  author `app/cash-runway-issues-reporter`,
  `hasVisibleMarkdownImage=true`, `screenshotUrlHost=raw.githubusercontent.com`,
  `hasDataUri=false`.
- 2026-06-14: Before commit, restored `ReportingSecrets.generated.swift` files
  to committed placeholder state; real generated secret payloads must not ship.
- 2026-06-14: Local validation passed: `npm test`, `npm run typecheck`,
  `npm audit --omit=dev`, `swift test --filter
  ReportIssueTests/reportingKeychainSecretProvider`, Xcode MCP `build_run_sim`,
  `git diff --check`, mirrored core diffs, and `just graph-sync`.
- 2026-06-14: PR `#48` checks passed before merge: Static Analysis,
  Integration Tests, Vercel reporting API, and Vercel app. UI End-to-End Tests
  were skipped by workflow.
- 2026-06-14: PR `#48` merged to `main` as `ce55427`.
- 2026-06-14: Older SideStore P0 work merged earlier as `6ae071c` via PR `#51`;
  `just lint && just verify` passed before that merge.

## Open Questions

- SideStore release rehearsal still needs physical-device/manual release
  validation through `sidestore-release.yml`: install/update same bundle
  identifier, verify data/Keychain persistence, refresh while locked or
  backgrounded, and confirm app opens after refresh. No repo-side validation can
  prove SideStore refresh/update lifecycle behavior.
