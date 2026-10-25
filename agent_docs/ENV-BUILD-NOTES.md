
# Cash Runway — build environment notes (2026-10-03)

- Local machine: macOS 15.7.4, Intel i7-8700B, **no Xcode.app** (Command Line Tools 26.3 only).
- Consequence: `swift test` fails "no such module 'Testing'" (SwiftPM can't discover Testing.framework via -I). Do not attempt locally.
- Local compile gate: `swift build --target CashRunwayCore`.
- Real test gates: GitHub Actions `iOS CI` (macos-26): unit tests, integration tests, Xcode app build — run on every PR.
- Prior worktree paths in CONTINUITY.md (/Users/roman/...) reference a different machine; this box is /Users/openclaw.
