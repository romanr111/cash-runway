# PR 124 — evidence-of-work

Generated locally on the PR head (`7cb96d8`, `feature/issue-122-retrospective-export`)
in worktree `~/projects/cash-runway-ev124` (branch `evidence-pr-124`).

## Environment (honest limitations)

- This Mac has **Command Line Tools only** (`xcode-select -p` = `/Library/Developer/CommandLineTools`):
  no Xcode.app, no iOS simulators → the UI flow shown in the PR screenshots could not be
  re-exercised here, and no UI screenshots are included. Evidence below is produced by the
  PR's actual Swift code (the exporter used by Settings → Data → Export Monthly Retrospective),
  built and run headless.
- CLT's Swift (6.2.4) **lacks the swift-testing runtime** (`libTesting.dylib`): the PR's test
  targets use `import Testing`, so the first `swift test` attempt failed with
  `error: no such module 'Testing'` (log: `test-logs/test-export-suite-initial-clt-failure.log`).
- Fix: the official swift.org/macOS package `swift-6.2.4-RELEASE-osx.pkg` was downloaded and
  extracted (pkgutil/xar; no admin needed) into a user-local toolchain
  `~/Library/Developer/Toolchains/swift-6.2.4-RELEASE.xctoolchain`, which ships the missing
  `Testing` module. All builds/tests/exports below ran with it (same Swift version, apple target).
- `swift build` also succeeds with **plain CLT** (exit 0, ~110 s) — only swift-testing is missing there.
- Docker 29.2.1 was available as a fallback but not needed.

## What ran (all real, all traced)

| Command | Result | Log |
|---|---|---|
| `swift build` (CLT, target CashRunwayCore et al.) | exit 0 (`Build complete! (110.35s)`) | noted in README (scratch dir kept out of repo) |
| `swift build --scratch-path .build-toolchain` (extracted toolchain) | exit 0 (`Build complete! (138.40s)`) | noted here |
| `swift test --filter MonthlyRetrospectiveExportTests` | **exit 0 — 12/12 passed** | `test-logs/test-export-suite.log` |
| `swift test --filter MonthlyRetrospectiveXLSXTests` | **exit 0 — 3/3 passed** | `test-logs/test-xlsx-suite.log` |
| evidence harness (real exporter, sample data) | exit 0, artifacts written | `test-logs/harness-run.log` |
| `unzip -l` on the generated .xlsx | exit 0, 5 OOXML parts | `test-logs/xlsx-unzip-listing.log` |
| CoreXLSX round-trip (in-harness) | `ROUND_TRIP_STATUS=OK`, 7 rows, sheet `Retrospective` | `test-logs/xlsx-corexlsx-roundtrip.log` |

## Generated artifacts (`generated/`)

Built by calling the PR's real API path — `MonthlyRetrospectiveExport.rows(from:)` →
`.csv(rows:)` → `MonthlyRetrospectiveXLSX.export(csvRows:)` → `ExportFile.name(from:to:format:)` —
on realistic sample snapshot data: 2 currencies (UAH, EUR) × 3 months (2026-04…2026-06),
one approximate rate (April UAH rate is a nearest-earlier fallback, effective 2026-04-28,
flagged `Approximate=yes`; the harness mirrors the snapshot service's half-up USD rounding).

- `cash-runway-retrospective-2026-04-2026-06.csv` (1 035 bytes) — RFC-4180 CSV, header + 6 rows
- `cash-runway-retrospective-2026-04-2026-06.xlsx` (5 380 bytes) — minimal OOXML archive;
  `file` reports `Microsoft Excel 2007+`; parts: `[Content_Types].xml`, `_rels/.rels`,
  `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/worksheets/sheet1.xml` (sheet name
  `Retrospective`, inline strings + numeric cells)
- `csv-export-table.png` (44 318 bytes) — the CSV rendered as an image table (Pillow), label:
  "Cash Runway retrospective export — CSV rendered as image"

Harness source (throwaway, committed only as documentation of exactly what ran):
`tooling/evidence-harness-main.swift` (compiled via `tooling/assemble-evidence-harness.sh`
against the PR build's swiftmodules/objects — no Package.swift or PR code was modified),
`tooling/render-csv-png.py` (CSV → PNG renderer).

## Reproduce

```bash
TC=~/Library/Developer/Toolchains/swift-6.2.4-RELEASE.xctoolchain
PATH="$TC/usr/bin:$PATH" swift build --scratch-path .build-toolchain
PATH="$TC/usr/bin:$PATH" swift test --scratch-path .build-toolchain --filter MonthlyRetrospective
bash tooling/assemble-evidence-harness.sh   # builds .build-toolchain/evidence-runner
.build-toolchain/evidence-runner docs/evidence/pr-124/generated
```

Note: XLSX round-trip verification is additionally covered — and passing — by the PR's own
CI-visible test `MonthlyRetrospectiveXLSXTests.xlsxRoundTripsThroughCoreXLSX` (see test log).