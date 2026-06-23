Goal: Resolve code-review findings on the CashRunwayCore modularization PR stack.

Branch: `codex/consume-core-module` (PR #70, top of stack)
Worktree: `/Users/roman/.codex/worktrees/cash-runway-dedup-core`

# Stack state (all rebased onto origin/main; nothing merged)
- PR #66 `codex/dedup-core-module`            — head 59fabd9 — CLEAN
- PR #69 `codex/core-reporting-config-extraction` — head 1dd822b — CLEAN
- PR #70 `codex/consume-core-module`          — head 2f4f382 — UNSTABLE
  (UNSTABLE only because its base is an open PR; no conflicts/failing checks)
Backup refs: refs/backups/pr{66,69,70}-before-rebase

# Migration / integration target
- Phase 2 implementation is COMPLETE (dedup + reporting-config + consume product).
- Ultimate integration target: `dev`. This migration must NOT enter `main` directly.
- `dev` is created from current `origin/main` (same commit), not from any PR branch.
- Targeted stack:
  dev ← PR #66 ← PR #69 ← PR #70  (only #66 retargets to dev; #69/#70 stay stacked)
- Integration order: #66→dev, rebase+retarget #69, #69→dev, rebase+retarget #70,
  #70→dev, then full validation + device testing on dev, then a separate dev→main PR.
- Nothing has been merged; no PR directly targets `main`.

# Done (this session) — review fixes
- Replaced brittle `Scripts/check-core-module-wiring.sh` (hardcoded Sources
  phase ID `A00600010001000100010001` + sed/awk section regex) with a real
  parser: `Scripts/check_core_module_wiring.py` walks project.pbxproj via
  `plutil -convert xml1` + plistlib. The old `.sh` is now a thin `exec` shim so
  pre-flight.sh and ios-ci.yml callers are unchanged. Reports "24 file(s)
  checked" by resolving real PBXFileReference paths — no IDs, no regex.
- Narrowed `Scripts/smoke-seeded-simulator.sh` ignore list: removed the four
  bare patterns (`FontServices`, `XPC_ERROR_CONNECTION_INTERRUPTED`,
  `interruptionHandler`, `Re-initialization successful`) that could mask app
  errors; replaced with subsystem-anchored `com\.apple\.FontServices` and
  `com\.apple\.xpc:connection`. Verified: 3 known benign sim lines still
  suppressed; a synthetic app-subsystem (`dev.roman.cashrunway`) XPC error is
  now correctly surfaced.

# Done (prior sessions, verified by full review)
- Phase 1 dedup (#66), reporting-config extraction (#69), consume product (#70).
- Destructive-recovery Release guard (`#if !DEBUG fatalError`) — confirmed safe:
  only callers of `allowsDestructiveRecovery: true` are DEBUG-guarded
  (AppHost/CashRunwayApp.swift:288, AppHost/UITestRuntime.swift:114) and tests;
  `CashRunwayRepository.init` defaults to false. No Release path can pass true.
- Reporting secret precedence: bundled secret authoritative, Keychain is cache,
  DEBUG env wins+persists, nothing logged.
- Module-wiring, CoreXLSX cleanup, smoke-noise, Release config wrapper.

# Validation (this session)
- py_compile + bash -n on both scripts — OK
- `Scripts/check-core-module-wiring.sh` (via shim) — all 5 checks pass
- smoke regex suppression/anti-mask test — pass
- `git diff --check` — clean
- `bash Scripts/verify-pbxproj.sh` — OK
- `just lint` — 0 violations / 78 files
- Not re-run (justified): swift build/tests — change is scripts-only
  (two .sh + one new .py); no Swift/Package.swift/pbxproj touched.

# Deferred follow-up (by user decision)
- Review "nice-to-have" CI coverage job (full 388-test suite instrumented with
  --enable-code-coverage) — intentionally NOT implemented. Risk: instrumented
  slow tests exceed local timeout and would need CI timeout/parallelism tuning;
  could introduce flakiness. Revisit if CI-side coverage reporting is needed.

# Full-suite validation status (from prior review, unchanged this session)
388 tests pass (373 fast + 14 perf + 1 property); Core coverage 87.55%;
Debug+Release sim builds SUCCEEDED; `just smoke` pass; CI green for all 3 PRs
(Static Analysis, Source Membership, Unit, Integration, Xcode App Build; UI
E2E skipped). SQLCipher pinned 4.15.0 / 967b937 in both Package.resolved files.
