import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CSVImportExportIntegrityTests {

    // MARK: - CR-013/CR-014: CSV import does not mutate existing transactions

    @Test func csvImportDoesNotMutateExistingManualTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let category = try #require(try repository.categories(kind: .expense).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let manualDraft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(amountMinor: 10_000)
            .with(occurredAt: now)
            .with(categoryID: category.id)
            .with(merchant: "Manual Shop")
            .with(source: .manual)
            .build()
        try repository.saveTransaction(manualDraft)

        let manualCountBefore = try transactionCountBySource(repository, source: .manual)
        let balanceBefore = try #require(try repository.wallets().first?.currentBalanceMinor)

        let csvText = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2025-01-02,Main Wallet,Expense,Groceries,CSV Shop,50.00,UAH,CSV note,,
        """
        let service = CSVService(repository: repository)
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category name",
            labelsColumn: "Labels",
            walletID: wallet.id,
            defaultKind: .expense,
            typeColumn: "Type",
            walletColumn: "Wallet",
            currencyColumn: "Currency"
        )
        let result = try service.importCSV(data: Data(csvText.utf8), fileName: "test.csv", mapping: mapping)

        #expect(result.insertedTransactions == 1)
        #expect(try transactionCountBySource(repository, source: .manual) == manualCountBefore)

        let manualTx = try #require(try repository.transactions(query: .init()).first { $0.merchant == "Manual Shop" })
        #expect(manualTx.amountMinor == -10_000)

        let balanceAfter = try #require(try repository.wallets().first?.currentBalanceMinor)
        #expect(balanceAfter == balanceBefore - 5_000)
    }

    @Test func csvImportDoesNotMutateExistingBankSyncTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let _ = try #require(try repository.categories(kind: .expense).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let syncStartAt = Date(timeIntervalSince1970: 1_600_000_000)
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: syncStartAt,
            tokenKeychainAccount: "mono-token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: now,
            updatedAt: now
        )
        let account = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "mono-acc",
            walletID: wallet.id,
            displayName: "Black",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "4444",
            iban: nil,
            isEnabled: true,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveBankIntegration(integration)
        try repository.saveBankAccount(account)

        _ = try repository.importMonobankExpenseItems(
            [MonobankStatementItem(
                id: "bank-tx-1",
                time: Int(now.timeIntervalSince1970),
                description: "Bank Merchant",
                mcc: nil,
                originalMcc: nil,
                amount: -8_000,
                operationAmount: nil,
                currencyCode: 980,
                commissionRate: nil,
                cashbackAmount: nil,
                balance: nil,
                hold: nil,
                receiptId: nil,
                comment: nil,
                counterEdrpou: nil,
                counterIban: nil,
                counterName: "Bank Merchant"
            )],
            account: account,
            integration: integration
        )

        let bankCountBefore = try transactionCountBySource(repository, source: .bankSync)
        let balanceBefore = try #require(try repository.wallets().first?.currentBalanceMinor)

        let csvText = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2025-01-02,Main Wallet,Expense,Groceries,CSV Shop,30.00,UAH,CSV note,,
        """
        let service = CSVService(repository: repository)
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category name",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense,
            typeColumn: "Type",
            walletColumn: "Wallet",
            currencyColumn: "Currency"
        )
        let result = try service.importCSV(data: Data(csvText.utf8), fileName: "test.csv", mapping: mapping)

        #expect(result.insertedTransactions == 1)
        #expect(try transactionCountBySource(repository, source: .bankSync) == bankCountBefore)

        let bankTx = try #require(try repository.transactions(query: .init()).first { $0.merchant == "Bank Merchant" })
        #expect(bankTx.amountMinor == -8_000)

        let balanceAfter = try #require(try repository.wallets().first?.currentBalanceMinor)
        #expect(balanceAfter == balanceBefore - 3_000)
    }

    // MARK: - CR-013: CSV export/import roundtrip preserves ledger totals and references

    @Test func csvExportImportRoundTripPreservesLedgerTotals() throws {
        let source = try TestSupport.makeRepository()
        try source.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: source)
        let wallet = try #require(try source.wallets().first)
        let expenseCategory = try #require(try source.categories(kind: .expense).first)
        let incomeCategory = try #require(try source.categories(kind: .income).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try source.saveTransaction(
            TransactionBuilder()
                .with(kind: .expense)
                .with(walletID: wallet.id)
                .with(amountMinor: 12_000)
                .with(occurredAt: now)
                .with(categoryID: expenseCategory.id)
                .with(merchant: "Grocery")
                .build()
        )
        try source.saveTransaction(
            TransactionBuilder()
                .with(kind: .income)
                .with(walletID: wallet.id)
                .with(amountMinor: 50_000)
                .with(occurredAt: now)
                .with(categoryID: incomeCategory.id)
                .with(merchant: "Salary")
                .build()
        )

        let service = CSVService(repository: source)
        let exported = try service.exportCSV()
        let sourceNetWorth = try source.wallets().reduce(0) { $0 + $1.currentBalanceMinor }

        let target = try TestSupport.makeRepository()
        try target.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: target)
        let targetWallet = try #require(try target.wallets().first)

        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category name",
            labelsColumn: nil,
            walletID: targetWallet.id,
            defaultKind: .expense,
            typeColumn: "Type",
            walletColumn: "Wallet",
            currencyColumn: "Currency"
        )
        let targetService = CSVService(repository: target)
        let result = try targetService.importCSV(data: Data(exported.utf8), fileName: "export.csv", mapping: mapping)

        #expect(result.insertedTransactions == 2)
        let targetNetWorth = try target.wallets().reduce(0) { $0 + $1.currentBalanceMinor }
        #expect(targetNetWorth == sourceNetWorth)
    }

    @Test func csvExportImportRoundTripPreservesTransactionReferences() throws {
        let source = try TestSupport.makeRepository()
        try source.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: source)
        let wallet = try #require(try source.wallets().first)
        let expenseCategory = try #require(try source.categories(kind: .expense).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try source.saveTransaction(
            TransactionBuilder()
                .with(kind: .expense)
                .with(walletID: wallet.id)
                .with(amountMinor: 15_000)
                .with(occurredAt: now)
                .with(categoryID: expenseCategory.id)
                .with(merchant: "Coffee")
                .with(note: "Morning")
                .build()
        )

        let service = CSVService(repository: source)
        let exported = try service.exportCSV()

        let target = try TestSupport.makeRepository()
        try target.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: target)
        let targetWallet = try #require(try target.wallets().first)

        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category name",
            labelsColumn: nil,
            walletID: targetWallet.id,
            defaultKind: .expense,
            typeColumn: "Type",
            walletColumn: "Wallet",
            currencyColumn: "Currency"
        )
        let targetService = CSVService(repository: target)
        let result = try targetService.importCSV(data: Data(exported.utf8), fileName: "export.csv", mapping: mapping)

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try target.transactions(query: .init()).first)
        #expect(imported.amountMinor == -15_000)
        #expect(imported.merchant == "Coffee")
        #expect(imported.note == "Morning")

        let importedDraft = try target.transactionDraft(id: imported.id)
        let targetCategory = try #require(try target.categories(kind: .expense).first { $0.name == expenseCategory.name })
        #expect(importedDraft.categoryID == targetCategory.id)
        #expect(importedDraft.walletID == targetWallet.id)
    }

    // MARK: - Helpers

    private func transactionCountBySource(_ repository: CashRunwayRepository, source: TransactionSource) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [source.rawValue]) ?? 0
        }
    }
}
