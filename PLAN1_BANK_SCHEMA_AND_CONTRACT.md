# PLAN1 — Bank Sync Schema and Safety Contract

## Goal

Prepare Cash Runway for local-first Monobank expense sync by adding the minimum durable data model needed for safe, idempotent bank imports.

This PR must not call Monobank yet and must not change app UI behavior yet.

## Product rule

Bank sync is append-only.

It must never modify, delete, merge, or recategorize existing manual, CSV, or recurring transactions.

## MVP constraints

- Monobank only.
- Personal-token integration only.
- Local-first; no backend.
- Expenses only.
- UAH only.
- No historical backfill.
- Only transactions after `sync_start_at` may be imported.
- No automatic income import.
- No webhook support in this PR.

## Core safety invariants

1. `sync_start_at` is immutable after connection.
2. Bank sync must never import transactions before `sync_start_at`.
3. Bank sync must never import positive amounts.
4. Bank sync must never import non-UAH transactions.
5. Existing Cash Runway transactions must not be matched or rewritten.
6. Idempotency is based only on Monobank statement item ID.
7. Duplicate Monobank item IDs must not create duplicate Cash Runway transactions.

## Code tasks

### 1. Extend transaction source

Add:

```swift
case bankSync = "bank_sync"
```

to `TransactionSource`.

Do not rename existing cases.

### 2. Add bank domain models

Add minimal models:

```swift
public enum BankProvider: String, Codable, Sendable {
    case monobank
}

public enum BankIntegrationStatus: String, Codable, Sendable {
    case active
    case disabled
    case tokenInvalid
    case syncFailed
}

public enum BankTransactionImportStatus: String, Codable, Sendable {
    case imported
    case skipped
    case failed
}
```

Add structs as needed:

- `BankIntegration`
- `BankAccount`
- `BankTransactionImport`
- `BankCategoryRule`

Keep models simple. Do not overbuild provider abstraction beyond what Monobank MVP needs.

### 3. Add database migration

Add migration:

```text
v3_bank_sync
```

Create table:

```sql
CREATE TABLE bank_integrations (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    display_name TEXT NOT NULL,
    status TEXT NOT NULL,
    sync_start_at DATETIME NOT NULL,
    token_keychain_account TEXT NOT NULL,
    last_client_info_sync_at DATETIME,
    last_successful_sync_at DATETIME,
    last_sync_error TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

Create table:

```sql
CREATE TABLE bank_accounts (
    id TEXT PRIMARY KEY,
    integration_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_account_id TEXT NOT NULL,
    wallet_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    account_type TEXT,
    currency_code INTEGER NOT NULL,
    masked_pan TEXT,
    iban TEXT,
    is_enabled BOOLEAN NOT NULL DEFAULT 1,
    sync_start_at DATETIME NOT NULL,
    last_successful_sync_at DATETIME,
    last_statement_item_time INTEGER,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE(integration_id, provider_account_id)
);
```

Create table:

```sql
CREATE TABLE bank_transaction_imports (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    integration_id TEXT NOT NULL,
    bank_account_id TEXT NOT NULL,
    provider_account_id TEXT NOT NULL,
    provider_statement_item_id TEXT NOT NULL,
    statement_time INTEGER NOT NULL,
    amount_minor_signed INTEGER NOT NULL,
    operation_amount_minor_signed INTEGER,
    currency_code INTEGER NOT NULL,
    mcc INTEGER,
    original_mcc INTEGER,
    description TEXT,
    comment TEXT,
    counter_name TEXT,
    counter_iban TEXT,
    receipt_id TEXT,
    hold BOOLEAN,
    raw_json TEXT NOT NULL,
    cash_runway_transaction_id TEXT,
    import_status TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE(provider, provider_account_id, provider_statement_item_id)
);
```

Create table:

```sql
CREATE TABLE bank_category_rules (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    rule_type TEXT NOT NULL,
    merchant_pattern TEXT,
    mcc INTEGER,
    category_id TEXT NOT NULL,
    confidence INTEGER NOT NULL DEFAULT 100,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

Add useful indexes:

```sql
CREATE INDEX idx_bank_accounts_integration ON bank_accounts(integration_id);
CREATE INDEX idx_bank_imports_account_time ON bank_transaction_imports(bank_account_id, statement_time);
CREATE INDEX idx_bank_imports_cash_transaction ON bank_transaction_imports(cash_runway_transaction_id);
CREATE INDEX idx_bank_category_rules_provider_type ON bank_category_rules(provider, rule_type);
```

### 4. Add repository methods

Add minimal repository methods:

```swift
func bankIntegrations() throws -> [BankIntegration]
func activeBankIntegrations() throws -> [BankIntegration]
func bankAccounts(integrationID: UUID) throws -> [BankAccount]
func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount]
func saveBankIntegration(_ integration: BankIntegration) throws
func saveBankAccount(_ account: BankAccount) throws
func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport?
```

Do not implement Monobank networking here.

### 5. Add atomic import foundation

Add repository method signature, but implementation may be completed in PLAN2:

```swift
func importBankExpense(
    provider: BankProvider,
    integration: BankIntegration,
    account: BankAccount,
    externalItem: BankExternalExpenseItem,
    draft: TransactionDraft
) throws
```

This method must eventually:

1. Check whether external item already exists.
2. If exists, skip.
3. If missing, insert bank import row.
4. Insert Cash Runway transaction with `source = .bankSync`.
5. Link bank import row to created transaction.
6. Update aggregates through normal repository path.

## Explicitly forbidden in this PR

- No Monobank HTTP client.
- No Settings UI.
- No foreground sync.
- No webhook code.
- No income support.
- No transaction matching by amount/date/merchant.
- No historical import.

## Tests

Add tests for:

```text
bank sync migration creates required tables
TransactionSource.bankSync encodes as "bank_sync"
bank import uniqueness prevents duplicate provider item IDs
bank integration stores immutable sync_start_at
manual transactions remain untouched by bank schema changes
CSV transactions remain untouched by bank schema changes
recurring transactions remain untouched by bank schema changes
```

## Acceptance criteria

- App builds.
- Existing transaction flows still work.
- Existing CSV import/export still works.
- Existing dashboard/timeline still work.
- New bank tables exist.
- No Monobank network calls exist yet.
- No existing transaction data is changed by migration.
