# Cash Runway Validation Matrix

## UI-Only SwiftUI Or Catalog Changes

Use for visual presentation, localized text, and UI catalog edits.

Preferred command:

```bash
just ui-check
```

Do not run unfiltered `swift test` unless business logic, persistence, parsing,
imports, security, mirrored core sources, merge conflicts, or publish readiness
are involved.

## Core, Business, Or Persistence Changes

Use when `Sources/CashRunwayCore` or mirrored package files change, or when code
touches data safety, imports, exports, encryption, category merge, recurring
transactions, repository queries, or migrations.

Preferred sequence:

```bash
just mirror-core
git diff --check
just check-unit-parallel
just check-integration
```

Apply mirrored core edits to canonical `Sources/CashRunwayCore/`, then run
`just mirror-core`. If the package mirror has local edits, review them before
using `just mirror-core --force`.

Run focused tests with `just test-filter '<suite or test>'` when that is the
smallest useful gate. Run `just check-perf` when performance-sensitive code
changed or before final PR signoff; it removes stale Cash Runway perf-test temp
data before running.

If SwiftPM appears blocked by stale build state or lock contention, retry once
with:

```bash
just test-isolated
```

or:

```bash
just check-isolated
```

## Import, Export, Or Security Changes

Run focused import/export/security tests first, then broaden:

```bash
just test-filter '<import/export/security suite or test>'
just check-unit-parallel
just check-integration
```

For Keychain or database encryption changes, add a simulator build and
launch/log smoke after package tests.

## PR Readiness

Start with a status snapshot:

```bash
just pr-status <PR>
```

Then run `just verify` unless the user explicitly asks for a narrower gate or
the environment blocks it. Keep repo validation, runtime smoke, backend/API
reachability, and release readiness as separate status buckets.

Use file-backed PR comments:

```bash
just pr-comment <PR> <markdown-file>
```

## Build-For-Testing

For simulator compile-only checks, use isolated DerivedData. Do not run this in
parallel with another clean build or validation script.

## Simulator Smoke

Use deterministic seeded smoke:

```bash
just smoke
Scripts/smoke-seeded-simulator.sh category_editor category_management
```

If runtime snapshots are empty, use screenshot evidence plus runtime/os log scan
instead of retrying interactive taps repeatedly.

## UI/E2E Policy

Do not run local UI/E2E tests unless the user explicitly requests them. CI owns
UI/E2E execution. Compiling UI tests with `build-for-testing` is allowed.

## Known Warning Noise

Summarize these as known warnings instead of pasting repeated warning floods:

- AppIcon size warnings.
- SQLCipher signed binary strip warning.
- AppIntents metadata extraction skipped.
- Existing UI-test main-actor compile warnings.
