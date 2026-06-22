# Cash Runway Token-Efficiency Audit

Date: 2026-06-14

Scope: root agent instructions, scoped agent docs, validation scripts, CI
workflow shape, `CONTINUITY.md`, and coding-agent token-efficiency practices.

Supported agent surfaces: OpenAI Codex, OpenCode, and Kimi Code CLI.

## Decision

Formalize this audit under `docs/testing/` as a durable implementation review.
The original working draft was useful evidence, but it was too compressed to
commit directly. This version records the audit result and the remediation that
landed afterward.

Final status: accept with corrections applied.

## Summary

The repository already had strong executable validation paths: `just` recipes,
`Scripts/agent-validate.sh`, `Scripts/smoke-seeded-simulator.sh`, CodeGraph
bootstrap checks, and CI-owned UI/E2E workflows. The main weakness was prompt
text quality after the instruction refactor: several root and scoped guidance
files had incomplete sentences and missing verbs.

The top three issues have been addressed:

1. Root and scoped instruction prose was repaired.
2. Model and output-routing guidance was added.
3. `CONTINUITY.md` was refreshed for the current task and branch.

## Evidence

Root instructions:
`AGENTS.md` keeps universal safety, validation, CodeGraph, large-file,
localization, and output rules. Classification: implemented after correction.
Impact: high token, high correctness.

Scoped instructions:
`agent_docs/instructions/*.md` keep iOS, API, security, validation, and worktree
guidance out of the root file. Classification: implemented after correction.
Impact: high token.

Model and output routing:
`AGENTS.md` now covers deterministic scripts, Headroom, OpenCode/Kimi smoke
verification, subagents, and escalation. Classification: implemented after
correction. Impact: medium-high token.

Generated and heavy files:
`AGENTS.md` now warns against hand-editing or reading generated, lock, coverage,
`.build`, `DerivedData`, `.codegraph`, and Xcode project files unless required.
Classification: implemented after correction. Impact: medium token and
correctness.

Validation scripts:
`Scripts/agent-validate.sh` checks `git diff --check`, Swift tests, coverage when
requested, and simulator build. Classification: implemented. Impact: high correctness.

Simulator smoke:
`Scripts/smoke-seeded-simulator.sh` builds, launches, captures screenshot/logs,
and filters noisy simulator output. Classification: implemented. Impact: medium
correctness.

Local XCUITest/E2E policy:
`AGENTS.md` and `agent_docs/instructions/validation.md` keep local XCUITest/E2E
off by default; CI owns E2E unless requested. Classification: implemented.
Impact: high correctness.

Worktree isolation:
`Scripts/codegraph-bootstrap.sh` uses `.codegraph/worktree-root`, and
`Scripts/test-codegraph-bootstrap.sh` covers copied-DB rejection.
Classification: implemented. Impact: high correctness.

Continuity ledger:
`CONTINUITY.md` now reflects this isolated worktree and task state.
Classification: implemented after correction. Impact: medium handoff.

## Validation Command Hierarchy

Use the repository entry points instead of recreating command lines:

| Command | Purpose |
| --- | --- |
| `just test <arguments>` | Swift package tests |
| `just ui-check` | UI-only validation wrapper |
| `just check` | `git diff --check`, full Swift tests, simulator build |
| `just smoke` | Deterministic simulator launch and log smoke |
| `just verify` | Full iOS readiness gate |

For reporting API changes, run from `reporting-api/`:

```bash
npm test
npm run typecheck
```

Run `npm audit --omit=dev` when dependencies change or publish-readiness or
security verification is explicitly required.

## Workflow Coverage

Small SwiftUI change:
Load `AGENTS.md`, `ios.md`, and `validation.md`. Run a focused package test or
simulator build, then `just check` when feasible. Status: supported.

Core logic change:
Load `AGENTS.md`, `ios.md`, and `validation.md`. Run focused package tests, then
`just check`. Status: supported.

Persistence or Keychain change:
Load `AGENTS.md`, `ios.md`, `security-privacy.md`, and `validation.md`. Run
focused repository tests, then `just check`. Status: supported.

Reporting API change:
Load `AGENTS.md`, `reporting-api.md`, and `validation.md`. Run `npm test` and
`npm run typecheck`; run `npm audit --omit=dev` if dependencies change. Status:
supported.

Localization change:
Load `AGENTS.md` and `ios.md`. Use `Scripts/localize-xcstrings.py` and review
the catalog diff. Status: supported.

Architectural change:
Load the relevant scoped docs plus `validation.md`. Plan first, run targeted
checks while iterating, and run the completion gate before handoff. Status:
supported.

PR readiness:
Load `AGENTS.md`, `validation.md`, and `worktrees.md`. Run `just verify`; add API
gates if API files changed. Status: supported.

Large-file bug investigation:
Load `AGENTS.md` and the relevant scoped doc. Use CodeGraph first, then targeted
`rg` and narrow line reads. Status: supported.

## Self-QA Findings

No blocking issues remain in the implemented top-three remediation.

Non-blocking follow-ups:

- Decide whether to keep or delete the older local planning draft
  `PLAN_Optimization.md` in the primary checkout.
- Consider archiving older continuity receipts if `CONTINUITY.md` grows again.
- Consider a lightweight local log-retention policy for
  `/tmp/cash-runway-agent-validation/` if disk usage becomes an issue.

## Verification Performed

From the isolated worktree:

```bash
Scripts/pre-flight.sh
git diff --check
just --list
bash -n \
  Scripts/agent-validate.sh \
  Scripts/smoke-seeded-simulator.sh \
  Scripts/codegraph-bootstrap.sh \
  Scripts/pre-flight.sh \
  Scripts/validate-ui-only.sh \
  Scripts/test-codegraph-bootstrap.sh
python3 -m py_compile Scripts/localize-xcstrings.py
```

Result: all checks passed.
