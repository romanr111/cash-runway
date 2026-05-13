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

    @Test func yearKeysAreStable() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 4, day: 7))!
        #expect(DateKeys.yearKey(for: date) == 2025)
    }

    @Test func periodLabelsAreFormatted() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 4, day: 7))!
        let monthKey = DateKeys.monthKey(for: date)
        let yearKey = DateKeys.yearKey(for: date)

        #expect(DateKeys.periodLabel(periodKey: monthKey, period: .month).contains("April"))
        #expect(DateKeys.periodLabel(periodKey: yearKey, period: .year) == "2025")
    }

    @Test func periodKeyRoundTripsToMonthKey() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 4, day: 7))!
        let monthKey = DateKeys.monthKey(for: date)

        let monthPeriodKey = DateKeys.periodKey(for: date, period: .month)
        #expect(DateKeys.monthKey(fromPeriodKey: monthPeriodKey, period: .month) == monthKey)

        let yearPeriodKey = DateKeys.periodKey(for: date, period: .year)
        #expect(DateKeys.monthKey(fromPeriodKey: yearPeriodKey, period: .year) == 202501)
    }

    @Test func timelineSnapshotGroupsByPeriod() throws {
        let location = TestSupport.makeLocation()
        let manager = try DatabaseManager(locationProvider: location)
        let repository = CashRunwayRepository(databaseManager: manager)
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)
        let wallet = wallets[0]
        let categories = try repository.categories(kind: .expense)
        #expect(categories.count >= 1)
        let category = categories[0]

        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2025, month: 4, day: 15))!
        let days = [0, 1, 2, 3, 10, 11, 12]
        for (index, offset) in days.enumerated() {
            let date = calendar.date(byAdding: .day, value: offset, to: base)!
            let draft = TransactionDraft(
                kind: .expense,
                walletID: wallet.id,
                amountMinor: Int64(100 * (index + 1)),
                occurredAt: date,
                categoryID: category.id,
                merchant: "Test \(offset)"
            )
            try repository.saveTransaction(draft)
        }

        let monthKey = DateKeys.monthKey(for: base)
        let monthSnapshot = try repository.timelineSnapshot(monthKey: monthKey, walletID: wallet.id, period: .month)
        #expect(monthSnapshot.period == .month)
        #expect(monthSnapshot.bars.count > 0)
        #expect(monthSnapshot.sections.count > 0)
        #expect(monthSnapshot.sections.allSatisfy { $0.periodKey >= monthKey * 100 + 1 && $0.periodKey <= monthKey * 100 + 31 })
        #expect(monthSnapshot.sections.allSatisfy { $0.periodLabel.contains("Apr") })

        let yearSnapshot = try repository.timelineSnapshot(monthKey: monthKey, walletID: wallet.id, period: .year)
        #expect(yearSnapshot.period == .year)
        #expect(yearSnapshot.sections.count > 0)
        #expect(yearSnapshot.sections.allSatisfy { $0.periodKey / 10_000 == 2025 })
        #expect(TimelinePeriod.allCases == [.month, .year])
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

    @Test func databaseKeyReadFailureDoesNotOverwriteStoredKey() throws {
        let location = TestSupport.makeLocation()
        let originalKey = Data("existing-database-key".utf8)
        let keychain = TestKeychainStore(
            items: ["database-key": originalKey],
            readError: KeychainStoreError.readFailed(errSecInteractionNotAllowed)
        )

        var didThrow = false
        do {
            _ = try DatabaseManager(locationProvider: location, keychain: keychain)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(keychain.item(account: "database-key") == originalKey)
        #expect(keychain.writeCount == 0)
    }

    @Test func invalidDatabaseKeyDataDoesNotOverwriteStoredKey() throws {
        let location = TestSupport.makeLocation()
        let invalidKey = Data([0xff, 0xfe])
        let keychain = TestKeychainStore(items: ["database-key": invalidKey])

        var didThrowInvalidData = false
        do {
            _ = try DatabaseManager(locationProvider: location, keychain: keychain)
        } catch KeychainStoreError.invalidStoredData("database-key") {
            didThrowInvalidData = true
        } catch {
            didThrowInvalidData = false
        }

        #expect(didThrowInvalidData)
        #expect(keychain.item(account: "database-key") == invalidKey)
        #expect(keychain.writeCount == 0)
    }

    @Test func databaseOpenFailureDoesNotQuarantineByDefault() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        let manager = try DatabaseManager(locationProvider: location, keychain: keychain)
        try CashRunwayRepository(databaseManager: manager).seedIfNeeded()

        let dbURL = try location.databaseURL()
        let originalSize = try TestSupport.fileSize(at: dbURL)
        let wrongKeychain = TestKeychainStore(items: ["database-key": Data("wrong-database-key".utf8)])

        var didThrow = false
        do {
            _ = try DatabaseManager(locationProvider: location, keychain: wrongKeychain)
        } catch {
            didThrow = true
        }

        let recoveryDirectory = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        #expect(didThrow)
        #expect(FileManager.default.fileExists(atPath: dbURL.path))
        #expect(!FileManager.default.fileExists(atPath: recoveryDirectory.path))
        #expect(try TestSupport.fileSize(at: dbURL) == originalSize)
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

    @Test func recurringGenerationRespectsMonthlyInterval() {
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
            ruleInterval: 3,
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
            end: DateKeys.startOfMonth(for: 202611)
        )
        #expect(dates.count == 4)
        #expect(DateKeys.dayKey(for: dates[0]) == 20260115)
        #expect(DateKeys.dayKey(for: dates[1]) == 20260415)
        #expect(DateKeys.dayKey(for: dates[2]) == 20260715)
        #expect(DateKeys.dayKey(for: dates[3]) == 20261015)
    }

    @Test func recurringGenerationRespectsYearlyInterval() {
        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: UUID(),
            counterpartyWalletID: nil,
            amountMinor: 100,
            categoryID: UUID(),
            merchant: nil,
            note: nil,
            ruleType: .yearly,
            ruleInterval: 2,
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
            end: DateKeys.startOfMonth(for: 202802)
        )
        #expect(dates.count == 2)
        #expect(DateKeys.dayKey(for: dates[0]) == 20260115)
        #expect(DateKeys.dayKey(for: dates[1]) == 20280115)
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

        let snapshot = try repository.timelineSnapshot(monthKey: monthKey, period: .month)
        #expect(snapshot.bars.count == 6)
        #expect(snapshot.heroCashFlowMinor == 37_700)
        let currentBar = try #require(snapshot.bars.first(where: { $0.periodKey == monthKey }))
        #expect(currentBar.incomeBarMinor == 50_000)
        #expect(currentBar.expenseBarMinor == 12_300)
        #expect(snapshot.sections.isEmpty == false)
        #expect(snapshot.sections.first?.items.contains(where: { $0.merchant == "Coffee" }) == true)
        #expect(snapshot.sections.flatMap(\.items).contains(where: { $0.merchant == "Taxi" }) == false)
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

    @Test func overviewSnapshotBatchBalancesMatchCumulativeTruth() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first?.id)
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        for monthOffset in 0..<4 {
            let date = calendar.date(byAdding: .month, value: monthOffset, to: base)!
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: Int64(10_000 * (monthOffset + 1)),
                    occurredAt: date,
                    categoryID: expenseCategory,
                    merchant: "Month \(monthOffset)",
                    note: ""
                )
            )
        }

        let lastMonthKey = DateKeys.monthKey(for: calendar.date(byAdding: .month, value: 3, to: base)!)
        let snapshot = try repository.overviewSnapshot(monthKey: lastMonthKey)
        #expect(snapshot.months.count == 6)

        let nonEmptyMonths = snapshot.months.filter { $0.expenseMinor > 0 || $0.incomeMinor > 0 }
        #expect(nonEmptyMonths.count == 4)

        let dashboardAllWallets = try repository.dashboard(monthKey: lastMonthKey, walletID: nil)
        let lastMonthPoint = try #require(snapshot.months.first(where: { $0.monthKey == lastMonthKey }))
        #expect(lastMonthPoint.totalWealthMinor == dashboardAllWallets.totalBalanceMinor)
    }

    @Test func overviewSnapshotIncludesTransactionsBeforeWindow() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first?.id)
        let calendar = Calendar(identifier: .gregorian)

        // Create a transaction 8 months before the overview window
        let earlyDate = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 50_000,
                occurredAt: earlyDate,
                categoryID: expenseCategory,
                merchant: "Early",
                note: ""
            )
        )

        // Create a transaction inside the window
        let lateDate = calendar.date(from: DateComponents(year: 2025, month: 8, day: 10))!
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 25_000,
                occurredAt: lateDate,
                categoryID: expenseCategory,
                merchant: "Late",
                note: ""
            )
        )

        let monthKey = DateKeys.monthKey(for: lateDate)

        // All-wallets view (default Overview filter) must include early transactions
        let snapshotAll = try repository.overviewSnapshot(monthKey: monthKey, walletID: nil)
        let pointAll = try #require(snapshotAll.months.first(where: { $0.monthKey == monthKey }))
        let dashboardAll = try repository.dashboard(monthKey: monthKey, walletID: nil)
        #expect(pointAll.totalWealthMinor == dashboardAll.totalBalanceMinor)

        // Single-wallet view must also include early transactions
        let snapshotOne = try repository.overviewSnapshot(monthKey: monthKey, walletID: walletID)
        let pointOne = try #require(snapshotOne.months.first(where: { $0.monthKey == monthKey }))
        let dashboardOne = try repository.dashboard(monthKey: monthKey, walletID: walletID)
        #expect(pointOne.totalWealthMinor == dashboardOne.totalBalanceMinor)
    }

    @Test func latestTransactionMonthKeyReflectsActualData() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first?.id)

        #expect(try repository.latestTransactionMonthKey() == nil)

        let pastDate = Calendar.current.date(byAdding: .month, value: -2, to: .now)!
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 1_000,
                occurredAt: pastDate,
                categoryID: expenseCategory,
                merchant: "Past",
                note: ""
            )
        )

        #expect(try repository.latestTransactionMonthKey() == DateKeys.monthKey(for: pastDate))
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
        #expect(exported.split(separator: "\n").first == "Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author")
        #expect(exported.contains("\"Expense\""))
        #expect(exported.contains("\"-123.45\""))
        #expect(exported.contains("\"Silpo\""))
    }

    @Test func cashRunwayWalletCSVFormatImportsSignedRowsAndExportsRoundTrippableFile() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let label = Label(id: UUID(), name: "Trip", colorHex: "#1CC389", createdAt: .now, updatedAt: .now)
        try repository.saveLabel(label)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,Groceries,,-123.45,UAH,"weekly, groceries",Trip,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Income,Salary,,400.00,UAH,Monthly salary,,ignored@example.com
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
        #expect(exported.split(separator: "\n").first == "Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author")
        #expect(exported.contains("\"Expense\",\"Groceries\",\"\",\"-123.45\""))
        #expect(exported.contains("\"Income\",\"Salary\",\"\",\"400.00\""))
        #expect(exported.contains(",\"Trip\",\""))

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
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,Pet Supplies,,-123.45,UAH,Kibble,,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Income,Side Project,,400.00,UAH,Invoice,,ignored@example.com
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
        #expect(imported.contains { $0.kind == .expense && $0.categoryName == "Pet Supplies" && $0.displayTitle == "Pet Supplies" })
        #expect(imported.contains { $0.kind == .income && $0.categoryName == "Side Project" && $0.displayTitle == "Side Project" })
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func csvImportCreatesMissingLabelsFromMappedColumn() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,Groceries,,-123.45,UAH,Weekly shopping,Trip;Work,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Expense,Groceries,,-50.00,UAH,Quick run,Trip,ignored@example.com
        2026-04-22T09:00:00Z,\(wallet.name),Income,Salary,,400.00,UAH,Monthly pay,Work,ignored@example.com
        """

        #expect(try repository.labels().isEmpty)

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "wallet.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: wallet.id)
        )

        #expect(result.insertedTransactions == 3)
        let labels = try repository.labels()
        #expect(labels.count == 2)
        #expect(labels.contains { $0.name == "Trip" })
        #expect(labels.contains { $0.name == "Work" })

        let imported = try repository.transactions(query: .init(), limit: nil)
        #expect(imported.filter { $0.labels.map(\.name).contains("Trip") }.count == 2)
        #expect(imported.filter { $0.labels.map(\.name).contains("Work") }.count == 2)
    }

    @Test func csvImportAssignsContextualIconsToLocalizedCreatedCategories() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,Food & Drink,,-123.45,UAH,Lunch,,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Expense,Отношения,,-50.00,UAH,Flowers,,ignored@example.com
        2026-04-22T09:00:00Z,\(wallet.name),Expense,Оренда,,-300.00,UAH,Flat,,ignored@example.com
        2026-04-23T10:00:00Z,\(wallet.name),Income,Фриланс,,400.00,UAH,Invoice,,ignored@example.com
        """

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "wallet.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: wallet.id)
        )

        #expect(result.insertedTransactions == 4)
        #expect(try repository.categories(kind: .expense).first(where: { $0.name == "Food & Drink" })?.iconName == "fork.knife")
        #expect(try repository.categories(kind: .expense).first(where: { $0.name == "Отношения" })?.iconName == "heart.fill")
        #expect(try repository.categories(kind: .expense).first(where: { $0.name == "Оренда" })?.iconName == "house.fill")
        #expect(try repository.categories(kind: .income).first(where: { $0.name == "Фриланс" })?.iconName == "briefcase.fill")
    }

    @Test func csvImportMatchesExistingCategoriesCaseInsensitivelyWithoutDuplicates() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let expenseCountBefore = try repository.categories(kind: .expense).count
        let incomeCountBefore = try repository.categories(kind: .income).count
        let csv = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,\(wallet.name),Expense,groceries,,-123.45,UAH,Weekly,,ignored@example.com
        2026-04-21T08:00:00Z,\(wallet.name),Income,SALARY,,400.00,UAH,Monthly,,ignored@example.com
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
        #expect(exported.split(separator: "\n").first == "Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author")
        #expect(TestSupport.csvRowCount(exported) == fixture.rowCount + 1)
    }

    @Test func csvExportIncludesMerchantColumn() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Amount,Merchant,Note
        2026-01-02,100.00,TestShop,Purchase
        """

        _ = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "export-test.csv",
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

        let exported = try service.exportCSV()
        let header = exported.split(separator: "\n").first ?? ""
        #expect(String(header) == "Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author")
        #expect(exported.contains("\"TestShop\""))
    }

    @Test func csvExportRoundTripPreservesMerchant() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Amount,Merchant,Note
        2026-01-10,250.00,Silpo,Groceries
        """

        _ = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "merchant.csv",
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

        let exported = try service.exportCSV()
        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
        let roundTripWalletID = try #require(try roundTripRepo.wallets().first?.id)
        let roundTripService = CSVService(repository: roundTripRepo)
        let result = try roundTripService.importCSV(
            data: Data(exported.utf8),
            fileName: "roundtrip-merchant.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
        )

        #expect(result.insertedTransactions == 1)
        let imported = try roundTripRepo.transactions(query: .init(), limit: nil)
        #expect(imported.count == 1)
        #expect(imported.first?.merchant == "Silpo")
        #expect(imported.first?.amountMinor == -25_000)
    }

    @Test func csvExportRoundTripPreservesAllFields() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let label = Label(id: UUID(), name: "Business", colorHex: "#1CC389", createdAt: .now, updatedAt: .now)
        try repository.saveLabel(label)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-03-15T10:00:00Z,Main Wallet,Income,Salary,ACME Corp,500.00,UAH,Monthly salary,Business,ignored@example.com
        2026-03-20T14:30:00Z,Main Wallet,Expense,Groceries,ATB,-150.75,UAH,Weekly shopping,Business,ignored@example.com
        """

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "all-fields.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: walletID)
        )

        #expect(result.insertedTransactions == 2)
        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)

        let exported = try service.exportCSV()
        let rows = TestSupport.parseCSVRows(exported)
        #expect(rows.count == 3)
        #expect(rows[0] == ["Date", "Wallet", "Type", "Category name", "Merchant", "Amount", "Currency", "Note", "Labels", "Author"])

        let row1 = rows.first(where: { $0.indices.contains(3) && $0[3] == "Salary" })
        #expect(row1 != nil)
        #expect(row1?.dropFirst().count == 9)

        let row2 = rows.first(where: { $0.indices.contains(3) && $0[3] == "Groceries" })
        #expect(row2 != nil)

        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
        let roundTripWalletID = try #require(try roundTripRepo.wallets().first?.id)
        let roundTripService = CSVService(repository: roundTripRepo)
        let roundTripResult = try roundTripService.importCSV(
            data: Data(exported.utf8),
            fileName: "roundtrip-all.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
        )

        #expect(roundTripResult.insertedTransactions == 2)
        let importedLabels = try roundTripRepo.transactions(query: .init(), limit: nil).flatMap { $0.labels }
        #expect(importedLabels.contains { $0.name == "Business" })
    }

    @Test func csvExportExcludesTransfersByDefault() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Amount,Merchant,Note
        2026-01-10,100.00,Expense Row,Test
        2026-01-11,200.00,Income Row,Credit
        """

        _ = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "mixed.csv",
            mapping: CSVImportMapping(
                dateColumn: "Date",
                amountColumn: "Amount",
                debitColumn: nil,
                creditColumn: nil,
                merchantColumn: "Merchant",
                noteColumn: "Note",
                categoryColumn: nil,
                labelsColumn: nil,
                walletID: wallets[0].id,
                defaultKind: .expense
            )
        )

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: wallets[0].id,
                destinationWalletID: wallets[1].id,
                amountMinor: 50_000,
                occurredAt: Date(),
                merchant: "Transfer Row",
                note: "Move"
            )
        )

        let allTransactions = try repository.transactions(query: .init(), limit: nil)
        let hasTransfer = allTransactions.contains { $0.kind == .transfer }
        #expect(hasTransfer)

        let exported = try service.exportCSV()
        let rows = TestSupport.parseCSVRows(exported)
        let dataRows = rows.dropFirst()
        #expect(dataRows.allSatisfy { row in
            row.indices.contains(2) && row[2] != "Transfer"
        })
        #expect(dataRows.count == allTransactions.filter { $0.kind != .transfer }.count)

        let transferOnlyExport = try service.exportCSV(query: .init(kinds: [.transfer]))
        #expect(TestSupport.parseCSVRows(transferOnlyExport).count == 1)
    }

    @Test func csvExportWithFilterReturnsSubset() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let csv = """
        Date,Amount,Merchant,Note
        2026-01-10,100.00,Shop A,First
        2026-01-15,200.00,Shop B,Second
        2026-02-01,300.00,Shop C,Third
        """

        _ = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "filter-test.csv",
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

        let startDate = ISO8601DateFormatter().date(from: "2026-01-14T00:00:00Z")!
        let filteredExport = try service.exportCSV(query: .init(startDate: startDate))
        let rows = TestSupport.parseCSVRows(filteredExport)
        #expect(rows.count == 3)
        #expect(rows.dropFirst().allSatisfy { row in
            row.indices.contains(4) && row[4] != "Shop A"
        })

        let searchExport = try service.exportCSV(query: .init(searchText: "Shop"))
        let searchRows = TestSupport.parseCSVRows(searchExport)
        #expect(searchRows.count == 4)

        let noMatchExport = try service.exportCSV(query: .init(searchText: "Nonexistent"))
        let noMatchRows = TestSupport.parseCSVRows(noMatchExport)
        #expect(noMatchRows.count == 1)
    }

    @Test func csvExportWithEmptyDBReturnsHeaderOnly() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let service = CSVService(repository: repository)
        let exported = try service.exportCSV()
        let rows = TestSupport.parseCSVRows(exported)
        #expect(rows.count == 1)
        #expect(rows[0] == ["Date", "Wallet", "Type", "Category name", "Merchant", "Amount", "Currency", "Note", "Labels", "Author"])
    }

    @Test func csvExportHandlesSpecialCharacters() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let walletName = try #require(try repository.wallets().first?.name)
        let label1 = Label(id: UUID(), name: "ProjectX", colorHex: "#1CC389", createdAt: .now, updatedAt: .now)
        let label2 = Label(id: UUID(), name: "YZ", colorHex: "#60788A", createdAt: .now, updatedAt: .now)
        try repository.saveLabel(label1)
        try repository.saveLabel(label2)
        let service = CSVService(repository: repository)

        let header = "Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author\n"
        let row1 = "2026-04-01T10:00:00Z,\(walletName),Expense,Groceries,Shop A,-100.00,UAH,\"Note with, comma\",\"ProjectX;YZ\",ignored@example.com\n"
        let csv = header + row1

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "special.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: walletID)
        )

        #expect(result.insertedTransactions == 1)
        let exported = try service.exportCSV()

        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
        try roundTripRepo.saveLabel(Label(id: UUID(), name: "ProjectX", colorHex: "#1CC389", createdAt: .now, updatedAt: .now))
        try roundTripRepo.saveLabel(Label(id: UUID(), name: "YZ", colorHex: "#60788A", createdAt: .now, updatedAt: .now))
        let roundTripWalletID = try #require(try roundTripRepo.wallets().first?.id)
        let roundTripService = CSVService(repository: roundTripRepo)
        let roundTripResult = try roundTripService.importCSV(
            data: Data(exported.utf8),
            fileName: "roundtrip-special.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
        )

        #expect(roundTripResult.insertedTransactions == 1)
        let roundTripTx = try #require(try roundTripRepo.transactions(query: .init(), limit: nil).first)
        #expect(roundTripTx.merchant == "Shop A")
        #expect(roundTripTx.note == "Note with, comma")
        #expect(roundTripTx.labels.contains { $0.name == "ProjectX" })
        #expect(roundTripTx.labels.contains { $0.name == "YZ" })
    }

    @Test func csvExportHandlesUnicodeCategoryLabels() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let walletName = try #require(try repository.wallets().first?.name)
        let service = CSVService(repository: repository)

        let header = "Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author\n"
        let row1 = "2026-04-15T12:00:00Z,\(walletName),Expense,Продукти,Сільпо,-250.50,UAH,Щотижня,Покупки,ignored@example.com\n"
        let row2 = "2026-04-16T09:00:00Z,\(walletName),Income,Зарплата,Робота,1000.00,UAH,Місячна,,ignored@example.com\n"
        let csv = header + row1 + row2

        let result = try service.importCSV(
            data: Data(csv.utf8),
            fileName: "unicode.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: walletID)
        )

        #expect(result.insertedTransactions == 2)
        let exported = try service.exportCSV()

        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
        let roundTripWalletID = try #require(try roundTripRepo.wallets().first?.id)
        let roundTripService = CSVService(repository: roundTripRepo)
        let roundTripResult = try roundTripService.importCSV(
            data: Data(exported.utf8),
            fileName: "roundtrip-unicode.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
        )

        #expect(roundTripResult.insertedTransactions == 2)
        let imported = try roundTripRepo.transactions(query: .init(), limit: nil)
        #expect(imported.contains { $0.categoryName == "Продукти" && $0.merchant == "Сільпо" })
        #expect(imported.contains { $0.categoryName == "Зарплата" && $0.merchant == "Робота" })
        #expect(imported.contains { $0.amountMinor == -25_050 })
        #expect(imported.contains { $0.amountMinor == 100_000 })
    }

    @Test func walletExportRoundTripVerifiesOldFormatImportsAndNewFormatExports() throws {
        let text = """
        Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author
        2026-04-20T12:30:00Z,Main Wallet,Expense,Groceries,-123.45,UAH,Weekly shopping,Trip|Work,ignored@example.com
        2026-04-21T08:00:00Z,Main Wallet,Income,Salary,400.00,UAH,Monthly pay,Work,ignored@example.com
        """
        let data = Data(text.utf8)

        let allRows = TestSupport.parseCSVRows(text)
        let headerRow = try #require(allRows.first)
        let oldHeaderCount = headerRow.count
        #expect(oldHeaderCount == 9)
        #expect(!headerRow.contains("Merchant"))

        let oldRowCount = allRows.count - 1

        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)

        let clock = ContinuousClock()
        var elapsedSeconds = 0.0
        let elapsed = try clock.measure {
            let result = try service.importCSV(
                data: data,
                fileName: "old-format-wallet-export.csv",
                mapping: TestSupport.cashRunwayWalletMapping(walletID: walletID)
            )
            #expect(result.insertedTransactions == oldRowCount)
            #expect(result.rowErrors.isEmpty)
        }
        elapsedSeconds = TestSupport.seconds(elapsed)
        #expect(elapsedSeconds < 60)

        let exported = try service.exportCSV()
        let exportedRows = TestSupport.parseCSVRows(exported)
        let exportedHeader = try #require(exportedRows.first)
        #expect(exportedHeader.count == 10)
        #expect(exportedHeader.contains("Merchant"))
        #expect(exportedRows.count == oldRowCount + 1)

        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
        let roundTripWalletID = try #require(try roundTripRepo.wallets().first?.id)
        let roundTripService = CSVService(repository: roundTripRepo)

        var roundTripElapsed = 0.0
        let roundTripElapsedDur = try clock.measure {
            let roundTripResult = try roundTripService.importCSV(
                data: Data(exported.utf8),
                fileName: "roundtrip-verification.csv",
                mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
            )
            #expect(roundTripResult.insertedTransactions == oldRowCount)
            #expect(roundTripResult.rowErrors.isEmpty)
        }
        roundTripElapsed = TestSupport.seconds(roundTripElapsedDur)
        #expect(roundTripElapsed < 60)

        let roundTripTransactions = try roundTripRepo.transactions(query: .init(), limit: nil)
        #expect(roundTripTransactions.count == oldRowCount)
        #expect(roundTripTransactions.allSatisfy { $0.merchant.isEmpty })

        let originalTransactions = try repository.transactions(query: .init(), limit: nil)
        #expect(originalTransactions.count == oldRowCount)
        #expect(originalTransactions.allSatisfy { $0.merchant.isEmpty })
        let originalLabeledCount = originalTransactions.filter { !$0.labels.isEmpty }.count
        #expect(originalLabeledCount > 0)
        let roundTripLabeledCount = roundTripTransactions.filter { !$0.labels.isEmpty }.count
        #expect(roundTripLabeledCount == originalLabeledCount)
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

    @Test func walletDeletionRemovesWalletAndTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)
        let firstWallet = wallets[0]
        let secondWallet = wallets[1]
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: firstWallet.id,
                amountMinor: 5_000,
                occurredAt: .now,
                categoryID: expenseCategory.id,
                merchant: "Coffee",
                note: ""
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: firstWallet.id,
                destinationWalletID: secondWallet.id,
                amountMinor: 3_000,
                occurredAt: .now,
                merchant: "Move",
                note: ""
            )
        )

        let preDeleteCount = try repository.wallets().count
        try repository.deleteWallet(id: firstWallet.id)
        let postDeleteWallets = try repository.wallets()
        #expect(postDeleteWallets.count == preDeleteCount - 1)
        #expect(postDeleteWallets.contains(where: { $0.id == firstWallet.id }) == false)

        let remainingTxs = try repository.transactions()
        #expect(remainingTxs.contains(where: { $0.walletName == firstWallet.name }) == false)

        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func walletDeletionCleansUpLinkedTransfersInOtherWallets() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)
        let sourceWallet = wallets[0]
        let destinationWallet = wallets[1]

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: sourceWallet.id,
                destinationWalletID: destinationWallet.id,
                amountMinor: 3_000,
                occurredAt: .now,
                merchant: "Move",
                note: ""
            )
        )

        let preDeleteTxCount = try repository.transactions(query: .init(kinds: [.transfer])).count
        #expect(preDeleteTxCount == 1)

        try repository.deleteWallet(id: destinationWallet.id)

        let postDeleteWallets = try repository.wallets()
        #expect(postDeleteWallets.contains(where: { $0.id == destinationWallet.id }) == false)

        let remainingTransferTxs = try repository.transactions(query: .init(kinds: [.transfer]))
        #expect(remainingTransferTxs.isEmpty)

        try TestSupport.assertWalletTruth(repository)
    }

    @Test func cannotDeleteLastActiveWallet() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        var wallets = try repository.wallets()
        while wallets.count > 1 {
            try repository.deleteWallet(id: wallets[0].id)
            wallets = try repository.wallets()
        }
        #expect(wallets.count == 1)
        #expect(throws: CashRunwayError.validation("At least one active wallet must remain.")) {
            try repository.deleteWallet(id: wallets[0].id)
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

    static func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    static func cashRunwayWalletMapping(walletID: UUID) -> CSVImportMapping {
        CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
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

    static func parseCSVRows(_ text: String) -> [[String]] {
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

private final class TestKeychainStore: KeychainStoring, @unchecked Sendable {
    private var items: [String: Data]
    private let readError: Error?
    private(set) var writeCount = 0

    init(items: [String: Data] = [:], readError: Error? = nil) {
        self.items = items
        self.readError = readError
    }

    func read(account: String) throws -> Data? {
        if let readError {
            throw readError
        }
        return items[account]
    }

    func write(_ data: Data, account: String) throws {
        writeCount += 1
        items[account] = data
    }

    func delete(account: String) {
        items.removeValue(forKey: account)
    }

    func item(account: String) -> Data? {
        items[account]
    }
}
