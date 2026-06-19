Snapshot
- Goal: Add MCC and Ukrainian bank-category-name fallback mapping for CSV bank imports, preserving Cash Runway Wallet round-trip.
- Success criteria: Bank-imported transactions resolve sensible categories from MCC and Ukrainian category names; legacy Cash Runway Wallet CSV imports preserve exact category labels; `swift test` and `just build` pass; core mirror stays in sync.
- State: Curated per-MCC mapping, deterministic generator with `--check` mode, conservative Ukrainian/Russian bank-category-name mapper, source-aware `BankCategoryResolution` resolver, CSV/XLSX wired through the resolver, bank-sync aligned, categoryID validation in `commitCSVImport`, and regression tests are complete. `just check` passed, `swift test` passed, `just build` succeeded, `just lint` clean, core mirror `diff -r` clean.
- Next action: Merge after final code review; no further implementation work is required.

Git Context
- Repo root: `/Users/roman/Documents/Development/Cash Runway`
- Branch: `main`

Receipts
- 2026-06-17: PrivatBank XLSX import implemented: `XLSXConverter` converts the first worksheet to CSV; `CSVService` detects PrivatBank headers and maps signed card-currency amounts to income default; UI row renamed to “Import Bank Statement” and document picker accepts `.xlsx`.
- 2026-06-17: `CashRunway.xcodeproj/project.pbxproj` updated to include `Sources/CashRunwayCore/XLSXConverter.swift` and link the remote `CoreXLSX` package.
- 2026-06-17: `swift test` passed (333 tests); `just build` succeeded for iOS Simulator.
- 2026-06-18: Initial MCC and Ukrainian bank-category-name mapping added.
- 2026-06-19: Revised implementation per self-QA: replaced broad MCC group mapping with curated per-MCC table; added deterministic generator with `--check`; narrowed bank-category keyword matching with word-aware logic; introduced source-aware `BankCategoryResolution` with explicit precedence; wired CSV/XLSX and bank sync through the resolver; added categoryID validation in commit; added precedence and round-trip regression tests. `just check`, `swift test`, `just build`, `just lint` all pass; core mirror clean.
