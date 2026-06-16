## Snapshot

- Goal: Fix SideStore feedback report submission returning server status `404`.
- Success criteria: Existing build `16` can reach the reporting API through the
  currently packaged bare-domain endpoint after deployment, and future SideStore
  releases package the canonical `/api/reports` endpoint.
- State: Fix implemented on `codex/reporting-404-fix`: `reporting-api/vercel.json`
  rewrites `/` to `/api/reports`; the SideStore release workflow trims/appends
  `/api/reports`, persists the normalized URL through `GITHUB_ENV`, and keeps
  `xcodebuild` on the normalized value; regression checks cover both.
- Next action: Commit, push, merge, then verify the Vercel deployment makes
  `https://cash-runway-reporting-api.vercel.app/` reach the report handler
  instead of returning Vercel `404`.

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
