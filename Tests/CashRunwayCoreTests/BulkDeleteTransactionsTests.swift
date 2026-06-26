import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BulkDeleteTransactionsTests {

    // Fixed "now" so period membership is deterministic regardless of test run date.
    private let now = Self.date(2026, 6, 15)
    private let thisMonthKey = 202606

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
        let category = CategoryBuilder().with(name: "Bulk Delete Expense").with(kind: .expense).build()
        try repository.saveCategory(category)
        return category
    }

    private func makeIncomeCategory(repository: CashRunwayRepository) throws -> CashRunwayCore.Category {
        let category = CategoryBuilder().with(name: "Bulk Delete Income").with(kind: .income).build()
        try repository.saveCategory(category)
        return category
    }

    @discardableResult
    private func saveTransaction(
        repository: CashRunwayRepository,
        kind: TransactionDraft.Kind,
        walletID: UUID,
        categoryID: UUID?,
        amountMinor: Int64,
        at date: Date,
        id: UUID = UUID(),
        labelIDs: [UUID] = [],
        destinationWalletID: UUID? = nil
    ) throws -> UUID {
        var draft = TransactionBuilder()
            .with(kind: kind)
            .with(walletID: walletID)
            .with(destinationWalletID: destinationWalletID)
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

    private func countRows(repository: CashRunwayRepository, table: String, transactionID: UUID) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE transaction_id = ?", arguments: [transactionID.uuidString]) ?? 0
        }
    }

    private func transactionExists(repository: CashRunwayRepository, id: UUID) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE id = ?", arguments: [id.uuidString]) ?? 0
        }
    }

    private func countTable(repository: CashRunwayRepository, _ table: String) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }

    /// Inserts a transaction row bypassing the draft/save pipeline, so we can place a
    /// transfer pair on different dates (the normal API forces both halves to one date).
    @discardableResult
    private func insertRawTransaction(
        repository: CashRunwayRepository,
        id: UUID,
        walletID: UUID,
        type: String,
        linkedTransferID: UUID?,
        amountMinor: Int64,
        occurredAt: Date
    ) throws -> UUID {
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transactions
                (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key,
                 category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id,
                 import_job_id, import_fingerprint, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, '', '', 0, 'manual', NULL, NULL, NULL, NULL, ?, ?)
                """,
                arguments: [
                    id.uuidString, walletID.uuidString, type, linkedTransferID?.uuidString,
                    amountMinor, occurredAt, DateKeys.dayKey(for: occurredAt), DateKeys.monthKey(for: occurredAt),
                    Date(), Date()
                ]
            )
        }
        return id
    }

    // MARK: - Summary

    @Test func summaryCountsAndSplitsAmountsByKind() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)
        let income = try makeIncomeCategory(repository: repository)

        // Today: 2 expenses + 1 income.
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .income, walletID: wallet.id, categoryID: income.id, amountMinor: 5_000, at: Self.date(2026, 6, 15))
        // This month, not today.
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 4_000, at: Self.date(2026, 6, 1))
        // This year, not this month.
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 8_000, at: Self.date(2026, 5, 20))
        // Last year (excluded everywhere).
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 16_000, at: Self.date(2025, 12, 15))

        let today = try repository.transactionDeletionSummary(for: .today, now: now)
        let month = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        let year = try repository.transactionDeletionSummary(for: .thisYear, now: now)

        #expect(today.count == 3)
        #expect(today.expenseMinor == 3_000)
        #expect(today.incomeMinor == 5_000)
        #expect(month.count == 4)
        #expect(month.expenseMinor == 7_000)
        #expect(month.incomeMinor == 5_000)
        #expect(year.count == 5)
        #expect(year.expenseMinor == 15_000)
    }

    // MARK: - Day

    @Test func deleteTodayRemovesOnlyTodayAndPreservesOthers() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 1))

        let deleted = try repository.deleteTransactions(for: .today, now: now)

        #expect(deleted == 1)
        #expect(try repository.transactionDeletionSummary(for: .today, now: now).count == 0)
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 1)
    }

    @Test func todayDeleteBoundaryExcludesAdjacentDays() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 14)) // yesterday
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 15)) // today
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 3_000, at: Self.date(2026, 6, 16)) // tomorrow

        _ = try repository.deleteTransactions(for: .today, now: now)

        #expect(try repository.transactionDeletionSummary(for: .today, now: now).count == 0)
        let monthSummary = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        #expect(monthSummary.count == 2)
        #expect(monthSummary.expenseMinor == 4_000) // yesterday + tomorrow survive
    }

    // MARK: - Month

    @Test func deleteMonthRecomputesCashflowAggregate() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 5_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 5_000, at: Self.date(2026, 6, 1))

        let before = try repository.dashboard(monthKey: thisMonthKey, walletID: wallet.id)
        #expect(before.monthExpenseMinor == 10_000)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(deleted == 2)
        let after = try repository.dashboard(monthKey: thisMonthKey, walletID: wallet.id)
        #expect(after.monthExpenseMinor == 0)
    }

    @Test func monthDeleteBoundaryExcludesAdjacentMonths() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 5, 31)) // prev month last day
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 1))  // this month first day
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 3_000, at: Self.date(2026, 7, 1))  // next month first day

        _ = try repository.deleteTransactions(for: .thisMonth, now: now)

        // Adjacent-month transactions survive.
        #expect(try repository.transactionDeletionSummary(for: .today, now: Self.date(2026, 5, 31)).count == 1)
        #expect(try repository.transactionDeletionSummary(for: .today, now: Self.date(2026, 7, 1)).count == 1)
        #expect(try repository.transactionDeletionSummary(for: .thisYear, now: now).count == 2)
    }

    // MARK: - Year

    @Test func deleteYearRemovesAllMonthsInRange() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 1, 10))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 12, 31))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 31))

        let deleted = try repository.deleteTransactions(for: .thisYear, now: now)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionSummary(for: .thisYear, now: now).count == 0)
        #expect(try repository.transactionDeletionSummary(for: .today, now: Self.date(2025, 12, 31)).count == 1)
    }

    @Test func yearDeleteBoundaryExcludesAdjacentYears() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 31)) // prev year
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 1, 1))   // this year first day
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 3_000, at: Self.date(2026, 12, 31)) // this year last day
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 4_000, at: Self.date(2027, 1, 1))   // next year

        let deleted = try repository.deleteTransactions(for: .thisYear, now: now)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionSummary(for: .today, now: Self.date(2025, 12, 31)).count == 1)
        #expect(try repository.transactionDeletionSummary(for: .today, now: Self.date(2027, 1, 1)).count == 1)
    }

    // MARK: - Multi-wallet

    @Test func deleteAffectsAllWalletsButOnlyInPeriod() throws {
        let repository = try makeRepository()
        let a = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let b = try makeWallet(repository: repository, name: "Card", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        // Both wallets have a transaction in-period and one out-of-period.
        try saveTransaction(repository: repository, kind: .expense, walletID: a.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: a.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: b.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: b.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 15))

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(deleted == 2) // one in-period txn per wallet
        // Both wallets' out-of-period transactions survive.
        #expect(try repository.transactionDeletionSummary(for: .thisYear, now: Self.date(2025, 12, 15)).count == 2)
    }

    // MARK: - Mixed types

    @Test func deleteCountsAllTransactionTypes() throws {
        let repository = try makeRepository()
        let source = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let destination = try makeWallet(repository: repository, name: "Savings", balanceMinor: 0)
        let expense = try makeExpenseCategory(repository: repository)
        let income = try makeIncomeCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: source.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .income, walletID: source.id, categoryID: income.id, amountMinor: 2_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .transfer, walletID: source.id, categoryID: nil, amountMinor: 500, at: Self.date(2026, 6, 15), destinationWalletID: destination.id)

        let summary = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        // Expense + income + both transfer halves = 4 rows.
        #expect(summary.count == 4)
        #expect(summary.expenseMinor == 1_000)
        #expect(summary.incomeMinor == 2_000)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)
        #expect(deleted == 4)
    }

    // MARK: - Cascade

    @Test func deleteCascadesTransactionLabels() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)
        let label = LabelBuilder().with(name: "To Remove").build()
        try repository.saveLabel(label)

        let inPeriodID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15), labelIDs: [label.id])
        let outPeriodID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 15), labelIDs: [label.id])

        #expect(try countRows(repository: repository, table: "transaction_labels", transactionID: inPeriodID) == 1)
        #expect(try countRows(repository: repository, table: "transaction_labels", transactionID: outPeriodID) == 1)

        _ = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(try countRows(repository: repository, table: "transaction_labels", transactionID: inPeriodID) == 0)
        #expect(try countRows(repository: repository, table: "transaction_labels", transactionID: outPeriodID) == 1)
    }

    @Test func deleteCascadesTransactionSearchRows() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        // saveSingleTransaction populates transaction_search via syncSearch.
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 10))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 15))

        let searchBefore = try countTable(repository: repository, "transaction_search")
        #expect(searchBefore == 3)

        _ = try repository.deleteTransactions(for: .thisMonth, now: now)

        // Only the out-of-period search row survives.
        let searchAfter = try countTable(repository: repository, "transaction_search")
        #expect(searchAfter == 1)
    }

    // MARK: - Transfers

    @Test func deleteTransferRemovesBothHalvesWhenInPeriod() throws {
        let repository = try makeRepository()
        let source = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let destination = try makeWallet(repository: repository, name: "Savings", balanceMinor: 0)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .transfer, walletID: source.id, categoryID: expense.id, amountMinor: 2_500, at: Self.date(2026, 6, 15), destinationWalletID: destination.id)

        let before = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        #expect(before.count == 2)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 0)
    }

    @Test func deleteDoesNotExpandToLinkedTransferOutsidePeriod() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        // A transfer pair deliberately split across the month boundary (the normal API
        // cannot produce this; raw insert can). The in-period half points at the
        // out-of-period half via linked_transfer_id.
        let inPeriodID = UUID()
        let outPeriodID = UUID()
        try insertRawTransaction(repository: repository, id: inPeriodID, walletID: wallet.id, type: "transfer_out", linkedTransferID: outPeriodID, amountMinor: 2_500, occurredAt: Self.date(2026, 6, 15))
        try insertRawTransaction(repository: repository, id: outPeriodID, walletID: wallet.id, type: "transfer_in", linkedTransferID: inPeriodID, amountMinor: 2_500, occurredAt: Self.date(2026, 5, 20))

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(deleted == 1)
        #expect(try transactionExists(repository: repository, id: inPeriodID) == 0)
        // The linked half outside the period is NOT followed/deleted.
        #expect(try transactionExists(repository: repository, id: outPeriodID) == 1)
    }

    // MARK: - Isolation: nothing but in-period transactions is touched

    @Test func deleteLeavesSiblingTablesUntouched() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 5_000_000)
        let expense = try makeExpenseCategory(repository: repository)
        let income = try makeIncomeCategory(repository: repository)
        let label = LabelBuilder().with(name: "Keep").build()
        try repository.saveLabel(label)
        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id, counterpartyWalletID: nil,
            amountMinor: 1_000, categoryID: expense.id, merchant: "Sub", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 1, weekday: nil,
            startDate: now, endDate: nil, isActive: true, createdAt: now, updatedAt: now
        )
        try repository.saveRecurringTemplate(template)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15), labelIDs: [label.id])
        try saveTransaction(repository: repository, kind: .income, walletID: wallet.id, categoryID: income.id, amountMinor: 9_000, at: Self.date(2026, 6, 10))

        let walletsBefore = try countTable(repository: repository, "wallets")
        let categoriesBefore = try countTable(repository: repository, "categories")
        let labelsBefore = try countTable(repository: repository, "labels")
        let templatesBefore = try repository.recurringTemplates().count

        _ = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(try countTable(repository: repository, "wallets") == walletsBefore)
        #expect(try countTable(repository: repository, "categories") == categoriesBefore)
        #expect(try countTable(repository: repository, "labels") == labelsBefore)
        // Recurring template survives even though a generated instance would be deleted.
        #expect(try repository.recurringTemplates().count == templatesBefore)
        #expect(try repository.recurringTemplates().contains { $0.id == template.id })
        // Label definition itself survives (only the transaction_labels join rows go).
        #expect(try repository.labels().contains { $0.id == label.id })
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 0)
    }

    // MARK: - Idempotency

    @Test func deleteIsIdempotent() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))

        let first = try repository.deleteTransactions(for: .thisMonth, now: now)
        let second = try repository.deleteTransactions(for: .thisMonth, now: now)

        #expect(first == 1)
        #expect(second == 0)
    }

    @Test func deleteEmptyPeriodReturnsZero() throws {
        let repository = try makeRepository()
        _ = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        let deleted = try repository.deleteTransactions(for: .thisMonth, now: now)
        #expect(deleted == 0)
        #expect(try repository.transactionDeletionSummary(for: .thisMonth, now: now).count == 0)
    }

    // MARK: - Public surface (identifiable id + button plural title)

    @Test func periodIdentityAndButtonTitleAreStable() {
        #expect(DeletePeriod.allCases.map(\.id) == ["today", "thisMonth", "thisYear"])
        // Plural helper embeds the count regardless of active language.
        #expect(L10n.deleteTransactionsButtonTitle(1).contains("1"))
        #expect(L10n.deleteTransactionsButtonTitle(3).contains("3"))
    }
}
