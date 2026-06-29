import Foundation
import GRDB
import Security
import CryptoKit
import OSLog

public enum KeychainStoreError: Error, LocalizedError, Equatable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case invalidStoredData(String)

    public var errorDescription: String? {
        switch self {
        case let .readFailed(status):
            "Keychain read failed with status \(status)."
        case let .writeFailed(status):
            "Keychain write failed with status \(status)."
        case let .invalidStoredData(account):
            "Keychain item \(account) could not be decoded."
        }
    }

    public var isInteractionNotAllowed: Bool {
        switch self {
        case .readFailed(errSecInteractionNotAllowed), .writeFailed(errSecInteractionNotAllowed):
            true
        case .readFailed, .writeFailed, .invalidStoredData:
            false
        }
    }
}

public struct CashRunwayStartupFailure: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public let isRetryable: Bool
    public let diagnosticCode: String

    public init(error: Error) {
        if Self.isKeychainInteractionNotAllowed(error) {
            message = "Unlock your iPhone, return to Cash Runway, and tap Retry. Your database was not changed."
            isRetryable = true
            diagnosticCode = "keychain-interaction-not-allowed"
        } else {
            message = error.localizedDescription
            isRetryable = false
            diagnosticCode = "startup-open-failed"
        }
    }

    public init(message: String) {
        self.message = message
        isRetryable = message.contains("status \(errSecInteractionNotAllowed)")
        diagnosticCode = isRetryable ? "keychain-interaction-not-allowed" : "startup-open-failed"
    }

    public var errorDescription: String? { message }

    private static func isKeychainInteractionNotAllowed(_ error: Error) -> Bool {
        if let keychainError = error as? KeychainStoreError {
            return keychainError.isInteractionNotAllowed
        }
        return error.localizedDescription.contains("status \(errSecInteractionNotAllowed)")
    }
}

public protocol KeychainStoring: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String)
}

public protocol BankTokenStore: Sendable {
    func readToken(account: String) throws -> String?
    func writeToken(_ token: String, account: String) throws
    func deleteToken(account: String) throws
}

