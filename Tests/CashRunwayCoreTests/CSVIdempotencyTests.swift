import Foundation
import CryptoKit
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CSVIdempotencyTests {

    @Test func csvImportRetryDoesNotDuplicateTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let row = PreparedImportRow(
            rowNumber: 2,
            draft: TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 12345,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                merchant: "Shop",
                note: "Note",
                source: .importCSV
            ),
            fingerprint: "fp-1",
            sourceName: "Test",
            rawCategoryName: "Groceries",
            rawLabelNames: [],
            currency: "UAH"
        )

        let result1 = try repository.commitCSVImport(
            fileName: "a.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )
        #expect(result1.insertedTransactions == 1)
        #expect(result1.duplicateRows == 0)

        let result2 = try repository.commitCSVImport(
            fileName: "b.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func csvImportRetryDoesNotChangeWalletBalance() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let balanceBefore = try #require(try repository.wallets().first?.currentBalanceMinor)

        let row = PreparedImportRow(
            rowNumber: 2,
            draft: TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 5000,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                merchant: "Shop",
                note: "Note",
                source: .importCSV
            ),
            fingerprint: "fp-balance",
            sourceName: "Test",
            rawCategoryName: "Groceries",
            rawLabelNames: [],
            currency: "UAH"
        )

        let result1 = try repository.commitCSVImport(
            fileName: "a.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )
        #expect(result1.insertedTransactions == 1)

        let balanceAfterFirst = try #require(try repository.wallets().first?.currentBalanceMinor)
        #expect(balanceAfterFirst == balanceBefore - 5000)

        let result2 = try repository.commitCSVImport(
            fileName: "b.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 1)

        let balanceAfterSecond = try #require(try repository.wallets().first?.currentBalanceMinor)
        #expect(balanceAfterSecond == balanceAfterFirst)
    }

    @Test func csvImportReportsDuplicateRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let rows = (0..<3).map { index in
            PreparedImportRow(
                rowNumber: index + 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-dup-\(index)",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            )
        }

        let result1 = try repository.commitCSVImport(
            fileName: "a.csv",
            sourceName: "Test",
            preparedRows: rows,
            rowErrors: []
        )
        #expect(result1.insertedTransactions == 3)
        #expect(result1.duplicateRows == 0)

        let result2 = try repository.commitCSVImport(
            fileName: "b.csv",
            sourceName: "Test",
            preparedRows: rows,
            rowErrors: []
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 3)
    }

    @Test func csvImportSkipsDuplicatesWithinSameFile() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let rows = [
            PreparedImportRow(
                rowNumber: 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-same",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            ),
            PreparedImportRow(
                rowNumber: 3,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-same",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            ),
        ]

        let result = try repository.commitCSVImport(
            fileName: "a.csv",
            sourceName: "Test",
            preparedRows: rows,
            rowErrors: []
        )
        #expect(result.insertedTransactions == 1)
        #expect(result.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func csvImportFailureRollsBackInsertedTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let rows = [
            PreparedImportRow(
                rowNumber: 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-ok",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            ),
            PreparedImportRow(
                rowNumber: 3,
                draft: TransactionDraft(
                    kind: .transfer,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-bad",
                sourceName: "Test",
                rawCategoryName: nil,
                rawLabelNames: [],
                currency: "UAH"
            ),
        ]

        #expect(throws: (any Error).self) {
            try repository.commitCSVImport(
                fileName: "a.csv",
                sourceName: "Test",
                preparedRows: rows,
                rowErrors: []
            )
        }

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 0)
    }

    @Test func csvImportFailureRollsBackCreatedCategoriesAndLabels() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let categoriesBefore = try repository.categories().count
        let labelsBefore = try repository.labels().count

        let rows = [
            PreparedImportRow(
                rowNumber: 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-cat",
                sourceName: "Test",
                rawCategoryName: "UniqueCategoryXYZ",
                rawLabelNames: ["UniqueLabelXYZ"],
                currency: "UAH"
            ),
            PreparedImportRow(
                rowNumber: 3,
                draft: TransactionDraft(
                    kind: .transfer,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-bad2",
                sourceName: "Test",
                rawCategoryName: nil,
                rawLabelNames: [],
                currency: "UAH"
            ),
        ]

        #expect(throws: (any Error).self) {
            try repository.commitCSVImport(
                fileName: "a.csv",
                sourceName: "Test",
                preparedRows: rows,
                rowErrors: []
            )
        }

        let categoriesAfter = try repository.categories().count
        let labelsAfter = try repository.labels().count
        #expect(categoriesAfter == categoriesBefore)
        #expect(labelsAfter == labelsBefore)
    }

    @Test func csvImportFailureDoesNotChangeWalletBalance() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let balanceBefore = try #require(try repository.wallets().first?.currentBalanceMinor)

        let rows = [
            PreparedImportRow(
                rowNumber: 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 5000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-bal",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            ),
            PreparedImportRow(
                rowNumber: 3,
                draft: TransactionDraft(
                    kind: .transfer,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-bad3",
                sourceName: "Test",
                rawCategoryName: nil,
                rawLabelNames: [],
                currency: "UAH"
            ),
        ]

        #expect(throws: (any Error).self) {
            try repository.commitCSVImport(
                fileName: "a.csv",
                sourceName: "Test",
                preparedRows: rows,
                rowErrors: []
            )
        }

        let balanceAfter = try #require(try repository.wallets().first?.currentBalanceMinor)
        #expect(balanceAfter == balanceBefore)
    }

    @Test func csvImportFailureDoesNotChangeAggregates() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        // Seed an existing transaction to create aggregate state
        let category = try #require(try repository.categories(kind: .expense).first)
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 1000,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                categoryID: category.id,
                merchant: "Seed",
                note: ""
            )
        )

        let snapshotBefore = try repository.overviewSnapshot(monthKey: DateKeys.monthKey(for: Date(timeIntervalSince1970: 1_700_000_000)))

        let rows = [
            PreparedImportRow(
                rowNumber: 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 5000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-agg",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            ),
            PreparedImportRow(
                rowNumber: 3,
                draft: TransactionDraft(
                    kind: .transfer,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-bad4",
                sourceName: "Test",
                rawCategoryName: nil,
                rawLabelNames: [],
                currency: "UAH"
            ),
        ]

        #expect(throws: (any Error).self) {
            try repository.commitCSVImport(
                fileName: "a.csv",
                sourceName: "Test",
                preparedRows: rows,
                rowErrors: []
            )
        }

        let snapshotAfter = try repository.overviewSnapshot(monthKey: DateKeys.monthKey(for: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(snapshotAfter.monthExpenseMinor == snapshotBefore.monthExpenseMinor)
    }

    @Test func csvImportFailureDoesNotLeaveFTSRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let rows = [
            PreparedImportRow(
                rowNumber: 2,
                draft: TransactionDraft(
                    kind: .expense,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-fts",
                sourceName: "Test",
                rawCategoryName: "Groceries",
                rawLabelNames: [],
                currency: "UAH"
            ),
            PreparedImportRow(
                rowNumber: 3,
                draft: TransactionDraft(
                    kind: .transfer,
                    walletID: walletID,
                    amountMinor: 1000,
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                    merchant: "Shop",
                    note: "Note",
                    source: .importCSV
                ),
                fingerprint: "fp-bad5",
                sourceName: "Test",
                rawCategoryName: nil,
                rawLabelNames: [],
                currency: "UAH"
            ),
        ]

        #expect(throws: (any Error).self) {
            try repository.commitCSVImport(
                fileName: "a.csv",
                sourceName: "Test",
                preparedRows: rows,
                rowErrors: []
            )
        }

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.ftsRowCount == 0)
    }

    @Test func csvImportInvalidRowsDoNotBlockValidRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let text = "Date,Amount,Note\n2025-01-01,100,Valid\ninvalid-date,200,Bad\n2025-01-03,300,Valid"
        let service = CSVService(repository: repository)
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
        #expect(result.insertedTransactions == 2)
        #expect(result.invalidRows == 1)
        #expect(result.rowErrors.count == 1)
    }

    @Test func csvImportFingerprintDoesNotIncludeFileName() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)

        let row = PreparedImportRow(
            rowNumber: 2,
            draft: TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 1000,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                merchant: "Shop",
                note: "Note",
                source: .importCSV
            ),
            fingerprint: "fp-fname",
            sourceName: "Test",
            rawCategoryName: "Groceries",
            rawLabelNames: [],
            currency: "UAH"
        )

        let result1 = try repository.commitCSVImport(
            fileName: "first.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )
        #expect(result1.insertedTransactions == 1)

        let result2 = try repository.commitCSVImport(
            fileName: "second.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 1)
    }

    @Test func csvImportReportsCorrectInvalidRowCountWhenManyRowsFail() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)

        var lines = ["Date,Amount,Note"]
        for index in 0..<25 {
            lines.append("bad-date-\(index),100,Note")
        }
        let data = Data(lines.joined(separator: "\n").utf8)
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

        let result = try service.importCSV(data: data, fileName: "bad.csv", mapping: mapping)
        #expect(result.insertedTransactions == 0)
        #expect(result.invalidRows == 25)
        #expect(result.rowErrors.count == 20)
        #expect(result.job.invalidRows == 25)
    }

    @Test func commitIgnoresInvalidPreparedCategoryID() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)

        let row = PreparedImportRow(
            rowNumber: 2,
            draft: TransactionDraft(
                kind: .expense,
                walletID: walletID,
                amountMinor: 12345,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                merchant: "Shop",
                note: "Note",
                source: .importCSV
            ),
            fingerprint: "fp-invalid-cat",
            sourceName: "Test",
            rawCategoryName: nil,
            rawLabelNames: [],
            currency: "UAH",
            categoryID: UUID() // does not exist
        )

        let result = try repository.commitCSVImport(
            fileName: "invalid-cat.csv",
            sourceName: "Test",
            preparedRows: [row],
            rowErrors: []
        )

        #expect(result.insertedTransactions == 1)
        let transaction = try #require(try repository.transactions().first { $0.merchant == "Shop" })
        #expect(transaction.categoryID == otherExpenseID)
    }

     @Test func importStatementMatchesHistoricalGenericCSVFingerprint() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z"))
        let transactionID = UUID()
        let merchant = "Cafe Terminal"
        let note = "Legacy row"
        let fingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 2450,
            merchant: merchant,
            note: note,
            categoryName: "Other Expense",
            currency: "UAH"
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 2450,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: merchant,
            note: note,
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [fingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note,Currency
        2025-01-01T00:00:00Z,-24.50,Cafe Terminal,Other Expense,Legacy row,UAH
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense,
            currencyColumn: "Currency"
        )

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "legacy.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 0)
        #expect(result.duplicateRows == 1)
    }

    @Test func legacyGenericMCCResolvedCategoryFingerprintMismatch() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z"))
        let transactionID = UUID()
        let fingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 4200,
            merchant: "Grocery Store",
            note: "",
            categoryName: "Other Expense",
            currency: "UAH"
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 4200,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "Grocery Store",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [fingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant,MCC\n2025-01-01T00:00:00Z,-42.00,Grocery Store,5411"
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
            mccColumn: "MCC"
        )

        withKnownIssue("Known limitation: legacy generic CSV dedup broken when category changes (MCC resolution)") {
            let result = try service.importStatement(
                normalizedData: Data(text.utf8),
                fileName: "legacy-mcc.csv",
                format: .genericBankCSV,
                mapping: mapping
            )

            #expect(result.duplicateRows == 1)
        }
    }

    @Test func legacyGenericBankAliasCategoryFingerprintMismatch() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z"))
        let transactionID = UUID()
        let fingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 10000,
            merchant: "АТБ",
            note: "",
            categoryName: "Other Expense",
            currency: "UAH"
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 10000,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "АТБ",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [fingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant,Category,Note\n2025-01-01T00:00:00Z,-100.00,АТБ,Продукти,Продукти"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )

withKnownIssue("Known limitation: legacy generic CSV dedup broken when category changes (bank alias 'Продукти' → 'Groceries')") {
            let result = try service.importStatement(
                normalizedData: Data(text.utf8),
                fileName: "legacy-alias.csv",
                format: .genericBankCSV,
                mapping: mapping
            )

            #expect(result.duplicateRows == 1)
        }
    }

    @Test func legacyGenericUnknownRawCategoryFingerprintIsStable() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z"))
        let transactionID = UUID()
        let rawCategoryName = "One-Time Bonus"
        let fingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 5000,
            merchant: "Employer",
            note: "",
            categoryName: rawCategoryName,
            currency: "UAH"
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 5000,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "Employer",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [fingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant,Category\n2025-01-01T00:00:00Z,-50.00,Employer,One-Time Bonus"
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: nil,
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: walletID,
            defaultKind: .expense
        )

        withKnownIssue("Known limitation: legacy generic CSV dedup broken for unknown raw category that creates new category") {
            let result = try service.importStatement(
                normalizedData: Data(text.utf8),
                fileName: "legacy-unknown-cat.csv",
                format: .genericBankCSV,
                mapping: mapping
            )

            #expect(result.duplicateRows == 1)
        }
    }

    private func historicalImportFingerprint(
        sourceName: String,
        walletID: UUID,
        kind: TransactionDraft.Kind,
        occurredAt: Date,
        amountMinor: Int64,
        merchant: String?,
        note: String?,
        categoryName: String?,
        currency: String?
    ) -> String {
        let components = [
            sourceName,
            walletID.uuidString,
            kind.rawValue,
            ISO8601DateFormatter().string(from: occurredAt),
            String(amountMinor),
            (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
        ]
        let input = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { byte in String(format: "%02x", byte) }.joined()
    }
}
