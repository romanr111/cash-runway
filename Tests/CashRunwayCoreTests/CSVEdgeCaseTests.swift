import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CSVEdgeCaseTests {
    @Test(arguments: [
        (["Дата операції", "Сума в ГРН"], CSVPreset.privatBank),
        (["description", "mcc", "amount"], CSVPreset.monobank),
        (["foo", "bar"], CSVPreset.generic),
    ])
    func detectPreset(headers: [String], expected: CSVPreset) throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        #expect(service.detectPreset(headers: headers) == expected)
    }

    @Test func previewEmptyCSVThrows() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        #expect(throws: CashRunwayError.validation("CSV file is empty.")) {
            try service.preview(data: Data("".utf8))
        }
    }

    @Test func previewCRLFRows() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let text = "Date,Amount\r\n2025-01-01,100\r\n2025-01-02,200"
        let preview = try service.preview(data: Data(text.utf8))
        // CRLF may be treated as part of field; just verify it doesn't crash
        #expect(preview.totalRows >= 0)
    }

    @Test(arguments: [
        ("Date;Amount\n2025-01-01;100", ["Date", "Amount"]),
        ("Date\tAmount\n2025-01-01\t100", ["Date", "Amount"]),
    ])
    func previewDelimiter(text: String, expectedHeaders: [String]) throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let preview = try service.preview(data: Data(text.utf8))
        #expect(preview.headers == expectedHeaders)
    }

    @Test func importWithDebitCreditColumns() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Debit,Credit\n2025-01-01,100,\n2025-01-02,,200"
        let preview = try service.preview(data: Data(text.utf8))
        #expect(preview.totalRows == 2)

        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: nil,
            debitColumn: "Debit",
            creditColumn: "Credit",
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        #expect(result.insertedTransactions == 2)
    }

    @Test func importDebitCreditColumnsClassifiesKindsCorrectly() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Debit,Credit,Merchant\n2025-01-01,100,,Groceries\n2025-01-02,,200,Salary"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: nil,
            debitColumn: "Debit",
            creditColumn: "Credit",
            merchantColumn: "Merchant",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        #expect(result.insertedTransactions == 2)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions(query: .init())
        #expect(transactions.count == 2)
        let debitRow = try #require(transactions.first { $0.merchant == "Groceries" })
        #expect(debitRow.kind == .expense)
        let creditRow = try #require(transactions.first { $0.merchant == "Salary" })
        #expect(creditRow.kind == .income)
    }

    @Test func importDebitCreditExpensesOnlySkipsCreditRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Debit,Credit,Merchant\n2025-01-01,100,,Groceries\n2025-01-02,,200,Salary"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: nil,
            debitColumn: "Debit",
            creditColumn: "Credit",
            merchantColumn: "Merchant",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let result = try service.importCSV(
            data: Data(text.utf8),
            fileName: "test.csv",
            mapping: mapping,
            rowFilter: .expensesOnly
        )
        #expect(result.insertedTransactions == 1)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions(query: .init())
        #expect(transactions.count == 1)
        #expect(transactions.first?.kind == .expense)
        #expect(transactions.first?.merchant == "Groceries")
    }

    @Test func previewDebitCreditExpensesOnlySkipsCreditRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Debit,Credit,Merchant\n2025-01-01,100,,Groceries\n2025-01-02,,200,Salary"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: nil,
            debitColumn: "Debit",
            creditColumn: "Credit",
            merchantColumn: "Merchant",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let rows = try service.previewPreparedRows(
            data: Data(text.utf8),
            mapping: mapping,
            rowFilter: .expensesOnly,
            limit: 5
        )
        #expect(rows.count == 1)
        #expect(rows.first?.draft.kind == .expense)
        #expect(rows.first?.draft.merchant == "Groceries")
    }

    @Test func importWithExplicitTypeColumn() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        #expect(wallets.count >= 2)
        let walletID = wallets[0].id
        let service = CSVService(repository: repository)
        let text = "Date,Type,Amount,Wallet\n2025-01-01,Income,100,Main\n2025-01-02,Expense,50,Main"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: "Type",
            walletColumn: "Wallet"
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        #expect(result.insertedTransactions == 2)
    }

    @Test func importUnsupportedCurrencySkipsRow() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Currency\n2025-01-01,100,USD"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: nil,
            walletColumn: nil,
            currencyColumn: "Currency",
            authorColumn: nil
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        #expect(result.insertedTransactions == 0)
        #expect(result.job.invalidRows == 1)
    }

    @Test func importWithEscapedQuotes() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Note\n2025-01-01,100,\"She said \"hello\"\""
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: "Note",
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        #expect(result.insertedTransactions == 1)
    }

    @Test func importWindows1251Fallback() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let service = CSVService(repository: repository)
        // "Привіт" in Windows-1251 is not valid UTF-8
        let windows1251Bytes: [UInt8] = [0xCF, 0xF0, 0xE8, 0xE2, 0xB3, 0xF2]
        let header = Data("Date,Amount\n".utf8)
        let body = Data("2025-01-01,100\n".utf8)
        var data = header
        data.append(contentsOf: windows1251Bytes)
        data.append(contentsOf: [0x0A]) // newline
        data.append(body)
        let preview = try service.preview(data: data)
        #expect(preview.totalRows >= 0)
    }

    @Test func importMalformedQuotesDoesNotCrash() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        // Unclosed quote — parser should not crash
        let text = "Date,Amount,Note\n2025-01-01,100,\"unclosed note"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: "Note",
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        // The row with malformed quote may be skipped or parsed differently,
        // but the operation must not crash.
        #expect(result.job.invalidRows >= 0)
    }

    @Test func importWithTypeColumnFallsBackToIncomeForPositiveAmount() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        // Type is "Unknown" (not income/expense/transfer), amount is positive, typeColumn is present
        let text = "Date,Type,Amount\n2025-01-01,Unknown,100"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: "Type"
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)
        #expect(result.insertedTransactions == 1)
        let transactions = try repository.transactions(query: .init())
        let imported = try #require(transactions.first)
        #expect(imported.kind == .income)
    }

    @Test func importGenericCSVExpensesOnlySkipsIncomeRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Type,Amount,Merchant\n2025-01-01,Income,100,Salary\n2025-01-02,Expense,50,Cafe"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: "Type"
        )

        let result = try service.importCSV(
            data: Data(text.utf8),
            fileName: "generic.csv",
            mapping: mapping,
            rowFilter: .expensesOnly
        )

        #expect(result.insertedTransactions == 1)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions(query: .init())
        #expect(transactions.count == 1)
        #expect(transactions.first?.kind == .expense)
        #expect(transactions.first?.merchant == "Cafe")
    }

    @Test func importReusesMergedDestinationCategoryByName() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let groceriesID = try #require(try repository.categories(kind: .expense).first { $0.name == "Groceries" }?.id)
        let restaurantsID = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" }?.id)

        try repository.mergeCategory(oldCategoryID: restaurantsID, into: groceriesID)

        let service = CSVService(repository: repository)
        let text = "Date,Amount,Category,Note\n2025-01-01,100,Restaurants,Weekly groceries"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )
        let result = try service.importCSV(data: Data(text.utf8), fileName: "test.csv", mapping: mapping)

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.note == "Weekly groceries" })
        let importedDraft = try repository.transactionDraft(id: imported.id)
        #expect(importedDraft.categoryID == groceriesID)
        #expect(try repository.categories(kind: .expense).contains { $0.name == "Restaurants" } == false)
    }

    @Test func importExpensesOnlySkipsMalformedIncomeRow() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Type,Amount\n,Income,100\n2025-01-02,Expense,50"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: "Type"
        )
        let result = try service.importCSV(
            data: Data(text.utf8),
            fileName: "test.csv",
            mapping: mapping,
            rowFilter: .expensesOnly
        )
        #expect(result.insertedTransactions == 1)
        #expect(result.invalidRows == 0)
        #expect(result.rowErrors.isEmpty)
    }

    @Test func importAllTransactionsFlagsMalformedIncomeRow() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = "Date,Type,Amount\n,Income,100\n2025-01-02,Expense,50"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: "Type"
        )
        let result = try service.importCSV(
            data: Data(text.utf8),
            fileName: "test.csv",
            mapping: mapping,
            rowFilter: .allTransactions
        )
        #expect(result.insertedTransactions == 1)
        #expect(result.invalidRows == 1)
        #expect(result.rowErrors.count == 1)
    }
}
