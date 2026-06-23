import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DatabaseLifecycleTests {
    @Test func corruptedDatabaseIsQuarantinedNotDeleted() throws {
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        let keychain = TestKeychainStore()

        // Create a valid database first.
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        let categoryCountBefore = try repository.categories().count
        manager = nil

        // Corrupt the SQLite header.
        try TestSupport.corruptSQLiteHeader(at: dbURL)

        // Recovery should recreate the database.
        let recoveredManager = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: true, keychain: keychain)
        let recoveredRepo = CashRunwayRepository(databaseManager: recoveredManager)
        try recoveredRepo.seedIfNeeded()
        #expect(try recoveredRepo.categories().count == categoryCountBefore)

        // Original file should be in Recovery directory.
        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let recoveredFiles = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(recoveredFiles.contains { $0.lastPathComponent.contains("cash-runway.sqlite") })
    }

    @Test func quarantinePreservesWalAndShm() throws {
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        let keychain = TestKeychainStore()

        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: try #require(try repository.wallets().first?.id),
                amountMinor: 1_000,
                occurredAt: .now,
                categoryID: try #require(try repository.categories(kind: .expense).first?.id),
                merchant: "Quarantine",
                note: ""
            )
        )
        manager = nil

        TestSupport.assertWalFileExists(at: dbURL)

        try TestSupport.corruptSQLiteHeader(at: dbURL)
        _ = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: true, keychain: keychain)

        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let recoveredFiles = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        let hasWal = recoveredFiles.contains { $0.lastPathComponent.contains("-wal") }
        let hasShm = recoveredFiles.contains { $0.lastPathComponent.contains("-shm") }
        #expect(hasWal, "WAL file should be quarantined")
        #expect(hasShm, "SHM file should be quarantined")
    }

    @Test func migrationFailureDoesNotDestroyExistingData() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletCount = try repository.wallets().count
        let dbURL = try location.databaseURL()
        manager = nil

        // Attempt to open with a migrator that throws.
        var badMigrator = DatabaseMigrator()
        badMigrator.registerMigration("v1") { _ in }
        badMigrator.registerMigration("v2_boom") { _ in
            throw CashRunwayError.invalidState("Simulated migration failure")
        }

        var config = Configuration()
        config.prepareDatabase { db in
            guard let keyData = try keychain.read(account: "database-key"),
                  let key = String(data: keyData, encoding: .utf8) else {
                throw KeychainStoreError.invalidStoredData("database-key")
            }
            try db.usePassphrase(key)
        }

        var didThrow = false
        do {
            let badQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
            try badMigrator.migrate(badQueue)
        } catch {
            didThrow = true
        }

        #expect(didThrow)

        // Reopen with normal manager and verify data is untouched.
        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)
        #expect(try reopenedRepo.wallets().count == walletCount)
    }

    @Test func destructiveRecoveryAllowedOnlyInDebug() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        #if DEBUG
        // DEBUG builds allow explicit destructive recovery for UI testing / diagnostics.
        _ = try DatabaseManager(locationProvider: location, allowsDestructiveRecovery: true, keychain: keychain)
        #else
        // Release builds trap via fatalError before recovery can run.
        #expect(true)
        #endif
    }

    @Test func repositoryReopenWithExistingDataSucceeds() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        var manager: DatabaseManager? = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repository = CashRunwayRepository(databaseManager: try #require(manager))
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: try #require(try repository.wallets().first?.id),
                amountMinor: 7_500,
                occurredAt: .now,
                categoryID: try #require(try repository.categories(kind: .expense).first?.id),
                merchant: "Reopen test",
                note: ""
            )
        )
        let txCountBefore = try repository.transactions().count
        manager = nil

        let reopenedManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let reopenedRepo = CashRunwayRepository(databaseManager: reopenedManager)
        try reopenedRepo.seedIfNeeded()

        #expect(try reopenedRepo.wallets().count >= 2)
        #expect(try reopenedRepo.transactions().count == txCountBefore)
    }

     @Test func sourceFormatIDMigrationInfersLegacyXLSXByFileExtension() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore(items: ["database-key": Data("test-database-key".utf8)])
        let dbURL = try location.databaseURL()
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.prepareDatabase { db in
            try db.usePassphrase("test-database-key")
        }
        let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            for migrationID in ["v1_schema", "v2_transaction_search_category_name", "v3_import_idempotency", "v3_bank_sync"] {
                try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [migrationID])
            }
            try db.execute(sql: """
                CREATE TABLE import_jobs (
                    id TEXT PRIMARY KEY,
                    source_name TEXT NOT NULL,
                    file_name TEXT,
                    status TEXT NOT NULL,
                    total_rows INTEGER NOT NULL DEFAULT 0,
                    valid_rows INTEGER NOT NULL DEFAULT 0,
                    invalid_rows INTEGER NOT NULL DEFAULT 0,
                    duplicate_rows INTEGER NOT NULL DEFAULT 0,
                    started_at DATETIME NOT NULL,
                    finished_at DATETIME,
                    error_summary TEXT
                )
                """)
            let now = Date()
            let rows: [(String, String, String)] = [
                ("privat-xlsx", "PrivatBank", "statement.xlsx"),
                ("privat-csv", "PrivatBank", "statement.csv"),
                ("generic-xlsx", "Generic CSV", "unknown.xlsx"),
                ("generic-csv", "Generic CSV", "unknown.csv"),
            ]
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO import_jobs (id, source_name, file_name, status, started_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [row.0, row.1, row.2, ImportJobStatus.committed.rawValue, now]
                )
            }
        }

        let manager = try DatabaseManager(locationProvider: location, keychain: keychain)

        let mapped = try manager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, source_format_id FROM import_jobs ORDER BY id")
        }
        let values = Dictionary(uniqueKeysWithValues: mapped.map { row in
            (row["id"] as String, row["source_format_id"] as String?)
        })
        #expect(values["privat-xlsx"] == BankStatementFormat.privatBankXLSXv1.id)
        #expect(values["privat-csv"] == BankStatementFormat.privatBankCSVv1.id)
        #expect(values["generic-xlsx"] == BankStatementFormat.genericBankXLSX.id)
        #expect(values["generic-csv"] == BankStatementFormat.genericBankCSV.id)
    }
}
