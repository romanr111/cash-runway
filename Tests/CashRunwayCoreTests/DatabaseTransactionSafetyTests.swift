import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseTransactionSafetyTests {
    @Test func writeThrowRollsBackAllChanges() throws {
        let location = TestSupport.makeLocation()
        let manager = try DatabaseManager(locationProvider: location, keychain: TestKeychainStore())
        let repository = CashRunwayRepository(databaseManager: manager)
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()

        let countBefore = try repository.transactions().count

        var didThrow = false
        do {
            try manager.dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO transactions (id, wallet_id, type, amount_minor, occurred_at, local_day_key, local_month_key, is_deleted, source, created_at, updated_at)
                    VALUES (?, ?, 'expense', ?, ?, ?, ?, 0, 'manual', ?, ?)
                    """,
                    arguments: [
                        UUID().uuidString, wallets[0].id.uuidString, 1_000,
                        Date(), DateKeys.dayKey(for: .now), DateKeys.monthKey(for: .now),
                        Date(), Date(),
                    ]
                )
                throw CashRunwayError.invalidState("Simulated mid-write failure")
            }
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        let countAfter = try repository.transactions().count
        #expect(countAfter == countBefore)
    }

    @Test func transferCreationMaintainsPairInvariants() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)

        for index in 0..<20 {
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .transfer,
                    walletID: wallets[0].id,
                    destinationWalletID: wallets[1].id,
                    amountMinor: Int64(1_000 * (index + 1)),
                    occurredAt: .now,
                    merchant: "Transfer \(index)",
                    note: ""
                )
            )
            try TestSupport.assertNoPartialTransfer(repository)
            try TestSupport.assertWalletTruth(repository)
        }
    }

    @Test func transferEditMaintainsPairInvariants() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: wallets[0].id,
                destinationWalletID: wallets[1].id,
                amountMinor: 10_000,
                occurredAt: .now,
                merchant: "Initial",
                note: ""
            )
        )

        let transfer = try #require(try repository.transactions(query: .init(kinds: [.transfer])).first)
        try repository.saveTransaction(
            TransactionDraft(
                id: transfer.id,
                kind: .transfer,
                walletID: wallets[1].id,
                destinationWalletID: wallets[0].id,
                amountMinor: 5_000,
                occurredAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
                merchant: "Edited",
                note: ""
            )
        )

        try TestSupport.assertNoPartialTransfer(repository)
        try TestSupport.assertWalletTruth(repository)
    }

    @Test func deleteTransactionMaintainsPairInvariants() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: wallets[0].id,
                destinationWalletID: wallets[1].id,
                amountMinor: 8_000,
                occurredAt: .now,
                merchant: "Delete me",
                note: ""
            )
        )

        let transfer = try #require(try repository.transactions(query: .init(kinds: [.transfer])).first)
        try repository.deleteTransaction(id: transfer.id)
        try TestSupport.assertNoPartialTransfer(repository)
        try TestSupport.assertWalletTruth(repository)
    }

    @Test func categoryMergeMaintainsTransactionConsistency() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategories = try repository.categories(kind: .expense)
        let oldCategory = try #require(expenseCategories.first)
        let newCategory = try #require(expenseCategories.dropFirst().first)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 5_000,
                occurredAt: .now,
                categoryID: oldCategory.id,
                merchant: "Merge test",
                note: ""
            )
        )

        try repository.mergeCategory(oldCategoryID: oldCategory.id, into: newCategory.id)

        let categoryIDs = try repository.databaseManager.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT category_id FROM transactions WHERE is_deleted = 0")
        }
        #expect(categoryIDs.contains(oldCategory.id.uuidString) == false)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func categoryMergeMovesDuplicateTransactionsAndHidesSource() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let restaurants = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" })
        let restaurant = CategoryBuilder()
            .with(name: "Restaurant")
            .with(kind: .expense)
            .with(iconName: "fork.knife")
            .with(colorHex: "#64D1D5")
            .with(sortOrder: 999)
            .build()
        try repository.saveCategory(restaurant)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 4_200,
                occurredAt: .now,
                categoryID: restaurant.id,
                merchant: "Corner Restaurant",
                note: ""
            )
        )

        try repository.mergeCategory(oldCategoryID: restaurant.id, into: restaurants.id)

        let activeExpenseCategories = try repository.categories(kind: .expense)
        #expect(activeExpenseCategories.contains { $0.id == restaurants.id })
        #expect(activeExpenseCategories.contains { $0.id == restaurant.id } == false)

        let managementItems = try repository.categoryManagementItems(kind: .expense)
        let sourceItem = try #require(managementItems.first { $0.category.id == restaurant.id })
        #expect(sourceItem.isVisible == false)

        let mergedTransaction = try #require(try repository.transactions().first { $0.merchant == "Corner Restaurant" })
        #expect(mergedTransaction.categoryName == "Restaurants")
        let mergedDraft = try repository.transactionDraft(id: mergedTransaction.id)
        #expect(mergedDraft.categoryID == restaurants.id)

        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func categoryMergeCombinesTransactionCountsAndAmounts() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let destination = CategoryBuilder()
            .with(name: "Merged Dining")
            .with(kind: .expense)
            .with(sortOrder: 998)
            .build()
        let restaurant = CategoryBuilder()
            .with(name: "Restaurant")
            .with(kind: .expense)
            .with(sortOrder: 999)
            .build()
        try repository.saveCategory(destination)
        try repository.saveCategory(restaurant)

        for (merchant, amount, categoryID) in [
            ("Source lunch", 1_200, restaurant.id),
            ("Source dinner", 3_400, restaurant.id),
            ("Destination cafe", 5_600, destination.id),
            ("Destination brunch", 7_800, destination.id),
            ("Destination delivery", 9_000, destination.id),
        ] as [(String, Int64, UUID)] {
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: amount,
                    occurredAt: .now,
                    categoryID: categoryID,
                    merchant: merchant,
                    note: ""
                )
            )
        }

        let sourceBefore = try transactionStats(repository, categoryID: restaurant.id)
        let destinationBefore = try transactionStats(repository, categoryID: destination.id)
        let allBefore = try transactionStats(repository)
        #expect(sourceBefore.count == 2)
        #expect(sourceBefore.amountMinor == 4_600)

        try repository.mergeCategory(oldCategoryID: restaurant.id, into: destination.id)

        let sourceAfter = try transactionStats(repository, categoryID: restaurant.id)
        let destinationAfter = try transactionStats(repository, categoryID: destination.id)
        let allAfter = try transactionStats(repository)
        #expect(sourceAfter.count == 0)
        #expect(sourceAfter.amountMinor == 0)
        #expect(destinationAfter.count == sourceBefore.count + destinationBefore.count)
        #expect(destinationAfter.amountMinor == sourceBefore.amountMinor + destinationBefore.amountMinor)
        #expect(allAfter.count == allBefore.count)
        #expect(allAfter.amountMinor == allBefore.amountMinor)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func categoryMergeRefreshesSearchIndexForMovedTransactionsOnly() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let source = CategoryBuilder()
            .with(name: "OldUniqueDining")
            .with(kind: .expense)
            .with(sortOrder: 997)
            .build()
        let destination = CategoryBuilder()
            .with(name: "NewUniqueDining")
            .with(kind: .expense)
            .with(sortOrder: 998)
            .build()
        try repository.saveCategory(source)
        try repository.saveCategory(destination)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 1_900,
                occurredAt: .now,
                categoryID: source.id,
                merchant: "Neutral Merchant",
                note: ""
            )
        )

        #expect(try repository.transactions(query: .init(searchText: "OldUniqueDining"), limit: nil).count == 1)

        try repository.mergeCategory(oldCategoryID: source.id, into: destination.id)

        #expect(try repository.transactions(query: .init(searchText: "OldUniqueDining"), limit: nil).isEmpty)
        #expect(try repository.transactions(query: .init(searchText: "NewUniqueDining"), limit: nil).count == 1)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func categoryMergeMovesRecurringAndBankRuleReferences() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let restaurants = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" })
        let restaurant = CategoryBuilder()
            .with(name: "Restaurant")
            .with(kind: .expense)
            .with(sortOrder: 999)
            .build()
        try repository.saveCategory(restaurant)

        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: walletID,
            counterpartyWalletID: nil,
            amountMinor: 9_900,
            categoryID: restaurant.id,
            merchant: "Lunch plan",
            note: "",
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
        try repository.refreshRecurringInstances()
        var instance = try #require(try repository.recurringInstances().first { $0.templateID == template.id })
        instance.overrideCategoryID = restaurant.id
        instance.updatedAt = .now
        try repository.saveRecurringInstance(instance)

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bank_category_rules (
                    id, provider, rule_type, merchant_pattern, mcc, category_id, confidence, created_at, updated_at
                )
                VALUES (?, ?, 'merchant', 'corner restaurant', NULL, ?, 100, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    restaurant.id.uuidString,
                    Date(timeIntervalSince1970: 1_800_000_000),
                    Date(timeIntervalSince1970: 1_800_000_000),
                ]
            )
        }

        try repository.mergeCategory(oldCategoryID: restaurant.id, into: restaurants.id)

        let mergedTemplate = try #require(try repository.recurringTemplates().first { $0.id == template.id })
        #expect(mergedTemplate.categoryID == restaurants.id)
        let mergedInstance = try #require(try repository.recurringInstances().first { $0.id == instance.id })
        #expect(mergedInstance.overrideCategoryID == restaurants.id)
        let mappedCategory = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: "Corner Restaurant",
            description: "Lunch",
            rawCategoryName: nil,
            mcc: nil,
            originalMcc: nil
        )
        #expect(mappedCategory?.categoryID == restaurants.id)
    }

    @Test func categoryMergeRecordsRemapAndAuditEntries() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let restaurants = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" })
        let restaurant = CategoryBuilder()
            .with(name: "Restaurant")
            .with(kind: .expense)
            .build()
        try repository.saveCategory(restaurant)

        try repository.mergeCategory(oldCategoryID: restaurant.id, into: restaurants.id)

        let records = try repository.databaseManager.dbQueue.read { db in
            let remapCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM category_remaps WHERE old_category_id = ? AND new_category_id = ?",
                arguments: [restaurant.id.uuidString, restaurants.id.uuidString]
            ) ?? 0
            let auditDiffJSON = try String.fetchOne(
                db,
                sql: "SELECT diff_json FROM audit_entries WHERE entity_type = 'category' AND entity_id = ? AND operation = 'remap'",
                arguments: [restaurant.id.uuidString]
            )
            return (remapCount, auditDiffJSON)
        }
        #expect(records.0 == 1)
        let auditDiffJSON = try #require(records.1)
        #expect(auditDiffJSON.contains("\"from\":\"\(restaurant.id.uuidString)\""))
        #expect(auditDiffJSON.contains("\"to\":\"\(restaurants.id.uuidString)\""))
    }

    @Test func categoryMergeRejectsInvalidCategoryPairs() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let restaurants = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" })
        let salary = try #require(try repository.categories(kind: .income).first { $0.name == "Salary" })

        #expect(throws: CashRunwayError.validation("Choose two different categories to merge.")) {
            try repository.mergeCategory(oldCategoryID: restaurants.id, into: restaurants.id)
        }
        #expect(throws: CashRunwayError.notFound) {
            try repository.mergeCategory(oldCategoryID: UUID(), into: restaurants.id)
        }
        #expect(throws: CashRunwayError.validation("Categories must have the same type to merge.")) {
            try repository.mergeCategory(oldCategoryID: restaurants.id, into: salary.id)
        }

        let activeRestaurants = try repository.categories(kind: .expense).filter { $0.id == restaurants.id }
        #expect(activeRestaurants.count == 1)
    }

    @Test func categoryMergeRejectsHiddenDestination() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let visibleSource = CategoryBuilder()
            .with(name: "Restaurant")
            .with(kind: .expense)
            .build()
        let hiddenDestination = CategoryBuilder()
            .with(name: "Hidden Restaurants")
            .with(kind: .expense)
            .with(isArchived: true)
            .build()
        try repository.saveCategory(visibleSource)
        try repository.saveCategory(hiddenDestination)

        #expect(throws: CashRunwayError.validation("Destination category must be active.")) {
            try repository.mergeCategory(oldCategoryID: visibleSource.id, into: hiddenDestination.id)
        }

        let activeCategories = try repository.categories(kind: .expense)
        #expect(activeCategories.contains { $0.id == visibleSource.id })
        #expect(activeCategories.contains { $0.id == hiddenDestination.id } == false)
    }

    private func transactionStats(_ repository: CashRunwayRepository, categoryID: UUID) throws -> (count: Int, amountMinor: Int64) {
        try repository.databaseManager.dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) AS count, COALESCE(SUM(amount_minor), 0) AS amount_minor
                FROM transactions
                WHERE is_deleted = 0 AND category_id = ?
                """,
                arguments: [categoryID.uuidString]
            )
            return (row?["count"] ?? 0, row?["amount_minor"] ?? 0)
        }
    }

    private func transactionStats(_ repository: CashRunwayRepository) throws -> (count: Int, amountMinor: Int64) {
        try repository.databaseManager.dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) AS count, COALESCE(SUM(amount_minor), 0) AS amount_minor
                FROM transactions
                WHERE is_deleted = 0
                """
            )
            return (row?["count"] ?? 0, row?["amount_minor"] ?? 0)
        }
    }

    @Test func walletDeletionRemovesAllLinkedData() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)
        let targetWallet = wallets[0]
        let otherWallet = wallets[1]
        let category = try #require(try repository.categories(kind: .expense).first)

        // Add transactions, transfers, templates
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: targetWallet.id,
                amountMinor: 3_000,
                occurredAt: .now,
                categoryID: category.id,
                merchant: "Expense",
                note: ""
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: targetWallet.id,
                destinationWalletID: otherWallet.id,
                amountMinor: 2_000,
                occurredAt: .now,
                merchant: "Transfer",
                note: ""
            )
        )

        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: targetWallet.id,
            counterpartyWalletID: nil,
            amountMinor: 1_000,
            categoryID: category.id,
            merchant: "Recurring",
            note: "",
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 1,
            weekday: nil,
            startDate: .now,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)

        try repository.deleteWallet(id: targetWallet.id)

        let remainingWallets = try repository.wallets()
        #expect(remainingWallets.contains(where: { $0.id == targetWallet.id }) == false)

        let txCountForDeletedWallet = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE wallet_id = ?", arguments: [targetWallet.id.uuidString]) ?? 0
        }
        #expect(txCountForDeletedWallet == 0)

        let remainingTemplates = try repository.recurringTemplates()
        #expect(remainingTemplates.contains(where: { $0.walletID == targetWallet.id }) == false)

        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertNoPartialTransfer(repository)
    }
}
