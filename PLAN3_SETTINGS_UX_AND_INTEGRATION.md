# PLAN3 — Settings UX, Foreground Sync, and Final Integration

## Goal

Expose Monobank local-first expense sync through a simple Settings flow and wire sync into app foreground refresh.

The user should be able to connect Monobank without understanding implementation details.

## Depends on

- PLAN1 completed.
- PLAN2 completed.
- Monobank client exists.
- BankSyncService exists.
- Bank schema and repository methods exist.

## Product rule

After setup, Cash Runway imports only new Monobank expenses after connection time when the app opens.

Old history is never imported.

Existing Cash Runway history is never rewritten.

## MVP constraints

- Monobank only.
- Personal token only.
- Local-first.
- UAH only.
- Expenses only.
- Start from now.
- No income.
- No old history.
- No backend.
- No webhooks.

## UX principles

1. Make the setup feel safe.
2. Tell the user exactly what will and will not happen.
3. Do not expose unnecessary bank/API terminology.
4. Make account-to-wallet mapping obvious.
5. Show sync status clearly after connection.
6. Never surprise the user with historical imports.

## Code tasks

### 1. Add Settings section

In Settings, add a new section:

```text
Bank Connections
```

Add row:

```text
Monobank
Connect cards and import new expenses automatically
```

Connected state:

```text
Monobank
2 cards connected · Last sync 3 min ago
```

Error state:

```text
Monobank
Sync failed · Tap to fix
```

### 2. Add Monobank connection wizard

Create:

```swift
MonobankConnectionView
MonobankTokenStepView
MonobankAccountSelectionView
MonobankStartConfirmationView
MonobankConnectionStatusView
```

Keep this simple. Use existing Cash Runway visual style.

### 3. Wizard Step 1 — Intro

Show:

```text
Connect Monobank

Cash Runway will import only new Monobank card expenses after connection.

Old bank history will not be imported.
Existing Cash Runway transactions will not be changed.
Income will not be imported.
Your Monobank token stays on this iPhone.
```

Button:

```text
Continue
```

### 4. Wizard Step 2 — Token

Show secure token input:

```text
Personal API token
```

Actions:

```text
Paste from Clipboard
Validate Token
```

Validation behavior:

- Call Monobank `client-info`.
- Do not fetch statements.
- Do not create integration yet unless validation succeeds.
- Show clear error if invalid.

### 5. Wizard Step 3 — Account selection

Display Monobank accounts/cards.

For UAH accounts:

```text
☑ Black card ****1234 · UAH
Map to wallet: [Existing Wallet ▼]
```

For non-UAH accounts:

```text
USD card ****9999 · Not supported in MVP
```

Rules:

- UAH accounts can be enabled.
- Non-UAH accounts are disabled.
- Each enabled account must map to one Cash Runway wallet.
- User can create a new wallet from this step.
- Default wallet name: `Monobank [card name] ****1234`.

### 6. Wizard Step 4 — Final confirmation

This step creates the actual integration.

Show exact timestamp:

```text
Sync starts from now

Cash Runway will import:
• New Monobank expenses after [timestamp]
• Only selected UAH card accounts
• Only outgoing expenses

Cash Runway will not:
• Import old bank history
• Import income
• Modify existing manual, CSV, or recurring transactions
```

Button:

```text
Start syncing new expenses
```

On tap:

1. Set `sync_start_at = Date.now`.
2. Store token in Keychain.
3. Create `bank_integrations` row.
4. Create selected `bank_accounts` rows.
5. Trigger first sync.
6. Reload app data.

Important: no statement data should be fetched before this final confirmation.

### 7. Add connected management screen

After connection, tapping Monobank row opens status screen:

Show:

```text
Monobank connected
Connected accounts: 2
Sync starts from: [timestamp]
Last successful sync: [timestamp]
Imported expenses: [count]
```

Actions:

```text
Sync now
Manage accounts
Disconnect
```

Disconnect behavior:

- Disable integration.
- Delete token from Keychain.
- Do not delete imported transactions.
- Do not delete existing bank import records unless explicitly required later.

### 8. Add foreground sync

In `CashRunwayAppModel.handleForegroundResume()`, add bank sync before snapshot reload:

```swift
try await bankSyncService.syncOnForeground()
try repository.runMaintenance()
try repository.refreshRecurringInstances()
return try Self.loadSnapshot(...)
```

Rules:

- Respect existing foreground throttling.
- Do not run parallel bank sync tasks.
- On sync failure, keep app usable.
- Show non-blocking sync error in Settings/status screen.
- Do not block dashboard rendering for too long.

### 9. Add manual “Sync now”

In Monobank status screen:

```text
Sync now
```

Behavior:

- Calls `bankSyncService.syncOnDemand()`.
- Shows progress.
- Reloads app data after success.
- Shows rate-limit or network message if failed.

### 10. Add category learning prompt

When user edits category of a `bank_sync` transaction:

Show:

```text
Use this category next time?

You changed “SILPO” from Other Expense to Groceries.
Apply Groceries to future SILPO transactions?
```

Actions:

```text
Apply next time
Only this transaction
```

If “Apply next time”:

- Create merchant rule in `bank_category_rules`.
- Future matching merchant imports use that category.

Keep this rule prompt simple. Do not build a complex rules manager in MVP.

### 11. Add privacy-safe diagnostics

In Diagnostics or Monobank status screen, show:

```text
Provider: Monobank
Enabled accounts: 2
Sync start: [timestamp]
Last sync: [timestamp]
Last result: success / failed
Imported expenses: [count]
```

Do not show:

- token
- full IBAN unless already intentionally displayed
- raw statement JSON
- full personal bank payloads in logs

## Explicitly forbidden in this PR

- No old transaction import.
- No income import.
- No automatic backfill option.
- No “import last 30 days” button.
- No auto-match with existing transactions.
- No webhook setup.
- No backend.
- No deleting user history on disconnect.

## UI tests

Add tests for:

```text
Settings shows Bank Connections section
Monobank row opens connection wizard
intro explains no old history and no existing transaction changes
token validation failure shows error
non-UAH accounts are disabled
enabled account requires wallet mapping
final confirmation shows exact sync start timestamp
connection creates active integration
connected screen shows last sync status
disconnect disables integration but does not delete transactions
```

## Integration tests

Add tests for:

```text
first sync after connection imports only post-connection expenses
first sync does not import old bank history
foreground resume triggers bank sync once
foreground resume does not create duplicate transactions
manual Sync now works
sync error does not block app reload
```

## Final acceptance criteria

- User can connect Monobank from Settings.
- User sees clear promise that old history will not be imported.
- User sees clear promise that existing transactions will not be changed.
- User can select only UAH accounts.
- User maps each selected account to a Cash Runway wallet.
- Connection stores immutable `sync_start_at`.
- First sync imports only new post-connection expenses.
- App foreground sync imports later expenses.
- Income is ignored.
- Duplicate statement items are ignored.
- Existing manual/CSV/recurring transactions remain untouched.
- Disconnect removes token but keeps imported transaction history.
