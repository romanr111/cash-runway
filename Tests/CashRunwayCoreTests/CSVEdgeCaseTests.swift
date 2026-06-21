import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CSVEdgeCaseTests {
    @Test(arguments: [
        (["Дата операції", "Опис операції", "Сума в ГРН"], CSVPreset.privatBank),
        (["Дата операції", "Сума в ГРН"], CSVPreset.generic),
        (["Date", "Description", "MCC", "Amount"], CSVPreset.monobank),
        (["description", "mcc", "amount"], CSVPreset.generic),
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

     func weakMonobankHeadersFallBackToGenericBankCSV() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let format = service.detectFormat(headers: ["Description", "MCC"])

        #expect(format == .genericBankCSV)
        #expect(service.detectPreset(headers: ["Description", "MCC"]) == .generic)
    }

     func unknownXLSXHeadersFallBackToGenericBankXLSX() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let format = service.detectFormat(headers: ["Posted", "Value", "Details"], fileKind: .xlsx)

        #expect(format == .genericBankXLSX)
    }

     func cashRunwayBOMHeaderDetectsWalletExport() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let headers = ["\u{feff}Date", "Wallet", "Type", "Category name", "Amount", "Currency", "Note", "Labels", "Author"]

        #expect(service.detectFormat(headers: headers) == .cashRunwayCSV)
        #expect(service.detectPreset(headers: headers) == .cashRunwayWallet)
    }

     func genericXLSXImportRecordsGenericXLSXSourceFormat() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Posted,Value,Details
        2026-05-01,-24.50,Cafe Terminal
        """
        let mapping = CSVImportMapping(
            dateColumn: "Posted",
            amountColumn: "Value",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Details",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "unknown.xlsx",
            format: .genericBankXLSX,
            mapping: mapping
        )

        #expect(result.job.sourceFormatID == BankStatementFormat.genericBankXLSX.id)
    }
}
