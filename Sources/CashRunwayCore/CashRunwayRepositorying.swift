import Foundation

// MARK: - Consumer-aligned sub-protocols
//
// `CashRunwayRepositorying` was a 57-method "god protocol" (ISP violation): a mock
// had to implement all 57 methods to test one feature, and every client transitively
// depended on the full surface. It is now decomposed into role-aligned sub-protocols
// so narrower consumers (BankSyncService, Fixtures, BackgroundWork) and test mocks
// can depend on only the capability they need.
//
// `CashRunwayRepositorying` is preserved as a typealias composition of the
// sub-protocols, so the god-consumer `AppModel` (which genuinely calls ~34 methods)
// and the concrete `CashRunwayRepository` keep compiling unchanged. Narrowing
// `AppModel.repository` to specific sub-protocols is a future follow-up.
//
// Segmentation is consumer-aligned (clustered by which consumer calls the method),
// not domain-aligned — domain alignment would re-create a god protocol per slice
// without reducing mock boilerplate.

/// Bank-sync capability: integration/account lifecycle, import, status, sync bookkeeping.
public protocol BankSyncRepositorying: Sendable {
    func bankIntegrations() throws -> [BankIntegration]
    func activeBankIntegrations() throws -> [BankIntegration]
    func bankAccounts(integrationID: UUID) throws -> [BankAccount]
    func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount]
    func saveBankIntegration(_ integration: BankIntegration) throws
    func saveBankAccount(_ account: BankAccount) throws
    func saveBankConnection(integration: BankIntegration, accounts: [BankAccount]) throws
    func markBankAccountSynced(_ accountID: UUID, at date: Date) throws
    func markBankIntegrationSynced(_ integrationID: UUID, at date: Date) throws
    func recordBankSyncError(integrationID: UUID, error: String, at date: Date) throws
    func disableBankIntegration(_ integrationID: UUID, at date: Date) throws
    func importedBankExpenseCount(integrationID: UUID) throws -> Int
    func bankConnectionStatus(provider: BankProvider) throws -> BankConnectionStatusSnapshot
    func learnBankMerchantCategoryRule(transactionID: UUID, categoryID: UUID) throws
    func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport?
    func importBankExpense(
        provider: BankProvider,
        integration: BankIntegration,
        account: BankAccount,
        externalItem: BankExternalExpenseItem,
        draft: TransactionDraft
    ) throws
    func importMonobankExpenseItems(
        _ items: [MonobankStatementItem],
        account: BankAccount,
        integration: BankIntegration
    ) throws -> BankSyncImportResult
}

/// Read-only dashboard/timeline/overview snapshot capability.
public protocol DashboardRepositorying: Sendable {
    func wallets() throws -> [Wallet]
    func walletCategories() throws -> [WalletCategory]
    func categories(kind: CategoryKind?) throws -> [Category]
    func labels() throws -> [Label]
    func budgets(monthKey: Int) throws -> [BudgetProgress]
    func latestTransactionMonthKey() throws -> Int?
    func dashboard(monthKey: Int, walletID: UUID?) throws -> DashboardSnapshot
    func timelineSnapshot(monthKey: Int, walletID: UUID?, query: TransactionQuery, period: TimelinePeriod) throws -> TimelineSnapshot
    func allBars(walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint]
    func overviewSnapshot(monthKey: Int, walletID: UUID?) throws -> OverviewSnapshot
    func transactions(query: TransactionQuery, limit: Int?) throws -> [TransactionListItem]
}

/// Transaction create/edit/delete capability (including bulk delete and category merge).
public protocol TransactionEditingRepositorying: Sendable {
    func transactionDraft(id: UUID) throws -> TransactionDraft
    func saveTransaction(_ draft: TransactionDraft) throws
    func deleteTransaction(id: UUID) throws
    func transactionDeletionSummary(for period: DeletePeriod, now: Date) throws -> TransactionDeletionSummary
    func transactionDeletionPlan(for period: DeletePeriod, now: Date) throws -> TransactionDeletionPlan
    func deleteTransactions(_ plan: TransactionDeletionPlan) throws -> Int
    func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) throws
    func failImport(jobID: UUID, errorSummary: String) throws
}

