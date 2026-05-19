import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseBackupTests {
    @Test func csvExportContainsEveryNonDeletedTransaction() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)

        try repository.saveTransaction(
            TransactionBuilder()
                .with(walletID: wallets[0].id)
                .with(amountMinor: 5_000)
                .with(categoryID: expenseCategory.id)
                .with(merchant: "A")
                .build()
        )
        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .income)
                .with(walletID: wallets[0].id)
                .with(amountMinor: 10_000)
                .with(categoryID: incomeCategory.id)
                .with(merchant: "B")
                .build()
        )
        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .transfer)
                .with(walletID: wallets[0].id)
                .with(destinationWalletID: wallets[1].id)
                .with(amountMinor: 2_000)
                .with(merchant: "C")
                .build()
        )

        let expectedNonTransferCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE is_deleted = 0 AND type NOT IN ('transfer_out', 'transfer_in')") ?? 0
        }

        let service = CSVService(repository: repository)
        let exported = try service.exportCSV()
        let rows = TestSupport.parseCSVRows(exported)
        let dataRows = rows.dropFirst()

        #expect(dataRows.count == expectedNonTransferCount)
    }

    @Test func csvExportContainsAllLabelsAndCategories() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let category = try #require(try repository.categories(kind: .expense).first)
        let label = LabelBuilder().with(name: "Trip").with(colorHex: "#1CC389").build()
        try repository.saveLabel(label)

        try repository.saveTransaction(
            TransactionBuilder()
                .with(walletID: walletID)
                .with(amountMinor: 3_000)
                .with(categoryID: category.id)
                .with(labelIDs: [label.id])
                .with(merchant: "Labeled")
                .build()
        )

        let service = CSVService(repository: repository)
        let exported = try service.exportCSV()

        #expect(exported.contains("Trip"))
        #expect(exported.contains(category.name))
    }

    @Test func csvRoundTripRestoresAllWalletsAndBalances() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let category = try #require(try repository.categories(kind: .expense).first)
        let service = CSVService(repository: repository)

        try repository.saveTransaction(
            TransactionBuilder()
                .with(walletID: wallet.id)
                .with(amountMinor: 2_500)
                .with(categoryID: category.id)
                .with(merchant: "R1")
                .build()
        )
        try repository.saveTransaction(
            TransactionBuilder()
                .with(walletID: wallet.id)
                .with(amountMinor: 1_500)
                .with(categoryID: category.id)
                .with(merchant: "R2")
                .build()
        )

        let exported = try service.exportCSV()
        let originalWallets = try repository.wallets()
        let originalBalances = Dictionary(uniqueKeysWithValues: originalWallets.map { ($0.id, $0.currentBalanceMinor) })

        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: roundTripRepo)
        let roundTripWalletID = try #require(try roundTripRepo.wallets().first?.id)
        let roundTripService = CSVService(repository: roundTripRepo)
        let result = try roundTripService.importCSV(
            data: Data(exported.utf8),
            fileName: "roundtrip.csv",
            mapping: TestSupport.cashRunwayWalletMapping(walletID: roundTripWalletID)
        )

        #expect(result.insertedTransactions == 2)

        let roundTripWallets = try roundTripRepo.wallets()
        for original in originalWallets {
            let restored = try #require(roundTripWallets.first(where: { $0.name == original.name }))
            #expect(restored.currentBalanceMinor == originalBalances[original.id])
        }

        try TestSupport.assertWalletTruth(roundTripRepo)
    }
}
