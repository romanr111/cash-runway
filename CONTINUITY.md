Goal: Review and finalize Monobank/PrivatBank import category mapping UI follow-up on `main`.

State:
- Branch: `main` at `7abc0b7` (`origin/main`).
- Working tree has local, uncommitted category-import changes plus pre-existing
  localization catalog edits.
- `.xcodebuildmcp/` remains untracked and unrelated.
- Core mirrors are in sync:
  `Sources/CashRunwayCore/` matches
  `Modules/CashRunwayCorePackage/Sources/CashRunwayCore/`.

Implemented:
- `CSVImportMapping.categoryMappingDisplayMode(for:)` returns read-only
  `.autoBankRules` for Monobank/PrivatBank mappings when no raw CSV category
  column exists.
- `CSVImportView` displays `Category` as `Auto: MCC / bank rules` for those
  bank presets and keeps the normal optional category-column picker for generic
  CSV and Cash Runway Wallet CSV.
- `CSVService.previewPreparedRows(...)` resolves preview categories through the
  same bank/MCC resolver path used by final import, without inserting
  transactions.
- Monobank regression coverage now verifies MCC preview category detection and
  category-row display mode behavior for bank, generic, and wallet CSV presets.
- Added localized `Auto: MCC / bank rules` / `Авто: MCC / правила банку`.

Validation receipts:
- `Scripts/pre-flight.sh` passed.
- `just test-filter MonobankCSVImportTests` passed.
- `just test-filter MCCCategoryMappingTests` passed.
- `diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore`
  passed.
- `git diff --check` passed.
- `just build` passed.
- `python3 -m json.tool AppHost/Localizable.xcstrings` passed.
- `ruby /Users/roman/.codex/skills/cash-runway-localization/scripts/validate_xcstrings_json.rb AppHost/Localizable.xcstrings`
  failed on pre-existing missing Ukrainian localization entries; the new
  auto-category key has both `en` and `uk` values.
- `just check` passed: mirror diff, whitespace check, full Swift tests, and
  clean iPhone 17 simulator build.

Open:
- Decide whether to keep, split, or clean up the broader pre-existing
  `AppHost/Localizable.xcstrings` semantic/formatting edits before commit.
- `.xcodebuildmcp/` is still untracked and unrelated.
