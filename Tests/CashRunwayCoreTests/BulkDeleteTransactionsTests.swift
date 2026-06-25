import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BulkDeleteTransactionsTests {

    // Fixed "now" so period membership is deterministic regardless of test run date.
    private let now = Self.date(2026, 6, 15)
    private let thisMonthKey = 202606
    private let thisYear = 2026

    private func makeRepository() throws -> CashRunwayRepository {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        return repository
    }

    private func makeWallet(repository: CashRunwayRepository, name: String, balanceMinor: Int64) throws -> Wallet {
        let wallet = WalletBuilder()
            .with(name: name)
            .with(kind: .cash)
            .with(startingBalanceMinor: balanceMinor)
            .with(currentBalanceMinor: balanceMinor)
            .build()
        try repository.saveWallet(wallet)
        return wallet
    }

    private func makeExpenseCategory(repository: CashRunwayRepository) throws -> CashRunwayCore.Category {
        let category = CategoryBuilder().with(name: "Bulk Delete Cat").with(kind: .expense).build()
        try repository.saveCategory(category)
        return category
    }

    private func saveExpense(
        repository: CashRunwayRepository,
        walletID: UUID,
        categoryID: UUID,
        amountMinor: Int64,
        at date: Date,
        id: UUID = UUID(),
        labelIDs: [UUID] = []
    ) throws -> UUID {
        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: walletID)
            .with(categoryID: categoryID)
            .with(amountMinor: amountMinor)
            .with(occurredAt: date)
            .with(labelIDs: labelIDs)
            .build()
        draft.id = id
        try repository.saveTransaction(draft)
        return id
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateKeys.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Summary

    @Test func summaryCountsTransactionsPerPeriod() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let category = try makeExpenseCategory(repository: repository)

        // today (2026-06-15): 2 transactions
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 2_000, at: Self.date(2026, 6, 15))
        // this month, not today (2026-06-01)
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 4_000, at: Self.date(2026, 6, 1))
        // this year, not this month (2026-05-20)
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 8_000, at: Self.date(2026, 5, 20))
        // last year (2025-12-15)
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 16_000, at: Self.date(2025, 12, 15))

        let today = try repository.transactionDeletionSummary(for: .today, now: now)
        let month = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        let year = try repository.transactionDeletionSummary(for: .thisYear, now: now)

        #expect(today.count == 2)
        #expect(today.totalAmountMinor == 3_000)
        #expect(month.count == 3)
        #expect(month.totalAmountMinor == 7_000)
        #expect(year.count == 4)
        #expect(year.totalAmountMinor == 15_000)
    }

    // MARK: - Day

    @Test func deleteTodayRemovesOnlyTodayAndPreservesOthers() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let category = try makeExpenseCategory(repository: repository)

        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 2_000, at: Self.date(2026, 6, 1))

        let deleted = try repository.deleteTransactions(for: .today, now: now)

        #expect(deleted == 1)
        #expect(try repository.transactionDeletionSummary(for: .today, now: now).count == 0)
        // The June 1 transaction survives and is still counted in this-month scope.
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 1)
    }

    // MARK: - Month + aggregates

    @Test func deleteMonthRecomputesCashflowAggregate() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let category = try makeExpenseCategory(repository: repository)

        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 5_000, at: Self.date(2026, 6, 15))
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 5_000, at: Self.date(2026, 6, 1))

        let before = try repository.dashboard(monthKey: thisMonthKey, walletID: wallet.id)
        #expect(before.monthExpenseMinor == 10_000)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(deleted == 2)
        let after = try repository.dashboard(monthKey: thisMonthKey, walletID: wallet.id)
        #expect(after.monthExpenseMinor == 0)
        // A different month is untouched.
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 3_000, at: Self.date(2026, 5, 20))
        let mayBefore = try repository.dashboard(monthKey: 202605, walletID: wallet.id)
        #expect(mayBefore.monthExpenseMinor == 3_000)
    }

    // MARK: - Year

    @Test func deleteYearRemovesAllMonthsInRange() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let category = try makeExpenseCategory(repository: repository)

        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 1_000, at: Self.date(2026, 1, 10))
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 1_000, at: Self.date(2026, 12, 31))
        try saveExpense(repository: repository, walletID: wallet.id, categoryID: category.id, amountMinor: 1_000, at: Self.date(2025, 12, 31))

        let deleted = try repository.deleteTransactions(for: .thisYear, now: now)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionSummary(for: .thisYear, now: now).count == 0)
        // Last-year transaction survives.
        #expect(try repository.transactionDeletionSummary(for: .today, now: Self.date(2025, 12, 31)).count == 1)
    }

    // MARK: - Cascade

    @Test func deleteCascadesTransactionLabels() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let category = try makeExpenseCategory(repository: repository)
        let label = LabelBuilder().with(name: "To Remove").build()
        try repository.saveLabel(label)

        let inPeriodID = try saveExpense(
            repository: repository, walletID: wallet.id, categoryID: category.id,
            amountMinor: 1_000, at: Self.date(2026, 6, 15), labelIDs: [label.id]
        )
        // Also tag a transaction outside the period; its label must survive.
        let outPeriodID = try saveExpense(
            repository: repository, walletID: wallet.id, categoryID: category.id,
            amountMinor: 1_000, at: Self.date(2025, 12, 15), labelIDs: [label.id]
        )

        func labelCount(for transactionID: UUID) throws -> Int {
            try repository.databaseManager.dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transaction_labels WHERE transaction_id = ?", arguments: [transactionID.uuidString]) ?? 0
            }
        }

        #expect(try labelCount(for: inPeriodID) == 1)
        #expect(try labelCount(for: outPeriodID) == 1)

        _ = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(try labelCount(for: inPeriodID) == 0)
        #expect(try labelCount(for: outPeriodID) == 1)
    }

    // MARK: - Transfers

    @Test func deleteTransferRemovesBothHalvesWhenInPeriod() throws {
        let repository = try makeRepository()
        let source = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let destination = try makeWallet(repository: repository, name: "Savings", balanceMinor: 0)
        let category = try makeExpenseCategory(repository: repository)

        var transfer = TransactionBuilder()
            .with(kind: .transfer)
            .with(walletID: source.id)
            .with(destinationWalletID: destination.id)
            .with(amountMinor: 2_500)
            .with(occurredAt: Self.date(2026, 6, 15))
            .with(categoryID: category.id)
            .build()
        transfer.id = UUID()
        try repository.saveTransaction(transfer)

        let before = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        // Both halves fall in June 2026.
        #expect(before.count == 2)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 0)
    }

    // MARK: - Empty

    @Test func deleteEmptyPeriodReturnsZero() throws {
        let repository = try makeRepository()
        _ = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)
        #expect(deleted == 0)
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 0)
    }
}
