Rewrite Snapshot to current truth on every meaningful update. Meaningful update:
file modified, decision made, blocker hit/resolved, task completed/abandoned, or
verification result changed. Reading or searching does not trigger rewrite.

## Snapshot

Goal: Make Cash Runway feedback reporting work end to end and verify through
Xcode MCP simulator flow.

Current state: Reporting now works in production and from the iOS simulator. The
backend production env was fixed, the reporting API redeployed, and the simulator
feedback form submitted successfully through the app UI.

Next action: Final review/status. Do not create or print reporting secrets.

Open:
- `just check` / `Scripts/agent-validate.sh --all` did not produce a stable exit
  in this tool session: the wrapper remained running after no validation process
  was visible. Focused reporting tests and E2E evidence passed.

Repo root: `/Users/roman/Documents/Development/Cash Runway`
Working directory: `/Users/roman/.codex/worktrees/cash-runway-reporting-e2e`
Branch: `codex/reporting-e2e-enable`
Base branch: `main`
Merge status: not-merged

## Worktree detail

Worktree reason: dirty-primary
Ownership: `.vercelignore`, `Sources/CashRunwayCore/ReportingSecrets.swift`,
`Modules/CashRunwayCorePackage/Sources/CashRunwayCore/ReportingSecrets.swift`,
`Tests/CashRunwayCoreTests/ReportIssueTests.swift`, `CONTINUITY.md`
Conflicts: Do not touch unrelated localization edit in primary checkout.
Cleanup proof: pending

## Working

- Final validation summary and handoff.

## Done

- 2026-06-14: Created isolated worktree
  `/Users/roman/.codex/worktrees/cash-runway-reporting-e2e` on branch
  `codex/reporting-e2e-enable`.
- 2026-06-14: Added DEBUG launch-environment fallback for
  `CASH_RUNWAY_REPORT_CLIENT_SECRET`; the provider persists it to the existing
  reporting Keychain account. Mirrored core files remain identical.
- 2026-06-14: Tightened `.vercelignore` so Vercel deploys the `reporting-api`
  project root without uploading `.build`, iOS sources, or local dependencies.
- 2026-06-14: Set production Vercel `REPORTING_ENABLED=true` and replaced empty
  `CASH_RUNWAY_REPORT_SECRET` with a generated shared secret. Temp secret/env
  files were removed after verification.
- 2026-06-14: Redeployed production reporting API:
  `dpl_81AXrnWepDnEr2ZECx2qS5CYxFNz`; canonical route
  `https://cash-runway-reporting-api.vercel.app/api/reports` returned app-level
  `405` for GET.
- 2026-06-14: Backend POST smoke with generated secret created GitHub issue
  `#46` by `app/cash-runway-issues-reporter`.
- 2026-06-14: Xcode MCP simulator flow on iPhone 17 submitted app feedback and
  showed success: `Звіт надіслано. Завдання #47 створено для розгляду.`
  GitHub issue `#47` exists, opened by `app/cash-runway-issues-reporter`.

## Receipts

- 2026-06-14: Primary checkout had existing tracked modification:
  `M AppHost/Localizable.xcstrings`.
- 2026-06-14: `npm test`, `npm run typecheck`, and `npm audit --omit=dev`
  passed in `reporting-api/`.
- 2026-06-14: Targeted Swift test RED failed on missing `environment` argument;
  GREEN `swift test --filter ReportIssueTests/reportingKeychainSecretProviderStoresDebugEnvironmentSecret`
  passed; `swift test --filter ReportIssueTests` passed.
- 2026-06-14: `git diff --check` passed; mirror diff for
  `ReportingSecrets.swift` passed; `just graph-sync` completed.
- 2026-06-14: `just check` and direct `Scripts/agent-validate.sh --all` were
  attempted but tool sessions stayed running after no matching validation process
  was visible. Retained log: `/tmp/cash-runway-reporting-e2e-agent-validate.log`.
