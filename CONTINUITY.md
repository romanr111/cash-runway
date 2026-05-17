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

- Goal: Optimize the GitHub Actions E2E path after run `26000733696` spent most of its time in a stuck UI test.
- Success criteria: E2E has per-test timeout guardrails, build/test are combined in one E2E job without a redundant prerequisite build job, the flaky recurring-switch UI helper waits for the observable state change, targeted validation passes, and a PR is open against `origin/main`.
- Current state: PR `#13` was opened from `codex/e2e-ci-optimization` with the E2E workflow optimization and recurring-switch UI-test hardening.
- Next action: Monitor GitHub Actions on PR `#13` and address any CI-only failures.
- Open questions: None.
- Merge status: not-merged.
- Worktree reason: ci-fix.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/.codex/worktrees/cash-runway-e2e-ci-optimization`
- Branch: `codex/e2e-ci-optimization`
- Base branch: `origin/main`

## Working set

- `.github/workflows/ios-ci.yml`
- `Tests/CashRunwayUITests/TransactionCRUDUITests.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-17 [TOOL] Created isolated worktree `/Users/roman/.codex/worktrees/cash-runway-e2e-ci-optimization` on branch `codex/e2e-ci-optimization` because the primary checkout had a local `CONTINUITY.md` edit.
- 2026-05-17 [ANALYSIS] GitHub Actions run `26000733696` showed E2E consumed `41m27s`; `Run UI E2E tests` consumed `40m48s`; `testComposerPreservesDraftWhenOpeningLabelsAndRepeatSheets` failed after `1740.782s`.
- 2026-05-17 [CODE] Removed the separate `ios-app-build` job and changed E2E to build for testing once, then run Monobank, overview, and transaction UI suites with `test-without-building`.
- 2026-05-17 [CODE] Added E2E per-test timeout caps: default `120s`, maximum `180s`, with diagnostics collected on failure.
- 2026-05-17 [FIX] Hardened the transaction recurring-switch helper to wait for the switch value after the coordinate tap required by the SwiftUI switch.
- 2026-05-17 [VERIFY] YAML parsing passed for `.github/workflows/ios-ci.yml`.
- 2026-05-17 [VERIFY] `xcodebuild build-for-testing` succeeded on iPhone 17 simulator.
- 2026-05-17 [VERIFY] `testComposerPreservesDraftWhenOpeningLabelsAndRepeatSheets` passed after rebuilding the UI-test bundle.
- 2026-05-17 [VERIFY] `TransactionFlowUITests` passed with `test-without-building` and the new timeout options.
- 2026-05-17 [VERIFY] Full `swift test` passed 219 tests in 21 suites after 134.117s.
- 2026-05-17 [TOOL] Committed the implementation as `af5afb3` and opened PR `https://github.com/romanr111/cash-runway/pull/13`.

## Receipts

- 2026-05-17 [TOOL] Primary checkout was on `main` at `cd8a309` with only `CONTINUITY.md` modified before this worktree was created.
- 2026-05-17 [TOOL] `xcodebuild -help` confirmed support for `-test-timeouts-enabled`, `-default-test-execution-time-allowance`, `-maximum-test-execution-time-allowance`, `build-for-testing`, and `test-without-building`.
- 2026-05-17 [TOOL] `gh api repos/romanr111/cash-runway/branches/main/protection` returned `Branch not protected`, so removing the exact `iOS App Build` check name should not block branch protection.
- 2026-05-17 [TOOL] Local `swiftlint` executable was not installed, so local SwiftLint validation was skipped; GitHub Actions will run repository lint.
- 2026-05-17 [TOOL] `swift test` emitted existing GRDB Sendable warnings while compiling vendored code.
