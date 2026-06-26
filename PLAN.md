# Plan: Custom Wallet Categories

## Goal

Allow users to create reusable, persistent custom wallet categories from the wallet editor, while preserving the four built-in categories, migrating existing wallets safely, keeping financial data unchanged, and maintaining backup/restore compatibility.

## Decisions

- **Backup format**: new exports use version 2; validation accepts versions 1 and 2; version-1 imports still work by mapping legacy `WalletKind` to built-in categories.
- **Legacy `wallets.kind`**: kept as a maintained semantic fallback; the authoritative wallet category is the new `category_id` column. This avoids destructive table recreation.

## Data model

- `WalletKind` remains unchanged (`cash`, `card`, `account`, `other`).
- New `WalletCategory` struct: `id`, `name`, `kind`, `isSystem`, `createdAt`, `updatedAt`.
  - Built-ins have stable UUIDs and names equal to the English keys; display uses existing `L10n.walletKind(...)`.
  - Custom categories have `isSystem = false` and `kind = .other` as the explicit safe semantic fallback.
- `Wallet` gains `categoryID: UUID` and keeps `kind: WalletKind` as a maintained fallback.
- `CashRunwayBackup` gains `walletCategories: [BackupWalletCategory]` and exports version 2.
- `BackupWallet` gains `categoryID: UUID?` and keeps `kind: WalletKind` for backward compatibility.

## Database migration `v5_custom_wallet_categories`

1. Create `wallet_categories` table.
2. Insert four built-in category rows with fixed UUIDs.
3. `ALTER TABLE wallets ADD COLUMN category_id TEXT`.
4. Backfill `category_id` from existing `kind` values.
5. Keep `wallets.kind` unchanged.

## Repository changes

- `walletCategories()` — return built-ins first, then custom categories.
- `saveWalletCategory(_:)` — trim, reject empty/whitespace-only, reject case-insensitive duplicates (including built-in names).
- `saveWallet(_:)` — persist `category_id` and keep `kind` synchronized from the category.
- `exportFullBackup()` — export `wallet_categories` and include `categoryID` in each wallet; version 2.
- `restoreFullBackup()` — import `wallet_categories` before wallets; for version-1 backups derive categories from `kind`.
- `clearSourceTables()` — also delete from `wallet_categories`.
- `BackupValidator` — accept versions 1 and 2; validate wallet category references in version 2.

## UI changes

- `AppModel`:
  - Add `walletCategories: [WalletCategory]`.
  - Load them in the snapshot pipeline.
  - Add `saveWalletCategory(_:)` wrapper.
- `WalletEditorView`:
  - Replace `WalletKind` picker with a picker bound to `wallet.categoryID`.
  - Items: built-in categories + custom categories + `New Wallet Category` action.
  - Selecting the action opens a focused sheet to create a category.
  - On save: validate, persist, reload, auto-select.
  - On cancel: dismiss, preserve draft, preserve previous selection, no persistence.
- `TransactionsView` wallet row subtitle shows resolved category display name.
- Other wallet creation sites keep using built-in `kind` values; default category mapping handles them.

## Localization

Use `Scripts/localize-xcstrings.py` to add:

- `New Wallet Category`
- `Category Name`
- `A category with this name already exists.`
- `Category name cannot be empty.`

## Tests

New file: `Tests/CashRunwayCoreTests/WalletCategoryTests.swift`

1. Built-in wallet categories remain available.
2. Migration maps each existing `WalletKind` to the correct built-in category.
3. Existing wallet IDs, balances, transactions preserved during migration.
4. Creating and persisting a custom wallet category works.
5. Empty and whitespace-only names rejected.
6. Case-insensitive duplicate-name rejection, including built-in names.
7. Assigning a custom category to a new wallet.
8. Changing an existing wallet category leaves financial values unchanged.
9. Custom category reusable across multiple wallets.
10. New backup export/restore round-trips custom categories and assignments.
11. Older version-1 backups remain importable and map to built-ins.
12. Backup validation rejects dangling wallet-category references.

Updates to existing tests:

- `RepositoryCRUDTests.swift` — wallet category references.
- `MigrationIntegrityTests.swift` — v5 migration coverage.
- `FullBackupTests.swift` — version 2 assertions.
- `TestDataBuilders.swift` — `WalletBuilder` can set `categoryID`.
- `ModelSerializationTests.swift` — `WalletKind` raw-value stability still passes.

No XCUITest, screenshot, or coordinate-based tests.

## Validation gates

After implementation:

1. `Scripts/pre-flight.sh`
2. `just graph-bootstrap`
3. `just check-unit-parallel`
4. `just check-integration`
5. `just lint`
6. `just build`
7. `just smoke` (if simulator available)

Every skipped gate will be reported with the reason.
