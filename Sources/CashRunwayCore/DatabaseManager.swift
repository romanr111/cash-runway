import Foundation
import GRDB
import Security
import CryptoKit
import LocalAuthentication

public final class KeychainStore: @unchecked Sendable {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func read(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public func write(_ data: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
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

public struct AppLockConfiguration: Codable, Sendable, Equatable {
    public var pinHash: String
    public var isEnabled: Bool
    public var usesBiometrics: Bool
    public var backgroundLockSeconds: Int
}

public final class AppLockStore: @unchecked Sendable {
    private let keychain: KeychainStore
    private let account = "app-lock-config"

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    public func configuration() -> AppLockConfiguration? {
        guard let data = keychain.read(account: account) else { return nil }
        return try? JSONDecoder().decode(AppLockConfiguration.self, from: data)
    }

    public func save(pin: String, biometrics: Bool, backgroundLockSeconds: Int) throws {
        guard pin.count >= 4 else {
            throw CashRunwayError.validation("PIN must be at least 4 digits.")
        }
        let config = AppLockConfiguration(
            pinHash: SHA256.hash(data: Data(pin.utf8)).compactMap { String(format: "%02x", $0) }.joined(),
            isEnabled: true,
            usesBiometrics: biometrics,
            backgroundLockSeconds: backgroundLockSeconds
        )
        keychain.write(try JSONEncoder().encode(config), account: account)
    }

    public func validate(pin: String) -> Bool {
        guard let config = configuration() else { return false }
        let hash = SHA256.hash(data: Data(pin.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return config.pinHash == hash
    }

    public func canUseBiometrics() -> Bool {
        guard configuration()?.usesBiometrics == true else { return false }
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    @MainActor
    public func unlockWithBiometrics(reason: String = "Unlock Cash Runway") async -> Bool {
        guard canUseBiometrics() else { return false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
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
    public let dbQueue: DatabaseQueue
    public let keychain: KeychainStore

    public init(locationProvider: DatabaseLocationProvider = .init(), allowsDestructiveRecovery: Bool = false) throws {
        self.keychain = KeychainStore(service: "dev.roman.cash-runway")
        let databaseURL = try locationProvider.databaseURL()
        self.dbQueue = try Self.openDatabase(
            at: databaseURL,
            keychain: keychain,
            migrator: Self.makeMigrator(),
            allowsDestructiveRecovery: allowsDestructiveRecovery
        )
    }

    private static func databaseKey(using keychain: KeychainStore) -> String {
        let account = "database-key"
        if let data = keychain.read(account: account), let key = String(data: data, encoding: .utf8) {
            return key
        }

        let key = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        keychain.write(Data(key.utf8), account: account)
        return key
    }

    private static func openDatabase(at url: URL, keychain: KeychainStore, migrator: DatabaseMigrator, allowsDestructiveRecovery: Bool) throws -> DatabaseQueue {
        do {
            let dbQueue = try DatabaseQueue(path: url.path, configuration: makeConfiguration(keychain: keychain))
            try migrator.migrate(dbQueue)
            return dbQueue
        } catch {
            guard allowsDestructiveRecovery, shouldRecover(from: error) else {
                throw error
            }
            try quarantineDatabase(at: url)
            keychain.delete(account: "database-key")
            let recoveredQueue = try DatabaseQueue(path: url.path, configuration: makeConfiguration(keychain: keychain))
            try migrator.migrate(recoveredQueue)
            return recoveredQueue
        }
    }

    private static func makeConfiguration(keychain: KeychainStore) -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.usePassphrase(databaseKey(using: keychain))
        }
        return configuration
    }

    private static func shouldRecover(from error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("not a database")
            || message.contains("error decrypting page")
            || message.contains("hmac check failed")
            || message.contains("sqlcipher")
    }

    private static func quarantineDatabase(at url: URL) throws {
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
        }
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_schema") { db in
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
        }

        return migrator
    }
}
