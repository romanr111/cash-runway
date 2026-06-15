## Snapshot

- Goal: Commit and push project-specific high-value agent-instruction
  recommendations.
- Success criteria: Project `AGENTS.md` includes mirrored-core verification,
  validation-bucket separation, and explicit SideStore physical-device release
  gate guidance. `CONTINUITY.md` reflects the project-only commit state.
- State: Complete.
- Next action: None for this task.

## Git Context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- HEAD before commit: `2dd1a67`
- Files touched for project commit:
  - `AGENTS.md`
  - `CONTINUITY.md`
- Global `/Users/roman/.codex/AGENTS.md` was updated locally outside this repo
  and is not part of this project commit.

## Receipts

- 2026-06-15: Added Cash Runway guidance for mirrored core verification,
  status-bucket separation, and the SideStore physical-device release gate.
- 2026-06-15: Restored the concrete SideStore manual-check list after
  self-review.
- 2026-06-15: Documentation-only task; no build or test suite was run.

## Done (recent)

- SideStore smoke-timeout worktree review: timeout/logging hardening remained
  useful for the opaque long `Run validation gate`, but not for the already
  fixed missing-`just` failure. Targeted shell checks passed in the timeout
  worktree.
- RTK cleanup: active Cash Runway and global Codex agent docs now make Headroom
  the default context-optimization layer and treat RTK as an explicit fallback.

## Open Questions

- SideStore release rehearsal still needs physical-device/manual release
  validation through `sidestore-release.yml`: install/update same bundle
  identifier, verify data/Keychain persistence, refresh while locked or
  backgrounded, and confirm app opens after refresh. Repo-side validation cannot
  prove SideStore refresh/update lifecycle behavior.
