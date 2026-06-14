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

- Goal: Refactor Cash Runway agent instructions for token efficiency.
- Success criteria: Compact root `AGENTS.md`, scoped `agent_docs/instructions/` and `agent_docs/reference/` files, internally consistent validation command hierarchy, no agent-specific duplicate files, and no application behavior changes.
- Current state: PR `#45` was merged via squash commit `7cd38d5` on main; worktree and branch cleaned up.
- Next action: Resume normal feature work from the main worktree.
- Open questions: None.
- Merge status: merged.
- Handoff trigger: when context is compacted or turns exceed ~50, rewrite this Snapshot to current truth before starting a fresh conversation.

## Git Context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- Base branch: `origin/main`
- Worktree reason: primary
- Merge status: merged

## Working Set

- `AGENTS.md`
- `agent_docs/instructions/ios.md`
- `agent_docs/instructions/reporting-api.md`
- `agent_docs/instructions/security-privacy.md`
- `agent_docs/instructions/validation.md`
- `agent_docs/instructions/worktrees.md`
- `agent_docs/reference/code-location-guide.md`
- `agent_docs/reference/github-app-setup.md`
- `agent_docs/reference/simulator-smoke-notes.md`
- `agent_docs/reference/ui-test-history.md`
- `justfile`
- `CONTINUITY.md`

## Receipts

- 2026-06-07 [COMMIT] `3138b54` `feat: add hardened text feedback reporting`.
- 2026-06-07 [PR] `#32` — https://github.com/romanr111/cash-runway/pull/32
- 2026-06-13 [LABELS] Confirmed `bug` and `improvement`; created `user-report`, `ios`, and `needs-triage`.
- 2026-06-13 [MERGE] Merged current `origin/main` into `codex/feedback-report-phase1`; resolved conflicts in `.gitignore`, `CONTINUITY.md`, and `CashRunway.xcodeproj/project.pbxproj`.
- 2026-06-13 [VERCEL] Created and linked `romanr111s-projects/cash-runway-reporting-api`; connected GitHub repo; added branch-scoped Preview placeholders for reporting, GitHub App, repo, and Upstash env names.
- 2026-06-13 [VALIDATED] `reporting-api` `npm test` passed 35 tests; `npm run typecheck` passed; production npm audit (`--omit=dev`) found 0 vulnerabilities.
- 2026-06-13 [VALIDATED] Core mirror diff, `git diff --check`, focused `ReportIssueTests`, full `swift test`, clean iPhone 17 simulator build, and seeded simulator smoke passed.
- 2026-06-13 [BLOCKED] Vercel remote deploy with explicit `nodejs22.x` runtime failed; removing the runtime made local `vercel build` pass, but local preview/prebuilt deployments stayed `UNKNOWN`.
- 2026-06-13 [VERCEL] Git-backed `cash-runway-reporting-api` deployment initially returned `NOT_FOUND` for `/api/reports` because Root Directory was `.`; updated project Root Directory to `reporting-api`.
- 2026-06-13 [VERCEL] Git-backed deployment `https://cash-runway-reporting-jbeft9xhq-romanr111s-projects.vercel.app` was `Ready`; direct public curl returned Vercel deployment protection `401`, while `vercel curl /api/reports` reached the API and returned `{"error":"Method not allowed."}` for GET.
- 2026-06-13 [CONFIG] Added `AppHost/ReportingConfig.debug.xcconfig` as a committed wrapper that loads `ReportingConfig.example.xcconfig` and optionally overlays the git-ignored `ReportingConfig.local.xcconfig`; Debug target now uses the wrapper, Release target remains on placeholder/example config.
- 2026-06-13 [VALIDATED] Debug build succeeds without `ReportingConfig.local.xcconfig` (reporting disabled); with the local config the built `Info.plist` contains the staging endpoint, rotated client marker, `enabled = YES`, and `environment = staging`; Release build resolves to disabled placeholder values.
- 2026-06-13 [E2E] iPhone 17 simulator run via XcodeBuildMCP navigated Settings → Report Bug or Suggest Improvement, submitted a bug report, and created GitHub issue `#41` with labels `user-report`, `bug`, `ios`, `needs-triage` and real safe diagnostics; issue closed after verification.
- 2026-06-13 [VALIDATED] `reporting-api npm test` (35/35), `npm run typecheck`, `swift test --filter ReportIssueTests` (11/11), `Scripts/agent-validate.sh --focused ReportIssueTests --full --ui-build`, and `Scripts/smoke-seeded-simulator.sh` all passed; `git diff --check` clean; no real secret or endpoint committed to tracked files.
- 2026-06-13 [PR] Updated PR `#32` description to current truth and marked it ready for review.
