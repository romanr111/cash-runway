import Foundation
import GRDB
import CryptoKit
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseKeyMismatchTests {
    @Test func wrongDatabaseKeyFailsWithoutMutatingDatabase() throws {
        let correctKey = "aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkkllllmmmmnnnnoooopppp"
        let wrongKey = "zzzzyyyyxxxxwwwwvvvvuuuuttttssssrrrrqqqqppppoooonnnnmmmmllllkkkk"

        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        let sentinelMerchant = "SentinelTransaction"

        let keychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repo = CashRunwayRepository(databaseManager: try #require(manager))
        try repo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repo)
        let wallet = try #require(try repo.wallets().first)
        let categories = try repo.categories(kind: .expense)
        try repo.saveTransaction(TransactionBuilder()
            .with(walletID: wallet.id)
            .with(amountMinor: 42_000)
            .with(categoryID: try #require(categories.first?.id))
            .with(merchant: sentinelMerchant)
            .with(source: .manual).build()
        )

        let walURL = TestSupport.walURL(for: dbURL)
        let preHash = sha256OfFile(at: dbURL)
        let preWalHash = sha256OfFile(at: walURL)

        manager = nil

        let wrongKeychain = TestKeychainStore(items: ["database-key": Data(wrongKey.utf8)])
        var thrownError: Error?
        do {
            _ = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: false, keychain: wrongKeychain)
        } catch {
            thrownError = error
        }
        #expect(thrownError != nil)

        let postHash = sha256OfFile(at: dbURL)
        let postWalHash = sha256OfFile(at: walURL)
        #expect(postHash == preHash)
        #expect(postWalHash == preWalHash)

        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: recoveryDir.path))

        let correctKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        let newManager = try DatabaseManager(locationProvider: location, keychain: correctKeychain)
        let newRepo = CashRunwayRepository(databaseManager: newManager)
        let sentinelTx = try newRepo.transactions().first { $0.merchant == sentinelMerchant }
        #expect(sentinelTx != nil)
    }

    private func sha256OfFile(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "MISSING" }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}