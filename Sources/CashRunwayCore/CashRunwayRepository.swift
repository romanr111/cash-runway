// swiftlint:disable file_length
import Foundation
import GRDB

private func resolvedCategoryID(_ db: Database, kind: CategoryKind, named name: String) throws -> UUID? {
    if let activeID = try String.fetchOne(
        db,
        sql: "SELECT id FROM categories WHERE kind = ? AND is_archived = 0 AND trim(name) = trim(?) COLLATE NOCASE",
        arguments: [kind.rawValue, name]
    ).flatMap(UUID.init(uuidString:)) {
        return activeID
    }

    var nextID = try String.fetchOne(
        db,
        sql: """
        SELECT cr.new_category_id
        FROM category_remaps cr
        JOIN categories c ON c.id = cr.old_category_id
        WHERE c.kind = ? AND c.is_archived = 1 AND trim(c.name) = trim(?) COLLATE NOCASE
        ORDER BY cr.remapped_at DESC
        LIMIT 1
        """,
        arguments: [kind.rawValue, name]
    )
    var visitedIDs = Set<String>()
    while let currentID = nextID {
        guard visitedIDs.insert(currentID).inserted else { return nil }
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT id, is_archived FROM categories WHERE id = ? AND kind = ?",
            arguments: [currentID, kind.rawValue]
        ) else {
            return nil
        }
        let isArchived: Bool = row["is_archived"]
        if !isArchived {
            return UUID(uuidString: row["id"])
        }
        nextID = try String.fetchOne(
            db,
            sql: """
            SELECT cr.new_category_id
            FROM category_remaps cr
            JOIN categories c ON c.id = cr.old_category_id
            WHERE cr.old_category_id = ? AND c.kind = ?
            ORDER BY cr.remapped_at DESC
            LIMIT 1
            """,
            arguments: [currentID, kind.rawValue]
        )
    }
    return nil
}

public final class CashRunwayRepository: CashRunwayRepositorying, @unchecked Sendable {
    // @unchecked Sendable is justified: `databaseManager` is Sendable (GRDB
    // DatabaseQueue serializes all DB access). `walletsHasCategoryIDColumn`
    // is a `var` cache but is only read/written inside `dbQueue.read/write`
    // callbacks, so GRDB's queue serialization prevents concurrent access.
    public let databaseManager: DatabaseManager
    private var walletsHasCategoryIDColumn: Bool?

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public convenience init(allowsDestructiveRecovery: Bool = false) throws {
        try self.init(databaseManager: DatabaseManager(allowsDestructiveRecovery: allowsDestructiveRecovery))
    }

    private func walletTableHasCategoryID(_ db: Database) throws -> Bool {
        if let cached = walletsHasCategoryIDColumn { return cached }
        let has = try Self.tableHasColumn(db, table: "wallets", column: "category_id")
        walletsHasCategoryIDColumn = has
        return has
    }
}

extension CashRunwayRepository {
    public func seedIfNeeded() throws {
        try databaseManager.dbQueue.write { db in
            let categoryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0
            if categoryCount == 0 {
                let now = Date()
                for (index, category) in SeedCategories.all.enumerated() {
                    try db.execute(
                        sql: """
                        INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, NULL, 1, 0, ?, ?, ?)
                        """,
                        arguments: [
                            category.id.uuidString,
                            category.name,
                            category.kind.rawValue,
                            category.iconName,
                            category.colorHex,
                            index,
                            now,
                            now,
                        ]
                    )
                }
            }

            // Do not auto-create wallets.
            // Do not auto-create budgets.
            // Do not delete or mutate existing user data.
        }
    }

