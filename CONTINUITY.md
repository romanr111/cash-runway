<!--
Rules:
- Rewrite Snapshot to current truth on every meaningful update.
- Meaningful update: file modified, decision made, blocker hit/resolved, task completed/abandoned, or verification result changed.
- Reading or searching does not trigger a rewrite.
- Omit Git context for non-repo tasks.
- Omit Worktree detail when working directly in the primary checkout.
- Current state: one sentence, past tense, what is true true.
- Next action: one imperative sentence, one concrete step.
- Merge status: not-merged | merged | abandoned | superseded | unknown.
- Worktree reason: dirty-primary | isolated-feature | ci-fix | hotfix | review | experimental.
- Ownership: glob patterns only.
- Receipts: decisions, commits, PRs, failures, unusual tool outcomes only.
- If file exceeds 120 lines, compress Done (recent) into milestone bullets.
-->

## Snapshot

- Goal: Apply SwiftUI Expert Skill improvements to Cash Runway — fix P0/P1 performance bottlenecks (DB query in view body, N+1 queries, non-lazy lists, DateFormatter allocation, deleteWallet batching) and decompose SettingsView state.
- Success criteria: All P0 and P1 issues resolved, swift test passes, app builds and boots on simulator, mirrored core stays in sync.
- Current state: New worktree created at `../Cash-Runway-swiftui-performance-improvements` on branch `kimi/swiftui-performance-improvements`; sub-agents not yet spawned.
- Next action: Spawn three sub-agents in the new worktree to execute the performance fixes in parallel.
- Open questions: None.
- Merge status: not-merged.

## Git context

- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Working directory: `/Users/roman/Documents/Development/Cash-Runway-swiftui-performance-improvements`
- Branch: `kimi/swiftui-performance-improvements`
- Base branch: `origin/main`
- Worktree reason: isolated-feature
- Merge status: not-merged

## Working set

- `Sources/CashRunwayUI/DashboardView.swift`
- `Sources/CashRunwayUI/Editors.swift`
- `Sources/CashRunwayUI/SettingsView.swift`
- `Sources/CashRunwayUI/AppModel.swift`
- `Sources/CashRunwayCore/CashRunwayRepository.swift`
- `Sources/CashRunwayCore/Theme.swift`
- `AppHost/CashRunwayApp.swift`
- `CONTINUITY.md`

## Done (recent)

- 2026-05-31 [AUDIT] Three explore agents completed full SwiftUI Expert Skill audit of the codebase.
- 2026-05-31 [PLAN] Performance-First improvement plan approved by user.
- 2026-05-31 [SETUP] Created worktree `../Cash-Runway-swiftui-performance-improvements` on branch `kimi/swiftui-performance-improvements`.

## Receipts

- 2026-05-31 [DECISION] Use separate worktree because primary checkout had local edits.
