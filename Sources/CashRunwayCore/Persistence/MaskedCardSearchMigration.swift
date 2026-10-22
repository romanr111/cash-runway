import GRDB

extension DatabaseManager {
    static func migrateMaskedCardSearchPrivacy(_ db: Database) throws {
        let searchTableExists = try Bool.fetchOne(
            db,
            sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'transaction_search'"
        ) != nil
        guard searchTableExists else { return }

        let rows = try Row.fetchAll(
            db,
            sql: "SELECT rowid, merchant FROM transaction_search"
        )

        for row in rows {
            let rowID: Int64 = row["rowid"]
            let merchant: String = row["merchant"]
            let privacyPreservingMerchant = MaskedCardIdentifier.privacyPreservingSearchText(for: merchant)
            guard privacyPreservingMerchant != merchant else { continue }

            try db.execute(
                sql: "UPDATE transaction_search SET merchant = ? WHERE rowid = ?",
                arguments: [privacyPreservingMerchant, rowID]
            )
        }
    }
}
