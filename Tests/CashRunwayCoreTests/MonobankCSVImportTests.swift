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
        16.06.2026 14:15:08,Bolt,4121,-42.0,-42.0,UAH,—,—,1.0,10042.00
        15.06.2026 13:11:03,Від: Тестовий Відправник,4829,250.0,250.0,UAH,—,—,—,10250.00
        12.06.2026 11:57:44,OpenAI,5734,-99.0,-2.0,USD,49.5,—,—,9950.00
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
        #expect(openAI.amountMinor == -9_900)

        let income = transactions[1]
        #expect(income.merchant == "Від: Тестовий Відправник")
        #expect(income.kind == .income)
        #expect(income.amountMinor == 25_000)

        let bolt = transactions[2]
        #expect(bolt.merchant == "Bolt")
        #expect(bolt.kind == .expense)
        #expect(bolt.amountMinor == -4_200)
    }

    @Test func importEnglishMonobankSampleRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Date and time,Description,MCC,"Card currency amount, (UAH)",Operation amount,Operation currency,Exchange rate,"Commission, (UAH)","Cashback amount, (UAH)",Balance
        16.06.2026 14:15:08,Bolt,4121,-42.0,-42.0,UAH,—,—,1.0,10042.00
        15.06.2026 13:11:03,From: Test Sender,4829,250.0,250.0,UAH,—,—,—,10250.00
        12.06.2026 11:57:44,OpenAI,5734,-99.0,-2.0,USD,49.5,—,—,9950.00
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
        #expect(openAI.amountMinor == -9_900)

        let income = transactions[1]
        #expect(income.merchant == "From: Test Sender")
        #expect(income.kind == .income)
        #expect(income.amountMinor == 25_000)

        let bolt = transactions[2]
        #expect(bolt.merchant == "Bolt")
        #expect(bolt.kind == .expense)
        #expect(bolt.amountMinor == -4_200)
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

    @Test func previewAssignsCategoriesFromMonobankMCC() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH)
        18.06.2026 18:52:23,Рукавичка,5499,-1659.49
        """
        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: walletID)

        let rows = try service.previewPreparedRows(data: Data(text.utf8), mapping: mapping, limit: 3)

        let row = try #require(rows.first)
        #expect(row.draft.kind == .expense)
        #expect(row.draft.merchant == "Рукавичка")
        #expect(row.rawCategoryName == "Groceries")
        #expect(row.categoryID != nil)
        #expect(try repository.transactions().isEmpty)
    }

    @Test func bankStatementCategoryMappingDisplaysAutoSourceWhenNoCategoryColumn() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)
        let monobankMapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: nil)
        let genericMapping = service.defaultMapping(headers: ["Date", "Amount"], preset: .generic, walletID: nil)
        let walletMapping = service.defaultMapping(
            headers: ["Date", "Wallet", "Type", "Category name", "Amount", "Currency", "Note", "Labels", "Author"],
            preset: .cashRunwayWallet,
            walletID: nil
        )

        #expect(monobankMapping.categoryMappingDisplayMode(for: .monobank) == .autoBankRules)
        #expect(genericMapping.categoryMappingDisplayMode(for: .generic) == .sourceColumn(nil))
        #expect(walletMapping.categoryMappingDisplayMode(for: .cashRunwayWallet) == .sourceColumn("Category name"))
    }

    @Test func importParsesMCCVariants() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH)
        18.06.2026 19:48:21,Spreadsheet MCC,5812.0,-1113.0
        18.06.2026 18:52:23,Padded MCC, 5499 ,-1659.49
        17.06.2026 12:09:02,No MCC,,-243.0
        """
        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: walletID)

        let result = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)

        #expect(result.insertedTransactions == 3)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions()

        let spreadsheet = try #require(transactions.first { $0.merchant == "Spreadsheet MCC" })
        #expect(spreadsheet.categoryName == "Restaurants")

        let padded = try #require(transactions.first { $0.merchant == "Padded MCC" })
        #expect(padded.categoryName == "Groceries")

        let noMCC = try #require(transactions.first { $0.merchant == "No MCC" })
        #expect(noMCC.categoryName == "Other Expense")
    }

    @Test func importAssignsCategoriesForCommonMonobankExportMCCs() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let headers = [
            "Дата i час операції",
            "Деталі операції",
            "MCC",
            "Сума в валюті картки (UAH)",
            "Валюта",
            "Курс",
            "Сума комісій (UAH)",
            "Сума кешбеку (UAH)",
            "Сума (UAH)",
            "Залишок після операції"
        ]
        let text = """
        Дата i час операції,Деталі операції,MCC,Сума в валюті картки (UAH),Валюта,Курс,Сума комісій (UAH),Сума кешбеку (UAH),Сума (UAH),Залишок після операції
        19.06.2026 10:00:00,Mobile operator,4814,-120.0,UAH,1,0,0,-120.0,10000.00
        19.06.2026 10:05:00,Sports club,7997,-600.0,UAH,1,0,0,-600.0,9400.00
        19.06.2026 10:07:00,Discount store,5310,-100.0,UAH,1,0,0,-100.0,9300.00
        19.06.2026 10:10:00,Marketplace,5399,-750.0,UAH,1,0,0,-750.0,8650.00
        19.06.2026 10:15:00,Software store,5734,-300.0,UAH,1,0,0,-300.0,8350.00
        19.06.2026 10:20:00,Book store,5942,-200.0,UAH,1,0,0,-200.0,8150.00
        19.06.2026 10:25:00,Home materials,5211,-500.0,UAH,1,0,0,-500.0,7650.00
        """
        let mapping = service.defaultMapping(
            headers: headers,
            preset: .monobank,
            walletID: walletID
        )

        let result = try service.importCSV(data: Data(text.utf8), fileName: "mono.csv", mapping: mapping)

        #expect(result.insertedTransactions == 7)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions()
        #expect(try #require(transactions.first { $0.merchant == "Mobile operator" }).categoryName == "Utilities")
        #expect(try #require(transactions.first { $0.merchant == "Sports club" }).categoryName == "Entertainment")
        #expect(try #require(transactions.first { $0.merchant == "Discount store" }).categoryName == "Shopping")
        #expect(try #require(transactions.first { $0.merchant == "Marketplace" }).categoryName == "Shopping")
        #expect(try #require(transactions.first { $0.merchant == "Software store" }).categoryName == "Shopping")
        #expect(try #require(transactions.first { $0.merchant == "Book store" }).categoryName == "Education")
        #expect(try #require(transactions.first { $0.merchant == "Home materials" }).categoryName == "Housing")
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

    @Test func importMonobankExpensesOnlySkipsIncomeRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH),Сума в валюті операції,Валюта,Курс,Сума комісій (UAH),Сума кешбеку (UAH),Залишок після операції
        16.06.2026 14:15:08,Рукавичка,5411,-420.0,-420.0,UAH,—,—,—,10000.00
        16.06.2026 14:20:08,Від: Тестовий Відправник,4829,1000.0,1000.0,UAH,—,—,—,11000.00
        """
        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: walletID)

        let result = try service.importCSV(
            data: Data(text.utf8),
            fileName: "mono.csv",
            mapping: mapping,
            rowFilter: .expensesOnly
        )

        #expect(result.insertedTransactions == 1)
        #expect(result.invalidRows == 0)
        let transactions = try repository.transactions()
        #expect(transactions.count == 1)
        #expect(transactions.first?.kind == .expense)
        #expect(transactions.first?.merchant == "Рукавичка")
        #expect(transactions.first?.categoryName == "Groceries")
    }

    @Test func previewMonobankExpensesOnlySkipsIncomeRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let text = """
        Дата і час операції,Деталі операції,MCC,Сума в валюті картки (UAH),Сума в валюті операції,Валюта,Курс,Сума комісій (UAH),Сума кешбеку (UAH),Залишок після операції
        16.06.2026 14:15:08,Від: Тестовий Відправник,4829,1000.0,1000.0,UAH,—,—,—,11000.00
        16.06.2026 14:20:08,Рукавичка,5411,-420.0,-420.0,UAH,—,—,—,10000.00
        """
        let mapping = service.defaultMapping(headers: monobankHeaders, preset: .monobank, walletID: walletID)

        let rows = try service.previewPreparedRows(
            data: Data(text.utf8),
            mapping: mapping,
            rowFilter: .expensesOnly,
            limit: 3
        )

        #expect(rows.count == 1)
        #expect(rows.first?.draft.kind == .expense)
        #expect(rows.first?.draft.merchant == "Рукавичка")
        #expect(rows.first?.rawCategoryName == "Groceries")
    }
}
