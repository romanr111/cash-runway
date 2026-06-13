<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Current state: one sentence, past tense, what is true now.
- Next action: one imperative sentence, one concrete step.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
-->

## Snapshot

- Goal: Implement and harden text-only user bug/improvement reporting using a Vercel TypeScript API and GitHub App server-side issue creation.
- Success criteria: Backend validation, sanitization, issue formatting, idempotency, Redis/Upstash rate limits, duplicate suppression, safe logging, GitHub failure mapping, mockable GitHub client, tests, and `.env.example`; iOS Codable payload, validation, idempotency key submission, safe diagnostics, anonymous install hash, service abstraction, SwiftUI Settings form, explicit config gating, and no screenshots/logs/files/financial data upload path.
- Current state: PR `#32` was locally merge-resolved against current `origin/main`; required GitHub labels and Vercel Preview placeholder environment variables were created, local Vercel build succeeded, backend/Swift/build/smoke validation passed, but Vercel deployments for `cash-runway-reporting-api` remained `UNKNOWN`/deployment-protected instead of returning a public API response.
- Next action: Push `codex/feedback-report-phase1`, then resolve Vercel deployment protection/status in the dashboard or with real project credentials before wiring the iOS production endpoint.
- Open questions: GitHub App installation scope, permissions, webhook state, and private credential storage could not be confirmed through the current `gh` token because GitHub App installation APIs returned 401/403.
- Merge status: not-merged.

## Git Context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-feedback-report-phase1`
- Branch: `codex/feedback-report-phase1`
- Base branch: `origin/main`
- Worktree reason: isolated-feature
- Merge status: not-merged

## Working Set

- `Sources/CashRunwayUI/SettingsView.swift`
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift`
- `Tests/CashRunwayUITests/SettingsNavigationUITests.swift`
- `Sources/CashRunwayCore/FeedbackReport.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/FeedbackReport.swift`
- `CashRunway.xcodeproj/project.pbxproj`
- `reporting-api/**`
- `.gitignore`
- `.vercelignore`
- `CONTINUITY.md`

## Receipts

- 2026-06-07 [COMMIT] `3138b54` `feat: add hardened text feedback reporting`.
- 2026-06-07 [PR] `#32` — https://github.com/romanr111/cash-runway/pull/32
- 2026-06-13 [LABELS] Confirmed `bug` and `improvement`; created `user-report`, `ios`, and `needs-triage`.
- 2026-06-13 [MERGE] Merged current `origin/main` into `codex/feedback-report-phase1`; resolved conflicts in `.gitignore`, `CONTINUITY.md`, and `CashRunway.xcodeproj/project.pbxproj`.
- 2026-06-13 [VERCEL] Created and linked `romanr111s-projects/cash-runway-reporting-api`; connected GitHub repo; added branch-scoped Preview placeholders for reporting, GitHub App, repo, and Upstash env names.
- 2026-06-13 [VALIDATED] `reporting-api` `npm test` passed 35 tests; `npm run typecheck` passed; production npm audit (`--omit=dev`) found 0 vulnerabilities.
- 2026-06-13 [VALIDATED] Core mirror diff, `git diff --check`, focused `ReportIssueTests`, full `swift test`, clean iPhone 17 simulator build, and seeded simulator smoke passed.
- 2026-06-13 [BLOCKED] Vercel remote deploy with explicit `nodejs22.x` runtime failed; removing the runtime made local `vercel build` pass, but preview/prebuilt deployments stayed `UNKNOWN` and public requests returned Vercel deployment protection instead of the API.
