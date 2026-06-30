import Foundation
import GRDB

extension CashRunwayRepository {
    public func exportFullBackup() throws -> CashRunwayBackup {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "exportFullBackup") else {
            throw CashRunwayError.validation("Protected data is unavailable. Try again after unlocking your device.")
        }
        return try databaseManager.dbQueue.read { db in
            let metadata = CashRunwayBackupMetadata(
                format: "cash-runway-backup",
                version: 3,
                createdAt: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                currency: "UAH"
            )

            let preferencesRow = try Row.fetchOne(
                db,
                sql: """
                SELECT default_currency_code, reporting_currency_code
                FROM currency_preferences
                WHERE id = 'default'
                LIMIT 1
                """
            )
            let preferences = preferencesRow.map {
                CurrencyPreferences(
                    defaultCurrencyCode: (try? CurrencyCode(validating: $0["default_currency_code"])) ?? .uah,
                    reportingCurrencyCode: (try? CurrencyCode(validating: $0["reporting_currency_code"])) ?? .uah
                )
            } ?? .default

            return CashRunwayBackup(
                metadata: metadata,
                wallets: try Row.fetchAll(db, sql: "SELECT * FROM wallets ORDER BY sort_order, name").map(Self.backupWallet),
                walletCategories: try Row.fetchAll(db, sql: "SELECT * FROM wallet_categories ORDER BY name").map(Self.backupWalletCategory),
                categories: try Row.fetchAll(db, sql: "SELECT * FROM categories ORDER BY kind, sort_order, name").map(Self.backupCategory),
                labels: try Row.fetchAll(db, sql: "SELECT * FROM labels ORDER BY name").map(Self.backupLabel),
                transactions: try Row.fetchAll(db, sql: "SELECT * FROM transactions ORDER BY occurred_at, created_at, id").map(Self.backupTransaction),
                transactionLabels: try Row.fetchAll(db, sql: "SELECT * FROM transaction_labels ORDER BY transaction_id, label_id").map(Self.backupTransactionLabel),
                budgets: try Row.fetchAll(db, sql: "SELECT * FROM budgets ORDER BY month_key, category_id").map(Self.backupBudget),
                recurringTemplates: try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates ORDER BY created_at, id").map(Self.backupRecurringTemplate),
                recurringInstances: try Row.fetchAll(db, sql: "SELECT * FROM recurring_instances ORDER BY due_date, id").map(Self.backupRecurringInstance),
                importJobs: try Row.fetchAll(db, sql: "SELECT * FROM import_jobs ORDER BY started_at, id").map(Self.backupImportJob),
                currencyPreferences: preferences
            )
        }
    }

    @discardableResult
    public func restoreFullBackup(_ backup: CashRunwayBackup) throws -> BackupRestoreResult {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "restoreFullBackup") else {
            throw CashRunwayError.validation("Protected data is unavailable. Try again after unlocking your device.")
        }
        return try restoreFullBackupCollectingClearedBankTokens(backup).result
    }

    func restoreFullBackupCollectingClearedBankTokens(
        _ backup: CashRunwayBackup
    ) throws -> (result: BackupRestoreResult, tokenAccounts: [String]) {
        let summary = try BackupValidator.validate(backup)
        let tokenAccounts = try databaseManager.dbQueue.write { db in
            let tokenAccounts = try clearBankSyncTables(db)
            try clearDerivedTables(db)
            try clearSourceTables(db)
            try insertBackupSourceData(backup, into: db)
            try db.execute(sql: "UPDATE wallets SET current_balance_minor = starting_balance_minor")
            let monthKeys = Set(backup.transactions.map(\.localMonthKey)).union(backup.budgets.map(\.monthKey))
            try rebuildMonths(db, monthKeys: monthKeys)
            try rebuildFTS(db)
            return tokenAccounts
        }
        return (BackupRestoreResult(summary: summary), tokenAccounts)
    }

    func clearDerivedTables(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM transaction_search")
        try db.execute(sql: "DELETE FROM aggregate_dirty_ranges")
        try db.execute(sql: "DELETE FROM budget_progress_snapshot")
        try db.execute(sql: "DELETE FROM daily_wallet_balance_delta")
        try db.execute(sql: "DELETE FROM monthly_category_spend")
        try db.execute(sql: "DELETE FROM monthly_label_spend")
        try db.execute(sql: "DELETE FROM monthly_wallet_cashflow")
    }

    func clearSourceTables(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM transaction_labels")
        try db.execute(sql: "DELETE FROM transactions")
        try db.execute(sql: "DELETE FROM recurring_instances")
        try db.execute(sql: "DELETE FROM recurring_templates")
        try db.execute(sql: "DELETE FROM import_jobs")
        try db.execute(sql: "DELETE FROM budgets")
        try db.execute(sql: "DELETE FROM labels")
        try db.execute(sql: "DELETE FROM categories")
        try db.execute(sql: "DELETE FROM wallets")
        try db.execute(sql: "DELETE FROM wallet_categories")
        try db.execute(sql: "DELETE FROM currency_preferences")
    }

    // swiftlint:disable:next function_body_length
    func clearBankSyncTables(_ db: Database) throws -> [String] {
        let tokenAccounts = try String.fetchAll(
            db,
            sql: "SELECT token_keychain_account FROM bank_integrations"
        )
        try db.execute(sql: "DELETE FROM bank_transaction_imports")
        try db.execute(sql: "DELETE FROM bank_accounts")
        try db.execute(sql: "DELETE FROM bank_category_rules")
        try db.execute(sql: "DELETE FROM bank_integrations")
        return tokenAccounts
    }

    func insertBackupSourceData(_ backup: CashRunwayBackup, into db: Database) throws {
        let preferences = backup.currencyPreferences ?? .default
        try db.execute(
            sql: """
            INSERT INTO currency_preferences (id, default_currency_code, reporting_currency_code, updated_at)
            VALUES ('default', ?, ?, ?)
            """,
            arguments: [preferences.defaultCurrencyCode.rawValue, preferences.reportingCurrencyCode.rawValue, Date()]
        )

        let walletCategories = backup.walletCategories.isEmpty
            ? WalletCategory.allBuiltIn.map {
                BackupWalletCategory(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    isSystem: $0.isSystem,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
            : backup.walletCategories

        for category in walletCategories {
            try db.execute(
                sql: """
                INSERT INTO wallet_categories (id, name, kind, is_system, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    category.id.uuidString, category.name, category.kind.rawValue,
                    category.isSystem, category.createdAt, category.updatedAt,
                ]
            )
        }

        for wallet in backup.wallets {
            let categoryID = wallet.categoryID ?? WalletCategory.builtIn(byKind: wallet.kind).id
            try db.execute(
                sql: """
                    INSERT INTO wallets (id, name, kind, category_id, color_hex, icon_name, starting_balance_minor, current_balance_minor, currency_code, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    wallet.id.uuidString, wallet.name, wallet.kind.rawValue, categoryID.uuidString,
                    wallet.colorHex, wallet.iconName,
                    wallet.startingBalanceMinor, wallet.startingBalanceMinor, wallet.currencyCode.rawValue, wallet.isArchived, wallet.sortOrder,
                    wallet.createdAt, wallet.updatedAt,
                ]
            )
        }

        for category in backup.categories {
            try db.execute(
                sql: """
                INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    category.id.uuidString, category.name, category.kind.rawValue, category.iconName, category.colorHex,
                    category.parentID?.uuidString, category.isSystem, category.isArchived, category.sortOrder,
                    category.createdAt, category.updatedAt,
                ]
            )
        }

        for label in backup.labels {
            try db.execute(
                sql: "INSERT INTO labels (id, name, color_hex, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [label.id.uuidString, label.name, label.colorHex, label.createdAt, label.updatedAt]
            )
        }

        for importJob in backup.importJobs {
            try db.execute(
                sql: """
                    INSERT INTO import_jobs (id, source_name, source_format_id, file_name, status, total_rows, valid_rows, invalid_rows, started_at, finished_at, error_summary)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    importJob.id.uuidString, importJob.sourceName, importJob.sourceFormatID, importJob.fileName, importJob.status.rawValue,
                    importJob.totalRows, importJob.validRows, importJob.invalidRows, importJob.startedAt,
                    importJob.finishedAt, importJob.errorSummary,
                ]
            )
        }

        for budget in backup.budgets {
            try db.execute(
                sql: "INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    budget.id.uuidString, budget.categoryID.uuidString, budget.monthKey, budget.limitMinor,
                    budget.isArchived, budget.createdAt, budget.updatedAt,
                ]
            )
        }

        for template in backup.recurringTemplates {
            try db.execute(
                sql: """
                    INSERT INTO recurring_templates (id, kind, wallet_id, counterparty_wallet_id, amount_minor, currency_code, category_id, merchant, note, rule_type, rule_interval, day_of_month, weekday, start_date, end_date, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    template.id.uuidString, template.kind.rawValue, template.walletID.uuidString,
                    template.counterpartyWalletID?.uuidString, template.amountMinor, template.currencyCode.rawValue, template.categoryID?.uuidString,
                    template.merchant, template.note, template.ruleType.rawValue, template.ruleInterval,
                    template.dayOfMonth, template.weekday, template.startDate, template.endDate, template.isActive,
                    template.createdAt, template.updatedAt,
                ]
            )
        }

        for instance in backup.recurringInstances {
            try db.execute(
                sql: """
                INSERT INTO recurring_instances (id, template_id, due_date, day_key, status, linked_transaction_id, override_amount_minor, override_category_id, override_note, override_merchant, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    instance.id.uuidString, instance.templateID.uuidString, instance.dueDate, instance.dayKey,
                    instance.status.rawValue, instance.linkedTransactionID?.uuidString, instance.overrideAmountMinor,
                    instance.overrideCategoryID?.uuidString, instance.overrideNote, instance.overrideMerchant,
                    instance.createdAt, instance.updatedAt,
                ]
            )
        }

        for transaction in backup.transactions {
            try db.execute(
                sql: """
                    INSERT INTO transactions (id, wallet_id, type, linked_transfer_id, amount_minor, currency_code, occurred_at, local_day_key, local_month_key, category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    transaction.id.uuidString, transaction.walletID.uuidString, transaction.type.rawValue,
                    transaction.linkedTransferID?.uuidString, transaction.amountMinor, transaction.currencyCode.rawValue, transaction.occurredAt,
                    transaction.localDayKey, transaction.localMonthKey, transaction.categoryID?.uuidString,
                    transaction.merchant, transaction.note, transaction.isDeleted, transaction.source.rawValue,
                    transaction.recurringTemplateID?.uuidString, transaction.recurringInstanceID?.uuidString,
                    transaction.createdAt, transaction.updatedAt,
                ]
            )
        }

        for row in backup.transactionLabels {
            try db.execute(
                sql: "INSERT INTO transaction_labels (transaction_id, label_id) VALUES (?, ?)",
                arguments: [row.transactionID.uuidString, row.labelID.uuidString]
            )
        }
    }
}
