# Savings Wallets ("Окремі заощадження") Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a new wallet type — savings / long-term investments — visible inside "Ручні гаманці" but visually distinct, opt-out of every shared aggregate via a "Separate entity" toggle, and surfaced in its own app section (mirrors Roman's "Investments in Myself" Apple Note).

**Architecture:** Extend `WalletKind` with a `savings` case (gives type semantics, localized name, built-in look) and add a persisted `is_excluded_from_summary` flag (the "separate entity" toggle). Aggregation scope SQL in `CashRunwayRepository` learns to exclude flagged wallets unless one is explicitly selected. UI: sectioned Manual Wallets list, editor toggle, dashboard wallet-menu section, savings total rendered separately from the global total.

**Tech stack:** Swift 6 / SwiftUI / GRDB (SQLCipher) / SwiftPM + Xcode dual-compile, `just` recipes for validation.

---

## Current Context (verified against code)

- `Wallet` struct: `Sources/CashRunwayCore/Models.swift:603` (kind, categoryID, colorHex, iconName, balances, currencyCode, isArchived, sortOrder).
- `WalletKind` enum: `Models.swift:3` (`cash`, `card`, `account`, `other`); built-in `WalletCategory` rows with reserved UUIDs `22222222-…-22–25` at `Models.swift:35-88`, `allBuiltIn` at `:70`.
- Schema: `wallets` table created in migration `v1_schema` (`DatabaseManager.swift:377`), `category_id` added in v5-era line `:761`, `currency_code` in `v8_currency_foundation` (`:950`). Migration list is append-only; `MigrationIntegrityTests` asserts the exact identifier sequence (`Tests/CashRunwayCoreTests/MigrationIntegrityTests.swift:16-35`).
- Shared aggregates that must skip flagged wallets:
  - All-wallet total: `CashRunwayRepository.swift:918` (`SUM(current_balance_minor) WHERE is_archived = 0`).
  - `activeWalletScope` (`:1209-1218`) → used by `dashboard`, monthly bars, `boundedSums` (`:1078`), `baselineExpense` (`:1099`), two inline scopes at `:1084`/`:1112`.
  - `aggregateCurrencyCode(selectedWalletID:)` — `WalletCurrencyAggregation.swift:8-21` (guards mixed-currency All-Wallets mode).
  - `rejectMixedCurrencyAllWalletSnapshot` call sites: `:911`, `:1012`, `:1301`.
- Balance recomputation: `AggregateMaintenance.recomputeWalletBalances` (`Persistence/Aggregates/AggregateMaintenance.swift:685`) and `mutateAggregate`'s per-wallet balance update (`:241`) are per-wallet — unaffected by exclusion.
- **Overview wealth (easy to miss):** `AggregateMaintenance.balance(atEndOfMonth:)` `:416-455` and `monthEndBalances` `:464-500` — the nil-wallet branch sums `starting_balance_minor` over non-archived wallets AND sums net delta over **all transactions with NO wallet scope**; both feed `OverviewSnapshot.totalWealthMinor` (Spending Overview `TimelineOverviewView.swift:577`). Must exclude flagged wallets in BOTH terms.
- **Transactions feed:** `listTransactions` (`AggregateMaintenance.swift:301-303`) applies `activeWalletScope(nil, …)` only when `query.walletID == nil` → default feed and All-Wallets timeline drop savings transactions (intended consequence; savings data reachable by selecting the savings wallet).
- Duplicate normalize logic (fix both): `Sources/CashRunwayUI/AppModel.swift:839-846` and protocol extension `Sources/CashRunwayCore/CashRunwayRepositorying.swift:170-178` (`first { !$0.isArchived }` fallback could silently select a savings wallet).
- Budgets: `recomputeBudgetSnapshots` sums category spend across ALL wallets (`AggregateMaintenance.swift:259-275`) — intentionally unchanged (category-level semantics; savings inflows are transfers, not expenses).
- UI touchpoints: `WalletManagementView.swift` (title "Manual Wallets" → UK "Ручні гаманці", `Localizable.xcstrings:4475`), `WalletEditorView.swift` (category/currency/balance editor, no toggle today), dashboard wallet `Menu` (`DashboardView.swift:282-319`, `walletMenu` at `:282`), Settings row (`SettingsView.swift:96`).
- Backup: `BackupService.swift:39` (export wallets), restore INSERT at `:158` (13 columns); `BackupWallet` has a hand-written decoder (`Models.swift:969-1035`) — new flag must decode with default `false` for old backups.
- Delete guard "at least one active wallet must remain": `CashRunwayRepository.swift:685-693` and `Sources/CashRunwayUI/AppModel.swift` (~`:618-622`).
- Localization: modify `AppHost/Localizable.xcstrings` only via `Scripts/localize-xcstrings.py` (repo rule).
- Xcode project: new `.swift` files must be registered in `CashRunway.xcodeproj/project.pbxproj` (explicit file refs, no synchronized groups). Follow the pbxproj backup/verify ritual in AGENTS.md when touching it.

