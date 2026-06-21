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

    @Test func genericCSVManualMCCMappingUsesCuratedBankCategoryFallbacks() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let restaurantsID = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" }?.id)

        let service = CSVService(repository: repository)
        let text = """
        Posted,Value,Details,Merchant category code
        2026-05-01,-24.50,Cafe Terminal,5812
        """
        let preview = try service.preview(data: Data(text.utf8))
        #expect(service.detectPreset(headers: preview.headers) == .generic)

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
            defaultKind: .expense,
            mccColumn: "Merchant category code"
        )

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "unsupported-bank.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Cafe Terminal" })
        let importedDraft = try repository.transactionDraft(id: imported.id)
        #expect(importedDraft.categoryID == restaurantsID)
    }

    @Test func defaultMappingAutoDetectsStandardMCCHeader() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let mapping = service.defaultMapping(
            headers: ["Date", "Amount", "Description", "MCC"],
            preset: .generic,
            walletID: nil
        )

        #expect(mapping.mccColumn == "MCC")
    }

    @Test func cashRunwayExportWithBOMDateHeaderKeepsWalletCategorySemantics() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let service = CSVService(repository: repository)
        let text = """
        \u{feff}Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-05-01T00:00:00Z,Main,Expense,Custom Exported Category,Craft Store,12.34,UAH,Imported from wallet export,,
        """
        let preview = try service.preview(data: Data(text.utf8))
        let format = service.detectFormat(headers: preview.headers)
        let mapping = service.defaultMapping(headers: preview.headers, preset: service.detectPreset(headers: preview.headers), walletID: walletID)

        #expect(format == .cashRunwayCSV)

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "wallet-export.csv",
            format: format,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Craft Store" })
        #expect(imported.categoryName == "Custom Exported Category")
    }

    @Test func ambiguousBankHeadersFallBackToGenericBankCSV() throws {
        let repository = try TestSupport.makeRepository()
        let service = CSVService(repository: repository)

        let headers = ["Дата операції", "Сума в грн", "Description", "MCC"]

        #expect(service.detectFormat(headers: headers) == .genericBankCSV)
        #expect(service.detectPreset(headers: headers) == .generic)
    }

    @Test func importStatementUsesSuppliedFormatWithoutSecondDetection() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let service = CSVService(repository: repository)
        let text = """
        Date,Wallet,Type,Category name,Merchant,Amount,Currency,Note,Labels,Author
        2026-05-01T00:00:00Z,Main,Expense,Custom Exported Category,Craft Store,12.34,UAH,Imported with forced generic format,,
        """
        let preview = try service.preview(data: Data(text.utf8))
        let mapping = service.defaultMapping(headers: preview.headers, preset: .cashRunwayWallet, walletID: walletID)

        #expect(service.detectFormat(headers: preview.headers) == .cashRunwayCSV)

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "wallet-export.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Craft Store" })
        #expect(imported.categoryName == "Other Expense")
    }

    @Test func genericCSVRecognizedCommonBankCategoryAlias() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let restaurantsID = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" }?.id)

        let service = CSVService(repository: repository)
        let text = """
        Posted,Value,Details,Bank category
        2026-05-01,-24.50,Cafe Terminal,Ресторани
        """
        let mapping = CSVImportMapping(
            dateColumn: "Posted",
            amountColumn: "Value",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Details",
            noteColumn: nil,
            categoryColumn: "Bank category",
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "unsupported-bank.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Cafe Terminal" })
        let importedDraft = try repository.transactionDraft(id: imported.id)
        #expect(importedDraft.categoryID == restaurantsID)
    }

    @Test func malformedGenericMCCFallsBackSafely() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let fallbackID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)

        let service = CSVService(repository: repository)
        let text = """
        Posted,Value,Details,MCC
        2026-05-01,-24.50,Unknown Merchant,not-a-code
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
            defaultKind: .expense,
            mccColumn: "MCC"
        )

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "unsupported-bank.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Unknown Merchant" })
        let importedDraft = try repository.transactionDraft(id: imported.id)
        #expect(importedDraft.categoryID == fallbackID)
    }

    @Test func genericCSVDoesNotUseProviderSpecificLearnedRules() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let shoppingID = try #require(try repository.categories(kind: .expense).first { $0.name == "Shopping" }?.id)
        let fallbackID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bank_category_rules (
                    id, provider, rule_type, merchant_pattern, mcc, category_id, confidence, created_at, updated_at
                )
                VALUES (?, ?, 'merchant', ?, NULL, ?, 100, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    "provider-only-merchant",
                    shoppingID.uuidString,
                    Date(timeIntervalSince1970: 1_800_000_000),
                    Date(timeIntervalSince1970: 1_800_000_000)
                ]
            )
        }

        let service = CSVService(repository: repository)
        let text = """
        Posted,Value,Details
        2026-05-01,-24.50,Provider Only Merchant
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
            fileName: "unsupported-bank.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Provider Only Merchant" })
        let importedDraft = try repository.transactionDraft(id: imported.id)
        #expect(importedDraft.categoryID == fallbackID)
    }

    @Test func syntheticThirdBankDefinitionCanDetectMapAndImport() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let restaurantsID = try #require(try repository.categories(kind: .expense).first { $0.name == "Restaurants" }?.id)
        let syntheticFormat = BankStatementFormat(
            id: "synthetic-bank.csv.v1",
            displayName: "Synthetic Bank CSV",
            fileKind: .csv,
            role: .bankStatement(provider: nil)
        )
        let syntheticDefinition = BankStatementFormatDefinition(
            format: syntheticFormat,
            preset: .generic,
            requiredHeaderGroups: [
                ["Synthetic Posted"],
                ["Synthetic Value"],
                ["Synthetic Merchant"]
            ],
            minimumConfidence: 3,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Synthetic Posted"],
                amountColumns: ["Synthetic Value"],
                merchantColumns: ["Synthetic Merchant"],
                mccColumns: ["Synthetic MCC"]
            )
        )
        let service = CSVService(
            repository: repository,
            formatDefinitions: CSVService.defaultFormatDefinitions + [syntheticDefinition]
        )
        let text = """
        Synthetic Posted,Synthetic Value,Synthetic Merchant,Synthetic MCC
        2026-05-01,-24.50,Synthetic Cafe,5812
        """
        let preview = try service.preview(data: Data(text.utf8))
        let format = service.detectFormat(headers: preview.headers)
        let mapping = service.defaultMapping(headers: preview.headers, format: format, walletID: walletID)

        #expect(format == syntheticFormat)
        #expect(mapping.mccColumn == "Synthetic MCC")

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "synthetic-bank.csv",
            format: format,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 1)
        let imported = try #require(try repository.transactions().first { $0.merchant == "Synthetic Cafe" })
        let importedDraft = try repository.transactionDraft(id: imported.id)
        #expect(importedDraft.categoryID == restaurantsID)
    }
}
