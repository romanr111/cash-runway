## Snapshot

- Goal: Clean up RTK usage in LLM agent documentation so Headroom is the
  default.
- Success criteria: Met. Active Cash Runway and global Codex agent docs now make
  Headroom the default context-optimization layer and no longer teach RTK as the
  default shell-command wrapper.
- State: Documentation-only cleanup.
- Next action: None for this cleanup.
- Handoff trigger: Rewrite this Snapshot before context compaction, a major task
  switch, or task completion.

## Git Context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`
- HEAD: `30ac772` (`docs: update continuity after reporting merge`)
- Worktrees observed:
  - `/Users/roman/Documents/Development/Cash Runway` on `main`
  - `/Users/roman/.codex/worktrees/cash-runway-localization-en-uk` on
    `codex/localization-en-uk`
  - `/Users/roman/.codex/worktrees/cash-runway-reporting-e2e` on
    `codex/reporting-e2e-enable`
  - `/Users/roman/.codex/worktrees/cash-runway-sidestore-release-fix` on
    `codex/sidestore-release-just-fix`
  - `/Users/roman/.codex/worktrees/cash-runway-sidestore-smoke-timeout`
  - `/Users/roman/Documents/Development/cash-runway-phase1-testing` on
    `codex/phase1-testing-improvements`

## Working Set

- `AGENTS.md`: Headroom-default wording tightened.
- `CONTINUITY.md`: Snapshot rewritten for this cleanup.
- `/Users/roman/.codex/AGENTS.md`: RTK instruction block replaced with
  Headroom-default guidance.
- `/Users/roman/.codex/RTK.md`: Reframed RTK as an explicit fallback only.
- `/Users/roman/.codex` is not a git repository.

## Receipts

- 2026-06-14: Removed the global Codex `headroom:rtk-instructions` block and
  the “always prefix with rtk” command-wrapper rule.
- 2026-06-14: Search found no remaining old `headroom:rtk-instructions`,
  `Token-Optimized Commands`, or “always prefix rtk” guidance in the checked
  Cash Runway and `.codex` docs.
- 2026-06-14: `git diff --check` passed for the Cash Runway repository.

## Done Recent

- Reporting screenshot upload work was completed earlier: production reporting
  API uses GitHub Contents uploads, app-submitted Xcode MCP E2E report created
  issue `#54` with a visible `raw.githubusercontent.com` screenshot image, and
  PR `#48` was merged.

## Open Questions

- SideStore release rehearsal still needs physical-device/manual release
  validation through `sidestore-release.yml`: install/update same bundle
  identifier, verify data/Keychain persistence, refresh while locked or
  backgrounded, and confirm app opens after refresh. No repo-side validation can
  prove SideStore refresh/update lifecycle behavior.
