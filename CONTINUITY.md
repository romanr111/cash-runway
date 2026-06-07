<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true true.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Implement and harden text-only user bug/improvement reporting using a Vercel TypeScript API and GitHub App server-side issue creation.
- Success criteria: Backend has validation, sanitization, GitHub issue formatting, idempotency, Redis/Upstash rate limits, duplicate suppression, safe logging, GitHub failure mapping, mockable GitHub client, tests, and `.env.example`; iOS has Codable payload, validation, idempotency key submission, safe diagnostics, anonymous install hash, service abstraction, SwiftUI Settings form, explicit config gating, and no screenshots/logs/files/financial data upload path.
- Current state: Draft PR `#32` was opened for text-only reporting plus production hardening; detailed self-review fixed unsupported-field acceptance, and all local backend, Swift, build, mirror, diff, and seeded simulator smoke validations passed.
- Next action: Create/install the GitHub App, create Vercel staging/production projects, add secrets, configure the iOS production endpoint/client secret, approve privacy copy, and run one real staging E2E report.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-feedback-report-phase1`
- Branch: `codex/feedback-report-phase1`
- Base branch: `origin/main`
- Worktree reason: isolated-feature
- Merge status: not-merged

## Working set

- `Sources/CashRunwayUI/SettingsView.swift`
- `Sources/CashRunwayUI/AccessibilityIdentifiers.swift`
- `Sources/CashRunwayCore/FeedbackReport.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/FeedbackReport.swift`
- `Sources/CashRunwayUI/FeedbackReportService.swift`
- `Sources/CashRunwayUI/FeedbackReportView.swift`
- `CashRunway.xcodeproj/project.pbxproj`
- `Tests/CashRunwayCoreTests/ReportIssueTests.swift`
- `Tests/CashRunwayUITests/CashRunwayUITestCase.swift`
- `Tests/CashRunwayUITests/SettingsNavigationUITests.swift`
- `reporting-api/**`
- `CONTINUITY.md`

## Done (recent)

- 2026-06-01 [CODE] Published PR `#24` category merge remap lookup fixes and regression coverage for built-in MCC fallback and CSV merged-name reuse.
- 2026-06-01 [CODE] Fixed CSV test verification through `transactionDraft(id:)` and made `resolvedCategoryID` follow remap chains to active destinations in both mirrored core trees.
- 2026-06-01 [MERGE] Merged newer `origin/main` through `f5d7ad4` into `codex/category-merge-fix`; only `CONTINUITY.md` conflicted.
- 2026-06-01 [VALIDATED] Focused category merge/import tests, full `swift test`, core mirror diff, `git diff --check`, iPhone 17 clean build, install/launch smoke, and app error/fault log scan passed.
- 2026-06-01 [CI] PR `#24` reported mergeable (`CLEAN`); Static Analysis, Unit Tests, and Integration Tests passed; UI E2E skipped per workflow policy.
- 2026-06-02 [TEST] Added category-merge regression coverage that records source/destination transaction counts and sums before merge, then asserts the destination receives their combined count/sum while global count/sum stay unchanged.
- 2026-06-02 [UI] Replaced the basic category merge form with a designed merge flow showing source/destination category cards, transaction-count preview, data-preservation copy, and an in-sheet success confirmation after merge.
- 2026-06-02 [MERGE] PR `#23` UI refresh landed on `main` at `ca1c3fa`; merging it into PR `#24` auto-merged source/test files and conflicted only in `CONTINUITY.md`.
- 2026-06-02 [VALIDATED] Post-`ca1c3fa` main merge passed focused category merge/import tests, core mirror diff, diff check, full `swift test`, iPhone 17 clean build, install/launch smoke, and app error/fault log scan.

## Receipts

- 2026-06-01 [PR] `#24` — https://github.com/romanr111/cash-runway/pull/24
- 2026-06-01 [MAIN] `fix/side-store-concurrency` was merged into `main` at `db9a1e4`; follow-up continuity update landed at `f5d7ad4`.
- 2026-06-02 [MAIN] PR `#23` UI refresh merged into `main` at `ca1c3fa`.
- 2026-06-02 [COMMIT] `0ea6ddb` — test: verify category merge preserves transaction totals
- 2026-06-02 [COMMIT] `0601948` — feat: add category merge success flow
- 2026-06-02 [TEST] Category merge UI update `swift test --filter 'DatabaseTransactionSafetyTests/categoryMerge|BankCategoryMapperTests|CSVEdgeCaseTests/importReusesMergedDestinationCategoryByName'` passed 14 tests.
- 2026-06-02 [TEST] Category merge UI update `swift test` passed 244 tests in 23 suites.
- 2026-06-02 [BUILD] Category merge UI update iPhone 17 clean build ended with `** BUILD SUCCEEDED **`; SQLCipher strip and AppIntents metadata warnings matched existing build noise.
- 2026-06-02 [SMOKE] Installed and launched latest `dev.roman.cashrunway` on iPhone 17; severity-filtered app log scan found no error/fault entries.
- 2026-06-02 [TEST] Post-`ca1c3fa` `swift test --filter 'DatabaseTransactionSafetyTests/categoryMerge|BankCategoryMapperTests|CSVEdgeCaseTests/importReusesMergedDestinationCategoryByName'` passed 14 tests.
- 2026-06-02 [TEST] Post-`ca1c3fa` `swift test` passed 251 tests in 24 suites.
- 2026-06-02 [BUILD] Post-`ca1c3fa` iPhone 17 clean build ended with `** BUILD SUCCEEDED **`; SQLCipher strip and AppIntents metadata warnings matched existing build noise.
- 2026-06-02 [SMOKE] Post-`ca1c3fa` install and launch returned `dev.roman.cashrunway: 10918`; severity-filtered app log scan found no error/fault entries.
- 2026-06-06 [UI] Added a staged progress panel and disabled in-flight controls when tapping Merge Categories before the existing success confirmation.
- 2026-06-06 [TEST] Category merge progress UI update `swift test --filter 'DatabaseTransactionSafetyTests/categoryMerge'` passed 7 tests.
- 2026-06-06 [BUILD] Category merge progress UI update iPhone 17 clean build ended with `** BUILD SUCCEEDED **`; SQLCipher strip and AppIntents metadata warnings matched existing build noise.
- 2026-06-06 [SMOKE] Installed and launched latest `dev.roman.cashrunway` on iPhone 17; severity-filtered app log scan found no error/fault entries.
- 2026-06-06 [NOTE] Extra broad `swift test` was stopped after hanging with partial output; it is not counted as a passing validation.
- 2026-06-06 [PERF] Removed fixed category merge progress UI waits and replaced full merge-time FTS rebuild with targeted search sync for moved transactions only.
- 2026-06-06 [PERF] Replaced full month aggregate rebuilds during category merge with source/destination category spend deltas plus affected-month budget snapshot recompute.
- 2026-06-06 [TEST] Added category-merge FTS regression coverage for old/destination category search terms after merge.
- 2026-06-06 [VALIDATED] Real category merge speedup passed 15 focused category merge/remap/import tests, core mirror diff, diff check, iPhone 17 clean build, install/launch smoke; launch log showed only Apple app-launch measurement CA Event errors, no crash/fatal entries.
- 2026-06-06 [REVIEW] Detailed code review found no blocking or important findings; full `swift test` passed 252 tests in 24 suites, core mirror diff and diff check passed, and iPhone 17 clean build ended with `** BUILD SUCCEEDED **`.
- 2026-06-06 [WORKTREE] Created `/Users/roman/.codex/worktrees/cash-runway-feedback-report-phase1` on branch `codex/feedback-report-phase1` from `main` at `d6118d5`.
- 2026-06-06 [PULL] Primary checkout `main` was already up to date with `origin/main`; pre-existing local edits were stashed, restored, and the temporary stash was dropped.
- 2026-06-06 [UI] Added a Support settings row that presents `FeedbackReportView` with category, title, description, diagnostics toggle, validation, loading, success, and error states.
- 2026-06-06 [CODE] Added `FeedbackReportService`, `RemoteFeedbackReportService`, and `MockFeedbackReportService`; remote submission posts only to a configured backend endpoint and never directly to GitHub.
- 2026-06-06 [TEST] Added `testSettingsToFeedbackReportAndBack` to `SettingsNavigationUITests` and verified the first build-for-testing red failed on missing feedback identifiers.
- 2026-06-06 [VALIDATED] `xcodebuild ... build-for-testing` passed after implementation; `Scripts/validate-ui-only.sh` passed; `Scripts/smoke-seeded-simulator.sh` passed on iPhone 17 with screenshot/log receipts.
- 2026-06-07 [CODE] Replaced the missing-backend submit path with a GitHub issue draft URL builder targeting `https://github.com/romanr111/cash-runway/issues/new`; no GitHub token or direct API call is embedded in the app.
- 2026-06-07 [TEST] Added `FeedbackReportTests`; `swift test --filter FeedbackReportTests` passed 4 tests covering trimming, validation, labels, destination URL, and diagnostics inclusion.
- 2026-06-07 [DESIGN] Polished `FeedbackReportView` with a clear GitHub-destination header, privacy/diagnostics copy, repository issues link, and honest success state.
- 2026-06-07 [VALIDATED] `xcodebuild ... build-for-testing`, `Scripts/validate-ui-only.sh`, core mirror diff, and `Scripts/smoke-seeded-simulator.sh` passed on iPhone 17.
- 2026-06-07 [E2E] Targeted `testFeedbackReportOpensPrefilledGitHubIssueDraft` passed through app UI to Safari/GitHub, but simulator Safari showed the GitHub sign-in screen; no real issue was submitted through UI.
- 2026-06-07 [BLOCKED] Desktop Playwright MCP could not open the GitHub issue URL because Chrome was missing at `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`; no browser package was installed.
- 2026-06-07 [CODE] Replaced GitHub-draft feedback with text-only Vercel reporting skeleton, GitHub App installation-token auth shell, mockable GitHub client, validation/sanitization, issue formatting, duplicate hash, `.env.example`, and README.
- 2026-06-07 [CODE] Replaced iOS feedback draft models with server-backed `ReportIssuePayload`, `ReportIssueDraft`, safe diagnostics, anonymous install hash, URLSession report service, view model, and SwiftUI form that sends no screenshots/logs/files/financial data.
- 2026-06-07 [TEST] `reporting-api npm test` passed 20 tests; `npm run typecheck` passed.
- 2026-06-07 [VALIDATED] `Scripts/agent-validate.sh --focused ReportIssueTests --full --ui-build` passed core mirror diff, `git diff --check`, focused Swift tests, full `swift test`, and clean iPhone 17 simulator build.
- 2026-06-07 [SMOKE] `Scripts/smoke-seeded-simulator.sh` passed on iPhone 17; screenshot/log receipts at `/tmp/cash-runway-agent-validation/20260607-084940-83131/`.
- 2026-06-07 [REVIEW] Detailed self-review fixed overbroad rejection of safe `balance`/`Monobank token screen` wording while still rejecting pasted balances/tokens.
- 2026-06-07 [REVIEW] Detailed self-review fixed backend acceptance of forbidden extra JSON fields such as `transactions` and `monobankToken`.
- 2026-06-07 [VALIDATED] Post-review `reporting-api npm test` passed 24 tests; `npm run typecheck` passed.
- 2026-06-07 [VALIDATED] Post-review `Scripts/agent-validate.sh --focused ReportIssueTests --full --ui-build` passed core mirror diff, `git diff --check`, focused Swift tests, full `swift test`, and clean iPhone 17 simulator build.
- 2026-06-07 [SMOKE] Post-review `Scripts/smoke-seeded-simulator.sh` passed on iPhone 17; screenshot/log receipts at `/tmp/cash-runway-agent-validation/20260607-092203-28244/`.
- 2026-06-07 [CODE] Hardened reporting with idempotency keys, Upstash Redis store abstraction, 24h duplicate suppression, per-install/IP rate limits, strict JSON allowlist validation, safe structured logs, env validation, kill switch, and GitHub API failure mapping.
- 2026-06-07 [CODE] Updated iOS reporting to send an idempotency key, reuse it for retries of the same unchanged draft, disable unavailable/missing-config reporting, and keep the payload allowlist text-only.
- 2026-06-07 [REVIEW] Detailed self-review found and fixed backend acceptance of unsupported non-forbidden extra JSON fields.
- 2026-06-07 [VALIDATED] Hardened reporting passed `reporting-api npm test` (35 tests), `npm run typecheck`, `swift test --filter ReportIssueTests` (11 tests), `Scripts/agent-validate.sh --focused ReportIssueTests --full --ui-build`, and seeded simulator smoke.
- 2026-06-07 [COMMIT] feat: add hardened text feedback reporting.
- 2026-06-07 [PR] `#32` — https://github.com/romanr111/cash-runway/pull/32
