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
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)

        for i in 0..<20 {
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .transfer,
                    walletID: wallets[0].id,
                    destinationWalletID: wallets[1].id,
                    amountMinor: Int64(1_000 * (i + 1)),
                    occurredAt: .now,
                    merchant: "Transfer \(i)",
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

    @Test func walletDeletionRemovesAllLinkedData() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
