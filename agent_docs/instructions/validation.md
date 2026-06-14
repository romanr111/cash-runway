# Validation Instructions

Use the smallest validation set that gives useful confidence during
implementation. Run the required completion gate once the change is stable.

## Terminology

- Targeted package tests: selected Swift unit or integration tests.
- Full package tests: the unfiltered Swift package unit/integration suite.
- Simulator build: compile the application for an iOS Simulator.
- Simulator smoke: install, launch, capture evidence, and scan runtime logs.
- XCUITest/E2E: UI automation owned by CI unless explicitly requested.

Full package tests are not XCUITest/E2E.

## Validation Matrix

| Change type | During implementation | Before completion |
| --- | --- | --- |
| Docs or agent instructions only | Path/reference review | `git diff --check`; script syntax checks |
| UI presentation only | Relevant targeted build | `just ui-check` |
| Core business logic | Targeted package tests | `just check` |
| Persistence, imports, exports, Keychain, or security | Focused tests | `just check` |
| Reporting API only | Targeted API tests/typecheck | Full API tests and typecheck |
| Mixed iOS and API change | Targeted checks for both areas | iOS and API completion gates |
| PR or publish readiness | Targeted checks as needed | `just verify`; add API gates if API files changed |
| XCUITest/E2E | Do not run locally by default | CI unless explicitly requested |

## Output Handling

- Preserve complete raw logs outside model context.
- Surface compact success output.
- On failure, surface the first relevant failure, enough context to diagnose it,
  and the complete log path.
- Report every skipped required gate and the reason.
- Do not substitute screenshot inspection for required package tests or builds.
- Do not treat simulator smoke as XCUITest.

## Repository Commands

Use repository entry points instead of rebuilding command lines:

```text
just test <arguments>  -> Swift package tests
just ui-check          -> UI-only validation
just check             -> mirror diff, git diff check, full package tests, simulator build
just smoke             -> deterministic simulator launch and log smoke
just verify            -> complete iOS readiness gate
```

The scripts and `justfile` are the executable source of truth.

## Completion Gates

- Small Swift/UI changes: run focused package tests or a simulator build that
  exercises the change, then run `just check` before handoff when feasible.
- Core logic changes: run focused Swift package tests first, then `just check`.
- Persistence or Keychain changes: run focused repository tests and `just check`.
- Reporting API changes: run `npm test` and `npm run typecheck` from
  `reporting-api/`.
- Localization changes: use `Scripts/localize-xcstrings.py` and review the
  catalog diff.
- PR readiness: run `just verify` unless the user explicitly asks for a narrower
  gate or the environment blocks it.

## Self-Review Proportionality

Perform a full second pass, including re-reading changed files, checking for
orphans, and verifying logic for:

- multi-file changes touching more than three files;
- architectural or API changes;
- security-sensitive changes such as Keychain, database encryption, or auth.

A quick `git diff --stat` plus targeted grep is sufficient for:

- single-file comment-only changes;
- simple test disables with explicit reasons;
- deprecation comments with no logic changes.