    public func wallets() throws -> [Wallet] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM wallets WHERE is_archived = 0 ORDER BY sort_order, name").map(Self.wallet)
        }
    }

    public func walletCategories() throws -> [WalletCategory] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM wallet_categories
                ORDER BY
                    is_system DESC,
                    CASE
                        WHEN is_system = 1 THEN
                            CASE kind
                                WHEN 'cash' THEN 0
                                WHEN 'card' THEN 1
                                WHEN 'account' THEN 2
                                ELSE 3
                            END
                        ELSE LOWER(name)
                    END
                """
            ).map(Self.walletCategory)
        }
    }

    public func categories(kind: CategoryKind? = nil) throws -> [Category] {
        try databaseManager.dbQueue.read { db in
            if let kind {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM categories WHERE is_archived = 0 AND kind = ? ORDER BY sort_order, name",
                    arguments: [kind.rawValue]
                ).map(Self.category)
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM categories WHERE is_archived = 0 ORDER BY kind, sort_order, name").map(Self.category)
        }
    }

    public func labels() throws -> [Label] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM labels ORDER BY name").map(Self.label)
        }
    }

    public func bankIntegrations() throws -> [BankIntegration] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM bank_integrations ORDER BY created_at, display_name").map(Self.bankIntegration)
        }
    }

    public func activeBankIntegrations() throws -> [BankIntegration] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM bank_integrations WHERE status = ? ORDER BY created_at, display_name",
                arguments: [BankIntegrationStatus.active.rawValue]
            ).map(Self.bankIntegration)
        }
    }

    public func bankAccounts(integrationID: UUID) throws -> [BankAccount] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM bank_accounts WHERE integration_id = ? ORDER BY display_name",
                arguments: [integrationID.uuidString]
            ).map(Self.bankAccount)
        }
    }

    public func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM bank_accounts WHERE integration_id = ? AND is_enabled = 1 ORDER BY display_name",
                arguments: [integrationID.uuidString]
            ).map(Self.bankAccount)
        }
    }

    public func saveBankIntegration(_ integration: BankIntegration) throws {
        try databaseManager.dbQueue.write { db in
            try Self.saveBankIntegration(integration, db: db)
        }
    }

    public func saveBankAccount(_ account: BankAccount) throws {
        try databaseManager.dbQueue.write { db in
            try Self.saveBankAccount(account, db: db)
        }
    }

    public func saveBankConnection(integration: BankIntegration, accounts: [BankAccount]) throws {
        try databaseManager.dbQueue.write { db in
            try Self.saveBankIntegration(integration, db: db)
            for account in accounts {
                try Self.saveBankAccount(account, db: db)
            }
        }
    }

    private static func saveBankIntegration(_ integration: BankIntegration, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO bank_integrations (
                id, provider, display_name, status, sync_start_at, token_keychain_account,
                last_client_info_sync_at, last_successful_sync_at, last_sync_error, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider = excluded.provider,
                display_name = excluded.display_name,
                status = excluded.status,
                sync_start_at = bank_integrations.sync_start_at,
                token_keychain_account = excluded.token_keychain_account,
                last_client_info_sync_at = excluded.last_client_info_sync_at,
                last_successful_sync_at = excluded.last_successful_sync_at,
                last_sync_error = excluded.last_sync_error,
                updated_at = excluded.updated_at
            """,
            arguments: [
                integration.id.uuidString,
                integration.provider.rawValue,
                integration.displayName,
                integration.status.rawValue,
                integration.syncStartAt,
                integration.tokenKeychainAccount,
                integration.lastClientInfoSyncAt,
                integration.lastSuccessfulSyncAt,
                integration.lastSyncError,
                integration.createdAt,
                integration.updatedAt,
            ]
        )
    }

    private static func saveBankAccount(_ account: BankAccount, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO bank_accounts (
                id, integration_id, provider, provider_account_id, wallet_id, display_name,
                account_type, currency_code, masked_pan, iban, is_enabled, sync_start_at,
                last_successful_sync_at, last_statement_item_time, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                integration_id = excluded.integration_id,
                provider = excluded.provider,
                provider_account_id = excluded.provider_account_id,
                wallet_id = excluded.wallet_id,
                display_name = excluded.display_name,
                account_type = excluded.account_type,
                currency_code = excluded.currency_code,
                masked_pan = excluded.masked_pan,
                iban = excluded.iban,
                is_enabled = excluded.is_enabled,
                sync_start_at = bank_accounts.sync_start_at,
                last_successful_sync_at = excluded.last_successful_sync_at,
                last_statement_item_time = excluded.last_statement_item_time,
                updated_at = excluded.updated_at
            """,
            arguments: [
                account.id.uuidString,
                account.integrationID.uuidString,
                account.provider.rawValue,
                account.providerAccountID,
                account.walletID.uuidString,
                account.displayName,
                account.accountType,
                account.currencyCode,
                account.maskedPAN,
                account.iban,
                account.isEnabled,
                account.syncStartAt,
                account.lastSuccessfulSyncAt,
                account.lastStatementItemTime,
                account.createdAt,
                account.updatedAt,
            ]
        )
    }

    public func markBankAccountSynced(_ accountID: UUID, at date: Date) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_accounts
                SET last_successful_sync_at = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [date, date, accountID.uuidString]
            )
        }
    }

    public func markBankIntegrationSynced(_ integrationID: UUID, at date: Date) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_integrations
                SET status = ?, last_successful_sync_at = ?, last_sync_error = NULL, updated_at = ?
                WHERE id = ?
                """,
                arguments: [BankIntegrationStatus.active.rawValue, date, date, integrationID.uuidString]
            )
        }
    }

    public func recordBankSyncError(integrationID: UUID, error: String, at date: Date) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_integrations
                SET last_sync_error = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [error, date, integrationID.uuidString]
            )
        }
    }

    public func disableBankIntegration(_ integrationID: UUID, at date: Date = Date()) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_integrations
                SET status = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [BankIntegrationStatus.disabled.rawValue, date, integrationID.uuidString]
            )
        }
    }

    public func importedBankExpenseCount(integrationID: UUID) throws -> Int {
        try databaseManager.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM bank_transaction_imports
                WHERE integration_id = ? AND import_status = ? AND cash_runway_transaction_id IS NOT NULL
                """,
                arguments: [integrationID.uuidString, BankTransactionImportStatus.imported.rawValue]
            ) ?? 0
        }
    }

    public func bankConnectionStatus(provider: BankProvider) throws -> BankConnectionStatusSnapshot {
        let integrations = try bankIntegrations().filter { $0.provider == provider }
        guard let integration = integrations.first(where: { $0.status == .active }) ?? integrations.first else {
            return BankConnectionStatusSnapshot(
                integration: nil,
                enabledAccountCount: 0,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            )
        }
        let accounts = try bankAccounts(integrationID: integration.id)
        let enabledAccounts = accounts.filter(\.isEnabled)
        let lastAccountSync = enabledAccounts.compactMap(\.lastSuccessfulSyncAt).max()
        return BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: enabledAccounts.count,
            syncStartAt: integration.syncStartAt,
            lastSuccessfulSyncAt: integration.lastSuccessfulSyncAt ?? lastAccountSync,
            lastSyncError: integration.lastSyncError,
            importedExpenseCount: try importedBankExpenseCount(integrationID: integration.id)
        )
    }

    public func learnBankMerchantCategoryRule(transactionID: UUID, categoryID: UUID) throws {
        try databaseManager.dbQueue.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT t.merchant, t.source, i.counter_name, i.description
                FROM transactions t
                LEFT JOIN bank_transaction_imports i ON i.cash_runway_transaction_id = t.id
                WHERE t.id = ?
                """,
                arguments: [transactionID.uuidString]
            ) else {
                throw CashRunwayError.notFound
            }
            guard (row["source"] as String) == TransactionSource.bankSync.rawValue else {
                throw CashRunwayError.validation(L10n.string("Category learning is available only for bank sync transactions."))
            }
            let merchant = [
                row["counter_name"] as String?,
                row["merchant"] as String?,
                row["description"] as String?,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            guard let merchant else {
                throw CashRunwayError.validation(L10n.string("Bank merchant is required to learn a category rule."))
            }
            let now = Date()
            try db.execute(
                sql: """
                INSERT INTO bank_category_rules (
                    id, provider, rule_type, merchant_pattern, mcc, category_id, confidence, created_at, updated_at
                )
                VALUES (?, ?, 'merchant', ?, NULL, ?, 100, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    merchant,
                    categoryID.uuidString,
                    now,
                    now,
                ]
            )
        }
    }

    public func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? {
        try databaseManager.dbQueue.read { db in
            try existingBankImport(db, provider: provider, providerAccountID: providerAccountID, statementItemID: statementItemID)
        }
    }

    public func importBankExpense(
        provider: BankProvider,
        integration: BankIntegration,
        account: BankAccount,
        externalItem: BankExternalExpenseItem,
        draft: TransactionDraft
    ) throws {
        throw CashRunwayError.validation(L10n.string("Bank expense import is not implemented yet."))
    }

    public func importMonobankExpenseItems(
        _ items: [MonobankStatementItem],
        account: BankAccount,
        integration: BankIntegration
    ) throws -> BankSyncImportResult {
        let resolver = try BankCategoryResolver(repository: self)
        return try databaseManager.dbQueue.write { db in
            var result = BankSyncImportResult()
            let lowerBound = max(integration.syncStartAt, account.syncStartAt)

            for item in items {
                let occurredAt = Date(timeIntervalSince1970: TimeInterval(item.time))
                guard occurredAt >= lowerBound, item.amount < 0, item.currencyCode == ISO4217NumericCurrencyCode.uah else {
                    result.skippedCount += 1
                    continue
                }
                if try existingBankImport(db, provider: .monobank, providerAccountID: account.providerAccountID, statementItemID: item.id) != nil {
                    result.skippedCount += 1
                    continue
                }

                let transactionID = UUID()
                let importID = UUID()
                let now = Date()
                guard let resolvedCategory = resolver.resolve(
                    source: .bankStatement(.monobank),
                    kind: .expense,
                    merchant: item.counterName,
                    description: item.description,
                    rawCategoryName: nil,
                    mcc: item.mcc,
                    originalMcc: item.originalMcc
                ) else {
                    throw CashRunwayError.notFound
                }
                let categoryID = resolvedCategory.categoryID
                let draft = TransactionDraft(
                    id: transactionID,
                    kind: .expense,
                    walletID: account.walletID,
                    amountMinor: abs(item.amount),
                    occurredAt: occurredAt,
                    categoryID: categoryID,
                    merchant: item.counterName ?? item.description,
                    note: item.comment ?? "",
                    source: .bankSync
                )

                try validate(draft)
                try validateTransactionCurrency(db, draft: draft)
                try saveSingleTransaction(db, draft: draft)
                try insertBankTransactionImport(
                    db,
                    id: importID,
                    provider: .monobank,
                    integrationID: integration.id,
                    bankAccountID: account.id,
                    providerAccountID: account.providerAccountID,
                    item: item,
                    cashRunwayTransactionID: transactionID,
                    now: now
                )
                result.importedCount += 1
            }

            return result
        }
    }

    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public func budgets(monthKey: Int) throws -> [BudgetProgress] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT b.*, c.name AS category_name, c.kind AS category_kind, c.icon_name AS category_icon_name, c.color_hex AS category_color_hex,
                       c.parent_id AS category_parent_id, c.is_system AS category_is_system, c.is_archived AS category_is_archived,
                       c.sort_order AS category_sort_order, c.created_at AS category_created_at, c.updated_at AS category_updated_at,
                       COALESCE(s.spent_minor, 0) AS spent_minor,
                       COALESCE(s.remaining_minor, b.limit_minor) AS remaining_minor,
                       COALESCE(s.percent_used_bp, 0) AS percent_used_bp
                FROM budgets b
                JOIN categories c ON c.id = b.category_id
                LEFT JOIN budget_progress_snapshot s ON s.budget_id = b.id AND s.month_key = b.month_key
                WHERE b.month_key = ? AND b.is_archived = 0
                ORDER BY c.name
                """,
                arguments: [monthKey]
            ).map { row in
                BudgetProgress(
                    id: UUID(uuidString: row["id"])!,
                    budget: try Self.budget(row),
                    category: try Self.category(prefixed: "category_", row: row),
                    spentMinor: row["spent_minor"],
                    remainingMinor: row["remaining_minor"],
                    percentUsedBP: row["percent_used_bp"]
                )
            }
        }
    }

    public func recurringTemplates() throws -> [RecurringTemplate] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates ORDER BY created_at DESC").map(Self.recurringTemplate)
        }
    }

    public func recurringInstances() throws -> [RecurringInstance] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recurring_instances ORDER BY due_date").map(Self.recurringInstance)
        }
    }

    public func latestTransactionMonthKey() throws -> Int? {
        try databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(local_month_key) FROM transactions WHERE is_deleted = 0")
        }
    }

    public func saveWalletCategory(_ category: WalletCategory) throws {
        let trimmedName = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CashRunwayError.validation(L10n.string("Category name cannot be empty."))
        }

        try databaseManager.dbQueue.write { db in
            let existing = try Row.fetchAll(db, sql: "SELECT * FROM wallet_categories").map(Self.walletCategory)
            let normalizedNew = trimmedName.lowercased()
            let hasDuplicate = existing.contains {
                $0.id != category.id &&
                $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedNew
            }
            if hasDuplicate {
                throw CashRunwayError.validation(L10n.string("A category with this name already exists."))
            }

            try db.execute(
                sql: """
                INSERT INTO wallet_categories (id, name, kind, is_system, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    kind = excluded.kind,
                    is_system = excluded.is_system,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    category.id.uuidString, trimmedName, category.kind.rawValue,
                    category.isSystem, category.createdAt, category.updatedAt,
                ]
            )
        }
    }

    public func saveWallet(_ wallet: Wallet) throws {
        try databaseManager.dbQueue.write { db in
            try validateWalletCurrencyChange(db, wallet: wallet)
            if try walletTableHasCategoryID(db), try Self.tableHasColumn(db, table: "wallets", column: "currency_code") {
                try db.execute(
                    sql: """
                    INSERT INTO wallets (id, name, kind, category_id, color_hex, icon_name, starting_balance_minor, current_balance_minor, currency_code, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        kind = excluded.kind,
                        category_id = excluded.category_id,
                        color_hex = excluded.color_hex,
                        icon_name = excluded.icon_name,
                        starting_balance_minor = excluded.starting_balance_minor,
                        current_balance_minor = excluded.current_balance_minor,
                        currency_code = excluded.currency_code,
                        is_archived = excluded.is_archived,
                        sort_order = excluded.sort_order,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [
                        wallet.id.uuidString, wallet.name, wallet.kind.rawValue, wallet.categoryID.uuidString,
                        wallet.colorHex, wallet.iconName,
                        wallet.startingBalanceMinor, wallet.currentBalanceMinor, wallet.currencyCode.rawValue, wallet.isArchived, wallet.sortOrder,
                        wallet.createdAt, wallet.updatedAt,
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        kind = excluded.kind,
                        color_hex = excluded.color_hex,
                        icon_name = excluded.icon_name,
                        starting_balance_minor = excluded.starting_balance_minor,
                        current_balance_minor = excluded.current_balance_minor,
                        is_archived = excluded.is_archived,
                        sort_order = excluded.sort_order,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [
                        wallet.id.uuidString, wallet.name, wallet.kind.rawValue, wallet.colorHex, wallet.iconName,
                        wallet.startingBalanceMinor, wallet.currentBalanceMinor, wallet.isArchived, wallet.sortOrder,
                        wallet.createdAt, wallet.updatedAt,
                    ]
                )
            }
        }
    }

    public func canChangeWalletCurrency(id: UUID) throws -> Bool {
        try databaseManager.dbQueue.read { db in
            guard try Self.tableHasColumn(db, table: "wallets", column: "currency_code"),
                  let row = try Row.fetchOne(
                    db,
                    sql: "SELECT starting_balance_minor, current_balance_minor FROM wallets WHERE id = ?",
                    arguments: [id.uuidString]
                  )
            else {
                return true
            }

            let existingStarting: Int64 = row["starting_balance_minor"]
            let existingCurrent: Int64 = row["current_balance_minor"]
            guard existingStarting == 0,
                  existingCurrent == 0,
                  try dependentCurrencyDataCount(db, walletID: id) == 0
            else {
                return false
            }

            return true
        }
    }

    public func deleteWallet(id: UUID) throws {
        let activeCount = try databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wallets WHERE is_archived = 0") ?? 0
        }
        guard activeCount > 1 else {
            throw CashRunwayError.validation(L10n.string("At least one active wallet must remain."))
        }

        let txIDs = try databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, linked_transfer_id FROM transactions WHERE wallet_id = ?",
                arguments: [id.uuidString]
            )
            var ids = Set<UUID>()
            for row in rows {
                if let txID = UUID(uuidString: row["id"]) {
                    ids.insert(txID)
                }
                if let linkedID = (row["linked_transfer_id"] as String?).flatMap(UUID.init) {
                    ids.insert(linkedID)
                }
            }
            return Array(ids)
        }

        try databaseManager.dbQueue.write { db in
            for txID in txIDs {
                do {
                    try deleteTransaction(id: txID, db: db)
                } catch CashRunwayError.notFound {
                    // Already deleted as a linked transfer; safe to ignore.
                }
            }

            let templateRows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM recurring_templates WHERE wallet_id = ? OR counterparty_wallet_id = ?",
                arguments: [id.uuidString, id.uuidString]
            )
            for row in templateRows {
                let templateID: String = row["id"]
                try db.execute(sql: "DELETE FROM recurring_instances WHERE template_id = ?", arguments: [templateID])
                try db.execute(sql: "DELETE FROM recurring_templates WHERE id = ?", arguments: [templateID])
            }

            try db.execute(sql: "DELETE FROM monthly_wallet_cashflow WHERE wallet_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM daily_wallet_balance_delta WHERE wallet_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM wallets WHERE id = ?", arguments: [id.uuidString])
            try rebuildFTS(db)
        }
    }

    public func deleteLabel(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM transaction_labels WHERE label_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM labels WHERE id = ?", arguments: [id.uuidString])
            try rebuildFTS(db)
        }
    }

    public func saveCategory(_ category: Category) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    kind = excluded.kind,
                    icon_name = excluded.icon_name,
                    color_hex = excluded.color_hex,
                    parent_id = excluded.parent_id,
                    is_archived = excluded.is_archived,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    category.id.uuidString, category.name, category.kind.rawValue, category.iconName, category.colorHex,
                    category.parentID?.uuidString, category.isSystem, category.isArchived, category.sortOrder,
                    category.createdAt, category.updatedAt,
                ]
            )
        }
    }

    public func saveLabel(_ label: Label) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO labels (id, name, color_hex, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    color_hex = excluded.color_hex,
                    updated_at = excluded.updated_at
                """,
                arguments: [label.id.uuidString, label.name, label.colorHex, label.createdAt, label.updatedAt]
            )
        }
    }

    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public func saveBudget(_ budget: Budget) throws {
        guard budget.limitMinor > 0 else {
            throw CashRunwayError.validation("Budget limit must be greater than zero.")
        }

        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    category_id = excluded.category_id,
                    month_key = excluded.month_key,
                    limit_minor = excluded.limit_minor,
                    is_archived = excluded.is_archived,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    budget.id.uuidString, budget.categoryID.uuidString, budget.monthKey, budget.limitMinor,
                    budget.isArchived, budget.createdAt, budget.updatedAt,
                ]
            )
            try recomputeBudgetSnapshots(db, monthKeys: [budget.monthKey])
        }
    }

    public func saveRecurringTemplate(_ template: RecurringTemplate) throws {
        try databaseManager.dbQueue.write { db in
            try validateRecurringTemplateCurrency(db, template: template)
            if try !Self.tableHasColumn(db, table: "recurring_templates", column: "currency_code") {
                try db.execute(
                    sql: """
                    INSERT INTO recurring_templates (id, kind, wallet_id, counterparty_wallet_id, amount_minor, category_id, merchant, note, rule_type, rule_interval, day_of_month, weekday, start_date, end_date, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        kind = excluded.kind,
                        wallet_id = excluded.wallet_id,
                        counterparty_wallet_id = excluded.counterparty_wallet_id,
                        amount_minor = excluded.amount_minor,
                        category_id = excluded.category_id,
                        merchant = excluded.merchant,
                        note = excluded.note,
                        rule_type = excluded.rule_type,
                        rule_interval = excluded.rule_interval,
                        day_of_month = excluded.day_of_month,
                        weekday = excluded.weekday,
                        start_date = excluded.start_date,
                        end_date = excluded.end_date,
                        is_active = excluded.is_active,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [
                        template.id.uuidString, template.kind.rawValue, template.walletID.uuidString,
                        template.counterpartyWalletID?.uuidString, template.amountMinor, template.categoryID?.uuidString,
                        template.merchant, template.note, template.ruleType.rawValue, template.ruleInterval,
                        template.dayOfMonth, template.weekday, template.startDate, template.endDate, template.isActive,
                        template.createdAt, template.updatedAt,
                    ]
                )
                try refreshRecurringInstances(db)
                return
            }

            try db.execute(
                sql: """
                INSERT INTO recurring_templates (id, kind, wallet_id, counterparty_wallet_id, amount_minor, currency_code, category_id, merchant, note, rule_type, rule_interval, day_of_month, weekday, start_date, end_date, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    wallet_id = excluded.wallet_id,
                    counterparty_wallet_id = excluded.counterparty_wallet_id,
                    amount_minor = excluded.amount_minor,
                    currency_code = excluded.currency_code,
                    category_id = excluded.category_id,
                    merchant = excluded.merchant,
                    note = excluded.note,
                    rule_type = excluded.rule_type,
                    rule_interval = excluded.rule_interval,
                    day_of_month = excluded.day_of_month,
                    weekday = excluded.weekday,
                    start_date = excluded.start_date,
                    end_date = excluded.end_date,
                    is_active = excluded.is_active,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    template.id.uuidString, template.kind.rawValue, template.walletID.uuidString,
                    template.counterpartyWalletID?.uuidString, template.amountMinor, template.currencyCode.rawValue, template.categoryID?.uuidString,
                    template.merchant, template.note, template.ruleType.rawValue, template.ruleInterval,
                    template.dayOfMonth, template.weekday, template.startDate, template.endDate, template.isActive,
                    template.createdAt, template.updatedAt,
                ]
            )
            try refreshRecurringInstances(db)
        }
    }

    public func saveRecurringInstance(_ instance: RecurringInstance) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE recurring_instances
                SET due_date = ?, day_key = ?, status = ?, linked_transaction_id = ?, override_amount_minor = ?, override_category_id = ?, override_note = ?, override_merchant = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    instance.dueDate,
                    instance.dayKey,
                    instance.status.rawValue,
                    instance.linkedTransactionID?.uuidString,
                    instance.overrideAmountMinor,
                    instance.overrideCategoryID?.uuidString,
                    instance.overrideNote,
                    instance.overrideMerchant,
                    instance.updatedAt,
                    instance.id.uuidString,
                ]
            )
        }
    }

    public func dashboard(monthKey: Int, walletID: UUID? = nil) throws -> DashboardSnapshot {
        try databaseManager.dbQueue.read { db in
            try rejectMixedCurrencyAllWalletSnapshot(db, walletID: walletID)
            let totalBalanceMinor: Int64
            if let walletID {
                totalBalanceMinor = try Int64.fetchOne(db, sql: "SELECT current_balance_minor FROM wallets WHERE id = ?", arguments: [walletID.uuidString]) ?? 0
            } else {
                totalBalanceMinor = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(current_balance_minor), 0) FROM wallets WHERE is_archived = 0") ?? 0
            }

            let monthCashflowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT income_minor, expense_minor, transfer_in_minor, transfer_out_minor
                FROM monthly_wallet_cashflow
                WHERE month_key = ?
                \(walletID == nil ? "" : "AND wallet_id = ?")
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )

            let monthIncomeMinor = monthCashflowRows.reduce(into: Int64.zero) { $0 += $1["income_minor"] }
            let monthExpenseMinor = monthCashflowRows.reduce(into: Int64.zero) { $0 += $1["expense_minor"] }
            let monthNetMinor = monthIncomeMinor - monthExpenseMinor

            let categoryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.name, c.color_hex, c.icon_name, m.expense_minor, m.txn_count
                FROM monthly_category_spend m
                JOIN categories c ON c.id = m.category_id
                WHERE m.month_key = ? AND m.kind = 'expense'
                  AND (? IS NULL OR m.wallet_id = ?)
                ORDER BY m.expense_minor DESC
                LIMIT 8
                """,
                arguments: [monthKey, walletID?.uuidString, walletID?.uuidString]
            )
            let totalExpense = max(monthExpenseMinor, 1)
            let categories = categoryRows.map { row in
                let amountMinor: Int64 = row["expense_minor"]
                return DashboardCategorySlice(
                    id: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    colorHex: row["color_hex"],
                    iconName: row["icon_name"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(totalExpense)
                )
            }

            let historyRows = try Row.fetchAll(
                db,
                sql: """
                SELECT day_key, COALESCE(SUM(net_delta_minor), 0) AS total
                FROM daily_wallet_balance_delta
                WHERE day_key BETWEEN ? AND ?
                GROUP BY day_key
                ORDER BY day_key
                """,
                arguments: [monthKey * 100 + 1, monthKey * 100 + 31]
            )
            var rollingBalance = totalBalanceMinor - historyRows.reduce(into: Int64.zero) { $0 += $1["total"] }
            let wealthHistory = historyRows.map { row -> BalancePoint in
                rollingBalance += row["total"]
                return BalancePoint(dayKey: row["day_key"], amountMinor: rollingBalance)
            }

            let recentTransactions = try listTransactions(db, query: .init(walletID: walletID))

            return DashboardSnapshot(
                monthKey: monthKey,
                walletFilterID: walletID,
                totalBalanceMinor: totalBalanceMinor,
                monthIncomeMinor: monthIncomeMinor,
                monthExpenseMinor: monthExpenseMinor,
                monthNetMinor: monthNetMinor,
                wealthHistory: wealthHistory,
                categories: categories,
                recentTransactions: Array(recentTransactions.prefix(8))
            )
        }
    }

}

