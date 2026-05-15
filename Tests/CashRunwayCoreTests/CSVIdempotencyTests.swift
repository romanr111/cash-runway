import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CSVIdempotencyTests {

    @Test func csvImportRetryDoesNotDuplicateTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
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
            categoryColumn: nil,
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
}
