# Validation Instructions

Use the smallest validation set that gives useful confidence during
implementation. Run the required completion gate once the change is stable.

## Terminology

- Targeted package tests: selected Swift unit or integration tests.
- Full package tests: Swift unit, integration, and performance tests.
- Simulator build: compile for iOS Simulator.
- Simulator smoke: install, launch, capture evidence, and scan runtime logs.
- XCUITest/E2E: UI automation owned by CI unless explicitly requested.

## Validation Matrix

| Change type | Early checks | Completion gate |
| --- | --- | --- |
| Docs or agent instructions | `git diff --check` | `just pr-status <PR>` when PR context exists |
| UI presentation | `just ui-check` or simulator build | `just check` when feasible |
| Core business logic | `just check-unit-parallel`, `just test-filter <pattern>` | `just check-integration`, `just check-perf` when relevant, then `just check` |
| Persistence, imports, exports, Keychain | focused repository tests | `just check` |
| Reporting API only | `npm test`, `npm run typecheck` in `reporting-api/` | API gates plus `just pr-status <PR>` |
| Mixed iOS changes | targeted tests and simulator build | `just verify` |
| XCUITest/E2E | Do not run locally unless explicitly requested | GitHub Actions |

## Reporting

- Surface compact success output.
- On failure, surface the first relevant failure and the complete log path.
- Report every skipped required gate and the reason.
- Do not substitute screenshot inspection for required package tests or builds.
- Do not treat simulator smoke as XCUITest.

## Repository Commands

Use repository entry points instead of rebuilding command lines:

```text
just test <arguments> -> Swift package tests
just test-filter <pattern> -> focused Swift package tests
just check-unit-parallel -> fast unit-focused Swift package tests
just check-integration -> non-performance integration/package tests
just check-perf -> performance timing gates with stale perf-temp cleanup
just test-isolated <arguments> -> Swift package tests with isolated scratch path
just check-isolated -> full Swift package tests with isolated scratch path
just mirror-core -> sync mirrored CashRunwayCore package sources
just ui-check -> UI-only validation
just check -> mirror diff, git diff check, full package tests, simulator build
just smoke -> deterministic simulator launch and log smoke
just verify -> complete iOS readiness gate
just pr-status <PR> -> local/PR readiness summary without running long gates
just pr-comment <PR> <markdown-file> -> multiline PR comment via --body-file
```

The scripts and `justfile` are the executable source of truth.

## Gates

- Small Swift/UI changes: run focused package tests or a simulator build that
  exercises the change, then run `just check` before handoff when feasible.
- Core logic changes: start with `just check-unit-parallel` or
  `just test-filter <pattern>`, run `just check-integration` for broader
  package coverage, and run `just check-perf` when performance-sensitive code
  changed or before final PR signoff. `just check-perf` removes stale
  Cash Runway perf-test temp data before running.
- Persistence or Keychain changes: run focused repository tests and `just check`.
- If SwiftPM failures look like stale build state or lock contention, retry once
  with `just test-isolated` or `just check-isolated`.
- Reporting API changes: run `npm test` and `npm run typecheck` from
  `reporting-api/`.
- Localization changes: use `Scripts/localize-xcstrings.py` and review the
  catalog diff.
- PR readiness: run `just pr-status <PR>` for the status snapshot, then
  `just verify` unless the user explicitly asks for a narrower gate or the
  environment blocks it.

## Self-Review Proportionality

Perform a full second pass, including re-reading changed files, checking for
orphans, and verifying logic for:

- multi-file changes touching more than three files;
- architectural or API changes;
- security-sensitive changes such as Keychain, database encryption, or auth.

For low-risk changes, `git diff --stat` plus targeted grep is enough:

- single-file comment-only changes;
- simple test disables with explicit reasons;
- deprecation comments with no behavior change.
