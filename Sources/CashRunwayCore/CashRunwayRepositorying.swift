import Foundation

public protocol CashRunwayRepositorying: Sendable {
    func seedIfNeeded() throws
    func wallets() throws -> [Wallet]
    func walletCategories() throws -> [WalletCategory]
    func categories(kind: CategoryKind?) throws -> [Category]
    func labels() throws -> [Label]
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
    func budgets(monthKey: Int) throws -> [BudgetProgress]
    func recurringTemplates() throws -> [RecurringTemplate]
    func recurringInstances() throws -> [RecurringInstance]
    func latestTransactionMonthKey() throws -> Int?
    func saveWalletCategory(_ category: WalletCategory) throws
    func saveWallet(_ wallet: Wallet) throws
    func deleteWallet(id: UUID) throws
    func deleteLabel(id: UUID) throws
    func saveCategory(_ category: Category) throws
    func saveLabel(_ label: Label) throws
    func saveBudget(_ budget: Budget) throws
    func saveRecurringTemplate(_ template: RecurringTemplate) throws
    func saveRecurringInstance(_ instance: RecurringInstance) throws
    func dashboard(monthKey: Int, walletID: UUID?) throws -> DashboardSnapshot
    func timelineSnapshot(monthKey: Int, walletID: UUID?, query: TransactionQuery, period: TimelinePeriod) throws -> TimelineSnapshot
    func allBars(walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint]
    func overviewSnapshot(monthKey: Int, walletID: UUID?) throws -> OverviewSnapshot
    func categoryManagementItems(kind: CategoryKind) throws -> [CategoryManagementItem]
    func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) throws
    func transactions(query: TransactionQuery, limit: Int?) throws -> [TransactionListItem]
    func transactionDraft(id: UUID) throws -> TransactionDraft
    func saveTransaction(_ draft: TransactionDraft) throws
    func deleteTransaction(id: UUID) throws
    func transactionDeletionSummary(for period: DeletePeriod, now: Date) throws -> TransactionDeletionSummary
    func transactionDeletionPlan(for period: DeletePeriod, now: Date) throws -> TransactionDeletionPlan
    func deleteTransactions(_ plan: TransactionDeletionPlan) throws -> Int
    func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) throws
    func failImport(jobID: UUID, errorSummary: String) throws
    func commitCSVImport(
        fileName: String,
        sourceName: String,
        sourceFormatID: String?,
        preparedRows: [PreparedImportRow],
        rowErrors: [CSVRowError],
        invalidRows: Int?
    ) throws -> CSVImportResult
    func runMaintenance() throws
    func refreshRecurringInstances() throws
    func postRecurringInstance(id: UUID, on date: Date) throws
    func skipRecurringInstance(id: UUID) throws
    func exportFullBackup() throws -> CashRunwayBackup
    func restoreFullBackup(_ backup: CashRunwayBackup) throws -> BackupRestoreResult
}

public extension CashRunwayRepositorying {
    func transactions(query: TransactionQuery = .init()) throws -> [TransactionListItem] {
        try transactions(query: query, limit: 300)
    }

    func transactionDeletionSummary(for period: DeletePeriod) throws -> TransactionDeletionSummary {
        try transactionDeletionSummary(for: period, now: Date())
    }

    func transactionDeletionPlan(for period: DeletePeriod) throws -> TransactionDeletionPlan {
        try transactionDeletionPlan(for: period, now: Date())
    }

    func postRecurringInstance(id: UUID) throws {
        try postRecurringInstance(id: id, on: Date())
    }
}