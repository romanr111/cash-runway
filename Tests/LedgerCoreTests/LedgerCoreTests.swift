import Foundation
import GRDB
import Testing
@testable import LedgerCore

struct LedgerCoreTests {
    @Test func parsesMoneyIntoMinorUnits() throws {
        #expect(try MoneyFormatter.parseMinorUnits("123,45") == 12_345)
        #expect(try MoneyFormatter.parseMinorUnits("-99.30") == -9_930)
    }

    @Test func monthAndDayKeysAreStable() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 4, day: 26))!
        #expect(DateKeys.dayKey(for: date) == 20260426)
        #expect(DateKeys.monthKey(for: date) == 202604)
    }

    @Test func migrationReopensExistingDatabase() throws {
        let location = TestSupport.makeLocation()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location)
        try LedgerRepository(databaseManager: try #require(manager)).seedIfNeeded()
        manager = nil
        let reopened = try DatabaseManager(locationProvider: location)
        let repository = LedgerRepository(databaseManager: reopened)
        #expect(try repository.wallets().count >= 2)
        #expect(try repository.categories().count >= SeedCategories.all.count)
    }

    @Test func destructiveRecoveryRecreatesUnreadableDatabase() throws {
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        try Data("not-a-database".utf8).write(to: dbURL)

        let manager = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: true)
        let repository = LedgerRepository(databaseManager: manager)
        try repository.seedIfNeeded()

        #expect(try repository.wallets().count >= 2)
        let recoveryDirectory = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let recoveredEntries = try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)
        #expect(recoveredEntries.contains { $0.lastPathComponent.contains("ledger.sqlite") })
    }

    @Test func recurringGenerationIsDeterministic() {
        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: UUID(),
            counterpartyWalletID: nil,
            amountMinor: 100,
            categoryID: UUID(),
            merchant: nil,
            note: nil,
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 15,
            weekday: nil,
            startDate: DateKeys.startOfMonth(for: 202601),
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
        let dates = LedgerRepository.generatedDates(
            for: template,
            start: DateKeys.startOfMonth(for: 202601),
            end: DateKeys.startOfMonth(for: 202603)
        )
        #expect(dates.count == 2)
        #expect(DateKeys.dayKey(for: dates[0]) == 20260115)
        #expect(DateKeys.dayKey(for: dates[1]) == 20260215)
    }

    @Test func transactionMutationsKeepAggregatesCorrect() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)

        let createdAt = DateKeys.startOfMonth(for: DateKeys.monthKey(for: .now))
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: wallets[0].id,
                amountMinor: 12_500,
                occurredAt: createdAt,
                categoryID: expenseCategory.id,
                merchant: "Market",
                note: "Initial"
            )
        )
        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)

        let draftID = try #require(try repository.transactions().first?.id)
        try repository.saveTransaction(
            TransactionDraft(
                id: draftID,
                kind: .income,
                walletID: wallets[1].id,
                amountMinor: 40_000,
                occurredAt: Calendar.current.date(byAdding: .month, value: -1, to: createdAt) ?? createdAt,
                categoryID: incomeCategory.id,
                merchant: "Salary",
                note: "Edited"
            )
        )

        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)
        try repository.deleteTransaction(id: draftID)
        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func transferEditsRemainBalanced() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let when = Date()

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: wallets[0].id,
                destinationWalletID: wallets[1].id,
                amountMinor: 18_000,
                occurredAt: when,
                merchant: "Move",
                note: "Initial transfer"
            )
        )

        let transferID = try #require(try repository.transactions(query: .init(kinds: [.transfer])).first?.id)
        try repository.saveTransaction(
            TransactionDraft(
                id: transferID,
                kind: .transfer,
                walletID: wallets[1].id,
                destinationWalletID: wallets[0].id,
                amountMinor: 9_500,
                occurredAt: Calendar.current.date(byAdding: .day, value: -2, to: when) ?? when,
                merchant: "Move Back",
                note: "Edited transfer"
            )
        )

        try TestSupport.assertWalletTruth(repository)
        let pairCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type IN ('transfer_out', 'transfer_in')") ?? 0
        }
        #expect(pairCount == 2)
    }

    @Test func budgetProgressTracksTransactionMutations() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let monthKey = DateKeys.monthKey(for: .now)
        let expenseCategories = try repository.categories(kind: .expense)
        let groceries = try #require(expenseCategories.first)
        let restaurants = try #require(expenseCategories.dropFirst().first)
        let budget = Budget(id: UUID(), categoryID: groceries.id, monthKey: monthKey, limitMinor: 50_000, isArchived: false, createdAt: .now, updatedAt: .now)
        try repository.saveBudget(budget)

        let walletID = try #require(try repository.wallets().first?.id)
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 12_000,
                occurredAt: .now,
                categoryID: groceries.id,
                merchant: "Groceries",
                note: ""
            )
        )

        var progress = try #require(try repository.budgets(monthKey: monthKey).first(where: { $0.budget.id == budget.id }))
        #expect(progress.spentMinor == 12_000)

        let transactionID = try #require(try repository.transactions().first?.id)
        try repository.saveTransaction(
            TransactionDraft(
                id: transactionID,
                kind: .expense,
                walletID: walletID,
                amountMinor: 9_000,
                occurredAt: .now,
                categoryID: restaurants.id,
                merchant: "Dinner",
                note: ""
            )
        )

        progress = try #require(try repository.budgets(monthKey: monthKey).first(where: { $0.budget.id == budget.id }))
        #expect(progress.spentMinor == 0)
    }

    @Test func timelineSnapshotGroupsHistoryAndMonthlyBars() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first?.id)
        let incomeCategory = try #require(try repository.categories(kind: .income).first?.id)
        let monthKey = DateKeys.monthKey(for: .now)
        let previousMonthDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: wallets[0].id,
                amountMinor: 12_300,
                occurredAt: .now,
                categoryID: expenseCategory,
                merchant: "Coffee",
                note: "Morning"
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .income,
                walletID: wallets[0].id,
                amountMinor: 50_000,
                occurredAt: .now,
                categoryID: incomeCategory,
                merchant: "Salary",
                note: "Monthly"
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: wallets[0].id,
                amountMinor: 7_500,
                occurredAt: previousMonthDate,
                categoryID: expenseCategory,
                merchant: "Taxi",
                note: ""
            )
        )

        let snapshot = try repository.timelineSnapshot(monthKey: monthKey)
        #expect(snapshot.monthlyBars.count == 6)
        #expect(snapshot.heroCashFlowMinor == 37_700)
        #expect(snapshot.sections.isEmpty == false)
        #expect(snapshot.sections.first?.items.contains(where: { $0.merchant == "Coffee" }) == true)
    }

    @Test func overviewSnapshotSeparatesExpenseAndIncomeCategories() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first?.id)
        let incomeCategory = try #require(try repository.categories(kind: .income).first?.id)
        let monthKey = DateKeys.monthKey(for: .now)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 9_900,
                occurredAt: .now,
                categoryID: expenseCategory,
                merchant: "Lunch",
                note: ""
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .income,
                walletID: walletID,
                amountMinor: 80_000,
                occurredAt: .now,
                categoryID: incomeCategory,
                merchant: "Payroll",
                note: ""
            )
        )

        let snapshot = try repository.overviewSnapshot(monthKey: monthKey)
        #expect(snapshot.months.count == 6)
        #expect(snapshot.monthExpenseMinor == 9_900)
        #expect(snapshot.monthIncomeMinor == 80_000)
        #expect(snapshot.categories.contains(where: { $0.kind == .expense && $0.amountMinor == 9_900 }))
        #expect(snapshot.categories.contains(where: { $0.kind == .income && $0.amountMinor == 80_000 }))
    }

    @Test func categoryManagementCountsAndOrderingPersist() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let firstCategory = try #require(categories.first)
        let secondCategory = try #require(categories.dropFirst().first)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: wallets[0].id,
                amountMinor: 1_500,
                occurredAt: .now,
                categoryID: firstCategory.id,
                merchant: "First wallet",
                note: ""
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: wallets[1].id,
                amountMinor: 2_000,
                occurredAt: .now,
                categoryID: firstCategory.id,
                merchant: "Second wallet",
                note: ""
            )
        )

        let items = try repository.categoryManagementItems(kind: .expense)
        let managedFirst = try #require(items.first(where: { $0.category.id == firstCategory.id }))
        #expect(managedFirst.transactionCount == 2)
        #expect(managedFirst.walletCount == 2)

        try repository.reorderCategories(kind: .expense, orderedCategoryIDs: [secondCategory.id, firstCategory.id] + categories.dropFirst(2).map(\.id))
        let reordered = try repository.categories(kind: .expense)
        #expect(reordered.first?.id == secondCategory.id)
    }

    @Test func recurringPostingUpdatesInstanceAndTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let categoryID = try #require(try repository.categories(kind: .expense).first?.id)
        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: walletID,
            counterpartyWalletID: nil,
            amountMinor: 7_500,
            categoryID: categoryID,
            merchant: "Gym",
            note: "Recurring",
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: Calendar.current.component(.day, from: .now),
            weekday: nil,
            startDate: .now,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)

        let instance = try #require(try repository.recurringInstances().first(where: { $0.templateID == template.id && $0.status == .scheduled }))
        try repository.postRecurringInstance(id: instance.id)
        let posted = try #require(try repository.recurringInstances().first(where: { $0.id == instance.id }))
        #expect(posted.status == .posted)
        #expect(posted.linkedTransactionID != nil)
        try TestSupport.assertWalletTruth(repository)
    }

    @Test func csvImportExportAndSearchWorkTogether() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Amount,Merchant,Note
        2026-01-02,123.45,Silpo,Weekly groceries
        2026-01-04,88.10,Metro,Home goods
        """

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "sample.csv",
            mapping: CSVImportMapping(
                dateColumn: "Date",
                amountColumn: "Amount",
                debitColumn: nil,
                creditColumn: nil,
                merchantColumn: "Merchant",
                noteColumn: "Note",
                categoryColumn: nil,
                labelsColumn: nil,
                walletID: walletID,
                defaultKind: .expense
            )
        )

        #expect(result.insertedTransactions == 2)
        let importStatus = try repository.databaseManager.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM import_jobs WHERE id = ?", arguments: [result.job.id.uuidString])
        }
        #expect(importStatus == ImportJobStatus.committed.rawValue)
        let searchResults = try repository.transactions(query: .init(searchText: "Silp"))
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.source == .importCSV)
        try TestSupport.assertCategoryTruth(repository)
        let exported = try service.exportCSV(query: .init(searchText: "Silp"))
        #expect(exported.contains("import_csv"))
    }

    @Test func randomizedMutationSequencePreservesTruth() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        var rng = FixtureGenerator.SeededRNG(seed: 77)
        let wallets = try repository.wallets()
        let expenseCategories = try repository.categories(kind: .expense)
        let incomeCategories = try repository.categories(kind: .income)
        var createdIDs: [UUID] = []

        for step in 0..<30 {
            if !createdIDs.isEmpty, Int.random(in: 0..<5, using: &rng) == 0 {
                let index = Int.random(in: 0..<createdIDs.count, using: &rng)
                try repository.deleteTransaction(id: createdIDs.remove(at: index))
            } else {
                let kind: TransactionDraft.Kind = Int.random(in: 0..<4, using: &rng) == 0 ? .income : .expense
                let wallet = wallets[Int.random(in: 0..<wallets.count, using: &rng)]
                let category = (kind == .income ? incomeCategories : expenseCategories)[Int.random(in: 0..<(kind == .income ? incomeCategories.count : expenseCategories.count), using: &rng)]
                let draftID = UUID()
                let draft = TransactionDraft(
                    id: draftID,
                    kind: kind,
                    walletID: wallet.id,
                    amountMinor: Int64(Int.random(in: 500...30_000, using: &rng)),
                    occurredAt: Calendar.current.date(byAdding: .day, value: -step, to: .now) ?? .now,
                    categoryID: category.id,
                    merchant: "Random \(step)",
                    note: "Mutation \(step)"
                )
                try repository.saveTransaction(draft)
                createdIDs.append(draftID)
            }
            try TestSupport.assertWalletTruth(repository)
            try TestSupport.assertCategoryTruth(repository)
        }
    }
}

private enum TestSupport {
    static func makeRepository() throws -> LedgerRepository {
        LedgerRepository(databaseManager: try DatabaseManager(locationProvider: makeLocation()))
    }

    static func makeLocation() -> DatabaseLocationProvider {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spendee-ledger-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return DatabaseLocationProvider(
            appGroupIdentifier: nil,
            databaseURLOverride: baseURL.appendingPathComponent("ledger.sqlite"),
            directoryName: UUID().uuidString
        )
    }

    static func assertWalletTruth(_ repository: LedgerRepository) throws {
        let expected = try repository.databaseManager.dbQueue.read { db in
            var truth: [UUID: Int64] = [:]
            let wallets = try Row.fetchAll(db, sql: "SELECT id, starting_balance_minor FROM wallets")
            for row in wallets {
                truth[UUID(uuidString: row["id"])!] = row["starting_balance_minor"]
            }
            let transactions = try Row.fetchAll(db, sql: "SELECT wallet_id, type, amount_minor FROM transactions WHERE is_deleted = 0")
            for row in transactions {
                let walletID = UUID(uuidString: row["wallet_id"])!
                let type = TransactionKind(rawValue: row["type"]) ?? .expense
                let amount: Int64 = row["amount_minor"]
                truth[walletID, default: 0] += amount * type.walletDeltaSign
            }
            return truth
        }
        let actual = try Dictionary(uniqueKeysWithValues: repository.wallets().map { ($0.id, $0.currentBalanceMinor) })
        #expect(actual == expected)
    }

    static func assertCategoryTruth(_ repository: LedgerRepository) throws {
        let expected = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT category_id, local_month_key, SUM(amount_minor) AS total
                FROM transactions
                WHERE is_deleted = 0 AND type = 'expense' AND category_id IS NOT NULL
                GROUP BY category_id, local_month_key
                """
            )
        }
        let actual = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT category_id, month_key, expense_minor FROM monthly_category_spend")
        }
        let expectedMap = Dictionary(uniqueKeysWithValues: expected.map { ("\($0["category_id"] as String)-\($0["local_month_key"] as Int)", $0["total"] as Int64) })
        let actualMap = Dictionary(uniqueKeysWithValues: actual.map { ("\($0["category_id"] as String)-\($0["month_key"] as Int)", $0["expense_minor"] as Int64) })
        #expect(actualMap == expectedMap)
    }
}
