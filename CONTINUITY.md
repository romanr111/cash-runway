Goal: Keep local XcodeBuildMCP session files out of Cash Runway git status.

State:
- Branch: `main`; category import mapping display fix was committed and pushed
  as `b5c3520`.
- `.xcodebuildmcp/` is local tool configuration for XcodeBuildMCP session
  defaults and should not ship with the app.

Implemented:
- Added `.xcodebuildmcp/` to `.gitignore`.

Validation receipts:
- `git status --short` shows only tracked `.gitignore` and `CONTINUITY.md`
  changes before commit.
- `git check-ignore -v .xcodebuildmcp/config.yaml` confirms the ignore rule.
