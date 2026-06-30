import Foundation
import Testing
@testable import CashRunwayCore

@Test func cashRunwayRepositoryingProtocolDoesNotRequireDatabaseManager() throws {
    let mock = MockRepository()
    let wallets = try mock.wallets()
    #expect(wallets.isEmpty)
    try mock.seedIfNeeded()
    #expect(mock.seedIfNeededCalled)
}

@Test func cashRunwayRepositoryingProtocolSupportsDefaultArguments() throws {
    let mock = MockRepository()
    try mock.postRecurringInstance(id: UUID())
    #expect(mock.postRecurringInstanceCalled)
}

private final class MockRepository: CashRunwayRepositorying, @unchecked Sendable {
    var seedIfNeededCalled = false
    var postRecurringInstanceCalled = false

    func seedIfNeeded() throws { seedIfNeededCalled = true }
    func wallets() throws -> [Wallet] { [] }
    func walletCategories() throws -> [WalletCategory] { [] }
    func categories(kind: CategoryKind?) throws -> [CashRunwayCore.Category] { [] }
    func labels() throws -> [Label] { [] }
    func bankIntegrations() throws -> [BankIntegration] { [] }
    func activeBankIntegrations() throws -> [BankIntegration] { [] }
    func bankAccounts(integrationID: UUID) throws -> [BankAccount] { [] }
    func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount] { [] }
    func saveBankIntegration(_ integration: BankIntegration) throws {}
    func saveBankAccount(_ account: BankAccount) throws {}
    func saveBankConnection(integration: BankIntegration, accounts: [BankAccount]) throws {}
    func markBankAccountSynced(_ accountID: UUID, at date: Date) throws {}
    func markBankIntegrationSynced(_ integrationID: UUID, at date: Date) throws {}
    func recordBankSyncError(integrationID: UUID, error: String, at date: Date) throws {}
    func disableBankIntegration(_ integrationID: UUID, at date: Date) throws {}
    func importedBankExpenseCount(integrationID: UUID) throws -> Int { 0 }
    func bankConnectionStatus(provider: BankProvider) throws -> BankConnectionStatusSnapshot {
        BankConnectionStatusSnapshot(integration: nil, enabledAccountCount: 0, syncStartAt: nil, lastSuccessfulSyncAt: nil, lastSyncError: nil, importedExpenseCount: 0)
    }
    func learnBankMerchantCategoryRule(transactionID: UUID, categoryID: UUID) throws {}
    func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? { nil }
    func importBankExpense(provider: BankProvider, integration: BankIntegration, account: BankAccount, externalItem: BankExternalExpenseItem, draft: TransactionDraft) throws {}
    func importMonobankExpenseItems(_ items: [MonobankStatementItem], account: BankAccount, integration: BankIntegration) throws -> BankSyncImportResult { BankSyncImportResult() }
    func budgets(monthKey: Int) throws -> [BudgetProgress] { [] }
    func recurringTemplates() throws -> [RecurringTemplate] { [] }
    func recurringInstances() throws -> [RecurringInstance] { [] }
    func latestTransactionMonthKey() throws -> Int? { nil }
    func saveWalletCategory(_ category: WalletCategory) throws {}
    func saveWallet(_ wallet: Wallet) throws {}
    func deleteWallet(id: UUID) throws {}
    func deleteLabel(id: UUID) throws {}
    func saveCategory(_ category: CashRunwayCore.Category) throws {}
    func saveLabel(_ label: Label) throws {}
    func saveBudget(_ budget: Budget) throws {}
    func saveRecurringTemplate(_ template: RecurringTemplate) throws {}
    func saveRecurringInstance(_ instance: RecurringInstance) throws {}
    func dashboard(monthKey: Int, walletID: UUID?) throws -> DashboardSnapshot {
        DashboardSnapshot(monthKey: monthKey, walletFilterID: walletID, totalBalanceMinor: 0, monthIncomeMinor: 0, monthExpenseMinor: 0, monthNetMinor: 0, wealthHistory: [], categories: [], recentTransactions: [])
    }
    func timelineSnapshot(monthKey: Int, walletID: UUID?, query: TransactionQuery, period: TimelinePeriod) throws -> TimelineSnapshot {
        TimelineSnapshot(anchorMonthKey: monthKey, walletFilterID: walletID, heroCashFlowMinor: 0, bars: [], sections: [], period: period)
    }
    func allBars(walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint] { [] }
    func overviewSnapshot(monthKey: Int, walletID: UUID?) throws -> OverviewSnapshot {
        OverviewSnapshot(selectedMonthKey: monthKey, walletFilterID: walletID, months: [], totalWealthMinor: 0, monthCashFlowMinor: 0, monthIncomeMinor: 0, monthExpenseMinor: 0, categories: [], labels: [])
    }
    func categoryManagementItems(kind: CategoryKind) throws -> [CategoryManagementItem] { [] }
    func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) throws {}
    func transactions(query: TransactionQuery, limit: Int?) throws -> [TransactionListItem] { [] }
    func transactionDraft(id: UUID) throws -> TransactionDraft {
        TransactionDraft(id: id, kind: .expense, walletID: UUID(), destinationWalletID: nil, amountMinor: 0, occurredAt: Date())
    }
    func saveTransaction(_ draft: TransactionDraft) throws {}
    func deleteTransaction(id: UUID) throws {}
    func transactionDeletionSummary(for period: DeletePeriod, now: Date) throws -> TransactionDeletionSummary {
        TransactionDeletionSummary(count: 0, displayCount: 0, expenseMinor: 0, incomeMinor: 0)
    }
    func transactionDeletionPlan(for period: DeletePeriod, now: Date) throws -> TransactionDeletionPlan {
        TransactionDeletionPlan(period: period, referenceDayKey: 0, referenceMonthKey: 0, referenceYear: 0, items: [], summary: TransactionDeletionSummary(count: 0, displayCount: 0, expenseMinor: 0, incomeMinor: 0))
    }
    func deleteTransactions(_ plan: TransactionDeletionPlan) throws -> Int { 0 }
    func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) throws {}
    func failImport(jobID: UUID, errorSummary: String) throws {}
    func commitCSVImport(fileName: String, sourceName: String, sourceFormatID: String?, preparedRows: [PreparedImportRow], rowErrors: [CSVRowError], invalidRows: Int?) throws -> CSVImportResult {
        CSVImportResult(
            job: ImportJob(id: UUID(), sourceName: sourceName, sourceFormatID: sourceFormatID, fileName: fileName, status: .committed, totalRows: 0, validRows: 0, invalidRows: 0, duplicateRows: 0, startedAt: Date(), finishedAt: Date(), errorSummary: nil),
            insertedTransactions: 0, duplicateRows: 0, invalidRows: 0, affectedMonths: [], rowErrors: []
        )
    }
    func runMaintenance() throws {}
    func refreshRecurringInstances() throws {}
    func postRecurringInstance(id: UUID, on date: Date) throws { postRecurringInstanceCalled = true }
    func skipRecurringInstance(id: UUID) throws {}
    func exportFullBackup() throws -> CashRunwayBackup {
        CashRunwayBackup(
            metadata: CashRunwayBackupMetadata(format: "cash-runway-backup", version: 2, createdAt: Date(), appVersion: "test", currency: "UAH"),
            wallets: [], walletCategories: [], categories: [], labels: [],
            transactions: [], transactionLabels: [], budgets: [],
            recurringTemplates: [], recurringInstances: [], importJobs: []
        )
    }
    func restoreFullBackup(_ backup: CashRunwayBackup) throws -> BackupRestoreResult {
        BackupRestoreResult(summary: BackupValidationSummary(
            createdAt: Date(), walletCount: 0, categoryCount: 0, labelCount: 0,
            transactionCount: 0, recurringTemplateCount: 0
        ))
    }
}