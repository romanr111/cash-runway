# Cash Runway Release Workflow Reference

## Determine latest tag and next version

```bash
git fetch --tags origin
git tag --list --sort=-version:refname | head -5
```

Default next patch version from `v0.1.2`:

```bash
python3 - <<'PY'
import re, subprocess
tags = subprocess.check_output(["git", "tag", "--list", "--sort=-version:refname"], text=True).splitlines()
latest = next((t for t in tags if re.match(r"v\d+\.\d+\.\d+$", t)), "v0.0.0")
major, minor, patch = map(int, latest[1:].split("."))
print(f"v{major}.{minor}.{patch+1}")
PY
```

## Create release branch

```bash
VERSION="0.1.3"
git fetch origin dev
git checkout -b "release/v${VERSION}" origin/dev
```

## Inspect commits since last tag

```bash
LAST_TAG="v0.1.2"
git log --oneline --no-merges "${LAST_TAG}..HEAD"
```

## Interactive rebase to group commits

```bash
git rebase -i "${LAST_TAG}"
```

Use `pick`, `squash`, `reword`, and `fixup` to produce logical commits. Example targets:

- One commit per feature or fix
- One commit for version/metadata changes
- Security/privacy changes kept separate

## Update Info.plist version

Default build number is the total commit count:

```bash
VERSION="0.1.3"
BUILD="$(git rev-list --count HEAD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" AppHost/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" AppHost/Info.plist
git add AppHost/Info.plist
git commit -m "chore(release): bump version to v${VERSION} (${BUILD})"
```

## Create annotated tag

```bash
VERSION="0.1.3"
git tag -a "v${VERSION}" -m "Release v${VERSION}"
```

## Push branch and tag

```bash
git push -u origin "release/v${VERSION}"
git push origin "v${VERSION}"
```

## Open release PR

```bash
VERSION="0.1.3"
gh pr create \
  --base main \
  --head "release/v${VERSION}" \
  --title "Release v${VERSION}" \
  --body-file release-notes.md
```

## Trigger SideStore release workflow

```bash
VERSION="0.1.3"
BUILD="$(git rev-list --count HEAD)"
gh workflow run sidestore-release.yml -f version="${VERSION}" -f build="${BUILD}"
```

## Example release notes structure

```markdown
## Release v0.1.3

### What's new
- Feature one
- Feature two

### Fixes
- Fix one
- Fix two

### Internal
- Refactor or dependency update

### SideStore
SideStore release workflow: `.github/workflows/sidestore-release.yml`
Run after merge: `gh workflow run sidestore-release.yml -f version=0.1.3 -f build=42`

### Manual gates
- [ ] Physical-device rehearsal completed
```
