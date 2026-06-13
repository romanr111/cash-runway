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
- Current state: PR `#32` was merged locally with current `origin/main`; merge conflicts in `.gitignore`, `CONTINUITY.md`, and `CashRunway.xcodeproj/project.pbxproj` were resolved, required GitHub labels were created, and Vercel preview setup still needed placeholder environment values plus redeploy verification.
- Next action: Configure the Vercel preview project with placeholder environment values, redeploy `reporting-api`, then run backend, Swift, build, and smoke validation.
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
