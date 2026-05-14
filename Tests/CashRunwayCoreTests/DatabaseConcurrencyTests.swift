import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseConcurrencyTests {
    @Test func simultaneousWritesDoNotCorruptAggregates() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let kind: TransactionDraft.Kind = i.isMultiple(of: 2) ? .expense : .income
                    let category = kind == .expense ? expenseCategory : incomeCategory
                    try repository.saveTransaction(
                        TransactionDraft(
                            kind: kind,
                            walletID: wallets[i % wallets.count].id,
                            amountMinor: Int64(1_000 * (i + 1)),
                            occurredAt: .now,
                            categoryID: category.id,
                            merchant: "Concurrent \(i)",
                            note: ""
                        )
                    )
                }
            }
            try await group.waitForAll()
        }

        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func readDuringWriteDoesNotSeePartialState() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let category = try #require(try repository.categories(kind: .expense).first)

        let writeTask = Task.detached {
            for i in 0..<50 {
                try repository.saveTransaction(
                    TransactionDraft(
                        kind: .expense,
                        walletID: wallets[0].id,
                        amountMinor: Int64(100 * (i + 1)),
                        occurredAt: .now,
                        categoryID: category.id,
                        merchant: "Batch \(i)",
                        note: ""
                    )
                )
            }
        }

        let readTask = Task.detached {
            for _ in 0..<50 {
                let _ = try repository.wallets()
                let _ = try repository.transactions()
            }
        }

        try await writeTask.value
        try await readTask.value

        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)
    }

    @Test func concurrentCSVImportsDoNotDeadlock() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try #require(try repository.wallets().first)
        let service = CSVService(repository: repository)

        let csvA = """
        Date,Amount,Merchant,Note
        2026-01-02,10.00,Shop A,First
        2026-01-03,20.00,Shop B,Second
        2026-01-04,30.00,Shop C,Third
        """

        let csvB = """
        Date,Amount,Merchant,Note
        2026-02-02,15.00,Shop D,Fourth
        2026-02-03,25.00,Shop E,Fifth
        2026-02-04,35.00,Shop F,Sixth
        """

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try service.importCSV(
                    data: Data(csvA.utf8),
                    fileName: "a.csv",
                    mapping: CSVImportMapping(
                        dateColumn: "Date",
                        amountColumn: "Amount",
                        debitColumn: nil,
                        creditColumn: nil,
                        merchantColumn: "Merchant",
                        noteColumn: "Note",
                        categoryColumn: nil,
                        labelsColumn: nil,
                        walletID: wallet.id,
                        defaultKind: .expense
                    )
                )
            }
            group.addTask {
                _ = try service.importCSV(
                    data: Data(csvB.utf8),
                    fileName: "b.csv",
                    mapping: CSVImportMapping(
                        dateColumn: "Date",
                        amountColumn: "Amount",
                        debitColumn: nil,
                        creditColumn: nil,
                        merchantColumn: "Merchant",
                        noteColumn: "Note",
                        categoryColumn: nil,
                        labelsColumn: nil,
                        walletID: wallet.id,
                        defaultKind: .expense
                    )
                )
            }
            try await group.waitForAll()
        }

        let imported = try repository.transactions()
        #expect(imported.count == 6)
        try TestSupport.assertWalletTruth(repository)
        try TestSupport.assertCategoryTruth(repository)
    }
}
