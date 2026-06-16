# Verification Strategies

Choose the cheapest verification method that gives confidence for the task.

## Decision table

| Goal | Preferred verification | Avoid |
|------|------------------------|-------|
| Code compiles | `just build` exit code + error grep | Full xcodebuild logs |
| Swift logic works | `just test` or `just test-filter <pattern>` | Simulator launch + manual check |
| Localization strings loaded | `plutil -p` on generated `.strings` files | Screenshot of every label |
| View exists / is wired | Read the SwiftUI source | Screenshot of static layout |
| Visual layout / spacing | MCP Xcode screenshot at final state | Raw 1206×2622 PNGs |
| Full user flow | 2–3 MCP screenshots at milestones | Screenshot after every build |
| Deep UI hierarchy | Xcode View Debugger or focused UI test | Guessing from screenshots |
| End-to-end behavior | `just smoke` | Manual simulator tapping |

---

## Build verification

Use the existing justfile recipe:

```bash
just build
```

If it fails, read only the filtered output. Do not paste full logs into the
conversation. Preserve the complete log at a known path:

```bash
just build > /tmp/cashrunway-build.log 2>&1
tail -30 /tmp/cashrunway-build.log
```

---

## Localization verification

After modifying `AppHost/Localizable.xcstrings`, build and inspect the generated
strings files:

```bash
plutil -p DerivedData/.../Products/Debug-iphonesimulator/CashRunway.app/en.lproj/Localizable.strings | grep "Feedback"
plutil -p DerivedData/.../Products/Debug-iphonesimulator/CashRunway.app/uk.lproj/Localizable.strings | grep "Feedback"
```

A single launch screenshot in the target language is enough to confirm the UI
uses the strings. Do not screenshot every screen.

---

## Visual verification

### Preferred: MCP Xcode screenshot

```
mcp__xcode__screenshot returnFormat:path
```

Returns an optimized JPEG (~20–50 KB, 368×800).

### Fallback: downsampled raw screenshot

If MCP screenshot fails:

```bash
xcrun simctl io <udid> screenshot /tmp/raw.png
sips -Z 800 /tmp/raw.png --out /tmp/screen.jpg
```

Read `/tmp/screen.jpg`, not the PNG.

### When to skip screenshots entirely

- Verifying that code compiles.
- Verifying that localized strings exist in the catalog.
- Verifying dynamic values driven by known data sources.
- Verifying view hierarchy wiring (read the source).

---

## Full-flow verification

For complete feature validation, use the project's smoke test:

```bash
just smoke
```

Do not manually tap through the simulator unless the smoke test is unavailable
or the task explicitly requires physical-device rehearsal.
