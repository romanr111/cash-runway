import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseCrashSimulationTests {
    @Test func committedDataSurvivesProcessDeath() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let category = try #require(try repository.categories(kind: .expense).first)

        for i in 0..<20 {
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .expense,
                    walletID: wallets[0].id,
                    amountMinor: Int64(500 * (i + 1)),
                    occurredAt: .now,
                    categoryID: category.id,
                    merchant: "Crash test \(i)",
                    note: ""
                )
            )
        }

        let countBefore = try repository.transactions().count
        let truthBefore = try TestSupport.transactionTruth(repository)

        // Simulate process death by dropping the queue reference.
        manager = nil

        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)
        let countAfter = try reopenedRepo.transactions().count
        let truthAfter = try TestSupport.transactionTruth(reopenedRepo)

        #expect(countAfter == countBefore)
        #expect(truthAfter == truthBefore)
        try TestSupport.assertWalletTruth(reopenedRepo)
        try TestSupport.assertCategoryTruth(reopenedRepo)
    }

    @Test func transferCommittedDataSurvivesProcessDeath() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: wallets[0].id,
                destinationWalletID: wallets[1].id,
                amountMinor: 25_000,
                occurredAt: .now,
                merchant: "Crash transfer",
                note: ""
            )
        )

        try TestSupport.assertNoPartialTransfer(repository)

        manager = nil

        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)
        try TestSupport.assertNoPartialTransfer(reopenedRepo)
        try TestSupport.assertWalletTruth(reopenedRepo)
    }

    @Test func seedDataSurvivesProcessDeath() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()

        let walletsBefore = try repository.wallets().count
        let categoriesBefore = try repository.categories().count

        manager = nil

        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)

        #expect(try reopenedRepo.wallets().count == walletsBefore)
        #expect(try reopenedRepo.categories().count == categoriesBefore)
    }
}