/// Settings/management capability: wallet/category/label/budget/recurring CRUD,
/// category management, backup/restore, and seeding.
public protocol SettingsRepositorying: Sendable {
    func seedIfNeeded() throws
    func saveWalletCategory(_ category: WalletCategory) throws
    func saveWallet(_ wallet: Wallet) throws
    func canChangeWalletCurrency(id: UUID) throws -> Bool
    func deleteWallet(id: UUID) throws
    func deleteLabel(id: UUID) throws
    func saveCategory(_ category: Category) throws
    func saveLabel(_ label: Label) throws
    func saveBudget(_ budget: Budget) throws
    func recurringTemplates() throws -> [RecurringTemplate]
    func recurringInstances() throws -> [RecurringInstance]
    func saveRecurringTemplate(_ template: RecurringTemplate) throws
    func saveRecurringInstance(_ instance: RecurringInstance) throws
    func postRecurringInstance(id: UUID, on date: Date) throws
    func skipRecurringInstance(id: UUID) throws
    func categoryManagementItems(kind: CategoryKind) throws -> [CategoryManagementItem]
    func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) throws
    func exportFullBackup() throws -> CashRunwayBackup
    func restoreFullBackup(_ backup: CashRunwayBackup) throws -> BackupRestoreResult
}

/// Background maintenance capability: aggregate rebuilds, recurring refresh,
/// CSV import commit, and expired-payload purge.
public protocol MaintenanceRepositorying: Sendable {
    func runMaintenance() throws
    /// Issue #121: monthly-USD snapshot refresh (dirty months only). Async and
    /// non-blocking on every thread — the service must NEVER run behind the
    /// synchronous `runMaintenance` bridge, which blocked callers on a semaphore
    /// for the full historical backfill.
    func refreshDirtyUSDSnapshots() async
    func refreshRecurringInstances() throws
    func commitCSVImport(
        fileName: String,
        sourceName: String,
        sourceFormatID: String?,
        preparedRows: [PreparedImportRow],
        rowErrors: [CSVRowError],
        invalidRows: Int?
    ) throws -> CSVImportResult
}

public protocol CurrencyRepositorying: Sendable {
    func currencyPreferences() throws -> CurrencyPreferences
    func saveCurrencyPreferences(_ preferences: CurrencyPreferences) throws
    func cachedExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date,
        source: String?
    ) throws -> ExchangeRate?
    func cachedExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date,
        source: String?,
        maxStaleness: TimeInterval
    ) throws -> ExchangeRate?
    func saveExchangeRates(_ rates: [ExchangeRate]) throws
    // MARK: Issue #121: retrospective monthly USD snapshots
    func historicalMonthKeys() throws -> [Int]
    func monthlyCashflow(monthKey: Int) throws -> [MonthlyWalletCashflowRow]
    func historicalExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date
    ) throws -> ExchangeRate?
    func nearestHistoricalExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        onOrBefore date: Date,
        maxLookbackDays: Int
    ) throws -> ExchangeRate?
    func monthlyUSDSnapshots(monthKeys: [Int]) throws -> [MonthlyUSDSnapshot]
    func allMonthlyUSDSnapshots() throws -> [MonthlyUSDSnapshot]
    func monthlyUSDMonthAggregates() throws -> [MonthlyUSDSnapshot.MonthAggregate]
    func saveMonthlyUSDSnapshot(_ snapshot: MonthlyUSDSnapshot) throws
    /// Issue #121: non-blocking refresh of persisted retrospective snapshots for
    /// the given months (or all history when nil). Runs the service to completion
    /// off the calling thread — the former synchronous variant blocked callers on
    /// a semaphore (`awaitBridge`) and froze the UI when reached from the main
    /// actor.
    func refreshRetrospectiveUSDSnapshots(monthKeys: Set<Int>?) async
}

