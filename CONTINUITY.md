# Continuity Ledger

## Snapshot — current branch

**Branch:** `codex/arch-phase-5-agent-access-design`
**PR:** https://github.com/romanr111/cash-runway/pull/89 — Phase 5.0: AgentAccess foundation
**State:** synced with `dev`; awaiting final CI/merge
**Base:** `dev` at `670b2a0`

## Active work

### AgentAccess foundation — synced and ready for merge

Security/scope fixes pushed to PR #89; second review fixes applied:

- Multi-wallet transaction scope fetches per selected wallet and merges results.
- Universal egress redaction applies to every read endpoint.
- Bank sync errors sanitized via `AgentBankSyncHealth`; raw `lastSyncError` removed.
- Consent version enforced; stale grants rejected with `.invalidConsentVersion`.
- Overview scope requires `monthKey` to overlap the session `dateScope`; multi-wallet overview aggregates per-wallet snapshots.
- `AgentMoneyDTO` replaces hardcoded `"UAH"` money fields.
- Stable canonical SHA-256 scope hash replaces `String.hash`.
- Typed `AgentCapability.auditOperation` replaces raw audit strings.
- Hard scope upper bounds (`maxTransactionCount <= 100`, `lastDays <= 365`).
- `.readRecurring` capability removed.
- `AgentAbuseBoundaryTests.swift` expanded with regression tests.

### Sync with `dev` (commit `670b2a0`)

- Merged `origin/dev` into `codex/arch-phase-5-agent-access-design`.
- Resolved conflicts in `AGENTS.md` and `CONTINUITY.md`.
- `CashRunway.xcodeproj/project.pbxproj`, `Package.swift`, and UI VM files were auto-merged by Git; require build verification.

## Validation after sync

| Gate | Result |
|---|---|
| `swift build --target CashRunwayCore` | pending |
| `swift test --filter Agent` | pending |
| `just check-unit-parallel` | pending |
| `just lint` | pending |
| `Scripts/pre-flight.sh` | pending |
| `Scripts/check-no-ungated-logging.sh` | pending |
| `Scripts/check-unchecked-sendable.sh` | pending |
| GitHub PR checks | pending |

## Next steps

1. Verify all required gates pass.
2. Push synced branch to origin.
3. Confirm GitHub CI is green and PR is mergeable.
4. Merge PR #89.

## Archive

Historical phases and resolved incidents moved to `agent_docs/reference/ledger-archive.md`.
