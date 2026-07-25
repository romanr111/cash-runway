---
name: cash-runway-release
description: Cash Runway release preparation workflow. Use when the user asks to create a release, prepare a release branch, bump version tags, open a release PR into main, summarize release changes, group/squash release commits, or trigger a SideStore release for Cash Runway.
---

# Cash Runway Release

## Overview

Prepare a Cash Runway release from `dev` to `main`: create an integration branch, bump the version tag, summarize changes, open a PR, and ready the SideStore release workflow.

## Required context

Before starting, confirm:

1. Target version (e.g. `0.1.3`). If not given, derive it from the latest tag.
2. Whether to update `AppHost/Info.plist` marketing version / build number.
3. Whether to trigger the SideStore workflow immediately or only prepare it.
4. Whether commits on `dev` since the last tag need squashing/restructuring.

## Release workflow

### 0. Prepare the working tree

Before branching, ensure the working tree is clean and generated files are in committed
state — especially `AppHost/AppReportingSecrets.generated.swift` (must have
`isPlaceholder = true`). Stash or revert any unrelated dirt.

### 1. Determine the version

Use `git tag --list --sort=-version:refname` to find the latest tag.
Default bump is the patch component: `v0.1.2` → `v0.1.3`.
Confirm the chosen version with the user before mutating any refs.

### 2. Create the integration branch

Create and check out a release branch from the current `dev` tip:

```bash
git fetch origin dev
git checkout -b release/v<VERSION> origin/dev
```

Use the exact `release/v<VERSION>` naming convention.

### 3. Restructure commits if needed

If `dev` has many small or unrelated commits since the last tag, group them
into logical commits on the release branch. Because the release branch is a fresh
branch from `origin/dev`, interactive rebase on this branch rewrites only the
local release-branch history, not `origin/dev` itself.

Prefer interactive rebase:

```bash
git rebase -i <LAST_TAG>
```

Guidelines:
- Group related changes under a single commit with a clear prefix (`feat:`, `fix:`, `refactor:`, `chore:`).
- Keep separate commits for unrelated features, security/privacy changes, and release-only changes (version bumps, metadata).
- Do not restructure if other branches or worktrees already depend on the exact commit hashes on this release branch.
- If unsure, show the commit list and ask before rebasing.

### 4. Update version metadata

If the user requested a source version update:

- Edit `AppHost/Info.plist`:
  - `CFBundleShortVersionString` → `<VERSION>`
  - `CFBundleVersion` → next appropriate build number
- Default build number: total commit count (`git rev-list --count HEAD`). This is
  monotonic and deterministic from the repo state. Override if the user or
  project convention requires a different number.
- Commit with `chore(release): bump version to v<VERSION>`.

The SideStore workflow will also inject `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` at build time, but source metadata should be consistent.

### 5. Create the release tag

Create an annotated tag on the release branch tip:

```bash
git tag -a v<VERSION> -m "Release v<VERSION>"
```

Push the tag only after the release PR is merged, unless the user explicitly asks to push it early.

### 6. Open the release PR into main

Push the release branch and create a PR into `main`:

```bash
git push -u origin release/v<VERSION>
gh pr create --base main --head release/v<VERSION> --title "Release v<VERSION>" --body-file release-notes.md
```

The PR body must contain:
- High-level summary of changes since the last tag.
- Grouped list of commits/features/fixes.
- Link to the SideStore release workflow.
- Any manual validation gates (physical-device rehearsal, etc.).

Use `scripts/release-notes.py` to generate the draft summary from commits.

### 7. Prepare or trigger SideStore release

The SideStore workflow is `.github/workflows/sidestore-release.yml`. It is triggered manually via `workflow_dispatch` with inputs:

- `version`: marketing version, e.g. `0.1.3`
- `build`: build number (optional, defaults to GitHub run number)

To trigger after the release PR merges:

```bash
gh workflow run sidestore-release.yml -f version=<VERSION> -f build=<BUILD>
```

If the user prefers not to auto-trigger, leave the command in the PR body or as a follow-up note.

### 8. Post-merge actions

After the release PR into `main` is merged:

1. Push the annotated tag to origin:
   ```bash
   git push origin v<VERSION>
   ```
2. Trigger the SideStore release workflow (or leave the command from step 7 in
   the PR body for manual execution):
   ```bash
   gh workflow run sidestore-release.yml -f version=<VERSION> -f build=<BUILD>
   ```
3. Verify the GitHub Release and SideStore source.json are published.

## Safety and confirmation

- State the exact version, branch, tag, and PR operation before executing.
- Ask for explicit confirmation before creating tags, pushing tags, or triggering the SideStore workflow.
- Never force-push the release branch without explicit approval.
- Preserve pre-existing work in other worktrees; do not delete or reset branches or tags you did not create.
- Keep release readiness gates explicit: physical-device rehearsal is required before describing a SideStore build as release-ready.

## Resources

- `references/release-workflow.md` — detailed command reference and examples
- `scripts/release-notes.py` — generate release summary and version suggestion from git history
