Goal: Deduplicate and Modularize CashRunwayCore — Phase 1

Branch: `codex/dedup-core-module`
Worktree: `/Users/roman/.codex/worktrees/cash-runway-dedup-core`

Structural changes:
- Root `Package.swift` defines `CashRunwayCore` target directly with GRDB + CoreXLSX dependencies.
- Nested `Modules/CashRunwayCorePackage/` deleted.
- `Scripts/mirror-core.sh` deleted.
- `Scripts/generate-reporting-secrets.swift` writes only to canonical tree.
- Xcode build phase updated to single output path.
- Coverage configs (`agent-validate.sh`, `coverage.sh`, `ios-nightly.yml`) use `/Sources/CashRunwayCore/` path with zero-files guard.
- `justfile` updated (mirror-core removed).
- `AGENTS.md`, `ios.md`, `validation.md`, `worktrees.md` updated with canonical tree rule.
- `.swiftlint.yml` updated.
- Pre-flight script now validates Xcode target membership for all CashRunwayCore files.

CI / dependency locking:
- `.gitignore` no longer ignores `Package.resolved`.
- Root `Package.resolved` and Xcode workspace `Package.resolved` committed.
- Added `source-membership-check` and `app-build` jobs to `.github/workflows/ios-ci.yml`.
- Unit tests, integration tests, and app build now run in parallel after static analysis.

Validation receipts (after rebase onto origin/main):
- `swift build --target CashRunwayCore` — BUILD SUCCEEDED
- `just build` (Xcode simulator) — BUILD SUCCEEDED
- `just lint` — 1 pre-existing `empty_enum_arguments` in `CSVImportView.swift` (out of scope)
- `swift test --enable-code-coverage` — 380 tests, 35 suites passed
- `Scripts/coverage.sh` — 88.78% (7781 / 8764 lines), threshold 85% met; Core files found successfully.
- Source membership check — all 14 canonical files present in Xcode app target.
- Rebase preserved newest canonical `CSVSupport.swift` and tests from `main`.

Known follow-ups:
- Root SPM and Xcode workspace `Package.resolved` currently pin different SQLCipher versions (4.15.0 vs 4.14.0). This pre-existing divergence on `main` remains; a follow-up should reconcile them.
- `empty_enum_arguments` lint warning in `CSVImportView.swift` is pre-existing.
