import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseWALTests {
    @Test func walFileIsCreatedAfterFirstWrite() throws {
        let location = TestSupport.makeLocation()
        let manager = try DatabaseManager(locationProvider: location, keychain: TestKeychainStore())
        let repository = CashRunwayRepository(databaseManager: manager)
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)

        let dbURL = try location.databaseURL()
        TestSupport.assertWalFileExists(at: dbURL)
    }

    @Test func checkpointTruncatesWalFile() throws {
        let location = TestSupport.makeLocation()
        let manager = try DatabaseManager(locationProvider: location, keychain: TestKeychainStore())
        let repository = CashRunwayRepository(databaseManager: manager)
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)

        let dbURL = try location.databaseURL()
        TestSupport.assertWalFileExists(at: dbURL)

        try manager.checkpointWal()
        try TestSupport.assertWalFileEmptyOrAbsent(at: dbURL)
    }

    @Test func committedDataSurvivesReopenWithWal() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let category = try #require(try repository.categories(kind: .expense).first)

        for index in 0..<10 {
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .expense,
                    walletID: wallets[0].id,
                    amountMinor: Int64(1_000 * (index + 1)),
                    occurredAt: .now,
                    categoryID: category.id,
                    merchant: "WAL commit \(index)",
                    note: ""
                )
            )
        }

        let countBefore = try repository.transactions().count
        manager = nil

        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)
        let countAfter = try reopenedRepo.transactions().count
        #expect(countAfter == countBefore)
        try TestSupport.assertWalletTruth(reopenedRepo)
        try TestSupport.assertCategoryTruth(reopenedRepo)
    }

    @Test func walAutoRecoveryAfterSHMLoss() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let category = try #require(try repository.categories(kind: .expense).first)

        for index in 0..<10 {
            try repository.saveTransaction(
                TransactionDraft(
                    kind: .expense,
                    walletID: wallets[0].id,
                    amountMinor: Int64(1_000 * (index + 1)),
                    occurredAt: .now,
                    categoryID: category.id,
                    merchant: "WAL recovery \(index)",
                    note: ""
                )
            )
        }

        let countBefore = try repository.transactions().count
        let dbURL = try location.databaseURL()

        // Close without checkpoint, then delete -shm to simulate power-loss corruption.
        manager = nil
        TestSupport.deleteSHMFile(at: dbURL)

        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)
        let countAfter = try reopenedRepo.transactions().count
        #expect(countAfter == countBefore)
        try TestSupport.assertWalletTruth(reopenedRepo)
        try TestSupport.assertCategoryTruth(reopenedRepo)
    }
}
