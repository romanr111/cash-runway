## Rebuilt head onto `dev` — conflicts resolved

The base branch `feature/issue-121-usd-retrospective` was already merged as #122 into `dev` (merge commit `9738df0`), so this PR's base pointed at already-consumed history while its head still carried **12 duplicate, pre-review-fix copies** of the #121 commits. GitHub saw 10 conflicting files; retargeting alone would not have fixed it (simulated with `git merge-tree` — same conflict set either way).

**Resolution:** rebuilt the head as a fresh squash-merge of the export stack onto `dev`:

- All 12 duplicate #121 pre-image commits dropped — dev already carries their review-fixed versions.
- The 15 export commits' content preserved **byte-identical**: `git diff 52803eb <new-head> -- Sources/CashRunwayCore/Export Tests/.../MonthlyRetrospective{Export,XLSX}Tests.swift Package.swift` is empty (verified programmatically). This includes the review fixes `7a595b6` (XLSX `inlineStr` + CSV formula-injection neutralization) and `52803eb` (mixed-base-currency guard).
- 9 of 10 conflicted files were byte-identical on both sides (verified via blob hashes against `origin/dev` before resolving) — resolved to dev's content, a no-op.
- `AppModel.swift` was the only real integration: kept dev's wallet-scoped `refreshRetrospectiveUSDSnapshots()` / `monthlyUSDMonthAggregates(walletID:)` engine, added the PR's `exportMonthlyRetrospective(format:)` pipeline + BackgroundWork actor path on top.
- `docs/evidence/pr-124/*` artifacts carried over unchanged.

**Local gates at new head `d0388b6`** (`dev` + 1 merge/squash commit):

| Gate | Command | Result |
|---|---|---|
| Export suites | swift.org 6.2.4 toolchain `swift test --filter MonthlyRetrospective` | **19/19 passed** (Export 15 + XLSX 4) |
| Static analysis | `swiftlint lint --strict` | **0 violations, 0 serious, 178 files** |
| History hygiene | duplicate commit subjects in `origin/dev..HEAD` | none (programmatic check) |
| Mergeability | `git merge --no-commit --no-ff origin/dev` | already up-to-date (dev is ancestor) |

Environment note: local gates run with CLT + user-local swift.org 6.2.4 toolchain (no full Xcode sim run possible locally); the real unit/integration/Xcode-UI gates run in CI, same as before.

Base is now retargeted to `dev`.