# Token Efficiency Reference

Concrete patterns to keep token usage low when working on Cash Runway.

---

## Builds

### Default: use the justfile recipe

| Task | Command |
|------|---------|
| iOS build | `just build` |
| Swift tests | `just test` or `just test-filter <pattern>` |
| Full validation | `just check` |
| Smoke tests | `just smoke` |
| Lint | `just lint` |

```bash
just build
```

This already pipes `xcodebuild` through `grep` and only shows warnings, errors,
and the final `BUILD SUCCEEDED` / `BUILD FAILED` line.

**Hard rule:** start with `just build`. Only fall back to raw `xcodebuild` if
you have verified the justfile recipe cannot satisfy the specific need, and
pipe the output to a file.

### When the justfile recipe is insufficient

If you must run `xcodebuild` directly, pipe the output to a file and report only
what matters:

```bash
xcodebuild -scheme CashRunway -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  > /tmp/cashrunway-build.log 2>&1
tail -20 /tmp/cashrunway-build.log
```

For an even quieter run:

```bash
xcodebuild ... -quiet > /tmp/cashrunway-build.log 2>&1 || tail -30 /tmp/cashrunway-build.log
```

### Long builds

Use a background task so the conversation can continue:

```bash
Bash(command="just build", run_in_background=true, description="CashRunway iOS build")
```

The system notifies you when it finishes.

### Result bundles

For full logs without streaming them into the conversation:

```bash
xcodebuild ... -resultBundlePath /tmp/CashRunway.xcresult build
```

Inspect failures later with `xcresulttool` only if needed.

---

## File reads

### Avoid whole-file reads for large files

For files over ~500 lines, locate the symbol first, then read a narrow range.

**Step 1: find the symbol**

```bash
rg -n "func moreRow" Sources/CashRunwayUI/SettingsView.swift
```

or use the Grep tool:

```
Grep(pattern: "func moreRow", path: "Sources/CashRunwayUI/SettingsView.swift",
     output_mode: "content", -n: true)
```

**Step 2: read only the block you need**

```
Read(path: "Sources/CashRunwayUI/SettingsView.swift",
     line_offset: 360, n_lines: 50)
```

### Use CodeGraph for symbol-specific reads

Instead of opening a whole file to inspect one function:

```
mcp__codegraph__codegraph_node symbol:moreRow
  file:SettingsView.swift includeCode:true
```

For broader context:

```
mcp__codegraph__codegraph_explore query: FeedbackReportView submitState
```

### Batch reads in parallel

When you need several files, emit multiple `Read` calls in one response:

```
Read(path: "Sources/CashRunwayUI/FeedbackReportView.swift",
     line_offset: 1, n_lines: 120)
Read(path: "Sources/CashRunwayUI/SettingsView.swift",
     line_offset: 360, n_lines: 50)
Read(path: "Sources/CashRunwayUI/Theme.swift",
     line_offset: 1, n_lines: 60)
```

### Localizable.xcstrings

Never read the full catalog to check one string. Use `Grep` first:

```
Grep(pattern: "\"Feedback\"|\"Report a bug",
     path: "AppHost/Localizable.xcstrings",
     output_mode: "content", -n: true)
```

Then read the 20–30 lines around the match.

Modify it with:

```bash
python3 Scripts/localize-xcstrings.py \
  AppHost/Localizable.xcstrings /tmp/new-strings.json
```

Do not hand-edit the entire catalog.

---

## Screenshots

### Preferred: MCP Xcode screenshot

```
mcp__xcode__screenshot returnFormat:path
```

This returns a small optimized JPEG (typically 368×800).

### Fallback: raw simulator screenshot

If MCP screenshot is unavailable, downsample immediately:

```bash
xcrun simctl io <udid> screenshot /tmp/raw.png
sips -Z 800 /tmp/raw.png --out /tmp/screen.jpg
```

Then read `/tmp/screen.jpg` instead of the PNG.

### When screenshots are unnecessary

- Build success / failure → exit code + error grep.
- Localization loaded → `plutil -p` on generated `.strings` files.
- Code-level UI structure → read the SwiftUI view source; do not screenshot to
  verify view hierarchy.
- Dynamic values (wallet counts, language name, etc.) → trust the data source
  or unit tests.

### Milestone-based screenshot discipline

- Screenshot once after the final design is implemented.
- Screenshot once after the fix is applied.
- Skip intermediate "did the build work?" screenshots.
- For a full flow, use 2–3 MCP screenshots, not 8–10.

For deep UI inspection (view hierarchy, accessibility labels) use Xcode's
View Debugger or a focused UI test, not simulator screenshots.

---

## Logs and diffs

### Keep bulky output out of the conversation

- Preserve complete logs in `/tmp/` or `DerivedData/Logs/`.
- Report only the first relevant failure and the retained log path.
- Use Headroom to compress summaries when you must include them.

### Git diffs

For large generated files (e.g., `Localizable.xcstrings` after a localization
pass), report the summary instead of the full diff:

```bash
git diff --stat AppHost/Localizable.xcstrings
```

Only inspect the actual changed strings, not the entire reformatted catalog.