extension CashRunwayRepository {
    public func timelineSnapshot(monthKey: Int, walletID: UUID? = nil, query: TransactionQuery = .init(), period: TimelinePeriod = .month) throws -> TimelineSnapshot {
        try timelineSnapshot(monthKey: monthKey, walletID: walletID, query: query, period: period, now: Date())
    }

    // swiftlint:disable:next function_body_length
    /// Deterministic snapshot overload. Production calls `timelineSnapshot(...)` which
    /// injects `Date()`; tests call this directly with a fixed date so month-to-date and
    /// comparison behavior is reproducible. Not part of `DashboardRepositorying`; keeping
    /// the clock off the protocol avoids forcing unrelated mocks/conformers to change.
    public func timelineSnapshot(monthKey: Int, walletID: UUID?, query: TransactionQuery, period: TimelinePeriod, now: Date) throws -> TimelineSnapshot {
        try databaseManager.dbQueue.read { db in
            let effectiveWalletID = walletID ?? query.walletID
            try rejectMixedCurrencyAllWalletSnapshot(db, walletID: effectiveWalletID)
            let anchorPeriodKey = Self.anchorPeriodKey(monthKey: monthKey, period: period)
            var bars = try Self.loadBars(db, monthKey: monthKey, walletID: effectiveWalletID, period: period)

            let window = TimelineComparisonWindow.comparisonWindow(
                selectedMonthKey: monthKey,
                period: period,
                now: now,
                calendar: DateKeys.calendar
            )

            // For a current partial period, the selected bar must reflect month-to-date /
            // year-to-date actuals rather than the full-period cashflow aggregate.
            if let window, window.isPartial {
                let bounded = try Self.boundedSums(db, walletID: effectiveWalletID, startDayKey: window.currentStartDayKey, endDayKey: window.currentEndDayKey)
                if let selectedIndex = bars.firstIndex(where: { $0.periodKey == anchorPeriodKey }) {
                    var selectedBar = bars[selectedIndex]
                    selectedBar = TimelineBarPoint(
                        periodKey: selectedBar.periodKey,
                        incomeMinor: bounded.income,
                        expenseMinor: bounded.expense,
                        xLabel: selectedBar.xLabel
                    )
                    bars[selectedIndex] = selectedBar
                }
            }

            var scopedQuery = query
            scopedQuery.walletID = effectiveWalletID
            Self.applyPeriodScope(&scopedQuery, period: period, periodKey: anchorPeriodKey)
            let items = try listTransactions(db, query: scopedQuery, limit: nil)
            let sections = Dictionary(grouping: items, by: \.dayKey)
                .map { key, values in
                    TimelineSection(
                        periodKey: key,
                        periodLabel: DateKeys.dayLabel(for: key),
                        totalMinor: values.reduce(into: Int64.zero) { $0 += $1.amountMinor },
                        items: values
                    )
                }
                .sorted { $0.periodKey > $1.periodKey }

            let selectedBar = bars.first(where: { $0.periodKey == anchorPeriodKey }) ?? bars.last
            let heroCashFlow = selectedBar.map { $0.incomeMinor - $0.expenseMinor } ?? 0
            let comparison = try Self.buildComparison(
                db: db,
                walletID: effectiveWalletID,
                window: window,
                selectedBarExpense: selectedBar?.expenseMinor ?? 0
            )

            return TimelineSnapshot(
                anchorMonthKey: monthKey,
                walletFilterID: effectiveWalletID,
                heroCashFlowMinor: heroCashFlow,
                bars: bars,
                sections: sections,
                period: period,
                comparison: comparison
            )
        }
    }

    /// Bounded income/expense sums over an inclusive local-day-key range.
    /// Transfers are excluded by the conditional sums (`type = 'income'`/`'expense'`).
    private static func boundedSums(_ db: Database, walletID: UUID?, startDayKey: Int, endDayKey: Int) throws -> (income: Int64, expense: Int64) {
        let walletArgument: any DatabaseValueConvertible = walletID?.uuidString ?? NSNull()
        let row = try Row.fetchOne(
            db,
            sql: """
            SELECT
                COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE 0 END), 0) AS income_minor,
                COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor ELSE 0 END), 0) AS expense_minor
            FROM transactions
            WHERE is_deleted = 0
              AND local_day_key BETWEEN ? AND ?
              AND (? IS NULL OR wallet_id = ?)
            """,
            arguments: [startDayKey, endDayKey, walletArgument, walletArgument]
        )
        return (row?["income_minor"] ?? 0, row?["expense_minor"] ?? 0)
    }

