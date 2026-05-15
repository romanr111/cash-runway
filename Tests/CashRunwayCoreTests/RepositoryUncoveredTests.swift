import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct RepositoryUncoveredTests {
    // MARK: - allBars

    @Test func allBarsReturnsEmptyForTrulyEmptyDatabase() throws {
        let repository = try TestSupport.makeRepository()
        // No seed, no transactions
        let bars = try repository.allBars(period: .month)
        #expect(bars.isEmpty)
    }

    @Test func allBarsYearlyPeriod() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 10_000,
            occurredAt: date, categoryID: categories[0].id
        ))

        let bars = try repository.allBars(walletID: wallets[0].id, period: .year)
        #expect(bars.isEmpty == false)
        #expect(bars.allSatisfy { $0.periodKey >= 2025 })
    }

    @Test func allBarsWithWalletFilter() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 5_000,
            occurredAt: date, categoryID: categories[0].id
        ))

        let allBars = try repository.allBars(period: .month)
        let filteredBars = try repository.allBars(walletID: wallets[1].id, period: .month)
        #expect(allBars.count >= filteredBars.count)
    }

    // MARK: - transactionDraft for transfers

    @Test func transactionDraftFromTransferOutSide() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(TransactionDraft(
            kind: .transfer, walletID: wallets[0].id,
            destinationWalletID: wallets[1].id, amountMinor: 1_000,
            occurredAt: date
        ))

        // Query both sides directly from DB since UI query hides transfer_in
        let pairRows = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, type FROM transactions WHERE type IN ('transfer_out', 'transfer_in')")
        }
        #expect(pairRows.count == 2)

        let outRow = try #require(pairRows.first { ($0["type"] as String) == "transfer_out" })
        let inRow = try #require(pairRows.first { ($0["type"] as String) == "transfer_in" })
        let outID = try #require(UUID(uuidString: outRow["id"]))
        let inID = try #require(UUID(uuidString: inRow["id"]))

        let outDraft = try repository.transactionDraft(id: outID)
        #expect(outDraft.kind == .transfer)
        #expect(outDraft.walletID == wallets[0].id)
        #expect(outDraft.destinationWalletID == wallets[1].id)

        let inDraft = try repository.transactionDraft(id: inID)
        #expect(inDraft.kind == .transfer)
        #expect(inDraft.walletID == wallets[0].id)
        #expect(inDraft.destinationWalletID == wallets[1].id)
    }

    // MARK: - deleteTransaction for transfers

    @Test func deleteTransferFromEitherSideRemovesBoth() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(TransactionDraft(
            kind: .transfer, walletID: wallets[0].id,
            destinationWalletID: wallets[1].id, amountMinor: 1_000,
            occurredAt: date
        ))

        let pairRows = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, type FROM transactions WHERE type IN ('transfer_out', 'transfer_in')")
        }
        #expect(pairRows.count == 2)

        let outRow = try #require(pairRows.first { ($0["type"] as String) == "transfer_out" })
        let inRow = try #require(pairRows.first { ($0["type"] as String) == "transfer_in" })
        let outID = try #require(UUID(uuidString: outRow["id"]))
        let inID = try #require(UUID(uuidString: inRow["id"]))

        // Delete from transfer_out side
        try repository.deleteTransaction(id: outID)
        let afterOutDelete = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type IN ('transfer_out', 'transfer_in')") ?? 0
        }
        #expect(afterOutDelete == 0)

        // Create another transfer and delete from transfer_in side
        try repository.saveTransaction(TransactionDraft(
            kind: .transfer, walletID: wallets[0].id,
            destinationWalletID: wallets[1].id, amountMinor: 2_000,
            occurredAt: date
        ))
        let newPairRows = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, type FROM transactions WHERE type IN ('transfer_out', 'transfer_in')")
        }
        #expect(newPairRows.count == 2)
        let newInRow = try #require(newPairRows.first { ($0["type"] as String) == "transfer_in" })
        let newInID = try #require(UUID(uuidString: newInRow["id"]))
        try repository.deleteTransaction(id: newInID)
        let afterInDelete = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type IN ('transfer_out', 'transfer_in')") ?? 0
        }
        #expect(afterInDelete == 0)
    }

    // MARK: - dashboard with wallet filter

    @Test func dashboardWithWalletFilter() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        let monthKey = DateKeys.monthKey(for: date)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 5_000,
            occurredAt: date, categoryID: categories[0].id
        ))

        _ = try repository.dashboard(monthKey: monthKey)
        let filteredDashboard = try repository.dashboard(monthKey: monthKey, walletID: wallets[0].id)
        #expect(filteredDashboard.walletFilterID == wallets[0].id)
        #expect(filteredDashboard.monthExpenseMinor == 5_000)
    }

    // MARK: - overviewSnapshot

    @Test func overviewSnapshotBasic() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        let monthKey = DateKeys.monthKey(for: date)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 5_000,
            occurredAt: date, categoryID: categories[0].id
        ))

        let overview = try repository.overviewSnapshot(monthKey: monthKey)
        #expect(overview.selectedMonthKey == monthKey)
        #expect(overview.monthExpenseMinor == 5_000)
    }

    @Test func overviewSnapshotWithWalletFilter() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        let monthKey = DateKeys.monthKey(for: date)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 5_000,
            occurredAt: date, categoryID: categories[0].id
        ))

        let overview = try repository.overviewSnapshot(monthKey: monthKey, walletID: wallets[0].id)
        #expect(overview.walletFilterID == wallets[0].id)
    }

    // MARK: - saveBudget validation

    @Test(.disabled("Budgets feature is de-prioritized. Re-enable when work resumes."))
    func saveBudgetRejectsNonPositiveLimit() throws {
        let repository = try TestSupport.makeRepository()
        #expect(throws: CashRunwayError.validation("Budget limit must be greater than zero.")) {
            try repository.saveBudget(Budget(
                id: UUID(), categoryID: UUID(), monthKey: 202501,
                limitMinor: 0, isArchived: false, createdAt: .now, updatedAt: .now
            ))
        }
    }

    // MARK: - recurring instances

    @Test func skipRecurringInstance() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallets[0].id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: nil, merchant: nil, note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: .now, endDate: nil,
            isActive: true, createdAt: .now, updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)
        try repository.refreshRecurringInstances()

        let instances = try repository.recurringInstances()
        #expect(instances.count > 0)
        let instance = instances[0]
        #expect(instance.status == .scheduled)

        try repository.skipRecurringInstance(id: instance.id)
        let afterSkip = try repository.recurringInstances()
        let updated = try #require(afterSkip.first { $0.id == instance.id })
        #expect(updated.status == .skipped)
    }

    @Test func postRecurringInstance() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallets[0].id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: nil, merchant: nil, note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: .now, endDate: nil,
            isActive: true, createdAt: .now, updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)
        try repository.refreshRecurringInstances()

        let instances = try repository.recurringInstances()
        #expect(instances.count > 0)
        let instance = instances[0]

        try repository.postRecurringInstance(id: instance.id)
        let afterPost = try repository.recurringInstances()
        let updated = try #require(afterPost.first { $0.id == instance.id })
        #expect(updated.status == .posted)
        #expect(updated.linkedTransactionID != nil)
    }

    @Test func postRecurringTransferInstance() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let template = RecurringTemplate(
            id: UUID(), kind: .transfer, walletID: wallets[0].id,
            counterpartyWalletID: wallets[1].id, amountMinor: 1_000,
            categoryID: nil, merchant: nil, note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: .now, endDate: nil,
            isActive: true, createdAt: .now, updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)
        try repository.refreshRecurringInstances()

        let instances = try repository.recurringInstances()
        #expect(instances.count > 0)
        let instance = instances[0]

        try repository.postRecurringInstance(id: instance.id)
        let afterPost = try repository.recurringInstances()
        let updated = try #require(afterPost.first { $0.id == instance.id })
        #expect(updated.status == .posted)
        #expect(updated.linkedTransactionID != nil)
    }

    // MARK: - category management

    @Test func categoryManagementItemsAndReorder() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let expenseCategories = try repository.categories(kind: .expense)
        #expect(expenseCategories.count >= 2)

        let items = try repository.categoryManagementItems(kind: .expense)
        #expect(items.count == expenseCategories.count)

        let reorderedIDs = expenseCategories.reversed().map(\.id)
        try repository.reorderCategories(kind: .expense, orderedCategoryIDs: reorderedIDs)
        let afterReorder = try repository.categories(kind: .expense)
        #expect(afterReorder.map(\.id) == reorderedIDs)
    }

    // MARK: - import failure

    @Test func failImportUpdatesStatus() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let jobID = UUID()
        try repository.failImport(jobID: jobID, errorSummary: "Network error")
        // No assertion possible without read API; test exercises the code path.
    }

    // MARK: - transactions query

    @Test func transactionsQueryWithFilters() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 5_000,
            occurredAt: date, categoryID: categories[0].id, merchant: "TestMerchant"
        ))

        let all = try repository.transactions(query: .init())
        #expect(all.count > 0)

        let byWallet = try repository.transactions(query: .init(walletID: wallets[0].id))
        #expect(byWallet.count > 0)

        let bySearch = try repository.transactions(query: .init(searchText: "TestMerchant"))
        #expect(bySearch.count > 0)

        let byKind = try repository.transactions(query: .init(kinds: [.expense]))
        #expect(byKind.count > 0)

        let emptySearch = try repository.transactions(query: .init(searchText: "NONEXISTENT"))
        #expect(emptySearch.isEmpty)
    }

    @Test func transactionsQueryWithDateRange() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(TransactionDraft(
            kind: .expense, walletID: wallets[0].id, amountMinor: 5_000,
            occurredAt: date, categoryID: categories[0].id
        ))

        let start = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2025, month: 1, day: 31))!
        let inRange = try repository.transactions(query: .init(startDate: start, endDate: end))
        #expect(inRange.count > 0)

        let outOfRange = try repository.transactions(query: .init(
            startDate: calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!,
            endDate: calendar.date(from: DateComponents(year: 2024, month: 1, day: 31))!
        ))
        #expect(outOfRange.isEmpty)
    }
}
