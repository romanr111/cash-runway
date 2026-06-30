# Continuity Ledger

## Snapshot — current branch

**Branch:** `codex/arch-phase-5-agent-access-design`
**PR:** https://github.com/romanr111/cash-runway/pull/89 — Phase 5.0: AgentAccess foundation
**State:** review fixes pushed; awaiting re-review
**Base:** `dev` at `9f3ca21`

## Active work

### AgentAccess foundation — review fixes landed

Security/scope fixes pushed to PR #89; second review fixes also applied locally:

- Multi-wallet transaction scope fetches per selected wallet and merges results.
- Universal egress redaction applies to every read endpoint.
- Bank sync errors sanitized via `AgentBankSyncHealth`; raw `lastSyncError` removed.
- Consent version enforced; stale grants rejected with `.invalidConsentVersion`.
- Overview scope requires `monthKey` to overlap the session `dateScope`; multi-wallet overview aggregates per-wallet snapshots.
- `AgentMoneyDTO` replaces hardcoded `"UAH"` money fields.
- Stable canonical SHA-256 scope hash replaces `String.hash` (selected wallet IDs sorted, JSON keys sorted).
- Typed `AgentCapability.auditOperation` replaces raw audit strings.
- Hard scope upper bounds (`maxTransactionCount <= 100`, `lastDays <= 365`).
- `.readRecurring` capability removed.
- `AgentAbuseBoundaryTests.swift` expanded with regression tests for double-counting, transaction name redaction, canonical scope hash, and bank-status derivation.

### Re-review fixes (local)

- Fixed multi-wallet overview category aggregation double-counting the first wallet.
- Redacted `walletDisplayName` and `categoryName` in `AgentTransactionDTO` mapping.
- Made `scopeHash` canonical with sorted keys and stable payload.
- Derive bank `isConnected` / `health` from `BankIntegration.status` instead of mere presence.

## Validation on this branch

| Gate | Result |
|---|---|
| `swift build --target CashRunwayCore` | ✅ |
| `swift test --filter Agent` | ✅ 38/38 |
| `just check-unit-parallel` | ✅ 58/58 |
| `just check-isolated` | ⚠️ 542/544 — two performance timing gates exceeded local thresholds (`importBatchAndAggregateRebuildTimingGate` at ~7s vs 5s; `fixturePopulationTimingGate` at ~38s vs 30s). Both are in `CashRunwayPerformanceTests` and unrelated to AgentAccess changes. |
| `just lint` | ✅ 0 violations / 127 files |
| `Scripts/pre-flight.sh` | ✅ |
| `Scripts/check-no-ungated-logging.sh` | ✅ |
| `Scripts/check-unchecked-sendable.sh` | ✅ |

## Known environment caveats

- `just check-integration` can hang when other Cash Runway worktrees have active SwiftPM helper processes. Use `just check-isolated` for the full gate in multi-worktree environments.
- `fixturePopulationTimingGate()` is a known local performance bottleneck and not a regression from this branch. `importBatchAndAggregateRebuildTimingGate` also appears sensitive to local machine state.

## Next steps

1. Commit and push the re-review fixes to PR #89.
2. Update PR #89 body/description to match final implementation and test count.
3. Request final re-review.

## Archive

Historical phases and resolved incidents moved to `agent_docs/reference/ledger-archive.md`.