    /// Bounded expense sum over the baseline window. Excludes income and both transfer
    /// directions by filtering `type = 'expense'`.
    private static func baselineExpense(_ db: Database, walletID: UUID?, startDayKey: Int, endDayKey: Int) throws -> Int64 {
        let walletArgument: any DatabaseValueConvertible = walletID?.uuidString ?? NSNull()
        let value = try Int64.fetchOne(
            db,
            sql: """
            SELECT COALESCE(SUM(amount_minor), 0)
            FROM transactions
            WHERE is_deleted = 0
              AND type = 'expense'
              AND local_day_key BETWEEN ? AND ?
              AND (? IS NULL OR wallet_id = ?)
            """,
            arguments: [startDayKey, endDayKey, walletArgument, walletArgument]
        ) ?? 0
        return value
    }

    /// Derives the comparison, honoring the snapshot invariant that the current expense
    /// equals the selected bar's expense whenever comparison is available.
    private static func buildComparison(
        db: Database,
        walletID: UUID?,
        window: TimelineComparisonWindow?,
        selectedBarExpense: Int64
    ) throws -> TimelineComparison? {
        // Strictly future selected period: retain stored totals, mark comparison unavailable.
        guard let window else { return nil }

        let baselineExpense = try Self.baselineExpense(
            db,
            walletID: walletID,
            startDayKey: window.baselineStartDayKey,
            endDayKey: window.baselineEndDayKey
        )

        // Invariant: comparison current expense mirrors the bounded selected-period bar.
        let currentExpense = selectedBarExpense

        let direction: TimelineComparison.Direction
        let percentage: Double?

        switch (currentExpense, baselineExpense) {
        case let (current, baseline) where current > baseline && baseline > 0:
            direction = .higher
            percentage = Self.percentageChange(current: current, baseline: baseline)
        case let (current, baseline) where current < baseline && baseline > 0:
            direction = .lower
            percentage = Self.percentageChange(current: current, baseline: baseline)
        case let (current, baseline) where current == baseline:
            // Equal, including both-zero: unchanged. Never NaN/infinity.
            direction = .unchanged
            percentage = baseline > 0 ? 0.0 : nil
        case let (current, baseline) where baseline == 0 && current > 0:
            // New spending with no baseline to compare against.
            direction = .unavailable
            percentage = nil
        default:
            // Defensive catch-all (e.g. negative guards): treat as unavailable.
            direction = .unavailable
            percentage = nil
        }

        return TimelineComparison(
            direction: direction,
            currentExpenseMinor: currentExpense,
            baselineExpenseMinor: baselineExpense,
            percentageChange: percentage,
            baselineStartDayKey: window.baselineStartDayKey,
            baselineEndDayKey: window.baselineEndDayKey,
            isPartialPeriod: window.isPartial
        )
    }

    private static func percentageChange(current: Int64, baseline: Int64) -> Double? {
        guard baseline > 0 else { return nil }
        return Double(current - baseline) / Double(baseline)
    }

    private static func anchorPeriodKey(monthKey: Int, period: TimelinePeriod) -> Int {
        let anchorDate = DateKeys.startOfMonth(for: monthKey)
        return DateKeys.periodKey(for: anchorDate, period: period)
    }

    private static func loadBars(_ db: Database, monthKey: Int, walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint] {
        switch period {
        case .month:
            return try loadMonthlyBars(db, monthKey: monthKey, walletID: walletID)
        case .year:
            return try loadYearlyBars(db, monthKey: monthKey, walletID: walletID)
        }
    }

