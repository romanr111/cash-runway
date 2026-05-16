# PLAN2 — Monobank Client and Expenses-Only Sync Service

## Goal

Implement the local Monobank personal-token client and bank sync service that imports only new Monobank expenses after connection time.

This PR should focus on core logic, not final Settings UI polish.

## Depends on

- PLAN1 completed.
- `TransactionSource.bankSync` exists.
- Bank sync tables exist.
- Repository has bank integration/account/import primitives.

## Product rule

Only new expenses after connection are imported.

No old history. No income. No rewriting existing transactions.

## MVP constraints

- Monobank only.
- Personal token only.
- Local-first.
- UAH only.
- Expenses only.
- Sync starts at immutable `sync_start_at`.
- Sync uses pull-on-open later, but this PR can expose the service without full UI wiring.

## Core safety invariants

1. Never query before `sync_start_at`.
2. Never import item where `amount >= 0`.
3. Never import item where `currencyCode != 980`.
4. Never modify manual/CSV/recurring transactions.
5. Never dedupe by date/amount/merchant.
6. Dedupe only by:
   - provider
   - provider account ID
   - provider statement item ID

## Code tasks

### 1. Add Monobank DTOs

Add DTOs for:

```swift
MonobankClientInfo
MonobankAccount
MonobankStatementItem
```

Include only fields needed for MVP:

```swift
struct MonobankStatementItem: Decodable, Sendable {
    let id: String
    let time: Int
    let description: String
    let mcc: Int?
    let originalMcc: Int?
    let amount: Int64
    let operationAmount: Int64?
    let currencyCode: Int
    let commissionRate: Int64?
    let cashbackAmount: Int64?
    let balance: Int64?
    let hold: Bool?
    let receiptId: String?
    let comment: String?
    let counterEdrpou: String?
    let counterIban: String?
    let counterName: String?
}
```

Keep decoding tolerant. Optional fields should not break sync.

### 2. Add token store

Add:

```swift
protocol BankTokenStore: Sendable {
    func readToken(account: String) throws -> String?
    func writeToken(_ token: String, account: String) throws
    func deleteToken(account: String) throws
}
```

Use existing Keychain infrastructure.

Never store the raw token in SQLite.

### 3. Add Monobank API client

Add:

```swift
protocol MonobankClient: Sendable {
    func clientInfo() async throws -> MonobankClientInfo
    func statement(accountID: String, from: Date, to: Date) async throws -> [MonobankStatementItem]
}
```

Implementation:

```swift
final class MonobankPersonalAPIClient: MonobankClient {
    ...
}
```

Rules:

- Use `X-Token`.
- Do not log token.
- Do not log raw statement payload.
- Handle HTTP 401/403 as token invalid.
- Handle HTTP 429 as rate limited.
- Handle transient failures cleanly.
- Statement windows must not exceed Monobank’s allowed range.

### 4. Add sync service

Add:

```swift
final class BankSyncService: Sendable {
    func syncOnDemand() async throws -> BankSyncResult
    func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult
}
```

Use this algorithm:

```swift
for integration in activeBankIntegrations {
    for account in enabledBankAccounts(integration.id) {
        guard account.currencyCode == 980 else { continue }

        let lowerBound = integration.syncStartAt

        let from = max(
            account.lastSuccessfulSyncAt?.addingTimeInterval(-6 * 60 * 60) ?? lowerBound,
            lowerBound
        )

        let to = Date.now

        let items = try await monobank.statement(
            accountID: account.providerAccountID,
            from: from,
            to: to
        )

        let importable = items.filter {
            Date(timeIntervalSince1970: TimeInterval($0.time)) >= lowerBound &&
            $0.amount < 0 &&
            $0.currencyCode == 980
        }

        try repository.importMonobankExpenseItems(importable, account: account, integration: integration)

        try repository.markBankAccountSynced(account.id, at: to)
    }
}
```

### 5. Add statement window helper

Add helper to split large ranges:

```swift
func statementWindows(from: Date, to: Date) -> [DateInterval]
```

Rules:

- Max range: 31 days.
- For MVP, because sync starts from now, ranges will normally be small.
- Still implement safely for long app inactivity.

### 6. Add import mapping

Map Monobank item to `TransactionDraft`:

```swift
TransactionDraft(
    kind: .expense,
    walletID: account.walletID,
    amountMinor: abs(item.amount),
    occurredAt: Date(timeIntervalSince1970: TimeInterval(item.time)),
    categoryID: categoryMapper.resolve(...),
    labelIDs: [],
    merchant: item.counterName ?? item.description,
    note: item.comment ?? "",
    source: .bankSync
)
```

### 7. Add category mapper

Add simple categorization:

```swift
final class BankCategoryMapper {
    func resolve(
        merchant: String?,
        description: String,
        mcc: Int?,
        originalMcc: Int?
    ) throws -> UUID
}
```

Resolution order:

1. Merchant rule.
2. MCC rule.
3. Built-in MCC mapping.
4. `Other Expense`.

Keep built-in MCC mapping small and practical for MVP:

```text
Groceries
Restaurants
Transport
Health
Shopping
Entertainment
Travel
Other Expense
```

Do not use AI/LLM categorization in MVP.

### 8. Implement idempotent repository import

Implement:

```swift
func importMonobankExpenseItems(
    _ items: [MonobankStatementItem],
    account: BankAccount,
    integration: BankIntegration
) throws -> BankSyncImportResult
```

For each item:

1. Re-check filters defensively:
   - `time >= sync_start_at`
   - `amount < 0`
   - `currencyCode == 980`
2. Check existing import by unique external ID.
3. If exists, skip.
4. Create `TransactionDraft(source: .bankSync)`.
5. Save transaction.
6. Insert `bank_transaction_imports` row.
7. Link import row to transaction ID.

All of this must be atomic per item or per batch.

### 9. Hold transaction policy

MVP policy:

```text
Import hold == true items as expenses.
If same statement item appears again, dedupe by statement ID.
Do not create duplicates.
Do not modify unrelated existing transactions.
```

Optional update of raw import metadata is allowed, but avoid complex settlement reconciliation in MVP.

## Explicitly forbidden in this PR

- No historical backfill.
- No income import.
- No non-UAH import.
- No webhook setup.
- No provider/corporate API.
- No auto-matching against existing manual/CSV transactions.
- No deleting imported transactions when token fails.

## Tests

Add tests for:

```text
sync does not query before sync_start_at
sync skips item before sync_start_at
sync imports negative UAH item after sync_start_at
sync skips positive amount
sync skips zero amount
sync skips non-UAH item
sync dedupes same Monobank statement item ID
sync does not modify manual transaction with same date/amount/merchant
sync does not modify CSV transaction with same date/amount/merchant
sync does not modify recurring transaction with same date/amount/merchant
category mapper merchant rule wins
category mapper MCC fallback works
Other Expense fallback works
rate limit returns safe error
invalid token marks integration as tokenInvalid
```

## Acceptance criteria

- Monobank client can validate token through `client-info`.
- Sync service can import new expenses after `sync_start_at`.
- Sync service imports no old transactions.
- Sync service imports no income.
- Sync service imports no non-UAH transactions.
- Running sync twice creates no duplicates.
- Existing manual/CSV/recurring transactions remain untouched.
- Imported transactions appear with `source = bank_sync`.