public extension CurrencyRepositorying {
    func cachedExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date,
        source: String?,
        maxStaleness: TimeInterval
    ) throws -> ExchangeRate? {
        try cachedExchangeRate(from: sourceCurrency, to: targetCurrency, on: date, source: source)
    }

    /// Issue #121: month aggregates scoped to ONE wallet, for wallet-filtered
    /// retrospective views (the summary card's USD lines must match the wallet
    /// scope the native figures were rendered with). `nil` returns the all-wallet
    /// aggregates unchanged.
    func monthlyUSDMonthAggregates(walletID: UUID?) throws -> [MonthlyUSDSnapshot.MonthAggregate] {
        guard let walletID else { return try monthlyUSDMonthAggregates() }
        let rows = try allMonthlyUSDSnapshots().filter { $0.walletID == walletID }
        let byMonth = Dictionary(grouping: rows) { $0.monthKey }
        return byMonth
            .map { MonthlyUSDSnapshot.MonthAggregate(rows: $0.value) }
            .sorted { $0.monthKey > $1.monthKey }
    }
}

// MARK: - Composed repository abstraction
//
// Preserved for the god-consumer `AppModel` (which genuinely calls ~34 methods)
// and for the concrete `CashRunwayRepository`. Narrower consumers may adopt the
// specific sub-protocol they need in a future follow-up; this typealias keeps the
// existing 13 `any CashRunwayRepositorying` call sites compiling unchanged.
public typealias CashRunwayRepositorying = BankSyncRepositorying &
    DashboardRepositorying &
    TransactionEditingRepositorying &
    SettingsRepositorying &
    CurrencyRepositorying &
    MaintenanceRepositorying

public extension DashboardRepositorying {
    /// Returns a wallet ID that is safe to use for aggregate queries.
    ///
    /// - A valid explicit `selectedWalletID` is returned unchanged.
    /// - A stale explicit `selectedWalletID` (e.g. the wallet was just deleted) falls
    ///   back to the first active wallet, preserving a useful single-wallet scope.
    /// - `nil` (All Wallets) is preserved as `nil` so the caller can aggregate every
    ///   active wallet. Mixed-currency All Wallets is rejected at the query boundary
    ///   (`rejectMixedCurrencyAllWalletSnapshot`), not here - this preserves a valid
    ///   same-currency all-wallet scope instead of silently narrowing it to one wallet.
    func normalizedWalletIDForAggregates(selectedWalletID: UUID?) throws -> UUID? {
        guard let selectedWalletID else { return nil }
        let wallets = try wallets()
        if wallets.contains(where: { $0.id == selectedWalletID }) {
            return selectedWalletID
        }
        return wallets.first(where: { !$0.isArchived })?.id ?? wallets.first?.id
    }
}

// MARK: - Default-argument convenience wrappers
//
// Protocol requirements cannot have default arguments; these extension methods
// restore the ergonomics of the original concrete API for consumers that depend
// on the composed `CashRunwayRepositorying` typealias.

public extension DashboardRepositorying {
    func transactions(query: TransactionQuery = .init()) throws -> [TransactionListItem] {
        try transactions(query: query, limit: 300)
    }
}

public extension TransactionEditingRepositorying {
    func transactionDeletionSummary(for period: DeletePeriod) throws -> TransactionDeletionSummary {
        try transactionDeletionSummary(for: period, now: Date())
    }

    func transactionDeletionPlan(for period: DeletePeriod) throws -> TransactionDeletionPlan {
        try transactionDeletionPlan(for: period, now: Date())
    }
}

public extension SettingsRepositorying {
    func postRecurringInstance(id: UUID) throws {
        try postRecurringInstance(id: id, on: Date())
    }
}
