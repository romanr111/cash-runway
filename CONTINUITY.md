Goal: Implement workflow helpers for faster Cash Runway validation, core mirror sync, PR status/comment safety, isolated SwiftPM retries, and related agent documentation.

State:
- Worktree: `/Users/roman/.codex/worktrees/cash-runway-workflow-validation-helpers`
- Branch: `codex/workflow-validation-helpers`
- Base: `origin/main` at `854c4a0`
- Main checkout had pre-existing edits and was left untouched.

Implemented:
- Added `just check-unit-parallel`, `just check-integration`, `just check-perf`, `just test-isolated`, `just check-isolated`, `just mirror-core`, `just pr-status`, and `just pr-comment`.
- Added scripts:
  - `Scripts/check-perf.sh`
  - `Scripts/mirror-core.sh`
  - `Scripts/pr-comment.sh`
  - `Scripts/pr-status.sh`
- Updated `AGENTS.md`, `agent_docs/instructions/ios.md`, `agent_docs/instructions/validation.md`, and `agent_docs/instructions/worktrees.md`.
- Updated global skill files:
  - `/Users/roman/.codex/skills/cash-runway-validation/SKILL.md`
  - `/Users/roman/.codex/skills/cash-runway-validation/references/validation-matrix.md`

Validation:
- `Scripts/pre-flight.sh` passed before edits.
- `bash -n Scripts/check-perf.sh Scripts/mirror-core.sh Scripts/pr-comment.sh Scripts/pr-status.sh` passed.
- `just --summary` lists all new recipes.
- `just mirror-core` passed and confirmed core sources are in sync.
- `just pr-status` passed local status checks and skipped GitHub checks without a PR argument.
- `git diff --check` passed.
- `just check-unit-parallel` passed.
- `just check-integration` passed.
- `just test-isolated --filter ModelSerializationTests` passed.
- `just check-perf` now runs through the cleaned perf wrapper, but the existing `fixturePopulationTimingGate` failed at about 95 seconds against a 30 second threshold. Earlier stale perf temp data caused disk-full failures; `Scripts/check-perf.sh` now cleans stale perf temp data before and after the run.

Open:
- Decide whether to tune or investigate `fixturePopulationTimingGate`; this is separate from the workflow-helper implementation.
