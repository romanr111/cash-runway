# Cash Runway Behavior-Risk Matrix

| ID | Area | Behavior | Risk | Primary validation layer | Target suite | Status |
|---|---|---|:-:|---|---|---|
| CR-001 | Ledger | Wallet balances match transaction ledger | 5 | Integration | LedgerInvariantTests | Phase 1 |
| CR-002 | Transactions | Create transaction preserves ledger correctness | 5 | Integration | LedgerInvariantTests | Phase 1 |
| CR-003 | Transactions | Edit transaction recalculates derived values | 5 | Integration | LedgerInvariantTests | Phase 1 |
| CR-004 | Transactions | Delete transaction removes its ledger effect | 5 | Integration | LedgerInvariantTests | Phase 1 |
| CR-005 | Transfers | Transfer preserves total net worth while moving value between wallets | 5 | Integration | LedgerInvariantTests | Phase 1 |
| CR-006 | Aggregates | Aggregate/dashboard summary matches raw transaction ledger after reload/rebuild | 5 | Integration | LedgerInvariantTests | Phase 1 |
| CR-007 | Categories | Category merge preserves transaction count and totals | 5 | Integration | CategoryIntegrityTests | Phase 1 |
| CR-008 | Categories | Category delete/reassign leaves no orphan references | 4 | Integration | CategoryIntegrityTests | Phase 1 (merge covered); Phase 2 (delete) |
| CR-009 | Monobank | Only selected UAH expenses are imported | 5 | Integration | MonobankSyncRuleTests / BankSyncImportTests / BankSyncServiceTests | Phase 2 |
| CR-010 | Monobank | Income, non-UAH, and pre-connection transactions are ignored | 5 | Integration | MonobankSyncRuleTests / BankSyncImportTests / BankSyncServiceTests | Phase 2 |
| CR-011 | Monobank | Repeated/overlapping sync is idempotent | 5 | Integration | MonobankSyncRuleTests / BankSyncServiceTests | Phase 2 |
| CR-012 | Monobank | Sync does not mutate manual/CSV/recurring transactions | 5 | Integration | BankSyncImportTests | Phase 2 |
| CR-013 | CSV | CSV import/export preserves ledger correctness | 4 | Integration | CSVImportExportIntegrityTests / CSVIdempotencyTests | Phase 2 |
| CR-014 | CSV | CSV import handles malformed rows safely | 4 | Integration | CSVEdgeCaseTests / CSVIdempotencyTests | Phase 2 |
| CR-015 | Backup | JSON backup/restore recreates equivalent domain state | 5 | Integration | FullBackupTests | Phase 2 |
| CR-016 | Backup | Backup/export does not include secrets or bank tokens | 5 | Integration | FullBackupTests | Phase 2 |
| CR-017 | UI launch | App launches and seeded dashboard renders | 3 | Seeded smoke | Future smoke validation | Future |
| CR-018 | UI workflow | Add transaction happy path works | 2 | UI/E2E smoke | CI-only UI smoke | Future |

## Phase 2 Blockers

### CR-008 (delete/reassign)

Category merge is exposed via `mergeCategory(oldCategoryID:into:)` and is covered in Phase 1.

A dedicated **category delete API that reassigns transactions** is not exposed below the UI layer in the current repository. The app UI may perform this via a private or UI-bound flow. Until a clean repository-level `deleteCategory(reassignTo:)` API exists, the delete half of CR-008 remains blocked.
