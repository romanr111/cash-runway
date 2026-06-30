import Foundation
import GRDB

/// Checks whether a table exists in the current database schema.
func tableExists(_ db: Database, name: String) throws -> Bool {
    let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
        arguments: [name]
    ) ?? 0
    return count > 0
}

/// Checks whether a column exists on a table in the current database schema.
func columnExists(_ db: Database, table: String, column: String) throws -> Bool {
    let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
    return rows.contains { ($0["name"] as String) == column }
}
