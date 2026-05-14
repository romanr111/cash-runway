import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseBackupTests {
    @Test func csvExportContainsEveryNonDeletedTransaction() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)

        try repository.saveTransaction(
            TransactionDraft(kind: .expense, walletID: wallets[0].id, amountMinor: 5_000, occurredAt: .now, categoryID: expenseCategory.id, merchant: "A", note: "")
        )
        try repository.saveTransaction(
            TransactionDraft(kind: .income, walletID: wallets[0].id, amountMinor: 10_000, occurredAt: .now, categoryID: incomeCategory.id, merchant: "B", note: "")
        )
        try repository.saveTransaction(
            TransactionDraft(kind: .transfer, walletID: wallets[0].id, destinationWalletID: wallets[1].id, amountMinor: 2_000, occurredAt: .now, merchant: "C", note: "")
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
        let walletID = try #require(try repository.wallets().first?.id)
        let category = try #require(try repository.categories(kind: .expense).first)
        let label = Label(id: UUID(), name: "Trip", colorHex: "#1CC389", createdAt: .now, updatedAt: .now)
        try repository.saveLabel(label)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 3_000,
                occurredAt: .now,
                categoryID: category.id,
                labelIDs: [label.id],
                merchant: "Labeled",
                note: ""
            )
        )

        let service = CSVService(repository: repository)
        let exported = try service.exportCSV()

        #expect(exported.contains("Trip"))
        #expect(exported.contains(category.name))
    }

    @Test func csvRoundTripRestoresAllWalletsAndBalances() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let category = try #require(try repository.categories(kind: .expense).first)
        let service = CSVService(repository: repository)

        try repository.saveTransaction(
            TransactionDraft(kind: .expense, walletID: wallet.id, amountMinor: 2_500, occurredAt: .now, categoryID: category.id, merchant: "R1", note: "")
        )
        try repository.saveTransaction(
            TransactionDraft(kind: .expense, walletID: wallet.id, amountMinor: 1_500, occurredAt: .now, categoryID: category.id, merchant: "R2", note: "")
        )

        let exported = try service.exportCSV()
        let originalWallets = try repository.wallets()
        let originalBalances = Dictionary(uniqueKeysWithValues: originalWallets.map { ($0.id, $0.currentBalanceMinor) })

        let roundTripRepo = try TestSupport.makeRepository()
        try roundTripRepo.seedIfNeeded()
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
