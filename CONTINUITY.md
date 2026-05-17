<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true now.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Finish the first-launch data behavior change and publish it as a PR into `origin/main`.
- Success criteria: Fresh first launch no longer creates fake starter wallets/budgets/transactions, fixture and UI-test paths seed their own test data, validation passes, and a PR is open against `origin/main`.
- Current state: PR `#10` had a local fix for the failing CI E2E Monobank UI tests, and targeted local Monobank UI validation passed.
- Next action: Push the CI fix and confirm GitHub Actions reruns for PR `#10`.
- Open questions: None.
- Merge status: not-merged.
- Worktree reason: isolated-feature.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data`
- Branch: `codex/stop-fake-data`
- Base branch: `origin/main`

## Working set

- `AppHost/UITestRuntime.swift`
- `Sources/CashRunwayCore/**`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/**`
- `Sources/CashRunwayUI/**`
- `Tests/CashRunwayCoreTests/**`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-17 [TOOL] Started from the preserved clean worktree `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data` on `codex/stop-fake-data`.
- 2026-05-17 [TOOL] Confirmed no open GitHub PR existed for the branch before publishing.
- 2026-05-17 [CODE] Rebased the feature branch onto current `origin/main` and resolved first-pass conflicts in `CONTINUITY.md` and `CSVEdgeCaseTests.swift`.
- 2026-05-17 [CODE] Completed the rebase as commits `c80d4ac` and `fc43bea`; second-pass conflicts kept current-main bank sync, backup/restore, and UI-test keychain behavior while preserving explicit fixture-wallet seeding.
- 2026-05-17 [FIX] Updated post-main BankSync and CSV idempotency tests to seed fixture wallets explicitly now that fresh `seedIfNeeded()` no longer creates wallets.
- 2026-05-17 [VERIFY] Focused affected suite run passed 51 tests across `CSVIdempotencyTests`, `BankSyncImportTests`, `BankSyncServiceTests`, `BankConnectionServiceTests`, `BankSyncSchemaTests`, and `RepositoryUncoveredTests`.
- 2026-05-17 [VERIFY] Full `swift test` passed 219 tests in 21 suites after 131.489s.
- 2026-05-17 [VERIFY] iPhone 17 simulator clean build ended `** BUILD SUCCEEDED **`.
- 2026-05-17 [VERIFY] iPhone 17 simulator launch succeeded as `dev.roman.cashrunway: 29261`; screenshot showed Timeline loaded with empty/no-data state.
- 2026-05-17 [TOOL] Pushed `codex/stop-fake-data` and opened PR `https://github.com/romanr111/cash-runway/pull/10` into `main`.
- 2026-05-17 [FIX] Fixed PR `#10` E2E failure from run `25992692058` / job `76402468097`: the shared UI-test boot wait assumed `transaction.addButton`, but the Monobank first-start scenario now correctly starts with zero wallets and hides that button.
- 2026-05-17 [FIX] Updated Monobank UI tests to create the Monobank wallet mapping from account selection before continuing to sync.
- 2026-05-17 [VERIFY] Targeted `xcodebuild test -only-testing:CashRunwayUITests/MonobankConnectionUITests` passed 3 tests on iPhone 17 simulator.
- 2026-05-15 [CODE] Changed `seedIfNeeded()` so fresh databases create default categories only; fake starter wallets, budgets, and transactions are no longer created on first launch.
- 2026-05-15 [CODE] Updated fixture, UI-test, and unit-test setup paths to seed wallets explicitly when tests need transaction-capable data.
- 2026-05-15 [CODE] Added zero-wallet UI guards and empty states so first launch remains usable without fake data.

## Receipts

- 2026-05-17 [TOOL] `git worktree list` showed primary checkout plus `/Users/roman/.codex/worktrees/cash-runway-stop-fake-data`.
- 2026-05-17 [TOOL] `gh auth status` confirmed GitHub CLI authentication for `romanr111`.
- 2026-05-17 [TOOL] `git rebase origin/main` stopped on `CONTINUITY.md` and `Tests/CashRunwayCoreTests/CSVEdgeCaseTests.swift`; conflicts were resolved manually.
- 2026-05-17 [TOOL] `diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore` returned clean after rebase.
- 2026-05-17 [TOOL] Local `swiftlint` executable was not installed, so local SwiftLint validation was skipped; GitHub Actions will run repository lint.
- 2026-05-17 [TOOL] Simulator startup log check found no crash/fatal/exception/error lines for `CashRunway`; only a non-fatal AMFI simulator message matched the broad predicate.
- 2026-05-17 [TOOL] GitHub Actions E2E failure log showed all three Monobank UI tests failing at `CashRunwayUITestCase.swift:26` with `Timeline did not finish bootstrapping`; other UI suites passed.
- 2026-05-17 [CODE] Decision: preserve current-main concise continuity format and discard stale legacy ledger blocks during conflict resolution.
