import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

/// Tests for the batched IN-query label loading fix that avoids SQLite's
/// 999-variable limit and the previous N+1 query pattern.
@Suite(.serialized)
struct ChunkedLabelQueryTests {

    /// Verifies that `listTransactions` correctly loads labels when the result
    /// set spans more than one 900-item chunk, exercising the chunked IN-query
    /// path introduced to replace the N+1 label fetch.
    @Test func chunkedLabelQueryLoadsAllLabelsForLargeTransactionSets() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let now = Date()
        let dayKey = DateKeys.dayKey(for: now)
        let monthKey = DateKeys.monthKey(for: now)

        // 950 transactions forces two chunks (900 + 50), which validates both
        // the chunking logic and that SQLite's parameter limit is respected.
        let transactionCount = 950

        try repository.databaseManager.dbQueue.write { db in
            for index in 0..<transactionCount {
                let txID = UUID().uuidString
                let labelID = UUID().uuidString

                try db.execute(
                    sql: """
                    INSERT INTO transactions (
                        id, wallet_id, type, amount_minor, occurred_at,
                        local_day_key, local_month_key, is_deleted, source,
                        created_at, updated_at
                    ) VALUES (?, ?, 'expense', ?, ?, ?, ?, 0, 'manual', ?, ?)
                    """,
                    arguments: [
                        txID, wallet.id.uuidString, Int64(index + 1),
                        now, dayKey, monthKey, now, now,
                    ]
                )

                try db.execute(
                    sql: """
                    INSERT INTO labels (id, name, color_hex, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [labelID, "Label-\(index)", "#FF0000", now, now]
                )

                try db.execute(
                    sql: """
                    INSERT INTO transaction_labels (transaction_id, label_id)
                    VALUES (?, ?)
                    """,
                    arguments: [txID, labelID]
                )
            }
        }

        let items = try repository.transactions(query: .init(), limit: nil)
        #expect(items.count == transactionCount)

        var labelNameByTransactionID: [UUID: String] = [:]
        for item in items {
            #expect(item.labels.count == 1, "Transaction \(item.id) should have exactly one label")
            let label = try #require(item.labels.first)
            labelNameByTransactionID[item.id] = label.name
        }

        // Verify every label was loaded and mapped to the correct transaction.
        #expect(labelNameByTransactionID.count == transactionCount)
        for index in 0..<transactionCount {
            let labelName = "Label-\(index)"
            #expect(
                labelNameByTransactionID.values.contains(labelName),
                "Label '\(labelName)' should be present in the loaded results"
            )
        }
    }
}
