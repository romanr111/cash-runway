## Snapshot
- Goal: Fix P0 release blockers that are code-owned: SideStore source metadata and full-backup restore cleanup for Monobank bank sync state.
- Success criteria: SideStore source declares a supported category (`utilities`) and matching photo privacy permission; full restore clears stale bank integrations/accounts/import IDs/category rules atomically and deletes cleared Monobank token Keychain entries; invalid backup failure leaves ledger and bank state unchanged; iOS deployment target raised to 18.0; release workflow requires `just lint && just verify` before building; Git tag releases are marked as prereleases; conflicting `ios-release.yml` workflow removed.
- State: Implemented on isolated worktree branch `codex/sidestore-p0-fixes`.
- Next action: Review/commit/publish if desired. Complete the physical-device SideStore release rehearsal separately; repository validation cannot prove SideStore refresh/update lifecycle behavior.
- Handoff trigger: Rewrite this Snapshot before context compaction, a major task switch, or task completion.

## Git Context
- Repo root: `/Users/roman/.codex/worktrees/cash-runway-sidestore-p0`
- Branch: `codex/sidestore-p0-fixes`
- Base: `main` at `1d10cf4`
- Primary worktree note: `/Users/roman/Documents/Development/Cash Runway` remains on `main` with a pre-existing `AppHost/Localizable.xcstrings` edit outside this branch.

## Working Set
- `.github/workflows/sidestore-release.yml`
- `.swiftlint.yml`
- `CONTINUITY.md`
- `CashRunway.xcodeproj/project.pbxproj`
- `Modules/CashRunwayCorePackage/Package.swift`
- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Sources/CashRunwayCore/Models.swift`
- `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/Models.swift`
- `Sources/CashRunwayUI/AppModel.swift`
- `Tests/CashRunwayCoreTests/FullBackupTests.swift`

## Receipts
- 2026-06-14: Created isolated worktree `/Users/roman/.codex/worktrees/cash-runway-sidestore-p0` on branch `codex/sidestore-p0-fixes`.
- 2026-06-14: `Scripts/pre-flight.sh` passed in isolated worktree; core mirror diff clean before edits.
- 2026-06-14: `just graph-bootstrap`, `just graph-status`, and post-edit `just graph-sync` completed for the isolated worktree.
- 2026-06-14: AltStore docs checked: accepted categories include `utilities`, not `finance`; `appPermissions.privacy` should include `UsageDescription` Info.plist keys.
- 2026-06-14: `python3 -m json.tool altstore.json` passed.
- 2026-06-14: `swift test --filter FullBackupTests` failed red before implementation on stale bank rows/token cleanup, then passed after implementation.
- 2026-06-14: `git diff --check` passed.
- 2026-06-14: Core mirror files remained identical after edits.
- 2026-06-14: First `just check` failed on unrelated/transient `timelineSnapshotGroupsByPeriod()` `readFailed(-67701)`; targeted `swift test --filter timelineSnapshotGroupsByPeriod` passed immediately after.
- 2026-06-14: Second `just check` passed, including iPhone 17 simulator build. Logs: `/tmp/cash-runway-agent-validation/20260614-132045-8587`.

## Open Questions
- SideStore release rehearsal still needs physical-device/manual release validation through `sidestore-release.yml`: install/update same bundle identifier, verify data/Keychain persistence, refresh while locked/backgrounded, and confirm app opens after refresh.
