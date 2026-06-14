Rewrite Snapshot to current truth on every meaningful update. Meaningful update:
file modified, decision made, blocker hit/resolved, task completed/abandoned, or
verification result changed. Reading or searching does not trigger rewrite.

## Snapshot

Goal: Make Cash Runway issue screenshot upload work end to end with proper
GitHub uploads, redeploy, and verify via Xcode MCP that an issue created from
the app has an attached screenshot.

Current state: Goal achieved. Production reporting API uses GitHub Contents
uploads again, and an app-submitted Xcode MCP E2E report created GitHub issue
`#54` with a visible `raw.githubusercontent.com` screenshot Markdown image and
no data URI.

Next action: Final status/handoff. Do not create or print reporting secrets.

Open:
- `just check` / `Scripts/agent-validate.sh --all` previously did not produce a
  stable exit in this tool session after the wrapper remained running with no
  visible validation child process. Targeted validations and Xcode MCP E2E are
  complete.

Repo root: `/Users/roman/Documents/Development/Cash Runway`
Working directory: `/Users/roman/.codex/worktrees/cash-runway-reporting-e2e`
Branch: `codex/reporting-e2e-enable`
Base branch: `main`
Merge status: not-merged

## Worktree detail

Worktree reason: dirty-primary
Ownership: `.vercelignore`, `.mcp.json`,
`Sources/CashRunwayCore/ReportingSecrets.swift`,
`Modules/CashRunwayCorePackage/Sources/CashRunwayCore/ReportingSecrets.swift`,
`Sources/CashRunwayCore/FeedbackReport.swift`,
`Modules/CashRunwayCorePackage/Sources/CashRunwayCore/FeedbackReport.swift`,
`Sources/CashRunwayUI/FeedbackReportService.swift`,
`Tests/CashRunwayCoreTests/ReportIssueTests.swift`, `reporting-api/**`,
`AppHost/Localizable.xcstrings`, `CONTINUITY.md`
Conflicts: Do not touch unrelated localization edit in primary checkout.
Cleanup proof: pending

## Working

- Final status/handoff only.

## Done

- 2026-06-14: Created isolated worktree
  `/Users/roman/.codex/worktrees/cash-runway-reporting-e2e` on branch
  `codex/reporting-e2e-enable`.
- 2026-06-14: Added DEBUG launch-environment fallback for
  `CASH_RUNWAY_REPORT_CLIENT_SECRET`; provider persists it to the existing
  reporting Keychain account. Later updated DEBUG env to override stale Keychain
  values during simulator E2E.
- 2026-06-14: Tightened `.vercelignore` so Vercel deploys the `reporting-api`
  project root without uploading `.build`, iOS sources, or local dependencies.
- 2026-06-14: Set production Vercel `REPORTING_ENABLED=true` and replaced empty
  `CASH_RUNWAY_REPORT_SECRET` with a generated shared secret.
- 2026-06-14: Text-only backend POST smoke created GitHub issue `#46`; Xcode MCP
  simulator feedback form created GitHub issue `#47`.
- 2026-06-14: Added server-side screenshot count/size logging.
- 2026-06-14: Raised rate limit from 3/hour to 10/hour, 30/day; rate-limit
  response now includes limit/remaining counter and client shows the counter.
- 2026-06-14: Merged `origin/main`, resolved `CONTINUITY.md` conflict.
- 2026-06-14: Reverted the data URI screenshot workaround back to
  `GitHubClient.uploadFile`, embedding returned file URLs in issue Markdown.
- 2026-06-14: Redeployed production reporting API:
  `dpl_AZN87SyJnMBNzSLC3VR7qc9ygkP2`.
- 2026-06-14: Direct backend screenshot POST smoke created GitHub issue `#53`;
  body has `raw.githubusercontent.com` screenshot URL and `hasDataUri=false`.
- 2026-06-14: Added DEBUG-only feedback screenshot preload env hook because the
  system Photos picker was visible but not exposed in Xcode MCP accessibility
  snapshots, and `cliclick`/AppleScript coordinate fallback lacked Accessibility
  permissions.
- 2026-06-14: Xcode MCP app E2E created GitHub issue `#54` from the feedback UI
  with preloaded screenshot attached. Verification: author
  `app/cash-runway-issues-reporter`, `hasVisibleMarkdownImage=true`,
  `screenshotUrlHost=raw.githubusercontent.com`, `hasDataUri=false`.

## Receipts

- 2026-06-14: Primary checkout had existing tracked modification:
  `M AppHost/Localizable.xcstrings`.
- 2026-06-14: API RED failed against data URI workaround; GREEN passed after
  restoring upload behavior.
- 2026-06-14: `npm test`, `npm run typecheck`, and `npm audit --omit=dev`
  passed in `reporting-api/`.
- 2026-06-14: `swift test --filter ReportIssueTests/reportingKeychainSecretProvider`
  passed after DEBUG env-overrides-stale-Keychain test was added.
- 2026-06-14: Xcode MCP `build_run_sim` passed after final iOS changes.
- 2026-06-14: Restored `ReportingSecrets.generated.swift` files to the
  committed placeholder state before staging; real generated secret payloads
  must not ship.
- 2026-06-14: `git diff --check` passed; mirror diff for
  `ReportingSecrets.swift` and `FeedbackReport.swift` passed; `just graph-sync`
  completed.
- 2026-06-14: `just check` and direct `Scripts/agent-validate.sh --all` were
  attempted earlier but tool sessions stayed running after no matching
  validation process was visible. Retained log:
  `/tmp/cash-runway-reporting-e2e-agent-validate.log`.