    private static func loadMonthlyBars(_ db: Database, monthKey: Int, walletID: UUID?) throws -> [TimelineBarPoint] {
        let months = Self.monthWindow(endingAt: monthKey, count: 6)
        var conditions = ["month_key BETWEEN ? AND ?"]
        var arguments: [any DatabaseValueConvertible] = [months.first ?? monthKey, months.last ?? monthKey]
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(arguments)
        )
        let byMonth = Dictionary(uniqueKeysWithValues: rows.map { row in
            let month: Int = row["month_key"]
            return (
                month,
                TimelineBarPoint(
                    periodKey: month,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: monthLabel(for: month)
                )
            )
        })
        return months.map { month in
            byMonth[month] ?? TimelineBarPoint(periodKey: month, incomeMinor: 0, expenseMinor: 0, xLabel: monthLabel(for: month))
        }
    }

    private static func loadYearlyBars(_ db: Database, monthKey: Int, walletID: UUID?) throws -> [TimelineBarPoint] {
        let year = monthKey / 100
        let years = Self.yearWindow(endingAt: year, count: 6)
        let startMonth = (year - 5) * 100 + 1
        let endMonth = year * 100 + 12
        var conditions = ["month_key BETWEEN ? AND ?"]
        var arguments: [any DatabaseValueConvertible] = [startMonth, endMonth]
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(arguments)
        )
        var byYear: [Int: (income: Int64, expense: Int64)] = [:]
        for row in rows {
            let month: Int = row["month_key"]
            let yearKey = month / 100
            var current = byYear[yearKey] ?? (0, 0)
            current.income += row["income_minor"]
            current.expense += row["expense_minor"]
            byYear[yearKey] = current
        }
        return years.map { yearKey in
            let values = byYear[yearKey] ?? (0, 0)
            return TimelineBarPoint(
                periodKey: yearKey,
                incomeMinor: values.income,
                expenseMinor: values.expense,
                xLabel: "\(yearKey)"
            )
        }
    }

    public func allBars(walletID: UUID? = nil, period: TimelinePeriod = .month) throws -> [TimelineBarPoint] {
        try databaseManager.dbQueue.read { db in
            try rejectMixedCurrencyAllWalletSnapshot(db, walletID: walletID)
            switch period {
            case .month:
                return try Self.loadAllMonthlyBars(db, walletID: walletID)
            case .year:
                return try Self.loadAllYearlyBars(db, walletID: walletID)
            }
        }
    }

    private static func loadAllMonthlyBars(_ db: Database, walletID: UUID?) throws -> [TimelineBarPoint] {
        var conditions: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let minMaxRow = try Row.fetchOne(db, sql: """
            SELECT MIN(month_key) as min_month, MAX(month_key) as max_month
            FROM monthly_wallet_cashflow
            \(whereClause)
            """, arguments: StatementArguments(arguments))

        guard let minMonth: Int = minMaxRow?["min_month"],
              let maxMonth: Int = minMaxRow?["max_month"] else {
            return []
        }

        var months: [Int] = []
        var current = minMonth
        while current <= maxMonth {
            months.append(current)
            if let nextDate = DateKeys.calendar.date(byAdding: .month, value: 1, to: DateKeys.startOfMonth(for: current)) {
                current = DateKeys.monthKey(for: nextDate)
            } else {
                break
            }
        }

        var dataConditions = ["month_key BETWEEN ? AND ?"]
        var dataArguments: [any DatabaseValueConvertible] = [minMonth, maxMonth]
        if let walletID {
            dataConditions.append("wallet_id = ?")
            dataArguments.append(walletID.uuidString)
        }
        let dataRows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(dataConditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(dataArguments)
        )
        let byMonth = Dictionary(uniqueKeysWithValues: dataRows.map { row in
            let month: Int = row["month_key"]
            return (
                month,
                TimelineBarPoint(
                    periodKey: month,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: monthLabel(for: month)
                )
            )
        })
        return months.map { month in
            byMonth[month] ?? TimelineBarPoint(periodKey: month, incomeMinor: 0, expenseMinor: 0, xLabel: monthLabel(for: month))
        }
    }

    private static func loadAllYearlyBars(_ db: Database, walletID: UUID?) throws -> [TimelineBarPoint] {
        var conditions: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let minMaxRow = try Row.fetchOne(db, sql: """
            SELECT MIN(month_key / 100) as min_year, MAX(month_key / 100) as max_year
            FROM monthly_wallet_cashflow
            \(whereClause)
            """, arguments: StatementArguments(arguments))

        guard let minYear: Int = minMaxRow?["min_year"],
              let maxYear: Int = minMaxRow?["max_year"] else {
            return []
        }

        let years = Array(minYear...maxYear)

        var dataConditions = ["month_key / 100 BETWEEN ? AND ?"]
        var dataArguments: [any DatabaseValueConvertible] = [minYear, maxYear]
        if let walletID {
            dataConditions.append("wallet_id = ?")
            dataArguments.append(walletID.uuidString)
        }
        let dataRows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key / 100 as year,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(dataConditions.joined(separator: " AND "))
            GROUP BY year
            ORDER BY year
            """,
            arguments: StatementArguments(dataArguments)
        )
        let byYear = Dictionary(uniqueKeysWithValues: dataRows.map { row in
            let year: Int = row["year"]
            return (
                year,
                TimelineBarPoint(
                    periodKey: year,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: "\(year)"
                )
            )
        })
        return years.map { year in
            byYear[year] ?? TimelineBarPoint(periodKey: year, incomeMinor: 0, expenseMinor: 0, xLabel: "\(year)")
        }
    }

    private static func applyPeriodScope(_ query: inout TransactionQuery, period: TimelinePeriod, periodKey: Int) {
        let bounds = periodDateBounds(period: period, periodKey: periodKey)
        if let startDate = query.startDate {
            query.startDate = max(startDate, bounds.start)
        } else {
            query.startDate = bounds.start
        }
        if let endDate = query.endDate {
            query.endDate = min(endDate, bounds.end)
        } else {
            query.endDate = bounds.end
        }
    }

    private static func periodDateBounds(period: TimelinePeriod, periodKey: Int) -> (start: Date, end: Date) {
        switch period {
        case .month:
            return (DateKeys.startOfMonth(for: periodKey), endOfMonth(for: periodKey))
        case .year:
            let startMonthKey = periodKey * 100 + 1
            let endMonthKey = periodKey * 100 + 12
            return (DateKeys.startOfMonth(for: startMonthKey), endOfMonth(for: endMonthKey))
        }
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func monthAbbreviation(for monthKey: Int) -> String {
        let month = monthKey % 100
        guard month >= 1 && month <= 12 else { return "" }
        return monthAbbreviations[month - 1]
    }

    private static func monthLabel(for monthKey: Int) -> String {
        let abbreviation = monthAbbreviation(for: monthKey)
        let year = monthKey / 100
        return "\(abbreviation)\n\(year)"
    }

    // swiftlint:disable:next function_body_length
    public func overviewSnapshot(monthKey: Int, walletID: UUID? = nil) throws -> OverviewSnapshot {
        try databaseManager.dbQueue.read { db in
            try rejectMixedCurrencyAllWalletSnapshot(db, walletID: walletID)
            let months = Self.monthWindow(endingAt: monthKey, count: 6)
            let cashflowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT month_key,
                       COALESCE(SUM(income_minor), 0) AS income_minor,
                       COALESCE(SUM(expense_minor), 0) AS expense_minor
                FROM monthly_wallet_cashflow
                WHERE month_key BETWEEN ? AND ?
                \(walletID == nil ? "" : "AND wallet_id = ?")
                GROUP BY month_key
                ORDER BY month_key
                """,
                arguments: walletID == nil
                    ? [months.first ?? monthKey, months.last ?? monthKey]
                    : [months.first ?? monthKey, months.last ?? monthKey, walletID!.uuidString]
            )
            let cashflowByMonth = Dictionary(uniqueKeysWithValues: cashflowRows.map { row in
                let month: Int = row["month_key"]
                return (month, (income: row["income_minor"] as Int64, expense: row["expense_minor"] as Int64))
            })

            let balances = try self.monthEndBalances(for: months + [monthKey], walletID: walletID, db: db)

            let monthPoints = months.map { month in
                let values = cashflowByMonth[month] ?? (income: Int64.zero, expense: Int64.zero)
                return OverviewMonthPoint(
                    monthKey: month,
                    totalWealthMinor: balances[month] ?? 0,
                    cashFlowMinor: values.income - values.expense,
                    incomeMinor: values.income,
                    expenseMinor: values.expense
                )
            }

            let selectedPoint: OverviewMonthPoint
            if let existingPoint = monthPoints.first(where: { $0.monthKey == monthKey }) {
                selectedPoint = existingPoint
            } else {
                selectedPoint = OverviewMonthPoint(
                    monthKey: monthKey,
                    totalWealthMinor: balances[monthKey] ?? 0,
                    cashFlowMinor: 0,
                    incomeMinor: 0,
                    expenseMinor: 0
                )
            }

            let categoryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.name, c.kind, c.color_hex, c.icon_name,
                       COALESCE(SUM(m.expense_minor), 0) AS expense_minor,
                       COALESCE(SUM(m.income_minor), 0) AS income_minor,
                       COALESCE(SUM(m.txn_count), 0) AS txn_count
                FROM categories c
                LEFT JOIN monthly_category_spend m
                  ON m.category_id = c.id
                 AND m.month_key = ?
                 \(walletID == nil ? "" : "AND m.wallet_id = ?")
                WHERE c.kind IN ('expense', 'income')
                GROUP BY c.id
                HAVING (expense_minor > 0 OR income_minor > 0)
                ORDER BY c.kind, expense_minor DESC, c.sort_order, c.name
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )
            let totalExpense = max(selectedPoint.expenseMinor, 1)
            let totalIncome = max(selectedPoint.incomeMinor, 1)
            let categories = categoryRows.map { row in
                let kind = CategoryKind(rawValue: row["kind"]) ?? .expense
                let amountMinor: Int64 = kind == .expense ? row["expense_minor"] : row["income_minor"]
                let transactionCount: Int = row["txn_count"]
                return OverviewCategoryRow(
                    id: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    kind: kind,
                    colorHex: row["color_hex"],
                    iconName: row["icon_name"],
                    amountMinor: amountMinor,
                    transactionCount: transactionCount,
                    percentage: Double(amountMinor) / Double(kind == .expense ? totalExpense : totalIncome)
                )
            }

            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT l.id, l.name, l.color_hex, m.kind,
                       COALESCE(SUM(m.amount_minor), 0) AS label_minor,
                       COALESCE(SUM(m.txn_count), 0) AS txn_count
                FROM labels l
                JOIN monthly_label_spend m
                  ON m.label_id = l.id
                 AND m.month_key = ?
                 \(walletID == nil ? "" : "AND m.wallet_id = ?")
                GROUP BY l.id, m.kind
                HAVING label_minor > 0
                ORDER BY m.kind, label_minor DESC, l.name
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )
            let labels = labelRows.map { row in
                let amountMinor: Int64 = row["label_minor"]
                let kind = CategoryKind(rawValue: row["kind"]) ?? .expense
                return OverviewLabelRow(
                    labelID: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    kind: kind,
                    colorHex: row["color_hex"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(kind == .expense ? totalExpense : totalIncome)
                )
            }

            return OverviewSnapshot(
                selectedMonthKey: monthKey,
                walletFilterID: walletID,
                months: monthPoints,
                totalWealthMinor: selectedPoint.totalWealthMinor,
                monthCashFlowMinor: selectedPoint.cashFlowMinor,
                monthIncomeMinor: selectedPoint.incomeMinor,
                monthExpenseMinor: selectedPoint.expenseMinor,
                categories: categories,
                labels: labels
            )
        }
    }

    public func categoryManagementItems(kind: CategoryKind) throws -> [CategoryManagementItem] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT c.*,
                       COUNT(DISTINCT t.id) AS txn_count,
                       COUNT(DISTINCT t.wallet_id) AS wallet_count
                FROM categories c
                LEFT JOIN transactions t
                  ON t.category_id = c.id
                 AND t.is_deleted = 0
                 AND t.type != 'transfer_in'
                WHERE c.kind = ?
                GROUP BY c.id
                ORDER BY c.sort_order, c.name
                """,
                arguments: [kind.rawValue]
            ).map { row in
                let category = try Self.category(row)
                return CategoryManagementItem(
                    category: category,
                    transactionCount: row["txn_count"],
                    walletCount: row["wallet_count"],
                    isVisible: !category.isArchived
                )
            }
        }
    }

}

extension CashRunwayRepository {
    public func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) throws {
        try databaseManager.dbQueue.write { db in
            for (index, id) in orderedCategoryIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE categories SET sort_order = ?, updated_at = ? WHERE id = ? AND kind = ?",
                    arguments: [index, Date.now, id.uuidString, kind.rawValue]
                )
            }
        }
    }

    public func transactions(query: TransactionQuery = .init(), limit: Int? = 300) throws -> [TransactionListItem] {
        try databaseManager.dbQueue.read { db in
            try listTransactions(db, query: query, limit: limit)
        }
    }

    public func transactionDraft(id: UUID) throws -> TransactionDraft {
        try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let transaction = try Self.transaction(row)
            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT label_id FROM transaction_labels WHERE transaction_id = ?
                UNION ALL
                SELECT label_id FROM transaction_labels WHERE transaction_id = ?
                """,
                arguments: [id.uuidString, transaction.linkedTransferID?.uuidString]
            )
            let labelIDs = labelRows.compactMap { UUID(uuidString: $0["label_id"]) }

            if transaction.type == .transferOut || transaction.type == .transferIn {
                guard let linkedID = transaction.linkedTransferID,
                      let linkedWalletID = try String.fetchOne(db, sql: "SELECT wallet_id FROM transactions WHERE id = ?", arguments: [linkedID.uuidString]).flatMap(UUID.init(uuidString:))
                else {
                    throw CashRunwayError.invalidState(L10n.string("Transfer pair is missing."))
                }
                let sourceWalletID = transaction.type == .transferOut ? transaction.walletID : linkedWalletID
                let destinationWalletID = transaction.type == .transferOut ? linkedWalletID : transaction.walletID
                return TransactionDraft(
                    id: sourceWalletID == transaction.walletID ? transaction.id : linkedID,
                    kind: .transfer,
                    walletID: sourceWalletID,
                    destinationWalletID: destinationWalletID,
                    amountMinor: transaction.amountMinor,
                    currencyCode: transaction.currencyCode,
                    occurredAt: transaction.occurredAt,
                    labelIDs: labelIDs,
                    merchant: transaction.merchant ?? "",
                    note: transaction.note ?? "",
                    source: transaction.source,
                    recurringTemplateID: transaction.recurringTemplateID,
                    recurringInstanceID: transaction.recurringInstanceID
                )
            }

            return TransactionDraft(
                id: transaction.id,
                kind: transaction.type == .expense ? .expense : .income,
                walletID: transaction.walletID,
                amountMinor: transaction.amountMinor,
                currencyCode: transaction.currencyCode,
                occurredAt: transaction.occurredAt,
                categoryID: transaction.categoryID,
                labelIDs: labelIDs,
                merchant: transaction.merchant ?? "",
                note: transaction.note ?? "",
                source: transaction.source,
                recurringTemplateID: transaction.recurringTemplateID,
                recurringInstanceID: transaction.recurringInstanceID
            )
        }
    }

    public func saveTransaction(_ draft: TransactionDraft) throws {
        try validate(draft)
        try databaseManager.dbQueue.write { db in
            try validateTransactionCurrency(db, draft: draft)
            if draft.kind == .transfer {
                try saveTransfer(db, draft: draft)
            } else {
                try saveSingleTransaction(db, draft: draft)
            }
        }
    }

    public func deleteTransaction(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            try deleteTransaction(id: id, db: db)
        }
    }

    private func deleteTransaction(id: UUID, db: Database) throws {
        guard let transactionRow = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
            throw CashRunwayError.notFound
        }
        let transaction = try Self.transaction(transactionRow)

        var transactionsToDelete = [transaction]
        if transaction.type == .transferOut || transaction.type == .transferIn,
           let linkedID = transaction.linkedTransferID,
           let linkedRow = try Row.fetchOne(
            db,
            sql: "SELECT * FROM transactions WHERE id = ?",
            arguments: [linkedID.uuidString]
           ) {
            transactionsToDelete.append(try Self.transaction(linkedRow))
        }

        for item in transactionsToDelete {
            let labelIDs: [UUID] = try String.fetchAll(
                db,
                sql: "SELECT label_id FROM transaction_labels WHERE transaction_id = ?",
                arguments: [item.id.uuidString]
            ).compactMap(UUID.init(uuidString:))
            try applyContribution(db, old: contribution(for: item, labelIDs: labelIDs), new: nil)
        }
        let idStrings = transactionsToDelete.map { $0.id.uuidString }
        try Self.cleanupTransactionReferences(db: db, idStrings: idStrings)
    }

    /// Counts transactions that would be removed for `period`, split by financial
    /// impact. `expenseMinor` / `incomeMinor` are absolute magnitudes so they render
    /// correctly regardless of the stored sign. Used to preview impact before a bulk
    /// delete. Transfers are counted in `count` but excluded from the money split
    /// (moving money between own wallets is not money gained or lost).
    ///
    /// Uses SQL aggregates rather than loading every matching row, so it stays fast
    /// for large year-scoped histories.
    public func transactionDeletionSummary(for period: DeletePeriod, now: Date = Date()) throws -> TransactionDeletionSummary {
        try databaseManager.dbQueue.read { db in
            let (predicate, arguments) = Self.deletePeriodPredicate(period, now: now)
            let hasCurrencyColumn = try Self.tableHasColumn(db, table: "transactions", column: "currency_code")
            let currencySelect = hasCurrencyColumn
                ? "COALESCE(GROUP_CONCAT(DISTINCT currency_code), '') AS currency_codes"
                : "'UAH' AS currency_codes"
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    COUNT(*) AS count,
                    COALESCE(SUM(CASE WHEN type != 'transfer_in' THEN 1 ELSE 0 END), 0) AS display_count,
                    COALESCE(SUM(CASE WHEN type = 'expense' THEN ABS(amount_minor) ELSE 0 END), 0) AS expense_minor,
                    COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE 0 END), 0) AS income_minor,
                    \(currencySelect)
                FROM transactions
                WHERE \(predicate)
                """,
                arguments: arguments
            )!
            let currencyCodesString: String = row["currency_codes"]
            let currencyCodes = Set(currencyCodesString.split(separator: ",").map(String.init))
            let isMixedCurrency = currencyCodes.count > 1
            return TransactionDeletionSummary(
                count: row["count"],
                displayCount: row["display_count"],
                expenseMinor: isMixedCurrency ? 0 : row["expense_minor"],
                incomeMinor: isMixedCurrency ? 0 : row["income_minor"],
                currencyCodes: currencyCodes
            )
        }
    }

    /// Creates an immutable plan of every transaction row that would be deleted for
    /// `period` as of `now`. The plan freezes the calendar scope and the exact row IDs
    /// so that later execution cannot drift to a different day/month/year or a
    /// different set of transactions.
    public func transactionDeletionPlan(for period: DeletePeriod, now: Date = Date()) throws -> TransactionDeletionPlan {
        try databaseManager.dbQueue.read { db in
            let impact = try Self.deletionImpactRows(db, period: period, now: now)
            return TransactionDeletionPlan(
                period: period,
                referenceDayKey: DateKeys.dayKey(for: now),
                referenceMonthKey: DateKeys.monthKey(for: now),
                referenceYear: DateKeys.yearKey(for: now),
                items: impact.items,
                summary: impact.summary
            )
        }
    }

    /// Executes a frozen deletion plan. Recomputes the matching rows from the plan's
    /// reference date keys; if the set of items has changed since preview — including
    /// same-ID mutations detected via `updatedAt` fingerprints — the operation
    /// aborts with `TransactionDeletionError.planStale` so the user must review again.
    /// Otherwise deletes exactly the planned IDs, maintaining aggregates, cascading to
    /// `transaction_labels` / `transaction_search`, and nulling dangling references in
    /// `bank_transaction_imports` / `recurring_instances`. Returns the number of deleted rows.
    @discardableResult
    public func deleteTransactions(_ plan: TransactionDeletionPlan) throws -> Int {
        guard !plan.items.isEmpty else { return 0 }

        return try databaseManager.dbQueue.write { db in
            // Recompute the current matching set from the frozen reference keys.
            let (predicate, arguments) = Self.deletePeriodPredicate(
                plan.period,
                dayKey: plan.referenceDayKey,
                monthKey: plan.referenceMonthKey,
                year: plan.referenceYear
            )
            let currentItems = try Set(
                Row.fetchAll(db, sql: "SELECT id, updated_at FROM transactions WHERE \(predicate)", arguments: arguments)
                    .compactMap { row -> TransactionDeletionItem? in
                        guard let id = UUID(uuidString: row["id"]) else { return nil }
                        let updatedAt: String = row["updated_at"]
                        return TransactionDeletionItem(id: id, updatedAt: updatedAt)
                    }
            )
            let plannedItems = Set(plan.items)
            guard currentItems == plannedItems else {
                throw TransactionDeletionError.planStale
            }

            // Apply aggregate reversals before deleting so dashboard/category totals
            // remain consistent even when the row disappears. The prior guard guarantees
            // every planned item still exists unchanged.
            for item in plan.items {
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [item.id.uuidString]) else {
                    continue
                }
                let transaction = try Self.transaction(row)
                let labelIDs: [UUID] = try String.fetchAll(
                    db,
                    sql: "SELECT label_id FROM transaction_labels WHERE transaction_id = ?",
                    arguments: [transaction.id.uuidString]
                ).compactMap(UUID.init(uuidString:))
                try applyContribution(db, old: contribution(for: transaction, labelIDs: labelIDs), new: nil)
            }

            let idStrings = plan.transactionIDs.map { $0.uuidString }
            try Self.cleanupTransactionReferences(db: db, idStrings: idStrings)

            return plan.items.count
        }
    }

    /// Deletes labels/search rows, nulls dangling FKs in bank_transaction_imports
    /// and recurring_instances, then deletes the transactions themselves.
    /// Chunked to stay under SQLite's 999-variable limit.
    private static func cleanupTransactionReferences(db: Database, idStrings: [String]) throws {
        let chunkSize = 900
        for chunk in idStrings.chunked(into: chunkSize) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let args: StatementArguments = StatementArguments(chunk)
            try db.execute(
                sql: "DELETE FROM transaction_labels WHERE transaction_id IN (\(placeholders))",
                arguments: args
            )
            try db.execute(
                sql: "DELETE FROM transaction_search WHERE transaction_id IN (\(placeholders))",
                arguments: args
            )
            try db.execute(
                sql: "UPDATE bank_transaction_imports SET cash_runway_transaction_id = NULL WHERE cash_runway_transaction_id IN (\(placeholders))",
                arguments: args
            )
            try db.execute(
                sql: "UPDATE recurring_instances SET linked_transaction_id = NULL WHERE linked_transaction_id IN (\(placeholders))",
                arguments: args
            )
            try db.execute(
                sql: "DELETE FROM transactions WHERE id IN (\(placeholders))",
                arguments: args
            )
        }
    }

    private struct DeletionImpact: Sendable {
        let items: [TransactionDeletionItem]
        let summary: TransactionDeletionSummary
    }

    private static func deletionImpactRows(_ db: Database, period: DeletePeriod, now: Date) throws -> DeletionImpact {
        let (sql, arguments) = Self.deletePeriodPredicate(period, now: now)
        let hasCurrencyColumn = try tableHasColumn(db, table: "transactions", column: "currency_code")
        let currencySelect = hasCurrencyColumn ? ", currency_code" : ""
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, type, amount_minor, updated_at\(currencySelect)
            FROM transactions
            WHERE \(sql)
            ORDER BY id
            """,
            arguments: arguments
        )
        var expenseMinor: Int64 = 0
        var incomeMinor: Int64 = 0
        var displayCount = 0
        var currencyCodes: Set<String> = []
        var items: [TransactionDeletionItem] = []
        items.reserveCapacity(rows.count)
        for row in rows {
            guard let id = UUID(uuidString: row["id"]) else { continue }
            let updatedAt: String = row["updated_at"]
            items.append(TransactionDeletionItem(id: id, updatedAt: updatedAt))
            let type: String = row["type"]
            let amount: Int64 = row["amount_minor"]
            if hasCurrencyColumn {
                let code: String = row["currency_code"]
                if !code.isEmpty { currencyCodes.insert(code) }
            }
            switch type {
            case "expense":
                expenseMinor += abs(amount)
                displayCount += 1
            case "income":
                incomeMinor += abs(amount)
                displayCount += 1
            case "transfer_in":
                break
            default:
                displayCount += 1
            }
        }
        if currencyCodes.isEmpty { currencyCodes = ["UAH"] }
        let isMixedCurrency = currencyCodes.count > 1
        return DeletionImpact(
            items: items,
            summary: TransactionDeletionSummary(
                count: items.count,
                displayCount: displayCount,
                expenseMinor: isMixedCurrency ? 0 : expenseMinor,
                incomeMinor: isMixedCurrency ? 0 : incomeMinor,
                currencyCodes: currencyCodes
            )
        )
    }

    private static func deletePeriodPredicate(_ period: DeletePeriod, now: Date) -> (sql: String, arguments: StatementArguments) {
        deletePeriodPredicate(
            period,
            dayKey: DateKeys.dayKey(for: now),
            monthKey: DateKeys.monthKey(for: now),
            year: DateKeys.yearKey(for: now)
        )
    }

    private static func deletePeriodPredicate(
        _ period: DeletePeriod,
        dayKey: Int,
        monthKey: Int,
        year: Int
    ) -> (sql: String, arguments: StatementArguments) {
        let periodSQL: String
        let periodArgs: StatementArguments
        switch period {
        case .allHistory:
            periodSQL = "1 = 1"
            periodArgs = StatementArguments()
        case .today:
            periodSQL = "local_day_key = ?"
            periodArgs = StatementArguments([dayKey])
        case .thisMonth:
            periodSQL = "local_month_key = ?"
            periodArgs = StatementArguments([monthKey])
        case .thisYear:
            periodSQL = "local_month_key >= ? AND local_month_key < ?"
            periodArgs = StatementArguments([year * 100, (year + 1) * 100])
        }
        return ("is_deleted = 0 AND \(periodSQL)", periodArgs)
    }

    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) throws {
        try databaseManager.dbQueue.write { db in
            guard oldCategoryID != newCategoryID else {
                throw CashRunwayError.validation(L10n.string("Choose two different categories to merge."))
            }
            guard let oldKind = try String.fetchOne(
                db,
                sql: "SELECT kind FROM categories WHERE id = ?",
                arguments: [oldCategoryID.uuidString]
            ),
                  let newCategoryRow = try Row.fetchOne(
                    db,
                    sql: "SELECT kind, is_archived FROM categories WHERE id = ?",
                    arguments: [newCategoryID.uuidString]
                  )
            else {
                throw CashRunwayError.notFound
            }
            let newKind: String = newCategoryRow["kind"]
            let newIsArchived: Bool = newCategoryRow["is_archived"]
            guard oldKind == newKind else {
                throw CashRunwayError.validation(L10n.string("Categories must have the same type to merge."))
            }
            guard !newIsArchived else {
                throw CashRunwayError.validation(L10n.string("Destination category must be active."))
            }

            let now = Date()
            let affectedMonths = Set(try Int.fetchAll(
                db,
                sql: "SELECT DISTINCT local_month_key FROM transactions WHERE category_id = ?",
                arguments: [oldCategoryID.uuidString]
            ))
            let affectedTransactionIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM transactions WHERE is_deleted = 0 AND category_id = ?",
                arguments: [oldCategoryID.uuidString]
            )
            let categorySpendDeltas = try Self.categorySpendDeltas(db, categoryID: oldCategoryID)
            try db.execute(
                sql: "UPDATE transactions SET category_id = ?, updated_at = ? WHERE category_id = ?",
                arguments: [newCategoryID.uuidString, now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: "UPDATE recurring_templates SET category_id = ?, updated_at = ? WHERE category_id = ?",
                arguments: [newCategoryID.uuidString, now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: "UPDATE recurring_instances SET override_category_id = ?, updated_at = ? WHERE override_category_id = ?",
                arguments: [newCategoryID.uuidString, now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: "UPDATE bank_category_rules SET category_id = ?, updated_at = ? WHERE category_id = ?",
                arguments: [newCategoryID.uuidString, now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: "UPDATE categories SET is_archived = 1, updated_at = ? WHERE id = ?",
                arguments: [now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: """
                INSERT INTO category_remaps (id, old_category_id, new_category_id, remapped_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, oldCategoryID.uuidString, newCategoryID.uuidString, now]
            )
            try db.execute(
                sql: """
                INSERT INTO audit_entries (id, entity_type, entity_id, operation, diff_json, created_at)
                VALUES (?, 'category', ?, 'remap', ?, ?)
                """,
                arguments: [UUID().uuidString, oldCategoryID.uuidString, "{\"from\":\"\(oldCategoryID.uuidString)\",\"to\":\"\(newCategoryID.uuidString)\"}", now]
            )
            try applyCategoryMergeDeltas(db, oldCategoryID: oldCategoryID, newCategoryID: newCategoryID, deltas: categorySpendDeltas)
            try recomputeBudgetSnapshots(db, monthKeys: affectedMonths)
            try syncSearch(db, transactionIDs: affectedTransactionIDs)
        }
    }

    public func failImport(jobID: UUID, errorSummary: String) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE import_jobs SET status = ?, finished_at = ?, error_summary = ? WHERE id = ?",
                arguments: [ImportJobStatus.failed.rawValue, Date(), errorSummary, jobID.uuidString]
            )
        }
    }

    public func commitCSVImport(
        fileName: String,
        sourceName: String,
        sourceFormatID: String? = nil,
        preparedRows: [PreparedImportRow],
        rowErrors: [CSVRowError],
        invalidRows: Int? = nil
    ) throws -> CSVImportResult {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "commitCSVImport") else {
            throw CashRunwayError.validation("Protected data is unavailable. Try again after unlocking your device.")
        }
        let now = Date()
        let jobID = UUID()
        let resolvedInvalidRows = invalidRows ?? rowErrors.count
        let totalRows = preparedRows.count + resolvedInvalidRows

        return try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO import_jobs (id, source_name, source_format_id, file_name, status, total_rows, valid_rows, invalid_rows, duplicate_rows, started_at, finished_at, error_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                        jobID.uuidString, sourceName, sourceFormatID, fileName, ImportJobStatus.validated.rawValue, totalRows,
                    preparedRows.count, resolvedInvalidRows, 0, now, nil, resolvedInvalidRows > 0 ? "\(resolvedInvalidRows) rows failed validation." : nil,
                ]
            )

            var seenFingerprints = Set<String>()
            var insertedRows = 0
            var duplicateRows = 0
            var affectedMonths = Set<Int>()

            for row in preparedRows {
                let semanticKey = importSemanticKey(for: row.draft)
                let fingerprintDuplicate = try importFingerprintExists(db, fingerprint: row.fingerprint)
                    || (row.legacyFingerprint.map { try importFingerprintExists(db, fingerprint: $0) } ?? false)
                let semanticDuplicate = try importSemanticKeyExists(db, key: semanticKey)
                if seenFingerprints.contains(row.fingerprint)
                    || row.legacyFingerprint.map({ seenFingerprints.contains($0) }) ?? false
                    || fingerprintDuplicate
                    || semanticDuplicate {
                    duplicateRows += 1
                    continue
                }

                let categoryID: UUID?
                if let preparedID = row.categoryID, let validID = try validCategoryID(db, id: preparedID, kind: row.draft.kind) {
                    categoryID = validID
                } else {
                    categoryID = try resolveOrCreateCategory(
                        db,
                        rawName: row.rawCategoryName,
                        kind: row.draft.kind,
                        iconName: row.categoryIconName,
                        colorHex: row.categoryColorHex
                    )
                }
                let labelIDs = try row.rawLabelNames.map { try resolveOrCreateLabel(db, name: $0) }

                var draft = row.draft
                draft.currencyCode = try walletCurrencyCode(db, walletID: draft.walletID)
                draft.categoryID = categoryID
                draft.labelIDs = labelIDs
                draft.importJobID = jobID
                draft.importFingerprint = row.fingerprint

                try validate(draft)
                if draft.kind == .transfer {
                    try saveTransfer(db, draft: draft)
                } else {
                    try saveSingleTransaction(db, draft: draft)
                }

                seenFingerprints.insert(row.fingerprint)
                insertedRows += 1
                affectedMonths.insert(DateKeys.monthKey(for: row.draft.occurredAt))
            }

            try db.execute(
                sql: """
                UPDATE import_jobs
                SET status = ?, valid_rows = ?, invalid_rows = ?, duplicate_rows = ?, finished_at = ?, error_summary = ?
                WHERE id = ?
                """,
                arguments: [
                    ImportJobStatus.committed.rawValue,
                    insertedRows,
                    resolvedInvalidRows,
                    duplicateRows,
                    Date(),
                    resolvedInvalidRows > 0 ? "\(resolvedInvalidRows) rows failed validation." : nil,
                    jobID.uuidString,
                ]
            )

        let job = ImportJob(
            id: jobID,
            sourceName: sourceName,
            sourceFormatID: sourceFormatID,
            fileName: fileName,
                status: .committed,
                totalRows: totalRows,
                validRows: insertedRows,
                invalidRows: resolvedInvalidRows,
                duplicateRows: duplicateRows,
                startedAt: now,
                finishedAt: Date(),
                errorSummary: resolvedInvalidRows > 0 ? "\(resolvedInvalidRows) rows failed validation." : nil
            )

            return CSVImportResult(
                job: job,
                insertedTransactions: insertedRows,
                duplicateRows: duplicateRows,
                invalidRows: resolvedInvalidRows,
                affectedMonths: affectedMonths,
                rowErrors: rowErrors
            )
        }
    }

    private func importFingerprintExists(_ db: Database, fingerprint: String) throws -> Bool {
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM transactions WHERE import_fingerprint = ?",
            arguments: [fingerprint]
        ) ?? 0
        return count > 0
    }

    private func importSemanticKeyExists(_ db: Database, key: String) throws -> Bool {
        let count = try Int.fetchOne(
            db,
            sql: """
            SELECT COUNT(*) FROM transactions
            WHERE is_deleted = 0
              AND (
                import_fingerprint IS NULL
                OR source IN ('manual', 'bank_sync')
              )
              AND wallet_id || '|' || type || '|' || local_day_key || '|' || amount_minor || '|' || lower(trim(coalesce(merchant, ''))) || '|' || lower(trim(coalesce(note, ''))) = ?
            """,
            arguments: [key]
        ) ?? 0
        return count > 0
    }

    @available(*, deprecated, message: "Replaced by per-row importFingerprintExists and importSemanticKeyExists checks")
    private func existingImportFingerprints(_ db: Database) throws -> Set<String> {
        let rows = try String.fetchAll(db, sql: "SELECT import_fingerprint FROM transactions WHERE import_fingerprint IS NOT NULL")
        return Set(rows)
    }

    @available(*, deprecated, message: "Replaced by per-row importSemanticKeyExists check")
    private func existingImportSemanticKeys(_ db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT wallet_id, type, local_day_key, amount_minor, merchant, note
            FROM transactions
            WHERE is_deleted = 0
              AND (
                import_fingerprint IS NULL
                OR source IN ('manual', 'bank_sync')
              )
            """
        )
        return Set(rows.map { row -> String in
            Self.importSemanticKey(
                walletID: row["wallet_id"],
                kind: row["type"],
                dayKey: row["local_day_key"],
                amountMinor: row["amount_minor"],
                merchant: row["merchant"],
                note: row["note"]
            )
        })
    }

    private static func importSemanticKey(
        walletID: String,
        kind: String,
        dayKey: Int,
        amountMinor: Int64,
        merchant: String?,
        note: String?
    ) -> String {
        let normalizedMerchant = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedNote = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            walletID,
            kind,
            String(dayKey),
            String(amountMinor),
            normalizedMerchant,
            normalizedNote,
        ].joined(separator: "|")
    }

    private func importSemanticKey(for draft: TransactionDraft) -> String {
        Self.importSemanticKey(
            walletID: draft.walletID.uuidString,
            kind: draft.kind.rawValue,
            dayKey: DateKeys.dayKey(for: draft.occurredAt),
            amountMinor: draft.amountMinor,
            merchant: draft.merchant,
            note: draft.note
        )
    }

    private func resolveOrCreateCategory(
        _ db: Database,
        rawName: String?,
        kind: TransactionDraft.Kind,
        iconName: String?,
        colorHex: String?
    ) throws -> UUID? {
        guard kind != .transfer else { return nil }
        let categoryKind: CategoryKind = kind == .income ? .income : .expense
        let fallbackName = kind == .income ? "Other Income" : "Other Expense"

        let allRows = try Row.fetchAll(db, sql: "SELECT * FROM categories WHERE kind = ? AND is_archived = 0", arguments: [categoryKind.rawValue])

        if let rawName, let categoryID = try resolvedCategoryID(db, kind: categoryKind, named: rawName) {
            return categoryID
        }

        if rawName == nil {
            if let fallbackRow = allRows.first(where: { ($0["name"] as String) == fallbackName }) {
                return UUID(uuidString: fallbackRow["id"])!
            }
            if let firstRow = allRows.first {
                return UUID(uuidString: firstRow["id"])!
            }
        }

        let fallbackRow = allRows.first(where: { ($0["name"] as String) == fallbackName }) ?? allRows.first
        let resolvedIconName = iconName ?? fallbackRow?["icon_name"]
        let resolvedColorHex = colorHex ?? fallbackRow?["color_hex"]

        let now = Date()
        let id = UUID()
        let name = rawName ?? fallbackName
        try db.execute(
            sql: """
            INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id.uuidString, name, categoryKind.rawValue, resolvedIconName, resolvedColorHex,
                nil, false, false, (allRows.map { $0["sort_order"] as Int }.max() ?? 0) + 1, now, now,
            ]
        )
        return id
    }

    private func validCategoryID(_ db: Database, id: UUID, kind: TransactionDraft.Kind) throws -> UUID? {
        guard kind != .transfer else { return nil }
        let categoryKind: CategoryKind = kind == .income ? .income : .expense
        return try String.fetchOne(
            db,
            sql: "SELECT id FROM categories WHERE id = ? AND kind = ? AND is_archived = 0",
            arguments: [id.uuidString, categoryKind.rawValue]
        ).flatMap(UUID.init(uuidString:))
    }

    private func resolveOrCreateLabel(_ db: Database, name: String) throws -> UUID {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM labels")
        for row in rows {
            let rowName: String = row["name"]
            if rowName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame {
                return UUID(uuidString: row["id"])!
            }
        }
        let now = Date()
        let id = UUID()
        try db.execute(
            sql: "INSERT INTO labels (id, name, color_hex, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            arguments: [id.uuidString, name, "#60788A", now, now]
        )
        return id
    }

    public func runMaintenance() throws {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "runMaintenance") else { return }
        try databaseManager.dbQueue.write { db in
            try processPendingAggregateRebuilds(db)
            try purgeExpiredRawJSON(db)
        }
    }

    public func refreshRecurringInstances() throws {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "refreshRecurringInstances") else { return }
        try databaseManager.dbQueue.write { db in
            try refreshRecurringInstances(db)
        }
    }

    public func postRecurringInstance(id: UUID, on date: Date = .now) throws {
        try databaseManager.dbQueue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM recurring_instances WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let instance = try Self.recurringInstance(row)

            guard instance.status != .posted else {
                return
            }
            guard let templateRow = try Row.fetchOne(db, sql: "SELECT * FROM recurring_templates WHERE id = ?", arguments: [instance.templateID.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let template = try Self.recurringTemplate(templateRow)
            let linkedTransactionID = UUID()

            let draft = TransactionDraft(
                id: linkedTransactionID,
                kind: template.kind == .transfer ? .transfer : (template.kind == .expense ? .expense : .income),
                walletID: template.walletID,
                destinationWalletID: template.counterpartyWalletID,
                amountMinor: instance.overrideAmountMinor ?? template.amountMinor,
                currencyCode: template.currencyCode,
                occurredAt: date,
                categoryID: instance.overrideCategoryID ?? template.categoryID,
                merchant: instance.overrideMerchant ?? template.merchant ?? "",
                note: instance.overrideNote ?? template.note ?? "",
                source: .recurring,
                recurringTemplateID: template.id,
                recurringInstanceID: instance.id
            )
            try draft.kind == .transfer ? saveTransfer(db, draft: draft) : saveSingleTransaction(db, draft: draft)
            try db.execute(
                sql: "UPDATE recurring_instances SET status = ?, linked_transaction_id = ?, updated_at = ? WHERE id = ?",
                arguments: [RecurringInstanceStatus.posted.rawValue, linkedTransactionID.uuidString, Date(), id.uuidString]
            )
        }
    }

    public func skipRecurringInstance(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recurring_instances SET status = ?, updated_at = ? WHERE id = ?",
                arguments: [RecurringInstanceStatus.skipped.rawValue, Date(), id.uuidString]
            )
        }
    }

}

extension CashRunwayRepository {
    private func saveSingleTransaction(_ db: Database, draft: TransactionDraft, updateDerivedData: Bool = true) throws {
        let now = Date()
        let id = draft.id ?? UUID()
        let existing: CashRunwayTransaction? = if let draftID = draft.id {
            try existingTransaction(db, id: draftID)
        } else {
            nil
        }
        let cashRunwayType: TransactionKind = draft.kind == .expense ? .expense : .income
        let record = CashRunwayTransaction(
            id: id,
            walletID: draft.walletID,
            type: cashRunwayType,
            linkedTransferID: nil,
            amountMinor: draft.amountMinor,
            currencyCode: draft.currencyCode,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: draft.categoryID,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            importJobID: draft.importJobID,
            importFingerprint: draft.importFingerprint,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        let existingLabelIDs: [UUID] = if let existing {
            try String.fetchAll(
                db,
                sql: "SELECT label_id FROM transaction_labels WHERE transaction_id = ?",
                arguments: [existing.id.uuidString]
            ).compactMap(UUID.init(uuidString:))
        } else {
            []
        }

        if updateDerivedData {
            try applyContribution(
                db,
                old: existing.map { contribution(for: $0, labelIDs: existingLabelIDs) },
                new: contribution(for: record, labelIDs: draft.labelIDs)
            )
        }
        try upsertTransactionRow(db, transaction: record)
        try syncLabels(db, transactionID: id, labelIDs: draft.labelIDs)
        if updateDerivedData {
            try syncSearch(db, transaction: record)
        }
    }

    private func saveTransfer(_ db: Database, draft: TransactionDraft, updateDerivedData: Bool = true) throws {
        guard let destinationWalletID = draft.destinationWalletID, destinationWalletID != draft.walletID else {
            throw CashRunwayError.validation(L10n.string("Transfer requires two different wallets."))
        }
        let now = Date()
        let sourceID = draft.id ?? UUID()
        let sourceExisting: CashRunwayTransaction? = if let draftID = draft.id {
            try existingTransaction(db, id: draftID)
        } else {
            nil
        }
        let targetExisting: CashRunwayTransaction? = if let linkedTransferID = sourceExisting?.linkedTransferID {
            try existingTransaction(db, id: linkedTransferID)
        } else {
            nil
        }
        let targetID = sourceExisting?.linkedTransferID ?? UUID()

        let sourceRecord = CashRunwayTransaction(
            id: sourceID,
            walletID: draft.walletID,
            type: .transferOut,
            linkedTransferID: targetID,
            amountMinor: draft.amountMinor,
            currencyCode: draft.currencyCode,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: nil,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            importJobID: draft.importJobID,
            importFingerprint: draft.importFingerprint,
            createdAt: sourceExisting?.createdAt ?? now,
            updatedAt: now
        )
        let targetRecord = CashRunwayTransaction(
            id: targetID,
            walletID: destinationWalletID,
            type: .transferIn,
            linkedTransferID: sourceID,
            amountMinor: draft.amountMinor,
            currencyCode: draft.currencyCode,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: nil,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            importJobID: draft.importJobID,
            importFingerprint: draft.importFingerprint,
            createdAt: targetExisting?.createdAt ?? now,
            updatedAt: now
        )

        let transferExistingLabelIDs: [UUID] = if let sourceExisting {
            try String.fetchAll(
                db,
                sql: "SELECT label_id FROM transaction_labels WHERE transaction_id IN (?, ?)",
                arguments: [sourceExisting.id.uuidString, targetID.uuidString]
            ).compactMap(UUID.init(uuidString:))
        } else {
            []
        }

        if updateDerivedData {
            try applyContribution(
                db,
                old: sourceExisting.map { contribution(for: $0, labelIDs: transferExistingLabelIDs) },
                new: contribution(for: sourceRecord, labelIDs: draft.labelIDs)
            )
            try applyContribution(
                db,
                old: targetExisting.map { contribution(for: $0, labelIDs: transferExistingLabelIDs) },
                new: contribution(for: targetRecord, labelIDs: draft.labelIDs)
            )
        }
        try upsertTransactionRow(db, transaction: sourceRecord)
        try upsertTransactionRow(db, transaction: targetRecord)
        try syncLabels(db, transactionID: sourceID, labelIDs: draft.labelIDs)
        try syncLabels(db, transactionID: targetID, labelIDs: draft.labelIDs)
        if updateDerivedData {
            try syncSearch(db, transaction: sourceRecord)
            try syncSearch(db, transaction: targetRecord)
        }
    }

    private func existingTransaction(_ db: Database, id: UUID) throws -> CashRunwayTransaction? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
            return nil
        }
        return try Self.transaction(row)
    }

    private func upsertTransactionRow(_ db: Database, transaction: CashRunwayTransaction) throws {
        guard try Self.tableHasColumn(db, table: "transactions", column: "currency_code") else {
            try db.execute(
                sql: """
                INSERT INTO transactions (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key, category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id, import_job_id, import_fingerprint, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    wallet_id = excluded.wallet_id,
                    type = excluded.type,
                    linked_transfer_id = excluded.linked_transfer_id,
                    amount_minor = excluded.amount_minor,
                    occurred_at = excluded.occurred_at,
                    local_day_key = excluded.local_day_key,
                    local_month_key = excluded.local_month_key,
                    category_id = excluded.category_id,
                    merchant = excluded.merchant,
                    note = excluded.note,
                    source = excluded.source,
                    recurring_template_id = excluded.recurring_template_id,
                    recurring_instance_id = excluded.recurring_instance_id,
                    import_job_id = excluded.import_job_id,
                    import_fingerprint = excluded.import_fingerprint,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    transaction.id.uuidString, transaction.walletID.uuidString, transaction.type.rawValue, transaction.linkedTransferID?.uuidString,
                    transaction.amountMinor, transaction.occurredAt, transaction.localDayKey, transaction.localMonthKey,
                    transaction.categoryID?.uuidString, transaction.merchant, transaction.note, transaction.isDeleted,
                    transaction.source.rawValue, transaction.recurringTemplateID?.uuidString, transaction.recurringInstanceID?.uuidString,
                    transaction.importJobID?.uuidString, transaction.importFingerprint,
                    transaction.createdAt, transaction.updatedAt,
                ]
            )
            return
        }

        try db.execute(
            sql: """
            INSERT INTO transactions (
                id, wallet_id, type, linked_transfer_id, amount_minor, currency_code, occurred_at, local_day_key,
                local_month_key, category_id, merchant, note, is_deleted, source, recurring_template_id,
                recurring_instance_id, import_job_id, import_fingerprint, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                wallet_id = excluded.wallet_id,
                type = excluded.type,
                linked_transfer_id = excluded.linked_transfer_id,
                amount_minor = excluded.amount_minor,
                currency_code = excluded.currency_code,
                occurred_at = excluded.occurred_at,
                local_day_key = excluded.local_day_key,
                local_month_key = excluded.local_month_key,
                category_id = excluded.category_id,
                merchant = excluded.merchant,
                note = excluded.note,
                source = excluded.source,
                recurring_template_id = excluded.recurring_template_id,
                recurring_instance_id = excluded.recurring_instance_id,
                import_job_id = excluded.import_job_id,
                import_fingerprint = excluded.import_fingerprint,
                updated_at = excluded.updated_at
            """,
            arguments: [
                transaction.id.uuidString, transaction.walletID.uuidString, transaction.type.rawValue, transaction.linkedTransferID?.uuidString,
                transaction.amountMinor, transaction.currencyCode.rawValue, transaction.occurredAt, transaction.localDayKey, transaction.localMonthKey,
                transaction.categoryID?.uuidString, transaction.merchant, transaction.note, transaction.isDeleted,
                transaction.source.rawValue, transaction.recurringTemplateID?.uuidString, transaction.recurringInstanceID?.uuidString,
                transaction.importJobID?.uuidString, transaction.importFingerprint,
                transaction.createdAt, transaction.updatedAt,
            ]
        )
    }

    private func validate(_ draft: TransactionDraft) throws {
        guard draft.amountMinor > 0 else {
            throw CashRunwayError.validation(L10n.string("Amount must be greater than zero."))
        }
        if draft.kind != .transfer, draft.categoryID == nil {
            throw CashRunwayError.validation(L10n.string("Category is required for income and expense transactions."))
        }
    }

    private func validateTransactionCurrency(_ db: Database, draft: TransactionDraft) throws {
        let sourceCurrency = try walletCurrencyCode(db, walletID: draft.walletID)
        if draft.kind == .transfer {
            guard let destinationWalletID = draft.destinationWalletID else { return }
            let destinationCurrency = try walletCurrencyCode(db, walletID: destinationWalletID)
            guard sourceCurrency == destinationCurrency, sourceCurrency == draft.currencyCode else {
                throw CashRunwayError.validation(L10n.string("Transfers require source wallet, destination wallet, and transaction currency to match."))
            }
        } else if sourceCurrency != draft.currencyCode {
            throw CashRunwayError.validation(L10n.string("Transaction currency must match the selected wallet currency."))
        }
    }

    private func validateRecurringTemplateCurrency(_ db: Database, template: RecurringTemplate) throws {
        let sourceCurrency = try walletCurrencyCode(db, walletID: template.walletID)
        if let counterpartyWalletID = template.counterpartyWalletID {
            let counterpartyCurrency = try walletCurrencyCode(db, walletID: counterpartyWalletID)
            guard sourceCurrency == counterpartyCurrency, sourceCurrency == template.currencyCode else {
                throw CashRunwayError.validation(L10n.string("Recurring transfer currency must match both wallets."))
            }
        } else if sourceCurrency != template.currencyCode {
            throw CashRunwayError.validation(L10n.string("Recurring template currency must match the selected wallet currency."))
        }
    }

    private func validateWalletCurrencyChange(_ db: Database, wallet: Wallet) throws {
        guard try Self.tableHasColumn(db, table: "wallets", column: "currency_code"),
              let row = try Row.fetchOne(
                  db,
                  sql: "SELECT currency_code, starting_balance_minor, current_balance_minor FROM wallets WHERE id = ?",
                  arguments: [wallet.id.uuidString]
              )
        else {
            return
        }

        let existingCurrency = try CurrencyCode(validating: row["currency_code"])
        guard existingCurrency != wallet.currencyCode else { return }

        let existingStarting: Int64 = row["starting_balance_minor"]
        let existingCurrent: Int64 = row["current_balance_minor"]
        guard existingStarting == 0,
              existingCurrent == 0,
              wallet.startingBalanceMinor == 0,
              wallet.currentBalanceMinor == 0,
              try dependentCurrencyDataCount(db, walletID: wallet.id) == 0
        else {
            throw CashRunwayError.validation(L10n.string("Wallet currency cannot be changed after ledger or bank data exists."))
        }
    }

    private func dependentCurrencyDataCount(_ db: Database, walletID: UUID) throws -> Int {
        let walletID = walletID.uuidString
        var count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM transactions WHERE wallet_id = ?",
            arguments: [walletID]
        ) ?? 0
        count += try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM recurring_templates WHERE wallet_id = ? OR counterparty_wallet_id = ?",
            arguments: [walletID, walletID]
        ) ?? 0
        if try tableExists(db, name: "bank_accounts") {
            count += try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM bank_accounts WHERE wallet_id = ?",
                arguments: [walletID]
            ) ?? 0
        }
        return count
    }

    private func walletCurrencyCode(_ db: Database, walletID: UUID) throws -> CurrencyCode {
        guard try Self.tableHasColumn(db, table: "wallets", column: "currency_code") else {
            return .uah
        }
        guard let rawValue = try String.fetchOne(
            db,
            sql: "SELECT currency_code FROM wallets WHERE id = ?",
            arguments: [walletID.uuidString]
        ) else {
            throw CashRunwayError.notFound
        }
        return try CurrencyCode(validating: rawValue)
    }

    private func rejectMixedCurrencyAllWalletSnapshot(_ db: Database, walletID: UUID?) throws {
        guard walletID == nil,
              try Self.tableHasColumn(db, table: "wallets", column: "currency_code")
        else {
            return
        }
        let activeCurrencyCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(DISTINCT currency_code) FROM wallets WHERE is_archived = 0"
        ) ?? 0
        guard activeCurrencyCount <= 1 else {
            throw CashRunwayError.validation(L10n.string("All-wallet totals require a single wallet currency until currency conversion is available."))
        }
    }

    private func syncLabels(_ db: Database, transactionID: UUID, labelIDs: [UUID]) throws {
        try db.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", arguments: [transactionID.uuidString])
        for labelID in Array(Set(labelIDs)) {
            try db.execute(
                sql: "INSERT INTO transaction_labels (transaction_id, label_id) VALUES (?, ?)",
                arguments: [transactionID.uuidString, labelID.uuidString]
            )
        }
    }

    private static func fallbackMerchant(for type: TransactionKind) -> String {
        switch type {
        case .expense: "Expense"
        case .income: "Income"
        case .transferOut: "Transfer"
        case .transferIn: "Transfer In"
        }
    }
}
