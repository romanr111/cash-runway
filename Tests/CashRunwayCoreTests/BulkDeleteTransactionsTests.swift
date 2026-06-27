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
    /// `isDeleted` allows creating tombstoned rows to verify bulk-delete filtering.
    @discardableResult
    private func insertRawTransaction(
        repository: CashRunwayRepository,
        id: UUID,
        walletID: UUID,
        type: String,
        linkedTransferID: UUID?,
        amountMinor: Int64,
        occurredAt: Date,
        isDeleted: Bool = false
    ) throws -> UUID {
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transactions
                (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key,
                 category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id,
                 import_job_id, import_fingerprint, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, '', '', ?, 'manual', NULL, NULL, NULL, NULL, ?, ?)
                """,
                arguments: [
                    id.uuidString, walletID.uuidString, type, linkedTransferID?.uuidString,
                    amountMinor, occurredAt, DateKeys.dayKey(for: occurredAt), DateKeys.monthKey(for: occurredAt),
                    isDeleted ? 1 : 0, Date(), Date()
                ]
            )
        }
        return id
    }

    private func setTransactionDate(repository: CashRunwayRepository, id: UUID, date: Date) throws {
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE transactions
                SET occurred_at = ?, local_day_key = ?, local_month_key = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [date, DateKeys.dayKey(for: date), DateKeys.monthKey(for: date), Date(), id.uuidString]
            )
        }
    }

    // MARK: - Summary / plan

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

        let today = try repository.transactionDeletionPlan(for: .today, now: now).summary
        let month = try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary
        let year = try repository.transactionDeletionPlan(for: .thisYear, now: now).summary

        #expect(today.count == 3)
        #expect(today.expenseMinor == 3_000)
        #expect(today.incomeMinor == 5_000)
        #expect(month.count == 4)
        #expect(month.expenseMinor == 7_000)
        #expect(month.incomeMinor == 5_000)
        #expect(year.count == 5)
        #expect(year.expenseMinor == 15_000)
    }

    @Test func planFreezesReferenceDateKeys() throws {
        let repository = try makeRepository()

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.period == .thisMonth)
        #expect(plan.referenceDayKey == 20260615)
        #expect(plan.referenceMonthKey == 202606)
        #expect(plan.referenceYear == 2026)
    }

    @Test func summaryMatchesPlanAndCountsTransfers() throws {
        let repository = try makeRepository()
        let source = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let destination = try makeWallet(repository: repository, name: "Savings", balanceMinor: 0)
        let expense = try makeExpenseCategory(repository: repository)
        let income = try makeIncomeCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: source.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .income, walletID: source.id, categoryID: income.id, amountMinor: 2_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .transfer, walletID: source.id, categoryID: nil, amountMinor: 500, at: Self.date(2026, 6, 15), destinationWalletID: destination.id)

        let summary = try repository.transactionDeletionSummary(for: .thisMonth, now: now)
        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)

        // The aggregate summary must match the plan summary exactly.
        #expect(summary == plan.summary)
        // `count` = physical rows (transfer pair = 2); `displayCount` = user-visible items.
        #expect(summary.count == 4)
        #expect(summary.displayCount == 3)
        #expect(summary.expenseMinor == 1_000)
        #expect(summary.incomeMinor == 2_000)
    }

    // MARK: - Day

    @Test func deleteTodayRemovesOnlyTodayAndPreservesOthers() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 1))

        let plan = try repository.transactionDeletionPlan(for: .today, now: now)
        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 1)
        #expect(try repository.transactionDeletionPlan(for: .today, now: now).summary.count == 0)
        #expect(try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary.count == 1)
    }

    @Test func todayDeleteBoundaryExcludesAdjacentDays() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 14)) // yesterday
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 15)) // today
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 3_000, at: Self.date(2026, 6, 16)) // tomorrow

        let plan = try repository.transactionDeletionPlan(for: .today, now: now)
        _ = try repository.deleteTransactions(plan)

        #expect(try repository.transactionDeletionPlan(for: .today, now: now).summary.count == 0)
        let monthSummary = try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary
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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        let deleted = try repository.deleteTransactions(plan)

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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        _ = try repository.deleteTransactions(plan)

        // Adjacent-month transactions survive.
        #expect(try repository.transactionDeletionPlan(for: .today, now: Self.date(2026, 5, 31)).summary.count == 1)
        #expect(try repository.transactionDeletionPlan(for: .today, now: Self.date(2026, 7, 1)).summary.count == 1)
        #expect(try repository.transactionDeletionPlan(for: .thisYear, now: now).summary.count == 2)
    }

    // MARK: - Year

    @Test func deleteYearRemovesAllMonthsInRange() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 1, 10))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 12, 31))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 31))

        let plan = try repository.transactionDeletionPlan(for: .thisYear, now: now)
        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionPlan(for: .thisYear, now: now).summary.count == 0)
        #expect(try repository.transactionDeletionPlan(for: .today, now: Self.date(2025, 12, 31)).summary.count == 1)
    }

    @Test func yearDeleteBoundaryExcludesAdjacentYears() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2025, 12, 31)) // prev year
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 1, 1))   // this year first day
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 3_000, at: Self.date(2026, 12, 31)) // this year last day
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 4_000, at: Self.date(2027, 1, 1))   // next year

        let plan = try repository.transactionDeletionPlan(for: .thisYear, now: now)
        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionPlan(for: .today, now: Self.date(2025, 12, 31)).summary.count == 1)
        #expect(try repository.transactionDeletionPlan(for: .today, now: Self.date(2027, 1, 1)).summary.count == 1)
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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 2) // one in-period txn per wallet
        // Both wallets' out-of-period transactions survive.
        #expect(try repository.transactionDeletionPlan(for: .thisYear, now: Self.date(2025, 12, 15)).summary.count == 2)
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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        // Expense + income + both transfer halves = 4 physical rows.
        #expect(plan.count == 4)
        // User-visible items: expense + income + 1 transfer = 3.
        #expect(plan.displayCount == 3)
        #expect(plan.expenseMinor == 1_000)
        #expect(plan.incomeMinor == 2_000)

        let deleted = try repository.deleteTransactions(plan)
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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        _ = try repository.deleteTransactions(plan)

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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        _ = try repository.deleteTransactions(plan)

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

        let before = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(before.count == 2)
        #expect(before.displayCount == 1)

        let deleted = try repository.deleteTransactions(before)

        #expect(deleted == 2)
        #expect(try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary.count == 0)
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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.transactionIDs == [inPeriodID])

        let deleted = try repository.deleteTransactions(plan)

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

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        _ = try repository.deleteTransactions(plan)

        #expect(try countTable(repository: repository, "wallets") == walletsBefore)
        #expect(try countTable(repository: repository, "categories") == categoriesBefore)
        #expect(try countTable(repository: repository, "labels") == labelsBefore)
        // Recurring template survives even though a generated instance would be deleted.
        #expect(try repository.recurringTemplates().count == templatesBefore)
        #expect(try repository.recurringTemplates().contains { $0.id == template.id })
        // Label definition itself survives (only the transaction_labels join rows go).
        #expect(try repository.labels().contains { $0.id == label.id })
        #expect(try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary.count == 0)
    }

    // MARK: - Idempotency

    @Test func deleteIsIdempotent() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))

        let first = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(try repository.deleteTransactions(first) == 1)

        let second = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(try repository.deleteTransactions(second) == 0)
    }

    @Test func deleteEmptyPeriodReturnsZero() throws {
        let repository = try makeRepository()
        _ = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.transactionIDs.isEmpty)

        let deleted = try repository.deleteTransactions(plan)
        #expect(deleted == 0)
        #expect(try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary.count == 0)
    }

    // MARK: - Frozen scope: date boundaries between preview and execution

    @Test func planForTodaySurvivesMidnightBoundary() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let june30 = Self.date(2026, 6, 30)
        let july1 = Self.date(2026, 7, 1)
        let juneID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: june30)
        let julyID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: july1)

        let plan = try repository.transactionDeletionPlan(for: .today, now: june30)
        #expect(plan.referenceDayKey == 20260630)
        #expect(plan.transactionIDs == [juneID])

        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 1)
        #expect(try transactionExists(repository: repository, id: juneID) == 0)
        #expect(try transactionExists(repository: repository, id: julyID) == 1)
    }

    @Test func planForMonthSurvivesMonthBoundary() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let june30 = Self.date(2026, 6, 30)
        let july1 = Self.date(2026, 7, 1)
        let juneID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: june30)
        let julyID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: july1)

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: june30)
        #expect(plan.referenceMonthKey == 202606)
        #expect(plan.transactionIDs == [juneID])

        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 1)
        #expect(try transactionExists(repository: repository, id: juneID) == 0)
        #expect(try transactionExists(repository: repository, id: julyID) == 1)
    }

    @Test func planForYearSurvivesYearBoundary() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let dec31 = Self.date(2026, 12, 31)
        let jan1 = Self.date(2027, 1, 1)
        let decID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: dec31)
        let janID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: jan1)

        let plan = try repository.transactionDeletionPlan(for: .thisYear, now: dec31)
        #expect(plan.referenceYear == 2026)
        #expect(plan.transactionIDs == [decID])

        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 1)
        #expect(try transactionExists(repository: repository, id: decID) == 0)
        #expect(try transactionExists(repository: repository, id: janID) == 1)
    }

    // MARK: - Frozen identity: set changes between preview and execution abort

    @Test func deleteAbortsWhenMatchingTransactionAddedAfterPreview() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let firstID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 10))
        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.transactionIDs == [firstID])

        let insertedID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 20))

        #expect(throws: TransactionDeletionError.planStale) {
            try repository.deleteTransactions(plan)
        }
        // Nothing was deleted.
        #expect(try transactionExists(repository: repository, id: firstID) == 1)
        #expect(try transactionExists(repository: repository, id: insertedID) == 1)
    }

    @Test func deleteAbortsWhenMatchingTransactionRemovedAfterPreview() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let firstID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 10))
        let secondID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 6, 20))

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.transactionIDs.sorted() == [firstID, secondID].sorted())

        try repository.deleteTransaction(id: firstID)

        #expect(throws: TransactionDeletionError.planStale) {
            try repository.deleteTransactions(plan)
        }
        // The surviving row is untouched.
        #expect(try transactionExists(repository: repository, id: firstID) == 0)
        #expect(try transactionExists(repository: repository, id: secondID) == 1)
    }

    @Test func deleteAbortsWhenTransactionsAreReplacedWithSameTotals() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let aID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 10))
        let bID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 20))
        let cID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 5, 10))

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.transactionIDs.sorted() == [aID, bID].sorted())
        #expect(plan.count == 2)
        #expect(plan.expenseMinor == 2_000)

        // Move A out of June and C into June: count and total stay the same, but the
        // identity of the rows changed. Execution must reject this.
        try setTransactionDate(repository: repository, id: aID, date: Self.date(2026, 5, 31))
        try setTransactionDate(repository: repository, id: cID, date: Self.date(2026, 6, 15))

        #expect(throws: TransactionDeletionError.planStale) {
            try repository.deleteTransactions(plan)
        }
        #expect(try transactionExists(repository: repository, id: aID) == 1)
        #expect(try transactionExists(repository: repository, id: bID) == 1)
        #expect(try transactionExists(repository: repository, id: cID) == 1)
    }

    @Test func deleteChunksLargePlan() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 100_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let ids = (0..<901).map { _ in UUID() }
        let date = Self.date(2026, 6, 15)
        let dayKey = DateKeys.dayKey(for: date)
        let monthKey = DateKeys.monthKey(for: date)
        let now = date
        try repository.databaseManager.dbQueue.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                    INSERT INTO transactions
                    (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key,
                     category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id,
                     import_job_id, import_fingerprint, created_at, updated_at)
                    VALUES (?, ?, 'expense', NULL, 1, ?, ?, ?, ?, '', '', 0, 'manual', NULL, NULL, NULL, NULL, ?, ?)
                    """,
                    arguments: [
                        id.uuidString, wallet.id.uuidString, date, dayKey, monthKey, expense.id.uuidString,
                        Date(), Date()
                    ]
                )
            }
        }

        let plan = try repository.transactionDeletionPlan(for: .today, now: now)
        #expect(plan.count == 901)

        let deleted = try repository.deleteTransactions(plan)

        #expect(deleted == 901)
        #expect(try repository.transactionDeletionPlan(for: .today, now: now).summary.count == 0)
    }

    // MARK: - Tombstones

    @Test func deleteExcludesTombstonedTransactionsFromImpactAndAggregateReversal() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let activeID = try saveTransaction(
            repository: repository,
            kind: .expense,
            walletID: wallet.id,
            categoryID: expense.id,
            amountMinor: 100_000,
            at: now
        )
        let tombstoneID = UUID()
        try insertRawTransaction(
            repository: repository,
            id: tombstoneID,
            walletID: wallet.id,
            type: "expense",
            linkedTransferID: nil,
            amountMinor: 100_000,
            occurredAt: now,
            isDeleted: true
        )

        // Preview and plan must see only the active transaction.
        let summary = try repository.transactionDeletionSummary(for: .today, now: now)
        #expect(summary.count == 1)
        #expect(summary.expenseMinor == 100_000)

        let plan = try repository.transactionDeletionPlan(for: .today, now: now)
        #expect(plan.transactionIDs == [activeID])

        // The active expense reduced the wallet; the tombstoned expense did not.
        let walletBefore = try repository.wallets().first { $0.id == wallet.id }
        #expect(walletBefore?.currentBalanceMinor == 900_000)

        _ = try repository.deleteTransactions(plan)

        // Only the active row is removed. The tombstone stays in place, still deleted.
        #expect(try transactionExists(repository: repository, id: activeID) == 0)
        #expect(try transactionExists(repository: repository, id: tombstoneID) == 1)
        let tombstoneFlag = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT is_deleted FROM transactions WHERE id = ?", arguments: [tombstoneID.uuidString])
        }
        #expect(tombstoneFlag == 1)

        // Wallet balance and monthly aggregates match the state after deleting only the
        // active row, because the tombstone is excluded from derived state.
        let walletAfter = try repository.wallets().first { $0.id == wallet.id }
        #expect(walletAfter?.currentBalanceMinor == 1_000_000)

        let dashboard = try repository.dashboard(monthKey: thisMonthKey, walletID: wallet.id)
        #expect(dashboard.monthExpenseMinor == 0)
        #expect(dashboard.monthIncomeMinor == 0)
    }

    @Test func planPeriodIdentityPreventsMismatchedSelection() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2026, 5, 15))

        let monthPlan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        let yearPlan = try repository.transactionDeletionPlan(for: .thisYear, now: now)

        // Each plan carries its own period so the UI can reject a stale result.
        #expect(monthPlan.period == .thisMonth)
        #expect(yearPlan.period == .thisYear)
        #expect(monthPlan != yearPlan)

        // Executing a plan still uses its frozen identity, not the caller's intent.
        let deleted = try repository.deleteTransactions(monthPlan)
        #expect(deleted == 1)
        #expect(try repository.transactionDeletionPlan(for: .thisMonth, now: now).summary.count == 0)
        #expect(try repository.transactionDeletionPlan(for: .thisYear, now: now).summary.count == 1)
    }

    // MARK: - Public surface (identifiable id + button plural title)

    @Test func periodIdentityAndButtonTitleAreStable() {
        #expect(DeletePeriod.allCases.map(\.id) == ["today", "thisMonth", "thisYear", "allHistory"])
        // Plural helper embeds the count regardless of active language.
        #expect(L10n.deleteTransactionsButtonTitle(1).contains("1"))
        #expect(L10n.deleteTransactionsButtonTitle(3).contains("3"))
    }

    // MARK: - Same-ID mutation detection (Finding 3)

    @Test func deleteAbortsWhenSameIDTransactionMutatedAfterPreview() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let txnID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        #expect(plan.transactionIDs == [txnID])

        // Mutate the transaction's amount while keeping the same ID and period.
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET amount_minor = ?, updated_at = ? WHERE id = ?",
                arguments: [100_000, Date(timeIntervalSinceNow: 100), txnID.uuidString]
            )
        }

        // Plan must reject because the updatedAt fingerprint changed.
        #expect(throws: TransactionDeletionError.planStale) {
            try repository.deleteTransactions(plan)
        }
        #expect(try transactionExists(repository: repository, id: txnID) == 1)
    }

    // MARK: - Dangling reference cleanup (Finding 4)

    @Test func deleteNullsBankImportTransactionReference() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let txnID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))

        // Simulate a bank import linked to this transaction.
        let importID = UUID()
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bank_transaction_imports
                (id, provider, integration_id, bank_account_id, provider_account_id,
                 provider_statement_item_id, statement_time, amount_minor_signed,
                 currency_code, raw_json, cash_runway_transaction_id, import_status, created_at, updated_at)
                VALUES (?, 'monobank', 'int1', 'acc1', 'acc1', 'item1', ?, ?, 980, '{}', ?, 'imported', ?, ?)
                """,
                arguments: [importID.uuidString, Int(now.timeIntervalSince1970), -1_000, txnID.uuidString, Date(), Date()]
            )
        }

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        _ = try repository.deleteTransactions(plan)

        // The import row survives (preserves dedup key) but its FK is nulled.
        let linkedID = try repository.databaseManager.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT cash_runway_transaction_id FROM bank_transaction_imports WHERE id = ?", arguments: [importID.uuidString])
        }
        #expect(linkedID == nil)
    }

    @Test func deleteNullsRecurringInstanceLinkedTransaction() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let txnID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))

        // Simulate a recurring instance linked to this transaction.
        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id, counterpartyWalletID: nil,
            amountMinor: 1_000, categoryID: expense.id, merchant: "Sub", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15, weekday: nil,
            startDate: now, endDate: nil, isActive: true, createdAt: now, updatedAt: now
        )
        try repository.saveRecurringTemplate(template)

        let instanceID = UUID()
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recurring_instances
                (id, template_id, due_date, day_key, status, linked_transaction_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'posted', ?, ?, ?)
                """,
                arguments: [instanceID.uuidString, template.id.uuidString, now, DateKeys.dayKey(for: now), txnID.uuidString, Date(), Date()]
            )
        }

        let plan = try repository.transactionDeletionPlan(for: .thisMonth, now: now)
        _ = try repository.deleteTransactions(plan)

        // The instance row survives (prevents repost) but its FK is nulled.
        let linkedID = try repository.databaseManager.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT linked_transaction_id FROM recurring_instances WHERE id = ?", arguments: [instanceID.uuidString])
        }
        #expect(linkedID == nil)
    }

    // MARK: - All History

    @Test func deleteAllHistoryRemovesEveryNonDeletedTransaction() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)
        let income = try makeIncomeCategory(repository: repository)

        // Transactions across many dates and kinds.
        _ = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        _ = try saveTransaction(repository: repository, kind: .income, walletID: wallet.id, categoryID: income.id, amountMinor: 2_000, at: Self.date(2025, 12, 1))
        _ = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 500, at: Self.date(2024, 1, 20))
        // Tombstone (excluded).
        let tombstoneID = UUID()
        try insertRawTransaction(repository: repository, id: tombstoneID, walletID: wallet.id, type: "expense", linkedTransferID: nil, amountMinor: 300, occurredAt: Self.date(2026, 6, 15), isDeleted: true)

        let plan = try repository.transactionDeletionPlan(for: .allHistory, now: now)
        #expect(plan.summary.count == 3)
        #expect(plan.transactionIDs.count == 3)

        let deleted = try repository.deleteTransactions(plan)
        #expect(deleted == 3)

        // Every non-tombstoned row is gone; the tombstone remains.
        #expect(try transactionExists(repository: repository, id: tombstoneID) == 1)
        #expect(try countTable(repository: repository, "transactions") == 1)
    }

    @Test func deleteAllHistoryMaintainsAggregates() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        _ = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 100_000, at: Self.date(2026, 6, 15))
        _ = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 200_000, at: Self.date(2025, 12, 1))

        // Wallet balance was reduced by 300_000.
        let walletBefore = try repository.wallets().first { $0.id == wallet.id }
        #expect(walletBefore?.currentBalanceMinor == 700_000)

        let plan = try repository.transactionDeletionPlan(for: .allHistory, now: now)
        _ = try repository.deleteTransactions(plan)

        // Wallet balance restored to starting amount.
        let walletAfter = try repository.wallets().first { $0.id == wallet.id }
        #expect(walletAfter?.currentBalanceMinor == 1_000_000)

        // Monthly aggregate table has no rows for this wallet.
        let aggregateCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM monthly_wallet_cashflow WHERE wallet_id = ?", arguments: [wallet.id.uuidString])
        }
        #expect(aggregateCount == 0)

        let categorySpendCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM monthly_category_spend WHERE category_id = ?", arguments: [expense.id.uuidString])
        }
        #expect(categorySpendCount == 0)
    }

    @Test func deleteAllHistoryPreservesRecurringTemplates() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id, counterpartyWalletID: nil,
            amountMinor: 1_000, categoryID: expense.id, merchant: "Sub", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15, weekday: nil,
            startDate: now, endDate: nil, isActive: true, createdAt: now, updatedAt: now
        )
        try repository.saveRecurringTemplate(template)

        // A posted instance linked to a transaction (the instance survives, FK nulled).
        let txnID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 15))
        let instanceID = UUID()
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recurring_instances
                (id, template_id, due_date, day_key, status, linked_transaction_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'posted', ?, ?, ?)
                """,
                arguments: [instanceID.uuidString, template.id.uuidString, now, DateKeys.dayKey(for: now), txnID.uuidString, Date(), Date()]
            )
        }

        let plan = try repository.transactionDeletionPlan(for: .allHistory, now: now)
        _ = try repository.deleteTransactions(plan)

        // Template is untouched; instance survives with nulled FK.
        let templateCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recurring_templates WHERE id = ?", arguments: [template.id.uuidString])
        }
        #expect(templateCount == 1)

        let linkedID = try repository.databaseManager.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT linked_transaction_id FROM recurring_instances WHERE id = ?", arguments: [instanceID.uuidString])
        }
        #expect(linkedID == nil)
    }

    @Test func deleteAllHistoryAbortsWhenTransactionAddedAfterPreview() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expense = try makeExpenseCategory(repository: repository)

        let firstID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 1_000, at: Self.date(2026, 6, 10))
        let plan = try repository.transactionDeletionPlan(for: .allHistory, now: now)
        #expect(plan.transactionIDs == [firstID])

        let insertedID = try saveTransaction(repository: repository, kind: .expense, walletID: wallet.id, categoryID: expense.id, amountMinor: 2_000, at: Self.date(2025, 5, 20))

        #expect(throws: TransactionDeletionError.planStale) {
            try repository.deleteTransactions(plan)
        }
        #expect(try transactionExists(repository: repository, id: firstID) == 1)
        #expect(try transactionExists(repository: repository, id: insertedID) == 1)
    }

    @Test func deleteAllHistoryEmptyDbIsNoop() throws {
        let repository = try makeRepository()
        // No transactions.
        let plan = try repository.transactionDeletionPlan(for: .allHistory, now: now)
        #expect(plan.summary.count == 0)
        #expect(try repository.deleteTransactions(plan) == 0)
    }
}
