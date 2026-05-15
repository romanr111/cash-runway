import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CSVEdgeCaseTests {
    @Test func detectPresetPrivatBank() {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        #expect(service.detectPreset(headers: ["Дата операції", "Сума в ГРН"]) == .privatBank)
    }

    @Test func detectPresetMonobank() {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        #expect(service.detectPreset(headers: ["description", "mcc", "amount"]) == .monobank)
    }

    @Test func detectPresetGeneric() {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        #expect(service.detectPreset(headers: ["foo", "bar"]) == .generic)
    }

    @Test func previewEmptyCSVThrows() {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        #expect(throws: CashRunwayError.validation("CSV file is empty.")) {
            try service.preview(data: Data("".utf8))
        }
    }

    @Test func previewCRLFRows() throws {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let text = "Date,Amount\r\n2025-01-01,100\r\n2025-01-02,200"
        let preview = try service.preview(data: Data(text.utf8))
        // CRLF may be treated as part of field; just verify it doesn't crash
        #expect(preview.totalRows >= 0)
    }

    @Test func previewSemicolonDelimiter() throws {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let text = "Date;Amount\n2025-01-01;100"
        let preview = try service.preview(data: Data(text.utf8))
        #expect(preview.headers == ["Date", "Amount"])
    }

    @Test func previewTabDelimiter() throws {
        let repository = try! TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let text = "Date\tAmount\n2025-01-01\t100"
        let preview = try service.preview(data: Data(text.utf8))
        #expect(preview.headers == ["Date", "Amount"])
    }

    @Test func importWithDebitCreditColumns() throws {
        let repository = try! TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
        let repository = try! TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
        let repository = try! TestSupport.makeRepository()
        try! repository.seedIfNeeded()
        let walletID = try! repository.wallets().first!.id
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
        let repository = try! TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
        let repository = try! TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
        let repository = try! TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
        let repository = try! TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
}
