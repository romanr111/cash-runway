import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CashRunwayCoreTests {
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
        try CashRunwayRepository(databaseManager: try #require(manager)).seedIfNeeded()
        manager = nil
        let reopened = try DatabaseManager(locationProvider: location)
        let repository = CashRunwayRepository(databaseManager: reopened)
        #expect(try repository.wallets().count >= 2)
        #expect(try repository.categories().count >= SeedCategories.all.count)
    }

    @Test func destructiveRecoveryRecreatesUnreadableDatabase() throws {
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        try Data("not-a-database".utf8).write(to: dbURL)

        let manager = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: true)
        let repository = CashRunwayRepository(databaseManager: manager)
        try repository.seedIfNeeded()

        #expect(try repository.wallets().count >= 2)
        let recoveryDirectory = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let recoveredEntries = try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)
        #expect(recoveredEntries.contains { $0.lastPathComponent.contains("cash-runway.sqlite") })
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
        let dates = CashRunwayRepository.generatedDates(
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
        let currentBar = try #require(snapshot.monthlyBars.first(where: { $0.monthKey == monthKey }))
        #expect(currentBar.incomeBarMinor == 50_000)
        #expect(currentBar.expenseBarMinor == 12_300)
        #expect(snapshot.sections.isEmpty == false)
        #expect(snapshot.sections.first?.items.contains(where: { $0.merchant == "Coffee" }) == true)
    }

    @Test func overviewSnapshotSeparatesExpenseIncomeAndLabels() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first?.id)
        let incomeCategory = try #require(try repository.categories(kind: .income).first?.id)
        let diningLabel = Label(id: UUID(), name: "Dining", colorHex: "#1CC389", createdAt: .now, updatedAt: .now)
        let payrollLabel = Label(id: UUID(), name: "Payroll", colorHex: "#60788A", createdAt: .now, updatedAt: .now)
        let monthKey = DateKeys.monthKey(for: .now)
        try repository.saveLabel(diningLabel)
        try repository.saveLabel(payrollLabel)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 9_900,
                occurredAt: .now,
                categoryID: expenseCategory,
                labelIDs: [diningLabel.id],
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
                labelIDs: [payrollLabel.id],
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
        let expenseLabel = try #require(snapshot.labels.first(where: { $0.kind == .expense && $0.labelID == diningLabel.id }))
        #expect(expenseLabel.amountMinor == 9_900)
        #expect(expenseLabel.transactionCount == 1)
        #expect(expenseLabel.percentage == 1)
        let incomeLabel = try #require(snapshot.labels.first(where: { $0.kind == .income && $0.labelID == payrollLabel.id }))
        #expect(incomeLabel.amountMinor == 80_000)
        #expect(incomeLabel.transactionCount == 1)
        #expect(incomeLabel.percentage == 1)
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
        #expect(exported.split(separator: "\n").first == "Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author")
        #expect(exported.contains("\"Expense\""))
        #expect(exported.contains("\"-123.45\""))
    }

    @Test func cashRunwayWalletCSVFormatImportsSignedRowsAndExportsRoundTrippableFile() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let label = Label(id: UUID(), name: "Trip", colorHex: "#1CC389", createdAt: .now, updatedAt: .now)
        try repository.saveLabel(label)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,Groceries,-123.45,UAH,"weekly, groceries",Trip,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Income,Salary,400.00,UAH,Monthly salary,,ignored@example.com
        """

        let preview = try service.preview(data: Data(csv.utf8))
        #expect(service.detectPreset(headers: preview.headers) == .cashRunwayWallet)
        #expect(preview.totalRows == 2)
        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "wallet.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: wallet.id)
        )

        #expect(result.insertedTransactions == 2)
        #expect(result.rowErrors.isEmpty)
        let imported = try repository.transactions()
        #expect(imported.filter { $0.kind == .expense }.count == 1)
        #expect(imported.filter { $0.kind == .income }.count == 1)
        #expect(imported.contains { $0.kind == .expense && $0.amountMinor == -12_345 && $0.categoryName == "Groceries" && $0.labels.map(\.id).contains(label.id) })
        #expect(imported.contains { $0.kind == .income && $0.amountMinor == 40_000 && $0.categoryName == "Salary" })
        #expect(try repository.transactions(query: .init(searchText: "weekly")).count == 1)
        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)

        let exported = try service.exportCSV()
        #expect(exported.split(separator: "\n").first == "Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author")
        #expect(exported.contains("\"Expense\",\"Groceries\",\"-123.45\""))
        #expect(exported.contains("\"Income\",\"Salary\",\"400.00\""))

        let roundTripRepository = try TestSupport.makeRepository()
        try roundTripRepository.seedIfNeeded()
        try roundTripRepository.saveLabel(label)
        let roundTripService = CSVService(repository: roundTripRepository)
        let roundTripWalletID = try #require(try roundTripRepository.wallets().first?.id)
        let roundTrip = try roundTripService.importCSV(
            data: Data(exported.utf8),
            fileName: "wallet-roundtrip.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
        )

        #expect(roundTrip.insertedTransactions == 2)
        try TestSupport.assertTypeMonthCategoryAndLabelTotalsMatch(repository, roundTripRepository)
    }

    @Test func csvImportCreatesMissingCategoriesFromMappedColumn() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,Pet Supplies,-123.45,UAH,Kibble,,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Income,Side Project,400.00,UAH,Invoice,,ignored@example.com
        """

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "wallet.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: wallet.id)
        )

        #expect(result.insertedTransactions == 2)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first(where: { $0.name == "Pet Supplies" }))
        let incomeCategory = try #require(try repository.categories(kind: .income).first(where: { $0.name == "Side Project" }))
        #expect(expenseCategory.isSystem == false)
        #expect(incomeCategory.isSystem == false)
        let imported = try repository.transactions(query: .init(), limit: nil)
        #expect(imported.contains { $0.kind == .expense && $0.categoryName == "Pet Supplies" })
        #expect(imported.contains { $0.kind == .income && $0.categoryName == "Side Project" })
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func csvImportMatchesExistingCategoriesCaseInsensitivelyWithoutDuplicates() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let expenseCountBefore = try repository.categories(kind: .expense).count
        let incomeCountBefore = try repository.categories(kind: .income).count
        let csv = """
        Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,groceries,-123.45,UAH,Weekly,,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Income,SALARY,400.00,UAH,Monthly,,ignored@example.com
        """

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "wallet.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: wallet.id)
        )

        #expect(result.insertedTransactions == 2)
        #expect(try repository.categories(kind: .expense).count == expenseCountBefore)
        #expect(try repository.categories(kind: .income).count == incomeCountBefore)
        let imported = try repository.transactions(query: .init(), limit: nil)
        #expect(imported.contains { $0.kind == .expense && $0.categoryName == "Groceries" })
        #expect(imported.contains { $0.kind == .income && $0.categoryName == "Salary" })
    }

    @Test func csvPreviewCountsRowsAndImportResultReportsSkippedRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Amount,Note
        2026-01-02,10.00,Valid row
        not-a-date,11.00,Invalid row
        """

        let preview = try service.preview(data: Data(csv.utf8))
        #expect(service.detectPreset(headers: preview.headers) == .generic)
        #expect(preview.totalRows == 2)

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "generic.csv",
            mapping: CSVImportMapping(
                dateColumn: "Date",
                amountColumn: "Amount",
                debitColumn: nil,
                creditColumn: nil,
                merchantColumn: nil,
                noteColumn: "Note",
                categoryColumn: nil,
                labelsColumn: nil,
                walletID: walletID,
                defaultKind: .expense
            )
        )

        #expect(result.insertedTransactions == 1)
        #expect(result.job.invalidRows == 1)
        #expect(result.rowErrors.first?.rowNumber == 3)
    }

    @Test func attachedWalletCSVFixtureImportsWithoutRowLossWhenPresent() throws {
        let fixtureURL = URL(fileURLWithPath: "/Users/roman/Downloads/transactions_export_2026-04-27_wallet.csv")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            return
        }

        let data = try Data(contentsOf: fixtureURL)
        let fixture = try TestSupport.walletCSVFixtureFacts(data: data)
        #expect(fixture.rowCount == 13_896)
        #expect(fixture.expenseCount == 13_627)
        #expect(fixture.incomeCount == 269)
        #expect(fixture.currencyCodes == ["UAH"])
        #expect(fixture.distinctWalletCount == 1)

        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        for labelName in fixture.labelNames {
            try repository.saveLabel(Label(id: UUID(), name: labelName, colorHex: "#60788A", createdAt: .now, updatedAt: .now))
        }

        let service = CSVService(repository: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let clock = ContinuousClock()
        var importOutcome: Result<CSVImportResult, any Error>?
        let elapsed = clock.measure {
            importOutcome = Result {
                try service.importCSV(
                    data: data,
                    fileName: fixtureURL.lastPathComponent,
                    mapping: TestSupport.cashRunwayWalletMapping(walletID: walletID)
                )
            }
        }
        let result = try #require(importOutcome).get()

        #expect(result.insertedTransactions == fixture.rowCount)
        #expect(result.rowErrors.isEmpty)
        #expect(TestSupport.seconds(elapsed) < 30)
        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.expenseCount == fixture.expenseCount)
        #expect(truth.incomeCount == fixture.incomeCount)
        #expect(truth.sourceImportCount == fixture.rowCount)
        #expect(truth.ftsRowCount == fixture.rowCount)
        #expect(truth.monthCount > 0)
        #expect(truth.labelLinkCount == fixture.labeledRowCount)

        let exported = try service.exportCSV()
        #expect(exported.split(separator: "\n").first == "Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author")
        #expect(TestSupport.csvRowCount(exported) == fixture.rowCount + 1)
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
    struct WalletCSVFixtureFacts {
        var rowCount: Int
        var expenseCount: Int
        var incomeCount: Int
        var distinctWalletCount: Int
        var currencyCodes: Set<String>
        var labelNames: Set<String>
        var labeledRowCount: Int
    }

    struct TransactionTruth {
        var expenseCount: Int
        var incomeCount: Int
        var sourceImportCount: Int
        var ftsRowCount: Int
        var monthCount: Int
        var labelLinkCount: Int
    }

    static func makeRepository() throws -> CashRunwayRepository {
        CashRunwayRepository(databaseManager: try DatabaseManager(locationProvider: makeLocation()))
    }

    static func makeLocation() -> DatabaseLocationProvider {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cash-runway-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return DatabaseLocationProvider(
            appGroupIdentifier: nil,
            databaseURLOverride: baseURL.appendingPathComponent("cash-runway.sqlite"),
            directoryName: UUID().uuidString
        )
    }

    static func cashRunwayWalletMapping(walletID: UUID) -> CSVImportMapping {
        CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: "Note",
            categoryColumn: "Category name",
            labelsColumn: "Labels",
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: "Type",
            walletColumn: "Wallet",
            currencyColumn: "Currency",
            authorColumn: "Author"
        )
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    static func walletCSVFixtureFacts(data: Data) throws -> WalletCSVFixtureFacts {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CashRunwayError.validation("Fixture is not UTF-8.")
        }
        let rows = parseCSVRows(text)
        guard let headers = rows.first else {
            throw CashRunwayError.validation("Fixture is empty.")
        }
        let index = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        guard
            let typeIndex = index["Type"],
            let walletIndex = index["Wallet"],
            let currencyIndex = index["Currency"],
            let labelsIndex = index["Labels"]
        else {
            throw CashRunwayError.validation("Fixture headers do not match wallet CSV format.")
        }

        var expenseCount = 0
        var incomeCount = 0
        var wallets = Set<String>()
        var currencies = Set<String>()
        var labels = Set<String>()
        var labeledRowCount = 0
        for row in rows.dropFirst() {
            let type = row.indices.contains(typeIndex) ? row[typeIndex] : ""
            if type == "Expense" {
                expenseCount += 1
            } else if type == "Income" {
                incomeCount += 1
            }
            if row.indices.contains(walletIndex), !row[walletIndex].isEmpty {
                wallets.insert(row[walletIndex])
            }
            if row.indices.contains(currencyIndex), !row[currencyIndex].isEmpty {
                currencies.insert(row[currencyIndex])
            }
            if row.indices.contains(labelsIndex), !row[labelsIndex].isEmpty {
                labeledRowCount += 1
                labels.insert(row[labelsIndex])
            }
        }
        return WalletCSVFixtureFacts(
            rowCount: rows.count - 1,
            expenseCount: expenseCount,
            incomeCount: incomeCount,
            distinctWalletCount: wallets.count,
            currencyCodes: currencies,
            labelNames: labels,
            labeledRowCount: labeledRowCount
        )
    }

    static func csvRowCount(_ text: String) -> Int {
        parseCSVRows(text).count
    }

    static func transactionTruth(_ repository: CashRunwayRepository) throws -> TransactionTruth {
        try repository.databaseManager.dbQueue.read { db in
            TransactionTruth(
                expenseCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type = 'expense'") ?? 0,
                incomeCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type = 'income'") ?? 0,
                sourceImportCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = 'import_csv'") ?? 0,
                ftsRowCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transaction_search") ?? 0,
                monthCount: try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT local_month_key) FROM transactions") ?? 0,
                labelLinkCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transaction_labels") ?? 0
            )
        }
    }

    static func assertTypeMonthCategoryAndLabelTotalsMatch(_ lhs: CashRunwayRepository, _ rhs: CashRunwayRepository) throws {
        let lhsTypeMonth = try groupedTotals(lhs, sql: "SELECT type || '|' || local_month_key AS key, SUM(amount_minor) AS total, COUNT(*) AS count FROM transactions GROUP BY type, local_month_key")
        let rhsTypeMonth = try groupedTotals(rhs, sql: "SELECT type || '|' || local_month_key AS key, SUM(amount_minor) AS total, COUNT(*) AS count FROM transactions GROUP BY type, local_month_key")
        #expect(lhsTypeMonth == rhsTypeMonth)

        let lhsCategory = try groupedTotals(lhs, sql: "SELECT type || '|' || COALESCE(category_id, '') AS key, SUM(amount_minor) AS total, COUNT(*) AS count FROM transactions GROUP BY type, category_id")
        let rhsCategory = try groupedTotals(rhs, sql: "SELECT type || '|' || COALESCE(category_id, '') AS key, SUM(amount_minor) AS total, COUNT(*) AS count FROM transactions GROUP BY type, category_id")
        #expect(lhsCategory == rhsCategory)

        let lhsLabels = try groupedTotals(lhs, sql: "SELECT tl.label_id || '|' || t.type AS key, SUM(t.amount_minor) AS total, COUNT(*) AS count FROM transaction_labels tl JOIN transactions t ON t.id = tl.transaction_id GROUP BY tl.label_id, t.type")
        let rhsLabels = try groupedTotals(rhs, sql: "SELECT tl.label_id || '|' || t.type AS key, SUM(t.amount_minor) AS total, COUNT(*) AS count FROM transaction_labels tl JOIN transactions t ON t.id = tl.transaction_id GROUP BY tl.label_id, t.type")
        #expect(lhsLabels == rhsLabels)
    }

    private static func groupedTotals(_ repository: CashRunwayRepository, sql: String) throws -> [String: String] {
        try repository.databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: sql)
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let key = row["key"] as String
                let total = row["total"] as Int64
                let count = row["count"] as Int
                return (key, "\(total)|\(count)")
            })
        }
    }

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        func appendField() {
            row.append(field.trimmingCharacters(in: .whitespaces))
            field = ""
        }

        func appendRowIfNeeded() {
            if !row.isEmpty || !field.isEmpty {
                appendField()
                rows.append(row)
                row = []
            }
        }

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if character == "\"" {
                if isQuoted, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append(character)
                    index = text.index(after: nextIndex)
                } else {
                    isQuoted.toggle()
                    index = nextIndex
                }
            } else if character == ",", !isQuoted {
                appendField()
                index = nextIndex
            } else if character == "\n", !isQuoted {
                appendRowIfNeeded()
                index = nextIndex
            } else if character == "\r", !isQuoted {
                appendRowIfNeeded()
                if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = text.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
            } else {
                field.append(character)
                index = nextIndex
            }
        }
        appendRowIfNeeded()
        return rows
    }

    static func assertWalletTruth(_ repository: CashRunwayRepository) throws {
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

    static func assertCategoryTruth(_ repository: CashRunwayRepository) throws {
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
