import Foundation
import GRDB
import CryptoKit
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseKeyStartupMatrixTests {

    @Test func missingKeychainKeyFailsWithoutMutatingDatabase() throws {
        let correctKey = "cccc1111dddd2222eeee3333ffff4444aaaa5555bbbb6666cccc7777dddd8888"
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()

        let createKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: createKeychain)
        let repo = CashRunwayRepository(databaseManager: try #require(manager))
        try repo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repo)
        let sentinelMerchant = "MissingKeySentinel"
        let wallet = try #require(try repo.wallets().first)
        let cats = try repo.categories(kind: .expense)
        try repo.saveTransaction(TransactionBuilder()
            .with(walletID: wallet.id).with(amountMinor: 5_000)
            .with(categoryID: try #require(cats.first?.id))
            .with(merchant: sentinelMerchant).build())
        manager = nil

        let preHash = sha256OfFile(at: dbURL)

        let emptyKeychain = TestKeychainStore(items: [:])
        var thrownError: Error?
        do {
            _ = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: false, keychain: emptyKeychain)
        } catch {
            thrownError = error
        }
        #expect(thrownError != nil)

        #expect(sha256OfFile(at: dbURL) == preHash)
        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: recoveryDir.path))

        let restoredKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        let reopened = try DatabaseManager(locationProvider: location, keychain: restoredKeychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopened)
        #expect(try reopenedRepo.transactions().contains(where: { $0.merchant == sentinelMerchant }))
    }

    @Test func lockedKeychainFailsWithoutMutatingDatabase() throws {
        let correctKey = "eeee1111ffff2222aaaa3333bbbb4444cccc5555dddd6666eeee7777ffff8888"
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()

        let createKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: createKeychain)
        let repo = CashRunwayRepository(databaseManager: try #require(manager))
        try repo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repo)
        let sentinel = "LockedKeySentinel"
        let wallet = try #require(try repo.wallets().first)
        let cats = try repo.categories(kind: .expense)
        try repo.saveTransaction(TransactionBuilder()
            .with(walletID: wallet.id).with(amountMinor: 3_000)
            .with(categoryID: try #require(cats.first?.id))
            .with(merchant: sentinel).build())
        manager = nil

        let preHash = sha256OfFile(at: dbURL)

        let lockedKeychain = TestKeychainStore(readError: KeychainStoreError.readFailed(errSecInteractionNotAllowed))
        var thrownError: Error?
        do {
            _ = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: false, keychain: lockedKeychain)
        } catch {
            thrownError = error
        }
        #expect(thrownError != nil)

        #expect(sha256OfFile(at: dbURL) == preHash)
        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: recoveryDir.path))

        let restoredKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        let reopened = try DatabaseManager(locationProvider: location, keychain: restoredKeychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopened)
        #expect(try reopenedRepo.transactions().contains(where: { $0.merchant == sentinel }))
    }

    @Test func malformedKeyDataFailsWithoutMutatingDatabase() throws {
        let correctKey = "aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888"
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()

        let createKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: createKeychain)
        let repo = CashRunwayRepository(databaseManager: try #require(manager))
        try repo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repo)
        let sentinel = "MalformedKeySentinel"
        let wallet = try #require(try repo.wallets().first)
        let cats = try repo.categories(kind: .expense)
        try repo.saveTransaction(TransactionBuilder()
            .with(walletID: wallet.id).with(amountMinor: 7_000)
            .with(categoryID: try #require(cats.first?.id))
            .with(merchant: sentinel).build())
        manager = nil

        let preHash = sha256OfFile(at: dbURL)

        let malformedKeychain = TestKeychainStore(items: ["database-key": Data()])
        var thrownError: Error?
        do {
            _ = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: false, keychain: malformedKeychain)
        } catch {
            thrownError = error
        }
        #expect(thrownError != nil)

        #expect(sha256OfFile(at: dbURL) == preHash)
        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: recoveryDir.path))

        let restoredKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        let reopened = try DatabaseManager(locationProvider: location, keychain: restoredKeychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopened)
        #expect(try reopenedRepo.transactions().contains(where: { $0.merchant == sentinel }))
    }

    @Test func correctKeyRestoredAfterFailureReopensSuccessfully() throws {
        let correctKey = "dddd1111cccc2222bbbb3333aaaa4444ffff5555eeee6666dddd7777cccc8888"
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()

        let createKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: createKeychain)
        let repo = CashRunwayRepository(databaseManager: try #require(manager))
        try repo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repo)
        let sentinel = "RestoreAfterFailureSentinel"
        let wallet = try #require(try repo.wallets().first)
        let cats = try repo.categories(kind: .expense)
        try repo.saveTransaction(TransactionBuilder()
            .with(walletID: wallet.id).with(amountMinor: 9_000)
            .with(categoryID: try #require(cats.first?.id))
            .with(merchant: sentinel).build())
        let txCountBefore = try repo.transactions().count
        manager = nil

        let wrongKey = "zzzz0000yyyy1111xxxx2222wwww3333vvvv4444uuuu5555tttt6666ssss7777"
        let wrongKeychain = TestKeychainStore(items: ["database-key": Data(wrongKey.utf8)])
        _ = try? DatabaseManager(locationProvider: location, allowsDestructiveRecovery: false, keychain: wrongKeychain)

        let emptyKeychain = TestKeychainStore(items: [:])
        _ = try? DatabaseManager(locationProvider: location, allowsDestructiveRecovery: false, keychain: emptyKeychain)

        let restoredKeychain = TestKeychainStore(items: ["database-key": Data(correctKey.utf8)])
        let reopened = try DatabaseManager(locationProvider: location, keychain: restoredKeychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopened)
        #expect(try reopenedRepo.transactions().count == txCountBefore)
        #expect(try reopenedRepo.transactions().contains(where: { $0.merchant == sentinel }))
    }

    private func sha256OfFile(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "MISSING" }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}