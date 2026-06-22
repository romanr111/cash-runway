import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct PrivatBankXLSXImportTests {
    private let privatBankXLSXHeaders = [
        "Дата",
        "Категорія",
        "Картка",
        "Опис операції",
        "Сума в валюті картки",
        "Валюта картки",
        "Сума в валюті транзакції",
        "Валюта транзакції",
        "Залишок на кінець періоду",
        "Валюта залишку"
    ]

    private var fixtureURL: URL {
        let fileURL = URL(fileURLWithPath: #file)
        let candidates = [
            fileURL.deletingLastPathComponent().appendingPathComponent("Fixtures/privatbank.xlsx"),
            fileURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tests/CashRunwayCoreTests/Fixtures/privatbank.xlsx"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/CashRunwayCoreTests/Fixtures/privatbank.xlsx"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("CashRunwayCoreTests/Fixtures/privatbank.xlsx")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    @Test func detectPrivatBankXLSXHeaders() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        #expect(service.detectPreset(headers: privatBankXLSXHeaders) == .privatBank)
    }

    @Test func defaultMappingForPrivatBankXLSX() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let mapping = service.defaultMapping(headers: privatBankXLSXHeaders, format: .privatBankXLSXv1, walletID: nil)

        #expect(mapping.dateColumn == "Дата")
        #expect(mapping.amountColumn == "Сума в валюті картки")
        #expect(mapping.merchantColumn == "Опис операції")
        #expect(mapping.categoryColumn == "Категорія")
        #expect(mapping.currencyColumn == nil)
        #expect(mapping.defaultKind == .income)
    }

    @Test func convertPrivatBankXLSXToCSV() throws {
        let data = try Data(contentsOf: fixtureURL)
        let csvText = try XLSXConverter.convertToCSV(data: data)
        let rows = csvText.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(rows.count >= 4)
        let headers = rows[0].components(separatedBy: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        #expect(headers.contains("Дата"))
        #expect(headers.contains("Опис операції"))
        #expect(headers.contains("Сума в валюті картки"))
    }

    @Test func importPrivatBankXLSXSample() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let data = try Data(contentsOf: fixtureURL)
        let csvText = try XLSXConverter.convertToCSV(data: data)
        let preview = try service.preview(data: Data(csvText.utf8))
        let format = service.detectFormat(headers: preview.headers, fileKind: .xlsx)
        #expect(format == .privatBankXLSXv1)
        let mapping = service.defaultMapping(headers: preview.headers, format: format, walletID: walletID)

        let result = try service.importStatement(
            normalizedData: Data(csvText.utf8),
            fileName: "privat.xlsx",
            format: format,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 3)
        #expect(result.job.sourceFormatID == BankStatementFormat.privatBankXLSXv1.id)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions()

        let expense = try #require(transactions.first { $0.merchant == "Synthetic Market" })
        #expect(expense.kind == .expense)
        #expect(expense.amountMinor == -12_345)
        #expect(expense.categoryName == "Groceries")

        let transfer = try #require(transactions.first { $0.merchant == "Тестовий Відправник" })
        #expect(transfer.kind == .income)
        #expect(transfer.amountMinor == 25_000)
        #expect(transfer.categoryName == "Other Income")

        let foreign = try #require(transactions.first { $0.merchant == "Sample Fuel Rental" })
        #expect(foreign.kind == .expense)
        #expect(foreign.amountMinor == -6_789)
        #expect(foreign.categoryName == "Transport")
    }

    @Test func legacyPrivatBankCSVStillImportsAsExpense() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата операції,Призначення,Сума в ГРН,Валюта
        15.06.2026,Test Merchant,100.00,UAH
        """
        let preview = try service.preview(data: Data(text.utf8))
        #expect(service.detectPreset(headers: preview.headers) == .privatBank)
        let mapping = service.defaultMapping(headers: preview.headers, format: .privatBankCSVv1, walletID: walletID)
        #expect(mapping.defaultKind == .expense)
        #expect(mapping.currencyColumn == "Валюта")

        let result = try service.importCSV(data: Data(text.utf8), fileName: "legacy.csv", mapping: mapping)

        #expect(result.insertedTransactions == 1)
        let transaction = try #require(try repository.transactions().first)
        #expect(transaction.merchant == "Test Merchant")
        #expect(transaction.kind == .expense)
    }
}
