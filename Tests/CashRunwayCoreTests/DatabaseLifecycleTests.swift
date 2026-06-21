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

    @Test func importJobSourceFormatBackfillUsesExplicitMappings() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CashRunwayMigration-\(UUID().uuidString)", isDirectory: true)
        let dbURL = tempDirectory.appendingPathComponent("cash-runway.sqlite")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let queue = try DatabaseQueue(path: dbURL.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE import_jobs (
                    id TEXT PRIMARY KEY NOT NULL,
                    source_name TEXT NOT NULL,
                    file_name TEXT NOT NULL,
                    status TEXT NOT NULL,
                    total_rows INTEGER NOT NULL,
                    valid_rows INTEGER NOT NULL,
                    invalid_rows INTEGER NOT NULL,
                    started_at TEXT NOT NULL,
                    finished_at TEXT,
                    error_summary TEXT
                )
                """)
            try db.execute(sql: """
                INSERT INTO import_jobs (id, source_name, file_name, status, total_rows, valid_rows, invalid_rows, started_at, finished_at, error_summary)
                VALUES
                    ('1', 'Cash Runway Wallet', 'wallet.csv', 'committed', 1, 1, 0, '2026-01-01T00:00:00Z', NULL, NULL),
                    ('2', 'Monobank', 'mono.csv', 'committed', 1, 1, 0, '2026-01-01T00:00:00Z', NULL, NULL),
                    ('3', 'Generic CSV', 'generic.csv', 'committed', 1, 1, 0, '2026-01-01T00:00:00Z', NULL, NULL),
                    ('4', 'PrivatBank', 'report.xlsx', 'committed', 1, 1, 0, '2026-01-01T00:00:00Z', NULL, NULL),
                    ('5', 'PrivatBank', 'report.csv', 'committed', 1, 1, 0, '2026-01-01T00:00:00Z', NULL, NULL),
                    ('6', 'Unknown', 'unknown.csv', 'committed', 1, 1, 0, '2026-01-01T00:00:00Z', NULL, NULL)
                """)
            try db.execute(sql: "ALTER TABLE import_jobs ADD COLUMN source_format_id TEXT")
            try db.execute(sql: """
                UPDATE import_jobs
                SET source_format_id = CASE
                    WHEN source_name = 'Cash Runway Wallet' THEN 'cash-runway.csv.v1'
                    WHEN source_name = 'Monobank' THEN 'monobank.csv.v1'
                    WHEN source_name = 'Generic CSV' THEN 'generic-bank.csv.v1'
                    WHEN source_name = 'PrivatBank' AND lower(file_name) LIKE '%.xlsx' THEN 'privatbank.xlsx.v1'
                    WHEN source_name = 'PrivatBank' AND lower(file_name) LIKE '%.csv' THEN 'privatbank.csv.v1'
                    ELSE NULL
                END
                WHERE source_format_id IS NULL
                """)
        }

        let rows = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT source_format_id FROM import_jobs ORDER BY id")
        }

        #expect(rows[0]["source_format_id"] as String? == BankStatementFormat.cashRunwayCSV.id)
        #expect(rows[1]["source_format_id"] as String? == BankStatementFormat.monobankCSVv1.id)
        #expect(rows[2]["source_format_id"] as String? == BankStatementFormat.genericBankCSV.id)
        #expect(rows[3]["source_format_id"] as String? == BankStatementFormat.privatBankXLSXv1.id)
        #expect(rows[4]["source_format_id"] as String? == BankStatementFormat.privatBankCSVv1.id)
        #expect(rows[5]["source_format_id"] as String? == nil)
    }
}
