import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct WalletExclusionFlagTests {
    @Test func backupWalletWithoutExclusionKeyDecodesFalse() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "name": "Legacy Wallet",
            "kind": "card",
            "categoryID": "22222222-2222-2222-2222-222222222223",
            "startingBalanceMinor": 100_00,
            "currentBalanceMinor": 100_00,
            "isArchived": false,
            "sortOrder": 0,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoded = try JSONDecoder().decode(BackupWallet.self, from: Data(json.utf8))

        #expect(decoded.isExcludedFromSummary == false)
    }

    @Test func backupWalletWithExclusionKeyTrueDecodesTrue() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444445",
            "name": "Savings Wallet",
            "kind": "savings",
            "isExcludedFromSummary": true,
            "startingBalanceMinor": 100_00,
            "currentBalanceMinor": 100_00,
            "isArchived": false,
            "sortOrder": 0,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoded = try JSONDecoder().decode(BackupWallet.self, from: Data(json.utf8))

        #expect(decoded.isExcludedFromSummary == true)
    }

    @Test func saveWalletPersistsExclusionFlag() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        var wallet = WalletBuilder().with(name: "Excluded Entity").with(kind: .card).build()
        wallet.isExcludedFromSummary = true
        try repository.saveWallet(wallet)

        let loaded = try #require(
            try repository.wallets().first { $0.id == wallet.id }
        )
        #expect(loaded.isExcludedFromSummary == true)

        wallet.isExcludedFromSummary = false
        try repository.saveWallet(wallet)

        let reloaded = try #require(
            try repository.wallets().first { $0.id == wallet.id }
        )
        #expect(reloaded.isExcludedFromSummary == false)
    }
}