**Design decisions**

1. New `WalletKind.savings` case instead of a free-form flag-only approach: user asked for a *type* that is visually different; a kind gives it a localized name ("Заощадження"), a system wallet category, default icon/color, and drives distinct styling in rows/cards with the compiler flagging every switch site.
2. The "separate entity" behavior is a separate persisted boolean `is_excluded_from_summary` — not implied by the kind — so the user keeps explicit control (checkbox/toggle), default ON for new savings wallets.
3. Transfers between operational wallets and savings wallets remain allowed (that's how savings get topped up); only *shared totals* exclude savings.

---

## Tasks

### Phase A — Core model & migration

#### Task 1: Add `v9_savings_wallets` migration

**Files:**
- Modify: `Sources/CashRunwayCore/DatabaseManager.swift` (append to `allMigrations()` after `v8_currency_foundation`, ~`:999`)
- Test: `Tests/CashRunwayCoreTests/MigrationIntegrityTests.swift`

**Step 1: Write failing test** — extend the identifier list in `migrationIdentifierSetMatchesRegistrationOrder` with `"v9_savings_wallets"`; expect the test to FAIL.

**Step 2: Add migration** (guarded like v8 for partial-schema installs):

```swift
("v9_savings_wallets", { db in
    let walletsExist = try Bool.fetchOne(db, sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'wallets'") != nil
    if walletsExist, try !Self.tableHasColumn(db, table: "wallets", column: "is_excluded_from_summary") {
        try db.alter(table: "wallets") { table in
            table.add(column: "is_excluded_from_summary", .boolean).notNull().defaults(to: false)
        }
    }
}),
```

Note: `tableHasColumn` exists (`CashRunwayRepository.swift`, used at `:607`); if it's not visible from `DatabaseManager`, reuse the v8 pattern (`Bool.fetchOne` on `PRAGMA table_info` or duplicate the tiny helper as `static` in `DatabaseManager`).

**Step 3: Run** `just test-filter MigrationIntegrityTests` → PASS (identifier list + default-false migration against a partial v8 DB).

**Step 4: Commit** `feat(persistence): add v9_savings_wallets migration`

#### Task 2: Add `isExcludedFromSummary` to model + backup compatibility

**Files:**
- Modify: `Sources/CashRunwayCore/Models.swift` (`Wallet` :603, `BackupWallet` :969)
- Modify: `Sources/CashRunwayCore/Persistence/DAOs/RowMappers.swift` (`wallet`, `backupWallet` mappers, `:10`/`:42`)
- Test: `Tests/CashRunwayCoreTests/CashRunwayRepositoryingTests.swift` (new test)

**Step 1: Write failing test** — decode an old backup JSON (fixture without the new key) → `BackupWallet.isExcludedFromSummary == false`; decode-with-key → `true`.

**Step 2: Implement**

- `Wallet`: add `public var isExcludedFromSummary: Bool` (place after `isArchived`), add `defaults` to memberwise init parameter list as `isExcludedFromSummary: Bool = false` so 60+ existing constructor call sites compile untouched (`WalletManagementView.swift:8`, `DashboardView.swift:16`, agent mocks, fixtures).
- `BackupWallet`: add same property; in the hand-written decoder use `try container.decodeIfPresent(Bool.self, forKey: .isExcludedFromSummary) ?? false`; add the encoding key.
- RowMappers: `isExcludedFromSummary: (row["is_excluded_from_summary"] as Bool?) ?? false` — nil-safe for partial-schema DBs, mirroring how other optional columns are read.
- Update `saveWallet` INSERT/UPSERT (`CashRunwayRepository.swift:606-683`) and `BackupService` restore INSERT (`:158`) + `backupWallet` export mapping to carry the flag.

**Step 3: Run** `just check-unit-parallel --filter Wallet` → PASS; **verify** no other Wallet JSON decode exists: `grep -rn "Wallet.self\|\[Wallet\].self" Sources Tests` (report result; only backup path is expected).

**Step 4: Commit** `feat(core): isExcludedFromSummary flag on Wallet and backup`

#### Task 3: Introduce `WalletKind.savings` + system category

**Files:**
- Modify: `Sources/CashRunwayCore/Models.swift` (`WalletKind` :3; `WalletCategory.builtIn` block :35-88)
- Modify: `Sources/CashRunwayCore/CashRunwayRepository.swift` (`walletCategories()` ORDER BY `CASE kind` :122-133)
- Modify: `Sources/CashRunwayCore/L10n.swift` (`walletKind(kind)` switch)
- Modify: `AppHost/Localizable.xcstrings` **via** `Scripts/localize-xcstrings.py`
- Test: `Tests/CashRunwayCoreTests/WalletCategoryTests.swift`

**Step 1: Write failing test** — `WalletCategory.builtIn(byKind: .savings)` returns a system category with a fresh reserved UUID `22222222-2222-2222-2222-222222222226`.

**Step 2: Implement**

- Add `case savings` to `WalletKind` (last position).
- Add `WalletCategory.savings` constant (reserved UUID above, `name: "walletKind.savings"`); append to `allBuiltIn`.
- `walletCategories()` ORDER BY: insert `WHEN 'savings' THEN 3` and move `ELSE 4`.
- Fix every compiler-forced switch: `L10n.walletKind` → new key `walletKind.savings`; any UI/VM switch flagged by `swift build --target CashRunwayCore` first (AGENTS.md pre-check).
- Localize keys (EN/UK) via the script:
  - `walletKind.savings` → "Savings" / "Заощадження"
  - `Savings Section` → "Savings & Investments" / "Заощадження та інвестиції"
  - `Separate Entity` → "Separate entity (excluded from totals)" / "Окрема сутність (не враховувати в підсумках)"
  - `Savings Excluded Hint` → "Not counted in the global summary or All Wallets data." / "Не враховується в загальній сумі та даних «Усі гаманці»."

**Step 3: Run** `just test-filter WalletCategoryTests` → PASS.

**Step 4: Commit** `feat(core): add savings wallet kind with built-in category`

### Phase B — Aggregation exclusion (Core)

#### Task 4: Scope helpers exclude flagged wallets

**Files:**
- Modify: `Sources/CashRunwayCore/CashRunwayRepository.swift` (`activeWalletScope` :1209; inline scopes `:1084`, `:1112`; all-wallet total `:918`; `rejectMixedCurrencyAllWalletSnapshot` helper)
- Test: `Tests/CashRunwayCoreTests/SavingsExclusionTests.swift` (new)

**Step 1: Write failing tests** (each drives the public seam):
1. `allWalletDashboardTotalExcludesFlaggedWallets` — two operational + one flagged wallet → `dashboard(monthKey:)` total equals the two operational balances.
2. `flaggedWalletDashboardStillAvailableWhenSelected` — `dashboard(monthKey:walletID:)` with the flagged wallet's ID returns its own total/cashflow.
3. `timelineAllWalletsScopeExcludesFlagged` — flagged wallet's transactions absent from All-Wallets snapshot bars/timeline, present when selected.
4. `deleteGuardCountsOperationalOnly` — with 1 operational + 1 flagged wallet, deleting the operational wallet throws; deleting the flagged one succeeds.
5. `overviewWealthExcludesSavings` — flagged wallet's starting balance + its transfers absent from `overviewSnapshot(monthKey:)` `totalWealthMinor`/wealth history; present when that wallet is selected.

**Step 2: Implement** — single predicate reused by all scope sites:

```swift
static let operationalScopeSQL = """
SELECT id FROM wallets
WHERE is_archived = 0
  AND (is_excluded_from_summary = 0 OR is_excluded_from_summary IS NULL)
"""
```

- `activeWalletScope` nil-branch: `\(column) IN (\(operationalScopeSQL))`.
- Replace the two inline `SELECT id FROM wallets WHERE is_archived = 0` fragments (`:1084`, `:1112`) with the same predicate.
- All-wallet total `:918`: `SELECT COALESCE(SUM(current_balance_minor), 0) FROM wallets WHERE is_archived = 0 AND (…pred…)`.
- **Wealth history (Overview):** in `AggregateMaintenance.balance(atEndOfMonth:)` and `monthEndBalances` nil-branch — add predicate to the `starting_balance_minor` sum AND scope the all-transactions net-delta query with `AND t.wallet_id IN (\(operationalScopeSQL))`. These are in `CashRunwayRepository`'s extension, so the helper must be `static` (not `private`) or moved to a shared file.
- Mixed-currency guard: flagged wallets must not poison All-Wallets single-currency detection → update the currency query inside `rejectMixedCurrencyAllWalletSnapshot` / any wallet-currency enumeration to filter flagged wallets (same predicate) **unless** a specific wallet is selected.
- Partial-schema safety: keep the existing `tableHasColumn("wallets", "is_excluded_from_summary")` style guard used by v8-era code paths; when the column is absent, behave as today (all archived-inclusive) — tests already construct pre-v9 DBs.

**Step 3: Run** `just check-unit-parallel --filter Savings` → PASS.

**Step 4: Commit** `feat(core): exclude separate-entity wallets from shared aggregates`

#### Task 5: Currency aggregation + projection boundaries

**Files:**
- Modify: `Sources/CashRunwayCore/WalletCurrencyAggregation.swift` (`aggregateCurrencyCode` :8-21 — extension-internal filter: `AppModel.swift:82` etc. stay untouched)
- Modify: duplicate normalize fallbacks — `Sources/CashRunwayCore/CashRunwayRepositorying.swift:170-178` and `Sources/CashRunwayUI/AppModel.swift:839-846`: stale-selection fallback `first { !$0.isArchived }` must skip flagged wallets (else a stale selection silently scopes aggregates to a savings wallet)
- Test: extend `SavingsExclusionTests.swift`

**Step 1: Write failing test** — `aggregateCurrencyCode` ignores flagged wallets (mixed UAH/USD operational-only UAH → returns `.uah`; adding a flagged USD wallet does not nil it out).

**Step 2: Implement** — in the nil-selection branch filter `!$0.isExcludedFromSummary`; selected-wallet branch unchanged. Grep callers passing `wallets` for aggregation (`AppModel.swift:82`) and pass the filtered array or filter inside the extension (extension-internal filter chosen: single point, call sites untouched).

**Step 3: Run** `just test-filter WalletCurrency` → PASS. **Commit** `feat(core): all-wallet currency aggregation ignores separate entities`

### Phase C — UI

#### Task 6: Wallet editor gains "Separate entity" toggle

**Files:**
- Modify: `Sources/CashRunwayUI/WalletEditorView.swift` (Wallet Details section, after currency picker ~`:56-70`)
- Modify: `Sources/CashRunwayUI/AccessibilityIdentifiers.swift`
- Modify: `AppHost/Localizable.xcstrings` via script

**Step 1:** When `wallet.kind == .savings`, render `Toggle(L10n.string("Separate Entity"), isOn: $wallet.isExcludedFromSummary)` plus the hint text `Savings Excluded Hint`; for other kinds render nothing (YAGNI). Default ON at creation: `WalletManagementView`'s `+` draft (:106-116) starts `.cash`/flag-off; inside `WalletEditorView`'s existing `onChange(of: wallet.categoryID)` (:48-55), when a brand-new wallet (id not present in `model.wallets`) picks a savings-kind category, set `wallet.isExcludedFromSummary = true`; when switching back to an operational kind on a new wallet, reset to `false`. Existing wallets keep their persisted flag regardless of kind switches.

**Step 2:** A11y: `.accessibilityIdentifier(CashRunwayAccessibilityID.walletSeparateEntityToggle)`; add the ID constant + per-surface screenshot check (Manual Wallets list, editor open) — visual gate per AGENTS.md, not just geometry.

**Step 3: Run** `just check-unit-parallel` (UI target compiles in Xcode app target — also `just build`). **Commit** `feat(ui): separate-entity toggle in wallet editor`

#### Task 7: Sectioned Manual Wallets screen with distinct savings styling

**Files:**
- Modify: `Sources/CashRunwayUI/WalletManagementView.swift` (full restructure, currently 63 lines)
- Modify: `Sources/CashRunwayUI/Theme.swift` (if a new token pair needed — prefer existing tokens)
- Modify: `AppHost/Localizable.xcstrings` via script

**Step 1:** Split `model.wallets` into `operational = filter { !$0.isExcludedFromSummary }` and `savings = filter { $0.isExcludedFromSummary }`. Render two `Section`s:
- Header `L10n.string("Manual Wallets")` (unchanged rows: name button + swipe delete).
- Header `L10n.string("Savings Section")`, rows visually distinct: leading `CategoryGlyph` with the savings tint (default colorHex `#B8860B`-family token — pick from `CashRunwayTheme` palette in implementation, verify contrast vs surface), trailing caption `L10n.string("walletKind.savings")` + small lock/eye-off style badge symbol (`eyebrow` style consistent with Theme). Same tap/swipe behavior.
- Keep `plus` toolbar as-is (editor's category picker chooses the kind); **optional stretch:** a second `+` in the savings section prefilled with `.savings`.

**Step 2:** Settings row (`SettingsView.swift:96`): subtitle switches to operational count; add a sibling row `moreRow(icon: "chart.line.uptrend.xyaxis", tint: savingsToken, title: L10n.string("Savings Section"), subtitle: L10n.walletCount(savingsCount)) { isWalletsPresented = true }` — same sheet, sectioned screen. A11y ID `settingsSavingsRow`.

**Step 3:** Screenshots at affected breakpoints (device sim, Manual Wallets + Settings). **Commit** `feat(ui): sectioned manual wallets with distinct savings entities`

#### Task 8: Dashboard — wallet menu section + separate savings total

**Files:**
- Modify: `Sources/CashRunwayUI/DashboardView.swift` (`walletMenu` at `:282`; `summaryCard` at `:196`)
- Modify: `Sources/CashRunwayUI/AppModel.swift` (expose computed `model.savingsWallets`, `model.savingsTotalMinor` single-currency-safe — UI module, mirrors Task 5 semantics)
- Modify: `AppHost/Localizable.xcstrings` via script
- Test: `Tests/CashRunwayUIVMTests` (new small suite for the split + total)

**Step 1: Failing VM test** — `savingsWallets` split correctness; `savingsTotalMinor` sums flagged wallets only when all share one currency, else nil (mixed-currency total renders "mixed" like existing mixed handling `DashboardView.swift:693` pattern).

**Step 2:** 
- `walletMenu`: keep "All Wallets" (eligibility now ignores flagged wallets — Task 5); operational wallets unchanged; appended `Section(L10n.string("Savings Section"))` listing flagged wallets with `chart.line.uptrend.xyaxis` icon so they're reachable/selectable (selecting one shows its timeline — already supported by `selectWallet`). Preserve the `aggregateCurrencyCode(selectedWalletID: nil)` guard semantics.
- Dashboard has NO balance card today (it shows timeline header + cash-flow summary card, `DashboardView.swift:37-42`). Place the savings strip between `summaryCard` and `filters`: compact card, label + single-currency savings total (or "Mixed currencies" indicator), Savings-tint (`CashRunwayTheme.warning` amber is the closest existing token; prefer it over inventing one), visually offset from the operational summary. Global summary numbers keep excluding flagged wallets purely via Core scopes — no UI math.
- Note: `OverviewSnapshot.totalWealthMinor` (Spending Overview) is a Core-computed number — covered by Task 4, nothing further in UI.
- Keys: `Savings Total` → "Savings" / "Заощадження"; `Savings Mixed` → "Mixed currencies" / "Різні валюти".

**Step 3: Run** `just check-unit-parallel` → PASS; screenshots (dashboard with/without savings wallet). **Commit** `feat(ui): savings section in wallet menu and separate savings strip`

### Phase D — Validation, compat, handoff

#### Task 9: Backup/restore round-trip + gates

**Files:**
- Test: `Tests/CashRunwayCoreTests/FullBackupTests.swift`, `DatabaseBackupTests.swift`

**Step 1:** Round-trip test: create DB, flag a wallet, export → wipe → restore → flag persisted; old-format fixture (no flag key) restores with `false`.

**Step 2:** Full gates in order: `just check-unit-parallel` → `just check-integration` (crosses DB boundaries; single-worktree machine, use it over parallel variant) → `just check-isolated` if contention/stale state appears (AGENTS.md stop rule: ~60-90s quiet → retry isolated once).

**Step 3:** Reporting API cross-check — repo grep earlier found no `current_balance_minor` usage under `reporting-api/`; re-verify after implementation with `grep -rn "sum\|balance" reporting-api/src | grep -i wallet` and report the result in the PR description.

**Step 4: Commit** `test(backup): savings flag survives restore and legacy imports`

#### Task 10: Localization sweep + CONTINUITY + PR

**Files:**
- Modify: `AppHost/Localizable.xcstrings` (script — verify no manual edits: `git diff AppHost/Localizable.xcstrings` should match script output only)
- Modify: `CONTINUITY.md` (Snapshot section per repo rules)
- New: PR from `feat/savings-wallets` 

**Step 1:** Run `Scripts/localize-xcstrings.py` pass; confirm every new key has EN + UK values; `git status --short` clean of unexpected files.

**Step 2:** Update `CONTINUITY.md` snapshot (branch, phase, validation status buckets: repo validation / runtime smoke / release readiness kept separate).

**Step 3:** Branch `feat/savings-wallets` from `main`; push and open PR **only after explicit user confirmation** (repo Git Safety). PR body: requirement → mapping table from this plan's self-check, gate outcomes, screenshots.

---

## Self-check (deliverable gate — verify before merging)

| # | Requirement (user wording) | Verified by |
|---|---|---|
| 1 | New wallet type (savings / long-term investments) | New case in `WalletKind` + system category + picker entry; `WalletCategoryTests` green |
| 2 | Lives in "Ручні гаманці" but visually distinct | Sectioned `WalletManagementView` + tint/badge; screenshots attached to PR |
| 3 | Checkbox/toggle = separate entity | `isExcludedFromSummary` persisted flag + editor toggle (a11y ID) |
| 4 | Doesn't overlap other wallets / global summary | All-wallet total, timeline scopes, cashflow, baseline, AND Overview `totalWealthMinor` (starting-balance + net-delta) all via `operationalScopeSQL`; `SavingsExclusionTests` (5 tests) green |
| 5 | Not counted in sum of funds | `dashboard(monthKey:)` total test explicit; mixed-currency guard updated |
| 6 | Separate section in app | Settings row + sectioned list + dashboard savings strip; selected savings wallet opens its own timeline |
| 7 | Data survives | v9 migration default-false; backup round-trip + legacy fixture test |

**Plan-review checklist:** tasks sequential & bite-sized ✅ · exact paths with line anchors ✅ · copy-pasteable SQL ✓ · exact `just` commands with expected gates ✅ · migration identifiers append-only + integrity test updated ✅ · backup back-compat handled ✅ · visual gates scheduled (not geometry-only) ✅ · pbxproj risk contained (only if new files added; prefer modifying existing files) ✅.

**Risks / tradeoffs**

- **Migration identifiers are sacred:** v9 appends; never reorder (`MigrationIntegrityTests` guards). 
- **Partial-schema DBs:** every new column read/scope guarded via `tableHasColumn` pattern (v8 precedent) — integration tests cover pre-v8 installs.
- **Backup compatibility:** old exports must restore; new exports stay readable (flag decodes `false`).
- **Mixed-currency savings totals:** MVP shows mixed-safe indicator only; FX-converted savings total via existing `WalletValueProjectionService` is a follow-up, not in scope (YAGNI).
- **pbxproj:** avoid new files where possible; if required, backup + `Scripts/verify-pbxproj.sh`.
- **Runway side effects:** runway/cashflow derives from shared aggregates → automatically excludes savings; verify one manual scenario (flag wallet, runway unchanged) before sign-off.
- **UX consequence (intended):** after flagging, savings transactions disappear from the default feed and All-Wallets timeline/cashflow/search scope; they remain visible by selecting the savings wallet (dashboard menu or overview wallet list) and in the sectioned list. State this in the PR so it reads as behavior, not a bug.
- **Budgets unchanged:** category-level budget spend keeps counting every wallet's expense rows (savings inflows are transfers anyway) — deliberate, do not "fix" during implementation.

**Open questions (default assumptions, ask only if blocking)**

1. FX-converted savings total in reporting currency — defer? (assumed: defer)
2. Should non-savings wallets also get the toggle? (assumed: no — toggle scoped to savings kind)
3. Name: "Заощадження та інвестиції" as the section title — OK?