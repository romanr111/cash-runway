import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct RecurringIdempotencyTests {
    @Test func postingRecurringInstanceTwiceAppliesLedgerEffectOnce() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let categories = try repository.categories(kind: .expense)
        let categoryID = try #require(categories.first?.id)
        let wallet = wallets[0]
        let initialBalance = wallet.currentBalanceMinor

        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id,
            counterpartyWalletID: nil, amountMinor: 10_000,
            categoryID: categoryID, merchant: "Monthly Fee", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: nil, isActive: true, createdAt: .now, updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)
        try repository.refreshRecurringInstances()

        let instances = try repository.recurringInstances()
        let instance = try #require(instances.first)
        #expect(instance.status == .scheduled)

        try repository.postRecurringInstance(id: instance.id)

        let afterFirst = try repository.recurringInstances()
        let firstUpdated = try #require(afterFirst.first { $0.id == instance.id })
        #expect(firstUpdated.status == .posted)
        #expect(firstUpdated.linkedTransactionID != nil)

        let linkedTxID = try #require(firstUpdated.linkedTransactionID)

        let linkedTxnCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE recurring_instance_id = ?", arguments: [instance.id.uuidString]) ?? 0
        }
        #expect(linkedTxnCount == 1)

        let walletAfterFirst = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfterFirst.currentBalanceMinor == initialBalance - 10_000)

        let dashboard = try repository.dashboard(monthKey: DateKeys.monthKey(for: .now))
        #expect(dashboard.monthExpenseMinor >= 10_000)

        try repository.postRecurringInstance(id: instance.id)

        let afterSecond = try repository.recurringInstances()
        let secondUpdated = try #require(afterSecond.first { $0.id == instance.id })
        #expect(secondUpdated.status == .posted)
        #expect(secondUpdated.linkedTransactionID == linkedTxID)

        let txsAfterSecond = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE recurring_instance_id = ?", arguments: [instance.id.uuidString]) ?? 0
        }
        #expect(txsAfterSecond == 1)

        let walletAfterSecond = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfterSecond.currentBalanceMinor == initialBalance - 10_000)

        let recurringRows = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE recurring_instance_id = ?", arguments: [instance.id.uuidString]) ?? 0
        }
        #expect(recurringRows == 1)
    }
}