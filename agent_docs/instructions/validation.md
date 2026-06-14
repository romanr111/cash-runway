# Validation Instructions

Use the smallest validation set that provides sufficient confidence during
implementation. Use the required completion gate once the change is ready.

## Terminology

- **Targeted package tests:** selected Swift unit or integration tests.
- **Full package tests:** the unfiltered Swift package unit/integration suite.
- **Simulator build:** compile the application for an iOS Simulator.
- **Simulator smoke:** install, launch, capture evidence, and scan runtime logs.
- **XCUITest/E2E:** UI automation owned by CI unless explicitly requested.

Full package tests are not XCUITest/E2E.

## Validation matrix

| Change type | During implementation | Before completion |
| --- | --- | --- |
| Documentation or agent instructions only | Path and reference review | `git diff --check`; syntax-check changed scripts |
| UI presentation only | Relevant targeted build | `just ui-check` |
| Core business logic | Targeted package tests | `just check` |
| Persistence, imports, exports, Keychain, or security | Focused tests | `just check` |
| Reporting API only | Targeted API tests/typecheck | Full API tests and typecheck |
| Mixed iOS and API change | Targeted checks for both areas | iOS and API completion gates |
| PR or publish readiness | Targeted checks as needed | `just verify`; add API gates if API files changed |
| XCUITest/E2E | Do not run locally by default | CI unless explicitly requested |

## Execution rules

- Use targeted tests while iterating.
- Re-run the smallest failing test until the defect is fixed.
- Do not repeatedly rerun successful broad suites during implementation.
- Run the required completion gate after implementation stabilizes.
- Preserve complete command output in files outside model context.
- Surface compact success output.
- On failure, surface the first relevant failure, enough surrounding context to
  diagnose it, and the complete log path.
- Report every skipped required gate and the reason.
- Do not substitute screenshot inspection for required package tests or builds.
- Do not treat simulator smoke as XCUITest.

## Repository commands

Use repository entry points instead of rebuilding command lines:

```text
just test <arguments>  → Swift package tests
just ui-check          → UI-only validation
just check             → mirror, diff, full package tests, simulator build
just smoke             → deterministic simulator launch and log smoke
just verify            → complete iOS readiness gate
```

The scripts and `justfile` are the executable source of truth.
