import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MaskedCardSearchIndexTests {
    @Test func newMaskedCardTransactionIndexesOnlyVisibleDigits() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let category = try #require(try repository.categories(kind: .expense).first)
        let transactionID = UUID()
        let rawTitle = "537552****6627"

        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 53_610,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            categoryID: category.id,
            merchant: rawTitle,
            source: .bankSync
        ))

        let storedValues = try repository.databaseManager.dbQueue.read { db in
            let persisted = try String.fetchOne(
                db,
                sql: "SELECT merchant FROM transactions WHERE id = ?",
                arguments: [transactionID.uuidString]
            )
            let indexed = try String.fetchOne(
                db,
                sql: "SELECT merchant FROM transaction_search WHERE transaction_id = ?",
                arguments: [transactionID.uuidString]
            )
            return (persisted, indexed)
        }
        let hiddenPrefixMatches = try repository.transactions(query: .init(searchText: "537552"))

        #expect(storedValues.0 == rawTitle)
        #expect(storedValues.1 == "5375 6627")
        #expect(try repository.transactions(query: .init(searchText: "5375")).map(\.id).contains(transactionID))
        #expect(try repository.transactions(query: .init(searchText: "6627")).map(\.id).contains(transactionID))
        #expect(!hiddenPrefixMatches.map(\.id).contains(transactionID))
    }

    @Test func migrationSanitizesLegacyFTSWithoutChangingPersistedMerchant() throws {
        let location = TestSupport.makeLocation()
        let key = "masked-card-search-migration-key"
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])
        let transactionID = UUID()
        let rawTitle = "537552****6627"

        do {
            let partialMigrator = DatabaseManager.makeMigrator(upTo: "v8_currency_foundation")
            let manager = try DatabaseManager(
                locationProvider: location,
                keychain: keychain,
                migrator: partialMigrator
            )
            let repository = CashRunwayRepository(databaseManager: manager)
            try repository.seedIfNeeded()
            try TestSupport.seedFixtureWallets(into: repository)
            let wallet = try #require(try repository.wallets().first)
            let category = try #require(try repository.categories(kind: .expense).first)

            try repository.saveTransaction(TransactionDraft(
                id: transactionID,
                kind: .expense,
                walletID: wallet.id,
                amountMinor: 53_610,
                occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
                categoryID: category.id,
                merchant: rawTitle,
                source: .bankSync
            ))

            try manager.dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE transaction_search SET merchant = ? WHERE transaction_id = ?",
                    arguments: [rawTitle, transactionID.uuidString]
                )
            }
            try manager.checkpointWal()
        }

        let manager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: manager)
        let storedValues = try manager.dbQueue.read { db in
            let persisted = try String.fetchOne(
                db,
                sql: "SELECT merchant FROM transactions WHERE id = ?",
                arguments: [transactionID.uuidString]
            )
            let indexed = try String.fetchOne(
                db,
                sql: "SELECT merchant FROM transaction_search WHERE transaction_id = ?",
                arguments: [transactionID.uuidString]
            )
            return (persisted, indexed)
        }
        let hiddenPrefixMatches = try repository.transactions(query: .init(searchText: "537552"))

        #expect(storedValues.0 == rawTitle)
        #expect(storedValues.1 == "5375 6627")
        #expect(try repository.transactions(query: .init(searchText: "5375")).map(\.id).contains(transactionID))
        #expect(try repository.transactions(query: .init(searchText: "6627")).map(\.id).contains(transactionID))
        #expect(!hiddenPrefixMatches.map(\.id).contains(transactionID))
    }
}
