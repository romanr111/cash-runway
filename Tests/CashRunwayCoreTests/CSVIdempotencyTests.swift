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

    @Test func legacyGenericMCCResolvedCategoryDedupWorks() throws {
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
            categoryName: nil,
            currency: nil
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

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "legacy-mcc.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.duplicateRows == 1)
        #expect(result.insertedTransactions == 0)
    }

    @Test func legacyGenericBankAliasFingerprintWithMappedCategory() throws {
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
            categoryName: "Продукти",
            currency: nil
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
        let text = "Date,Amount,Merchant,Category,Note\n2025-01-01T00:00:00Z,-100.00,АТБ,Продукти,"
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

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "legacy-alias.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.duplicateRows == 1)
        #expect(result.insertedTransactions == 0)
    }

    @Test func legacyGenericUnknownRawCategoryDedupWorks() throws {
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
            amountMinor: 5000,
            merchant: "Employer",
            note: "",
            categoryName: "Other Expense",
            currency: nil
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

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "legacy-unknown-cat.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.duplicateRows == 1)
        #expect(result.insertedTransactions == 0)
    }

    @Test func importStatementMatchesLegacyGenericCSVEmptyCategoryNoCurrency() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z"))
        let transactionID = UUID()
        let seededFingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 1500,
            merchant: "Coffee Shop",
            note: "",
            categoryName: nil,
            currency: nil
        )
        let currentFingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 1500,
            merchant: "Coffee Shop",
            note: "",
            categoryName: "Other Expense",
            currency: nil
        )
        #expect(seededFingerprint == currentFingerprint,
            "Category-independent fingerprint matches regardless of resolved category")
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 1500,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "Coffee Shop",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [seededFingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant\n2025-01-01T00:00:00Z,-15.00,Coffee Shop"
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
            defaultKind: .expense
        )

        let result = try service.importStatement(
                normalizedData: Data(text.utf8),
                fileName: "legacy-basic.csv",
                format: .genericBankCSV,
                mapping: mapping
            )

            #expect(result.duplicateRows == 1)
            #expect(result.insertedTransactions == 0)
    }

    @Test func importStatementMatchesLegacyGenericCSVWithCurrency() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-01-15T00:00:00Z"))
        let transactionID = UUID()
        let seededFingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 3000,
            merchant: "Supermarket",
            note: "",
            categoryName: nil,
            currency: "UAH"
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 3000,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "Supermarket",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [seededFingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant,Currency\n2025-01-15T00:00:00Z,-30.00,Supermarket,UAH"
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
            currencyColumn: "Currency"
        )

        let result = try service.importStatement(
                normalizedData: Data(text.utf8),
                fileName: "legacy-currency.csv",
                format: .genericBankCSV,
                mapping: mapping
            )

            #expect(result.duplicateRows == 1)
            #expect(result.insertedTransactions == 0)
    }

    @Test func legacyGenericCSVEmptyCategoryMatchesMappedCategoryRow() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-02-01T00:00:00Z"))
        let transactionID = UUID()
        let seededFingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 5000,
            merchant: "Bistro",
            note: "",
            categoryName: nil,
            currency: nil
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 5000,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "Bistro",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [seededFingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant,Category\n2025-02-01T00:00:00Z,-50.00,Bistro,Restaurants"
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

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "mapped-category.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.insertedTransactions == 0)
        #expect(result.duplicateRows == 1)
    }

    @Test func legacyGenericCSVEmptyCellInMappedCategoryDedupWorks() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-03-01T00:00:00Z"))
        let transactionID = UUID()
        let seededFingerprint = historicalImportFingerprint(
            sourceName: "Generic CSV",
            walletID: walletID,
            kind: .expense,
            occurredAt: occurredAt,
            amountMinor: 1500,
            merchant: "Coffee Shop",
            note: "",
            categoryName: nil,
            currency: nil
        )
        try repository.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 1500,
            occurredAt: occurredAt,
            categoryID: otherExpenseID,
            merchant: "Coffee Shop",
            source: .importCSV
        ))
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [seededFingerprint, transactionID.uuidString]
            )
        }
        let service = CSVService(repository: repository)
        let text = "Date,Amount,Merchant,Category\n2025-03-01T00:00:00Z,-15.00,Coffee Shop,"
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

        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "empty-cell.csv",
            format: .genericBankCSV,
            mapping: mapping
        )

        #expect(result.duplicateRows == 1)
        #expect(result.insertedTransactions == 0)
    }

    // MARK: - Dedup hardening (category-independent identity + semantic fallback)

    @Test func importingSameCSVTwiceIsIdempotent() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-01-01T00:00:00Z,-50.00,Shop,Groceries,Weekly groceries
        2025-01-02T00:00:00Z,-30.00,Cafe,Restaurants,Coffee
        2025-01-10T00:00:00Z,1000.00,Employer,Salary,January
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )

        let result1 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "first.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 3)
        #expect(result1.duplicateRows == 0)

        let balanceAfterFirst = try #require(try repository.wallets().first?.currentBalanceMinor)
        let snapshotAfterFirst = try repository.overviewSnapshot(
            monthKey: DateKeys.monthKey(for: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!)
        )

        let result2 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "second.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 3)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 3)

        let balanceAfterSecond = try #require(try repository.wallets().first?.currentBalanceMinor)
        #expect(balanceAfterSecond == balanceAfterFirst)

        let snapshotAfterSecond = try repository.overviewSnapshot(
            monthKey: DateKeys.monthKey(for: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!)
        )
        #expect(snapshotAfterSecond.monthExpenseMinor == snapshotAfterFirst.monthExpenseMinor)
        #expect(snapshotAfterSecond.monthIncomeMinor == snapshotAfterFirst.monthIncomeMinor)
    }

    @Test func reimportAfterCategoryChangedIsIdempotent() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )

        let firstText = """
        Date,Amount,Merchant,Category,Note
        2025-02-01T00:00:00Z,-50.00,Shop,Groceries,Weekly
        """
        let result1 = try service.importStatement(
            normalizedData: Data(firstText.utf8),
            fileName: "first.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 1)

        let secondText = """
        Date,Amount,Merchant,Category,Note
        2025-02-01T00:00:00Z,-50.00,Shop,Restaurants,Weekly
        """
        let result2 = try service.importStatement(
            normalizedData: Data(secondText.utf8),
            fileName: "second.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func reimportCashRunwayExportIsIdempotent() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: wallet.id,
                amountMinor: 12_000,
                occurredAt: now,
                categoryID: expenseCategory.id,
                merchant: "Grocery",
                source: .manual
            )
        )
        try repository.saveTransaction(
            TransactionDraft(
                kind: .income,
                walletID: wallet.id,
                amountMinor: 50_000,
                occurredAt: now,
                categoryID: incomeCategory.id,
                merchant: "Salary",
                source: .manual
            )
        )

        let exportService = CSVService(repository: repository)
        let exported = try exportService.exportCSV()

        let importService = CSVService(repository: repository)
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
        let result = try importService.importCSV(data: Data(exported.utf8), fileName: "export.csv", mapping: mapping)

        #expect(result.insertedTransactions == 0)
        #expect(result.duplicateRows == 2)

        let allTransactions = try repository.transactions()
        #expect(allTransactions.count == 2)
    }

    @Test func oldTransactionsWithNullFingerprintProtectedBySemanticFallback() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let otherExpenseID = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" }?.id)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-03-01T00:00:00Z"))
        let transactionID = UUID()
        try repository.saveTransaction(
            TransactionDraft(
                id: transactionID,
                kind: .expense,
                walletID: wallet.id,
                amountMinor: 4200,
                occurredAt: occurredAt,
                categoryID: otherExpenseID,
                merchant: "Old Shop",
                source: .importCSV
            )
        )
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET import_fingerprint = NULL WHERE id = ?",
                arguments: [transactionID.uuidString]
            )
        }

        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-03-01T00:00:00Z,-42.00,Old Shop,Groceries,
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "legacy-null-fp.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result.insertedTransactions == 0)
        #expect(result.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func duplicateRowsInSameCSVDoNotMultiplyWhenOnlyCategoryDiffers() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-04-01T00:00:00Z,-50.00,Shop,Groceries,Same note
        2025-04-01T00:00:00Z,-50.00,Shop,Restaurants,Same note
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "intra-dup.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result.insertedTransactions == 1)
        #expect(result.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func legitimateRepeatedPaymentsAreNotCollapsed() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-05-01T08:00:00Z,-50.00,Gym,Fitness,May dues
        2025-06-01T08:00:00Z,-50.00,Gym,Fitness,June dues
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "repeated.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result.insertedTransactions == 2)
        #expect(result.duplicateRows == 0)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 2)
    }

    @Test func sameDaySameMerchantSameAmountDifferentTimestampsAreNotCollapsed() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-05-01T08:00:00Z,-50.00,Gym,Fitness,Membership
        2025-05-01T18:00:00Z,-50.00,Gym,Fitness,Membership
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "same-day-repeat.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result.insertedTransactions == 2)
        #expect(result.duplicateRows == 0)
        #expect(try repository.transactions().count == 2)
    }

    @Test func existingDayKeyDoesNotSuppressLaterDistinctTimestamp() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )

        let firstText = """
        Date,Amount,Merchant,Category,Note
        2025-05-01T08:00:00Z,-50.00,Gym,Fitness,Membership
        """
        let result1 = try service.importStatement(
            normalizedData: Data(firstText.utf8),
            fileName: "first.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 1)

        let secondText = """
        Date,Amount,Merchant,Category,Note
        2025-05-01T08:00:00Z,-50.00,Gym,Fitness,Membership
        2025-05-01T18:00:00Z,-50.00,Gym,Fitness,Membership
        """
        let result2 = try service.importStatement(
            normalizedData: Data(secondText.utf8),
            fileName: "second.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 1)
        #expect(result2.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 2)
    }

    @Test func reimportAfterSoftDeleteReInserts() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-07-01T08:00:00Z,-50.00,Gym,Fitness,Dues
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let result1 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "first.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 1)

        let imported = try #require(try repository.transactions().first)
        try repository.deleteTransaction(id: imported.id)

        let result2 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "second.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 1)
        #expect(result2.duplicateRows == 0)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func crossSourceReimportDoesNotCollapseFingerprintedRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-08-01T08:00:00Z,-50.00,Gym,Fitness,Dues
        """
        let result1 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "generic.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 1)

        let result2 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "cashrunway.csv",
            format: .cashRunwayCSV,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 1)
        #expect(result2.duplicateRows == 0)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 2)
    }

    @Test func reimportMonobankCSVIsIdempotent() throws {
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

        let result1 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "first.csv",
            format: .monobankCSVv1,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 1)

        let result2 = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "second.csv",
            format: .monobankCSVv1,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
    }

    @Test func reimportPrivatBankCSVIsIdempotent() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = CSVService(repository: repository)
        let headers = [
            "Дата", "Категорія", "Картка", "Опис операції",
            "Сума в валюті картки", "Валюта картки", "Сума в валюті транзакції",
            "Валюта транзакції", "Залишок на кінець періоду", "Валюта залишку"
        ]
        let mapping = service.defaultMapping(
            headers: headers,
            format: .privatBankCSVv1,
            walletID: walletID
        )
        let csvText = """
        Дата,Категорія,Картка,Опис операції,Сума в валюті картки,Валюта картки,Сума транзакції,Валюта транзакції,Залишок на кінець періоду,Валюта залишку
        16.06.2026,Житло,1234,Temu,-552.70,UAH,-552.70,UAH,1000.00,UAH
        """

        let result1 = try service.importStatement(
            normalizedData: Data(csvText.utf8),
            fileName: "first.csv",
            format: .privatBankCSVv1,
            mapping: mapping
        )
        #expect(result1.insertedTransactions == 1)

        let result2 = try service.importStatement(
            normalizedData: Data(csvText.utf8),
            fileName: "second.csv",
            format: .privatBankCSVv1,
            mapping: mapping
        )
        #expect(result2.insertedTransactions == 0)
        #expect(result2.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repository)
        #expect(truth.sourceImportCount == 1)
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
            (currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
        ]
        let input = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { byte in String(format: "%02x", byte) }.joined()
    }
}
