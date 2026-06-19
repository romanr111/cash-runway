import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MonobankCSVImportTests {
    private let monobankHeaders = [
        "Дата і час операції",
        "Деталі операції",
        "MCC",
        "Сума в валюті картки (UAH)",
        "Сума в валюті операції",
        "Валюта",
        "Курс",
        "Сума комісій (UAH)",
        "Сума кешбеку (UAH)",
        "Залишок після операції"
    ]

    private let englishMonobankHeaders = [
        "Date and time",
        "Description",
        "MCC",
        "Card currency amount, (UAH)",
        "Operation amount",
        "Operation currency",
        "Exchange rate",
        "Commission, (UAH)",
        "Cashback amount, (UAH)",
        "Balance"
    ]

    @Test func detectUkrainianMonobankPreset() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        #expect(service.detectPreset(headers: monobankHeaders) == .monobank)
    }

    @Test func defaultMappingForUkrainianMonobank() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: nil)

        #expect(mapping.dateColumn == "Дата і час операції")
        #expect(mapping.amountColumn == "Сума в валюті картки (UAH)")
        #expect(mapping.merchantColumn == "Деталі операції")
        #expect(mapping.mccColumn == "MCC")
        #expect(mapping.currencyColumn == nil)
        #expect(mapping.defaultKind == .income)
    }

    @Test func detectEnglishMonobankPreset() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        #expect(service.detectPreset(headers: englishMonobankHeaders) == .monobank)
    }

    @Test func defaultMappingForEnglishMonobank() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let mapping = service.defaultMapping(headers: englishMonobankHeaders, preset: .monobank, walletID: nil)

        #expect(mapping.dateColumn == "Date and time")
        #expect(mapping.amountColumn == "Card currency amount, (UAH)")
        #expect(mapping.merchantColumn == "Description")
        #expect(mapping.currencyColumn == nil)
        #expect(mapping.defaultKind == .income)
    }

    @Test func importParsesDateWithTime() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH)
        17.06.2026 07:59:13,Bolt,4121,-128.0
        """
        let mapping = CSVImportMapping(
            dateColumn: "Дата і час операції",
            amountColumn: "Сума в валюті картки (UAH)",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Деталі операції",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .income
        )

        let result = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)

        #expect(result.insertedTransactions == 1)
        let transaction = try #require(try repository.transactions().first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: transaction.occurredAt)
        #expect(components.year == 2026)
        #expect(components.month == 6)
        #expect(components.day == 17)
        #expect(components.hour == 7)
        #expect(components.minute == 59)
        #expect(components.second == 13)
    }

    @Test func importMonobankSampleRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH),Сума в валюті операції,Валюта,Курс,Сума комісій (UAH),Сума кешбеку (UAH),Залишок після операції
        16.06.2026 14:15:08,Bolt,4121,-128.0,-128.0,UAH,—,—,6.4,401279.78
        15.06.2026 13:11:03,Від: Ольга Ярмош,4829,2700.0,2700.0,UAH,—,—,—,405151.78
        12.06.2026 11:57:44,OpenAI,5734,-904.0,-20.0,USD,45.2,—,—,410399.07
        """
        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: walletID)

        let result = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)

        #expect(result.insertedTransactions == 3)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions().sorted { $0.occurredAt < $1.occurredAt }
        #expect(transactions.count == 3)

        let openAI = transactions[0]
        #expect(openAI.merchant == "OpenAI")
        #expect(openAI.kind == .expense)
        #expect(openAI.amountMinor == -90_400)

        let income = transactions[1]
        #expect(income.merchant == "Від: Ольга Ярмош")
        #expect(income.kind == .income)
        #expect(income.amountMinor == 270_000)

        let bolt = transactions[2]
        #expect(bolt.merchant == "Bolt")
        #expect(bolt.kind == .expense)
        #expect(bolt.amountMinor == -12_800)
    }

    @Test func importEnglishMonobankSampleRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Date and time,Description,MCC,"Card currency amount, (UAH)",Operation amount,Operation currency,Exchange rate,"Commission, (UAH)","Cashback amount, (UAH)",Balance
        16.06.2026 14:15:08,Bolt,4121,-128.0,-128.0,UAH,—,—,6.4,401279.78
        15.06.2026 13:11:03,From: Ольга Ярмош,4829,2700.0,2700.0,UAH,—,—,—,405151.78
        12.06.2026 11:57:44,OpenAI,5734,-904.0,-20.0,USD,45.2,—,—,410399.07
        """
        let mapping = service.defaultMapping(headers: englishMonobankHeaders, preset: .monobank, walletID: walletID)

        let result = try service.importCSV(data: Data(text.utf8), fileName: "mono-en.csv", mapping: mapping)

        #expect(result.insertedTransactions == 3)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions().sorted { $0.occurredAt < $1.occurredAt }
        #expect(transactions.count == 3)

        let openAI = transactions[0]
        #expect(openAI.merchant == "OpenAI")
        #expect(openAI.kind == .expense)
        #expect(openAI.amountMinor == -90_400)

        let income = transactions[1]
        #expect(income.merchant == "From: Ольга Ярмош")
        #expect(income.kind == .income)
        #expect(income.amountMinor == 270_000)

        let bolt = transactions[2]
        #expect(bolt.merchant == "Bolt")
        #expect(bolt.kind == .expense)
        #expect(bolt.amountMinor == -12_800)
    }

    @Test func importAssignsCategoriesFromMCCForExpenses() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH)
        18.06.2026 19:48:21,The Bar,5812,-1113.0
        18.06.2026 18:52:23,Рукавичка,5499,-1659.49
        17.06.2026 12:09:02,ОККО,5541,-243.0
        """
        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: walletID)

        let result = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)

        #expect(result.insertedTransactions == 3)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions()

        let restaurant = try #require(transactions.first { $0.merchant == "The Bar" })
        #expect(restaurant.kind == .expense)
        #expect(restaurant.categoryName == "Restaurants")

        let grocery = try #require(transactions.first { $0.merchant == "Рукавичка" })
        #expect(grocery.kind == .expense)
        #expect(grocery.categoryName == "Groceries")

        let transport = try #require(transactions.first { $0.merchant == "ОККО" })
        #expect(transport.kind == .expense)
        #expect(transport.categoryName == "Transport")
    }

    @Test func importingSameMonobankFileTwiceIsIdempotent() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH)
        16.06.2026 14:15:08,Bolt,4121,-128.0
        """
        let mapping = CSVImportMapping(
            dateColumn: "Дата і час операції",
            amountColumn: "Сума в валюті картки (UAH)",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Деталі операції",
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .income
        )

        let firstResult = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)
        #expect(firstResult.insertedTransactions == 1)

        let secondResult = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)
        #expect(secondResult.insertedTransactions == 0)
        #expect(secondResult.duplicateRows == 1)
    }
}