public final class KeychainStore: KeychainStoring, @unchecked Sendable {
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let` (service, accessibility). Keychain operations (SecItem*) are
    // thread-safe per Apple's documentation.
    private let service: String
    private let accessibility: CFString

    public init(service: String, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) {
        self.service = service
        self.accessibility = accessibility
    }

    public func read(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.readFailed(status) }
        return result as? Data
    }

    public func write(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: accessibility,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.writeFailed(updateStatus)
        }

        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = accessibility
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.writeFailed(addStatus)
        }
    }

    public func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public final class KeychainBankTokenStore: BankTokenStore, @unchecked Sendable {
    // @unchecked Sendable is justified: `keychain` is an immutable `let` to a
    // Sendable protocol; `BankTokenStore` methods delegate to `KeychainStore`
    // which is thread-safe.
    private let keychain: any KeychainStoring

    public init(keychain: any KeychainStoring) {
        self.keychain = keychain
    }

    public func readToken(account: String) throws -> String? {
        guard let data = try keychain.read(account: account) else { return nil }
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidStoredData(account)
        }
        return token
    }

    public func writeToken(_ token: String, account: String) throws {
        try keychain.write(Data(token.utf8), account: account)
    }

    public func deleteToken(account: String) throws {
        keychain.delete(account: account)
    }
}

public struct DatabaseLocationProvider {
    public var appGroupIdentifier: String?
    public var databaseURLOverride: URL?
    public var directoryName: String

    public init(
        appGroupIdentifier: String? = nil,
        databaseURLOverride: URL? = nil,
        directoryName: String = "CashRunway"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.databaseURLOverride = databaseURLOverride
        self.directoryName = directoryName
    }

    public func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        if let databaseURLOverride {
            try fileManager.createDirectory(at: databaseURLOverride.deletingLastPathComponent(), withIntermediateDirectories: true)
            return databaseURLOverride
        }
        if let appGroupIdentifier,
           let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let databaseDirectory = url.appendingPathComponent("Database", isDirectory: true)
            try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
            return databaseDirectory.appendingPathComponent("cash-runway.sqlite")
        }

        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseDirectory = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        return databaseDirectory.appendingPathComponent("cash-runway.sqlite")
    }

}

public final class DatabaseManager: @unchecked Sendable {
    // @unchecked Sendable is justified: `dbQueue` (GRDB DatabaseQueue) is
    // Sendable and serializes all DB access; `keychain` is an immutable `let`
    // to a Sendable protocol. No mutable instance state outside GRDB's lock.
    private static let logger = Logger(subsystem: "dev.roman.cashrunway", category: "keychain")

    public let dbQueue: DatabaseQueue
    public let keychain: any KeychainStoring

    public convenience init(
        locationProvider: DatabaseLocationProvider = .init(),
        allowsDestructiveRecovery: Bool = false,
        keychainService: String = "dev.roman.cash-runway"
    ) throws {
        #if !DEBUG
        if allowsDestructiveRecovery {
            fatalError("Destructive recovery is not allowed in release builds.")
        }
        #endif
        try self.init(
            locationProvider: locationProvider,
            allowsDestructiveRecovery: allowsDestructiveRecovery,
            keychain: KeychainStore(service: keychainService)
        )
    }

    public init(
        locationProvider: DatabaseLocationProvider = .init(),
        allowsDestructiveRecovery: Bool = false,
        keychain: any KeychainStoring,
        migrator: DatabaseMigrator
    ) throws {
        self.keychain = keychain
        let databaseURL = try locationProvider.databaseURL()
        self.dbQueue = try Self.openDatabase(
            at: databaseURL,
            keychain: keychain,
            migrator: migrator,
            allowsDestructiveRecovery: allowsDestructiveRecovery
        )
    }

    public init(
        locationProvider: DatabaseLocationProvider = .init(),
        allowsDestructiveRecovery: Bool = false,
        keychain: any KeychainStoring
    ) throws {
        #if !DEBUG
        if allowsDestructiveRecovery {
            fatalError("Destructive recovery is not allowed in release builds.")
        }
        #endif
        self.keychain = keychain
        let databaseURL = try locationProvider.databaseURL()
        self.dbQueue = try Self.openDatabase(
            at: databaseURL,
            keychain: keychain,
            migrator: Self.makeMigrator(),
            allowsDestructiveRecovery: allowsDestructiveRecovery
        )
    }

    private static func databaseKey(using keychain: any KeychainStoring) throws -> (key: String, hadExistingKey: Bool) {
        let account = "database-key"
        if let data = try keychain.read(account: account) {
            guard let key = String(data: data, encoding: .utf8), !key.isEmpty else {
                throw KeychainStoreError.invalidStoredData(account)
            }
            stampDatabaseKeyAccessibility(data, using: keychain)
            return (key, true)
        }

        let key = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try keychain.write(Data(key.utf8), account: account)
        return (key, false)
    }

    private static func stampDatabaseKeyAccessibility(_ data: Data, using keychain: any KeychainStoring) {
        do {
            try keychain.write(data, account: "database-key")
        } catch {
            logger.error("Database key accessibility stamp failed: \(CashRunwayStartupFailure(error: error).diagnosticCode, privacy: .public)")
        }
    }

    private static func openDatabase(at url: URL, keychain: any KeychainStoring, migrator: DatabaseMigrator, allowsDestructiveRecovery: Bool) throws -> DatabaseQueue {
        let databaseExists = FileManager.default.fileExists(atPath: url.path)

        if databaseExists {
            let hadKey = (try? keychain.read(account: "database-key")) != nil
            if !hadKey && !allowsDestructiveRecovery {
                throw CashRunwayStartupFailure(message: "Database exists but no encryption key was found in Keychain. The database was not modified.")
            }
        }

        do {
            let dbQueue = try DatabaseQueue(path: url.path, configuration: makeConfiguration(keychain: keychain))
            try migrator.migrate(dbQueue)
            FileProtectionService().protectSQLiteTrio(at: url)
            return dbQueue
        } catch {
            guard allowsDestructiveRecovery, shouldRecover(from: error) else {
                throw error
            }
            try quarantineDatabases(at: url)
            keychain.delete(account: "database-key")
            let recoveredQueue = try DatabaseQueue(path: url.path, configuration: makeConfiguration(keychain: keychain))
            try migrator.migrate(recoveredQueue)
            FileProtectionService().protectSQLiteTrio(at: url)
            return recoveredQueue
        }
    }

    private static func makeConfiguration(keychain: any KeychainStoring) -> Configuration {
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.prepareDatabase { db in
            try db.usePassphrase(try databaseKey(using: keychain).key)
        }
        return configuration
    }

    func checkpointWal() throws {
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    private static func shouldRecover(from error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("not a database")
            || message.contains("error decrypting page")
            || message.contains("hmac check failed")
            || message.contains("sqlcipher")
    }

    static func quarantineDatabases(at url: URL) throws {
        let fileManager = FileManager.default
        let recoveryDirectory = url.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = recoveryDirectory.appendingPathComponent("\(url.lastPathComponent).\(stamp)\(suffix).bak")
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            FileProtectionService().protect(destinationURL)
        }
    }

    static func allMigrations() -> [(String, @Sendable (Database) throws -> Void)] {
        // Migration identifiers are permanent. GRDB tracks applied migrations
        // by identifier (not by name ordering) and runs them in registration order.
        // Existing identifiers are immutable in place; new migrations append only.
        // Never rename, reorder, or delete an existing entry — existing databases
        // would treat a renamed/reordered migration as new and re-run it, corrupting data.
        // The non-monotonic position of `v3_bank_sync` (registered after `v4_…`) is
        // intentional and must not be "fixed" by reordering.
        // Use monotonic names (`v6_*`, `v7_*`, …) for NEW migrations only.
        // `MigrationIntegrityTests.migrationIdentifierSetMatchesRegistrationOrder`
        // asserts this exact ordered set so accidental edits are caught.
        [
            ("v1_schema", { db in
                try db.create(table: "wallets") { table in
                    table.column("id", .text).primaryKey()
                    table.column("name", .text).notNull()
                    table.column("kind", .text).notNull()
                    table.column("color_hex", .text)
                    table.column("icon_name", .text)
                    table.column("starting_balance_minor", .integer).notNull()
                    table.column("current_balance_minor", .integer).notNull()
                    table.column("is_archived", .boolean).notNull().defaults(to: false)
                    table.column("sort_order", .integer).notNull().defaults(to: 0)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(table: "categories") { table in
                    table.column("id", .text).primaryKey()
                    table.column("name", .text).notNull()
                    table.column("kind", .text).notNull()
                    table.column("icon_name", .text)
                    table.column("color_hex", .text)
                    table.column("parent_id", .text)
                    table.column("is_system", .boolean).notNull().defaults(to: false)
                    table.column("is_archived", .boolean).notNull().defaults(to: false)
                    table.column("sort_order", .integer).notNull().defaults(to: 0)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(table: "labels") { table in
                    table.column("id", .text).primaryKey()
                    table.column("name", .text).notNull()
                    table.column("color_hex", .text)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(table: "transactions") { table in
                    table.column("id", .text).primaryKey()
                    table.column("wallet_id", .text).notNull().indexed()
                    table.column("type", .text).notNull()
                    table.column("linked_transfer_id", .text)
                    table.column("amount_minor", .integer).notNull()
                    table.column("occurred_at", .datetime).notNull()
                    table.column("local_day_key", .integer).notNull()
                    table.column("local_month_key", .integer).notNull()
                    table.column("category_id", .text)
                    table.column("merchant", .text)
                    table.column("note", .text)
                    table.column("is_deleted", .boolean).notNull().defaults(to: false)
                    table.column("source", .text).notNull()
                    table.column("recurring_template_id", .text)
                    table.column("recurring_instance_id", .text)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(table: "transaction_labels", options: [.withoutRowID]) { table in
                    table.column("transaction_id", .text).notNull()
                    table.column("label_id", .text).notNull()
                    table.primaryKey(["transaction_id", "label_id"])
                }

                try db.create(table: "budgets") { table in
                    table.column("id", .text).primaryKey()
                    table.column("category_id", .text).notNull()
                    table.column("month_key", .integer).notNull()
                    table.column("limit_minor", .integer).notNull()
                    table.column("is_archived", .boolean).notNull().defaults(to: false)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["category_id", "month_key"])
                }

                try db.create(table: "recurring_templates") { table in
                    table.column("id", .text).primaryKey()
                    table.column("kind", .text).notNull()
                    table.column("wallet_id", .text).notNull()
                    table.column("counterparty_wallet_id", .text)
                    table.column("amount_minor", .integer).notNull()
                    table.column("category_id", .text)
                    table.column("merchant", .text)
                    table.column("note", .text)
                    table.column("rule_type", .text).notNull()
                    table.column("rule_interval", .integer).notNull()
                    table.column("day_of_month", .integer)
                    table.column("weekday", .integer)
                    table.column("start_date", .datetime).notNull()
                    table.column("end_date", .datetime)
                    table.column("is_active", .boolean).notNull().defaults(to: true)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(table: "recurring_instances") { table in
                    table.column("id", .text).primaryKey()
                    table.column("template_id", .text).notNull()
                    table.column("due_date", .datetime).notNull()
                    table.column("day_key", .integer).notNull()
                    table.column("status", .text).notNull()
                    table.column("linked_transaction_id", .text)
                    table.column("override_amount_minor", .integer)
                    table.column("override_category_id", .text)
                    table.column("override_note", .text)
                    table.column("override_merchant", .text)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["template_id", "day_key"])
                }

                try db.create(table: "category_remaps") { table in
                    table.column("id", .text).primaryKey()
                    table.column("old_category_id", .text).notNull()
                    table.column("new_category_id", .text).notNull()
                    table.column("remapped_at", .datetime).notNull()
                }

                try db.create(table: "audit_entries") { table in
                    table.column("id", .text).primaryKey()
                    table.column("entity_type", .text).notNull()
                    table.column("entity_id", .text).notNull()
                    table.column("operation", .text).notNull()
                    table.column("diff_json", .text).notNull()
                    table.column("created_at", .datetime).notNull()
                }

                try db.create(table: "import_jobs") { table in
                    table.column("id", .text).primaryKey()
                    table.column("source_name", .text).notNull()
                    table.column("file_name", .text).notNull()
                    table.column("status", .text).notNull()
                    table.column("total_rows", .integer).notNull()
                    table.column("valid_rows", .integer).notNull()
                    table.column("invalid_rows", .integer).notNull()
                    table.column("started_at", .datetime).notNull()
                    table.column("finished_at", .datetime)
                    table.column("error_summary", .text)
                }

                try db.create(table: "monthly_wallet_cashflow") { table in
                    table.column("wallet_id", .text).notNull()
                    table.column("month_key", .integer).notNull()
                    table.column("income_minor", .integer).notNull().defaults(to: 0)
                    table.column("expense_minor", .integer).notNull().defaults(to: 0)
                    table.column("transfer_in_minor", .integer).notNull().defaults(to: 0)
                    table.column("transfer_out_minor", .integer).notNull().defaults(to: 0)
                    table.column("txn_count", .integer).notNull().defaults(to: 0)
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["wallet_id", "month_key"])
                }

                try db.create(table: "monthly_category_spend") { table in
                    table.column("category_id", .text).notNull()
                    table.column("month_key", .integer).notNull()
                    table.column("expense_minor", .integer).notNull().defaults(to: 0)
                    table.column("txn_count", .integer).notNull().defaults(to: 0)
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["category_id", "month_key"])
                }

                try db.create(table: "daily_wallet_balance_delta") { table in
                    table.column("wallet_id", .text).notNull()
                    table.column("day_key", .integer).notNull()
                    table.column("net_delta_minor", .integer).notNull().defaults(to: 0)
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["wallet_id", "day_key"])
                }

                try db.create(table: "budget_progress_snapshot") { table in
                    table.column("budget_id", .text).notNull()
                    table.column("month_key", .integer).notNull()
                    table.column("spent_minor", .integer).notNull().defaults(to: 0)
                    table.column("remaining_minor", .integer).notNull().defaults(to: 0)
                    table.column("percent_used_bp", .integer).notNull().defaults(to: 0)
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["budget_id", "month_key"])
                }

                try db.create(table: "aggregate_dirty_ranges") { table in
                    table.column("id", .text).primaryKey()
                    table.column("kind", .text).notNull()
                    table.column("wallet_id", .text)
                    table.column("category_id", .text)
                    table.column("budget_id", .text)
                    table.column("month_key", .integer)
                    table.column("status", .text).notNull()
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(virtualTable: "transaction_search", using: FTS5()) { table in
                    table.column("transaction_id").notIndexed()
                    table.column("merchant")
                    table.column("note")
                    table.column("wallet_name")
                    table.column("category_name")
                    table.column("labels")
                    table.tokenizer = .unicode61()
                }

                try db.create(index: "idx_transactions_wallet_occurred", on: "transactions", columns: ["wallet_id", "occurred_at"])
                try db.create(index: "idx_transactions_day", on: "transactions", columns: ["local_day_key", "id"])
                try db.create(index: "idx_transactions_month_wallet", on: "transactions", columns: ["local_month_key", "wallet_id"])
                try db.create(index: "idx_transactions_category_month", on: "transactions", columns: ["category_id", "local_month_key"])
                try db.create(index: "idx_transactions_recurring_template", on: "transactions", columns: ["recurring_template_id"])
                try db.create(index: "idx_transactions_source", on: "transactions", columns: ["source"])
                try db.create(index: "idx_transaction_labels_label_transaction", on: "transaction_labels", columns: ["label_id", "transaction_id"])
                try db.create(index: "idx_budgets_month_category", on: "budgets", columns: ["month_key", "category_id"])
                try db.create(index: "idx_monthly_wallet_cashflow_month_wallet", on: "monthly_wallet_cashflow", columns: ["month_key", "wallet_id"])
                try db.create(index: "idx_monthly_category_spend_month_category", on: "monthly_category_spend", columns: ["month_key", "category_id"])
                try db.create(index: "idx_daily_wallet_balance_delta_day_wallet", on: "daily_wallet_balance_delta", columns: ["day_key", "wallet_id"])
                try db.create(index: "idx_recurring_instances_template_day", on: "recurring_instances", columns: ["template_id", "day_key"])
            }),

            ("v2_transaction_search_category_name", { db in
                try db.drop(table: "transaction_search")
                try db.create(virtualTable: "transaction_search", using: FTS5()) { table in
                    table.column("transaction_id").notIndexed()
                    table.column("merchant")
                    table.column("note")
                    table.column("wallet_name")
                    table.column("category_name")
                    table.column("labels")
                    table.tokenizer = .unicode61()
                }

                try db.execute(
                    sql: """
                    INSERT INTO transaction_search (transaction_id, merchant, note, wallet_name, category_name, labels)
                    SELECT
                        t.id,
                        COALESCE(t.merchant, ''),
                        COALESCE(t.note, ''),
                        COALESCE(w.name, ''),
                        COALESCE(c.name, ''),
                        COALESCE((
                            SELECT group_concat(l.name, ' ')
                            FROM transaction_labels tl
                            JOIN labels l ON l.id = tl.label_id
                            WHERE tl.transaction_id = t.id
                        ), '')
                    FROM transactions t
                    JOIN wallets w ON w.id = t.wallet_id
                    LEFT JOIN categories c ON c.id = t.category_id
                    WHERE t.is_deleted = 0
                    """
                )
            }),

            ("v3_import_idempotency", { db in
                try db.execute(sql: "ALTER TABLE import_jobs ADD COLUMN duplicate_rows INTEGER NOT NULL DEFAULT 0")
                try db.execute(sql: "ALTER TABLE transactions ADD COLUMN import_job_id TEXT")
                try db.execute(sql: "ALTER TABLE transactions ADD COLUMN import_fingerprint TEXT")
                try db.execute(sql: "CREATE UNIQUE INDEX idx_transactions_import_fingerprint ON transactions(import_fingerprint) WHERE import_fingerprint IS NOT NULL")
            }),

            ("v4_import_job_source_format_id", { db in
                try db.execute(sql: "ALTER TABLE import_jobs ADD COLUMN source_format_id TEXT")
                try db.execute(sql: """
                    UPDATE import_jobs
                    SET source_format_id = CASE
                        WHEN source_name IN ('Cash Runway Wallet', 'Cash Runway Wallet CSV') THEN 'cash-runway.csv.v1'
                        WHEN source_name IN ('Monobank', 'Monobank CSV') THEN 'monobank.csv.v1'
                        WHEN source_name = 'PrivatBank XLSX' THEN 'privatbank.xlsx.v1'
                        WHEN source_name = 'PrivatBank' AND lower(file_name) LIKE '%.xlsx' THEN 'privatbank.xlsx.v1'
                        WHEN source_name IN ('PrivatBank', 'PrivatBank CSV') THEN 'privatbank.csv.v1'
                        WHEN source_name = 'Generic Bank XLSX' THEN 'generic-bank.xlsx.v1'
                        WHEN source_name = 'Generic CSV' AND lower(file_name) LIKE '%.xlsx' THEN 'generic-bank.xlsx.v1'
                        WHEN source_name IN ('Generic CSV', 'Generic Bank CSV') THEN 'generic-bank.csv.v1'
                        ELSE NULL
                    END
                    WHERE source_format_id IS NULL
                    """)
            }),

            ("v3_bank_sync", { db in
                try db.create(table: "bank_integrations") { table in
                    table.column("id", .text).primaryKey()
                    table.column("provider", .text).notNull()
                    table.column("display_name", .text).notNull()
                    table.column("status", .text).notNull()
                    table.column("sync_start_at", .datetime).notNull()
                    table.column("token_keychain_account", .text).notNull()
                    table.column("last_client_info_sync_at", .datetime)
                    table.column("last_successful_sync_at", .datetime)
                    table.column("last_sync_error", .text)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(table: "bank_accounts") { table in
                    table.column("id", .text).primaryKey()
                    table.column("integration_id", .text).notNull()
                    table.column("provider", .text).notNull()
                    table.column("provider_account_id", .text).notNull()
                    table.column("wallet_id", .text).notNull()
                    table.column("display_name", .text).notNull()
                    table.column("account_type", .text)
                    table.column("currency_code", .integer).notNull()
                    table.column("masked_pan", .text)
                    table.column("iban", .text)
                    table.column("is_enabled", .boolean).notNull().defaults(to: true)
                    table.column("sync_start_at", .datetime).notNull()
                    table.column("last_successful_sync_at", .datetime)
                    table.column("last_statement_item_time", .integer)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["integration_id", "provider_account_id"])
                }

                try db.create(table: "bank_transaction_imports") { table in
                    table.column("id", .text).primaryKey()
                    table.column("provider", .text).notNull()
                    table.column("integration_id", .text).notNull()
                    table.column("bank_account_id", .text).notNull()
                    table.column("provider_account_id", .text).notNull()
                    table.column("provider_statement_item_id", .text).notNull()
                    table.column("statement_time", .integer).notNull()
                    table.column("amount_minor_signed", .integer).notNull()
                    table.column("operation_amount_minor_signed", .integer)
                    table.column("currency_code", .integer).notNull()
                    table.column("mcc", .integer)
                    table.column("original_mcc", .integer)
                    table.column("description", .text)
                    table.column("comment", .text)
                    table.column("counter_name", .text)
                    table.column("counter_iban", .text)
                    table.column("receipt_id", .text)
                    table.column("hold", .boolean)
                    table.column("raw_json", .text).notNull()
                    table.column("cash_runway_transaction_id", .text)
                    table.column("import_status", .text).notNull()
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["provider", "provider_account_id", "provider_statement_item_id"])
                }

                try db.create(table: "bank_category_rules") { table in
                    table.column("id", .text).primaryKey()
                    table.column("provider", .text).notNull()
                    table.column("rule_type", .text).notNull()
                    table.column("merchant_pattern", .text)
                    table.column("mcc", .integer)
                    table.column("category_id", .text).notNull()
                    table.column("confidence", .integer).notNull().defaults(to: 100)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                try db.create(index: "idx_bank_accounts_integration", on: "bank_accounts", columns: ["integration_id"])
                try db.create(index: "idx_bank_imports_account_time", on: "bank_transaction_imports", columns: ["bank_account_id", "statement_time"])
                try db.create(index: "idx_bank_imports_cash_transaction", on: "bank_transaction_imports", columns: ["cash_runway_transaction_id"])
                try db.create(index: "idx_bank_category_rules_provider_type", on: "bank_category_rules", columns: ["provider", "rule_type"])
            }),

            ("v5_custom_wallet_categories", { db in
                try db.create(table: "wallet_categories") { table in
                    table.column("id", .text).primaryKey()
                    table.column("name", .text).notNull()
                    table.column("kind", .text).notNull()
                    table.column("is_system", .boolean).notNull().defaults(to: false)
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                }

                let now = Date()
                for category in WalletCategory.allBuiltIn {
                    try db.execute(
                        sql: """
                        INSERT INTO wallet_categories (id, name, kind, is_system, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            category.id.uuidString, category.name, category.kind.rawValue,
                            true, now, now,
                        ]
                    )
                }

                let walletsTableExists = try Bool.fetchOne(
                    db,
                    sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'wallets'"
                ) != nil
                guard walletsTableExists else { return }

                try db.execute(sql: "ALTER TABLE wallets ADD COLUMN category_id TEXT")

                for category in WalletCategory.allBuiltIn {
                    try db.execute(
                        sql: "UPDATE wallets SET category_id = ? WHERE kind = ?",
                        arguments: [category.id.uuidString, category.kind.rawValue]
                    )
                }
            }),

            ("v6_bank_raw_json_ttl", { db in
                // Recreate bank_transaction_imports so raw_json becomes nullable.
                // This allows the 30-day TTL purge to actually delete payloads.
                let tableExists = try Bool.fetchOne(
                    db,
                    sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'bank_transaction_imports'"
                ) != nil

                if tableExists {
                    try db.execute(sql: "ALTER TABLE bank_transaction_imports RENAME TO bank_transaction_imports_old")
                }

                try db.create(table: "bank_transaction_imports") { table in
                    table.column("id", .text).primaryKey()
                    table.column("provider", .text).notNull()
                    table.column("integration_id", .text).notNull()
                    table.column("bank_account_id", .text).notNull()
                    table.column("provider_account_id", .text).notNull()
                    table.column("provider_statement_item_id", .text).notNull()
                    table.column("statement_time", .integer).notNull()
                    table.column("amount_minor_signed", .integer).notNull()
                    table.column("operation_amount_minor_signed", .integer)
                    table.column("currency_code", .integer).notNull()
                    table.column("mcc", .integer)
                    table.column("original_mcc", .integer)
                    table.column("description", .text)
                    table.column("comment", .text)
                    table.column("counter_name", .text)
                    // DEPRECATED post-v6: always NULL going forward. Retained as
                    // nullable for schema compatibility, but no code path populates
                    // them. Do not re-enable without privacy review — these columns
                    // hold PII (IBAN, receipt id) that the v6 migration intentionally
                    // redacted from existing rows.
                    table.column("counter_iban", .text)
                    table.column("receipt_id", .text)
                    table.column("hold", .boolean)
                    table.column("raw_json", .text)
                    table.column("raw_json_expires_at", .datetime)
                    table.column("cash_runway_transaction_id", .text)
                    table.column("import_status", .text).notNull()
                    table.column("created_at", .datetime).notNull()
                    table.column("updated_at", .datetime).notNull()
                    table.uniqueKey(["provider", "provider_account_id", "provider_statement_item_id"])
                }

                if tableExists {
                    // raw_json is intentionally set to NULL for all migrated rows; existing
                    // full payloads are redacted on upgrade per the privacy policy.
                    // raw_json_expires_at is set to created_at+30d for bookkeeping, but
                    // the payload is already gone. counter_iban and receipt_id are also
                    // cleared (NULL) to drop retained PII from legacy imports.
                    try db.execute(sql: """
                        INSERT INTO bank_transaction_imports (
                            id, provider, integration_id, bank_account_id, provider_account_id,
                            provider_statement_item_id, statement_time, amount_minor_signed,
                            operation_amount_minor_signed, currency_code, mcc, original_mcc,
                            description, comment, counter_name, counter_iban, receipt_id, hold,
                            raw_json, raw_json_expires_at, cash_runway_transaction_id, import_status, created_at, updated_at
                        )
                        SELECT
                            id, provider, integration_id, bank_account_id, provider_account_id,
                            provider_statement_item_id, statement_time, amount_minor_signed,
                            operation_amount_minor_signed, currency_code, mcc, original_mcc,
                            description, comment, counter_name, NULL, NULL, hold,
                            NULL, datetime(created_at, '+30 days'), cash_runway_transaction_id, import_status, created_at, updated_at
                        FROM bank_transaction_imports_old
                        """)
                    try db.execute(sql: "DROP TABLE bank_transaction_imports_old")
                }

                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_bank_imports_account_time ON bank_transaction_imports(bank_account_id, statement_time)")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_bank_imports_cash_transaction ON bank_transaction_imports(cash_runway_transaction_id)")
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_bank_transaction_imports_statement_time ON bank_transaction_imports(statement_time)")
            }),
        ]
    }

    private static func makeMigrator() -> DatabaseMigrator {
        let all = allMigrations()
        var migrator = DatabaseMigrator()
        for (name, block) in all {
            migrator.registerMigration(name, migrate: block)
        }
        return migrator
    }

    static func makeMigrator(upTo version: String) -> DatabaseMigrator {
        let all = allMigrations()
        var migrator = DatabaseMigrator()
        for (name, block) in all {
            migrator.registerMigration(name, migrate: block)
            if name == version { break }
}
        return migrator
    }
}
