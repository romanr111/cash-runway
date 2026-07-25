---
name: cash-runway-validation
description: Cash Runway validation workflow for choosing and running the correct checks, Xcode simulator builds, build-for-testing compiles, seeded smoke launches, warning triage, validation log scans, PR readiness, DerivedData failures, and avoiding local UI/E2E execution.
---

# Cash Runway Validation

## Core Rules

- Run cheap checks before simulator builds.
- Never run local UI/E2E tests unless the user explicitly requests them.
- Never run parallel Xcode builds that share DerivedData.
- Use isolated DerivedData for `build-for-testing`.
- Search validation/smoke logs; do not grep DerivedData, `.build`,
  SourcePackages, or dependency headers.
- Report known non-blocking warning noise without pasting floods.

## Repo Helper Commands

Prefer the repo's `just` recipes:

- `just check-unit-parallel` for fast unit-focused Swift package tests.
- `just check-integration` for non-performance integration/package tests.
- `just check-perf` for performance timing gates with stale perf-temp cleanup.
- `just mirror-core` after editing canonical `Sources/CashRunwayCore` sources;
  review package mirror edits before using `just mirror-core --force`.
- `just test-isolated` or `just check-isolated` after one SwiftPM stale-state
  or lock-contention failure.
- `just pr-status <PR>` for PR readiness snapshots.
- `just pr-comment <PR> <markdown-file>` for multiline GitHub PR comments.
- If a focused SwiftPM test goes quiet for roughly 60-90 seconds, inspect the
  process state and retry once with `just test-isolated`.
- Do not use `|` alternation with `just test-filter` or `just test --filter`;
  run each filter separately or add a dedicated safe recipe.

## Validation Routing

Read `references/validation-matrix.md` before choosing a validation run.

For `just check-integration` and `just check`, read the retained log first and
report the first relevant failure plus log location before broad reruns.

Default routing:

- UI-only SwiftUI/catalog changes: run `just ui-check`.
- Core/business/persistence/import/export/security changes: start with focused
  tests or `just check-unit-parallel`, then broaden with `just
  check-integration`; run `just check-perf` for performance-sensitive work.
- PR readiness and merge conflict checks: run `just pr-status <PR>`, then
  `just verify` when feasible.
- UI/E2E tests: do not run locally unless explicitly requested.

## Build-For-Testing

If `xcodebuild build-for-testing` fails with missing intermediate files such as
`empty-CashRunwayUITests.plist`, rerun once with isolated `-derivedDataPath`
before treating it as a code failure.

## Warning Triage

Known non-blocking build noise:

- AppIcon size warnings from `AppHost/Assets.xcassets`.
- SQLCipher "not stripping binary because it is signed".
- AppIntents metadata extraction skipped when no AppIntents framework dependency
  exists.
- Existing UI-test main-actor compile warnings in `CashRunwayUITests`.

Report these as known warnings. Do not paste repeated warning floods into the
final answer.

## SwiftPM Signal 9 Stop Rule

If a focused SwiftPM validation command fails before tests run with
`signal 9`, `killed`, or `compile command failed due to signal 9`, treat it as
compiler memory/build-environment pressure until proven otherwise.

Use this sequence:

1. Run the intended focused gate once through the normal `just` recipe.
2. If stale state or lock contention is plausible, retry once with
   `just test-isolated --filter <SuiteOrTest>`.
3. If isolated compilation is killed before tests run, retry once with lower
   concurrency: `just test-isolated --jobs 1 --filter <SuiteOrTest>`.
4. If the isolated build is killed again before tests run, stop retrying
   isolated builds and switch to the cached path:
   `just test --jobs 1 --filter <SuiteOrTest>`.

Do not spend a third attempt on isolated SwiftPM unless the error changes.
Report the isolated gate as a build-environment failure, then report whether the
cached focused test is an equivalent behavioral substitute.

## GitHub Check Triage

After pushing a PR update, run `gh pr checks <PR>`. If a GitHub check fails,
prefer check annotations before full logs:

```bash
gh api repos/romanr111/cash-runway/check-runs/<job_id>/annotations --paginate
```

Use full logs only when annotations are missing or insufficient. Static Analysis
failures often surface the exact SwiftLint file and line only through check-run
annotations.

## Log Summary Helper

Use the bundled helper to summarize run directories under
`/tmp/cash-runway-agent-validation`:

```bash
bash "${SKILL_DIR}/scripts/summarize_cash_runway_validation_logs.sh" \
  /tmp/cash-runway-agent-validation/<run-id>
```

The helper only inspects passed log directories and does not mutate files.
