import Foundation
import GRDB

extension CashRunwayRepository {
    static func wallet(_ row: Row) throws -> Wallet {
        let kind: WalletKind = WalletKind(rawValue: row["kind"]) ?? .other
        let categoryID = (row["category_id"] as String?).flatMap(UUID.init(uuidString:))
            ?? WalletCategory.builtIn(byKind: kind).id
        return Wallet(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: kind,
            categoryID: categoryID,
            colorHex: row["color_hex"],
            iconName: row["icon_name"],
            startingBalanceMinor: row["starting_balance_minor"],
            currentBalanceMinor: row["current_balance_minor"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func walletCategory(_ row: Row) throws -> WalletCategory {
        WalletCategory(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: WalletKind(rawValue: row["kind"]) ?? .other,
            isSystem: row["is_system"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupWallet(_ row: Row) throws -> BackupWallet {
        let kind: WalletKind = WalletKind(rawValue: row["kind"]) ?? .other
        let categoryID = (row["category_id"] as String?).flatMap(UUID.init(uuidString:))
        return BackupWallet(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: kind,
            categoryID: categoryID,
            colorHex: row["color_hex"],
            iconName: row["icon_name"],
            startingBalanceMinor: row["starting_balance_minor"],
            currentBalanceMinor: row["current_balance_minor"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupWalletCategory(_ row: Row) throws -> BackupWalletCategory {
        BackupWalletCategory(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: WalletKind(rawValue: row["kind"]) ?? .other,
            isSystem: row["is_system"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func category(_ row: Row) throws -> Category {
        try category(prefixed: "", row: row)
    }

    static func monthWindow(endingAt monthKey: Int, count: Int) -> [Int] {
        let start = DateKeys.startOfMonth(for: monthKey)
        return (0..<count).compactMap { offset in
            DateKeys.calendar.date(byAdding: .month, value: offset - (count - 1), to: start)
        }.map(DateKeys.monthKey(for:))
    }

    static func yearWindow(endingAt year: Int, count: Int) -> [Int] {
        (0..<count).map { year + $0 - (count - 1) }
    }

    static func endOfMonth(for monthKey: Int) -> Date {
        let start = DateKeys.startOfMonth(for: monthKey)
        let nextMonth = DateKeys.calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateKeys.calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? nextMonth
    }

    static func category(prefixed prefix: String, row: Row) throws -> Category {
        Category(
            id: UUID(uuidString: row["\(prefix)id"])!,
            name: row["\(prefix)name"],
            kind: CategoryKind(rawValue: row["\(prefix)kind"]) ?? .expense,
            iconName: row["\(prefix)icon_name"],
            colorHex: row["\(prefix)color_hex"],
            parentID: (row["\(prefix)parent_id"] as String?).flatMap(UUID.init(uuidString:)),
            isSystem: row["\(prefix)is_system"],
            isArchived: row["\(prefix)is_archived"],
            sortOrder: row["\(prefix)sort_order"],
            createdAt: row["\(prefix)created_at"],
            updatedAt: row["\(prefix)updated_at"]
        )
    }

    static func backupCategory(_ row: Row) throws -> BackupCategory {
        BackupCategory(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: CategoryKind(rawValue: row["kind"]) ?? .expense,
            iconName: row["icon_name"],
            colorHex: row["color_hex"],
            parentID: (row["parent_id"] as String?).flatMap(UUID.init(uuidString:)),
            isSystem: row["is_system"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func label(_ row: Row) throws -> Label {
        Label(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            colorHex: row["color_hex"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func bankIntegration(_ row: Row) throws -> BankIntegration {
        BankIntegration(
            id: UUID(uuidString: row["id"])!,
            provider: BankProvider(rawValue: row["provider"]) ?? .monobank,
            displayName: row["display_name"],
            status: BankIntegrationStatus(rawValue: row["status"]) ?? .syncFailed,
            syncStartAt: row["sync_start_at"],
            tokenKeychainAccount: row["token_keychain_account"],
            lastClientInfoSyncAt: row["last_client_info_sync_at"],
            lastSuccessfulSyncAt: row["last_successful_sync_at"],
            lastSyncError: row["last_sync_error"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func bankAccount(_ row: Row) throws -> BankAccount {
        BankAccount(
            id: UUID(uuidString: row["id"])!,
            integrationID: UUID(uuidString: row["integration_id"])!,
            provider: BankProvider(rawValue: row["provider"]) ?? .monobank,
            providerAccountID: row["provider_account_id"],
            walletID: UUID(uuidString: row["wallet_id"])!,
            displayName: row["display_name"],
            accountType: row["account_type"],
            currencyCode: row["currency_code"],
            maskedPAN: row["masked_pan"],
            iban: row["iban"],
            isEnabled: row["is_enabled"],
            syncStartAt: row["sync_start_at"],
            lastSuccessfulSyncAt: row["last_successful_sync_at"],
            lastStatementItemTime: row["last_statement_item_time"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func tableHasColumn(_ db: Database, table: String, column: String) throws -> Bool {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        return rows.contains { ($0["name"] as String?) == column }
    }

    static func bankTransactionImport(_ row: Row) throws -> BankTransactionImport {
        BankTransactionImport(
            id: UUID(uuidString: row["id"])!,
            provider: BankProvider(rawValue: row["provider"]) ?? .monobank,
            integrationID: UUID(uuidString: row["integration_id"])!,
            bankAccountID: UUID(uuidString: row["bank_account_id"])!,
            providerAccountID: row["provider_account_id"],
            providerStatementItemID: row["provider_statement_item_id"],
            statementTime: row["statement_time"],
            amountMinorSigned: row["amount_minor_signed"],
            operationAmountMinorSigned: row["operation_amount_minor_signed"],
            currencyCode: row["currency_code"],
            mcc: row["mcc"],
            originalMCC: row["original_mcc"],
            description: row["description"],
            comment: row["comment"],
            counterName: row["counter_name"],
            counterIBAN: row["counter_iban"],
            receiptID: row["receipt_id"],
            hold: row["hold"],
            rawJSON: row["raw_json"],
            rawJSONExpiresAt: row["raw_json_expires_at"],
            cashRunwayTransactionID: (row["cash_runway_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            importStatus: BankTransactionImportStatus(rawValue: row["import_status"]) ?? .failed,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    func existingBankImport(_ db: Database, provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT * FROM bank_transaction_imports
            WHERE provider = ? AND provider_account_id = ? AND provider_statement_item_id = ?
            """,
            arguments: [provider.rawValue, providerAccountID, statementItemID]
        ) else {
            return nil
        }
        return try Self.bankTransactionImport(row)
    }

    func insertBankTransactionImport(
        _ db: Database,
        id: UUID,
        provider: BankProvider,
        integrationID: UUID,
        bankAccountID: UUID,
        providerAccountID: String,
        item: MonobankStatementItem,
        cashRunwayTransactionID: UUID,
        now: Date
    ) throws {
        let auditPayload = BankTransactionRawAuditPayload(
            from: item,
            provider: provider,
            providerAccountID: providerAccountID
        )
        let rawJSON = String(data: try JSONEncoder().encode(auditPayload), encoding: .utf8)
        let rawJSONExpiresAt = Calendar.current.date(byAdding: .day, value: 30, to: now)
        try db.execute(
            sql: """
            INSERT INTO bank_transaction_imports (
                id, provider, integration_id, bank_account_id, provider_account_id,
                provider_statement_item_id, statement_time, amount_minor_signed,
                operation_amount_minor_signed, currency_code, mcc, original_mcc,
                description, comment, counter_name, counter_iban, receipt_id, hold,
                raw_json, raw_json_expires_at, cash_runway_transaction_id, import_status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id.uuidString,
                provider.rawValue,
                integrationID.uuidString,
                bankAccountID.uuidString,
                providerAccountID,
                item.id,
                item.time,
                item.amount,
                item.operationAmount,
                item.currencyCode,
                item.mcc,
                item.originalMcc,
            item.description,
            item.comment,
            item.counterName,
            nil,
            nil,
            item.hold,
                rawJSON,
                rawJSONExpiresAt,
                cashRunwayTransactionID.uuidString,
                BankTransactionImportStatus.imported.rawValue,
                now,
                now,
            ]
        )
    }

    static func backupLabel(_ row: Row) throws -> BackupLabel {
        BackupLabel(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            colorHex: row["color_hex"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func transaction(_ row: Row) throws -> CashRunwayTransaction {
        CashRunwayTransaction(
            id: UUID(uuidString: row["id"])!,
            walletID: UUID(uuidString: row["wallet_id"])!,
            type: TransactionKind(rawValue: row["type"]) ?? .expense,
            linkedTransferID: (row["linked_transfer_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            occurredAt: row["occurred_at"],
            localDayKey: row["local_day_key"],
            localMonthKey: row["local_month_key"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            isDeleted: row["is_deleted"],
            source: TransactionSource(rawValue: row["source"]) ?? .manual,
            recurringTemplateID: (row["recurring_template_id"] as String?).flatMap(UUID.init(uuidString:)),
            recurringInstanceID: (row["recurring_instance_id"] as String?).flatMap(UUID.init(uuidString:)),
            importJobID: (row["import_job_id"] as String?).flatMap(UUID.init(uuidString:)),
            importFingerprint: row["import_fingerprint"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupTransaction(_ row: Row) throws -> BackupTransaction {
        BackupTransaction(
            id: UUID(uuidString: row["id"])!,
            walletID: UUID(uuidString: row["wallet_id"])!,
            type: TransactionKind(rawValue: row["type"]) ?? .expense,
            linkedTransferID: (row["linked_transfer_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            occurredAt: row["occurred_at"],
            localDayKey: row["local_day_key"],
            localMonthKey: row["local_month_key"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            isDeleted: row["is_deleted"],
            source: TransactionSource(rawValue: row["source"]) ?? .manual,
            recurringTemplateID: (row["recurring_template_id"] as String?).flatMap(UUID.init(uuidString:)),
            recurringInstanceID: (row["recurring_instance_id"] as String?).flatMap(UUID.init(uuidString:)),
            importJobID: nil,
            importFingerprint: nil,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupTransactionLabel(_ row: Row) throws -> BackupTransactionLabel {
        BackupTransactionLabel(
            transactionID: UUID(uuidString: row["transaction_id"])!,
            labelID: UUID(uuidString: row["label_id"])!
        )
    }

    static func budget(_ row: Row) throws -> Budget {
        Budget(
            id: UUID(uuidString: row["id"])!,
            categoryID: UUID(uuidString: row["category_id"])!,
            monthKey: row["month_key"],
            limitMinor: row["limit_minor"],
            isArchived: row["is_archived"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupBudget(_ row: Row) throws -> BackupBudget {
        BackupBudget(
            id: UUID(uuidString: row["id"])!,
            categoryID: UUID(uuidString: row["category_id"])!,
            monthKey: row["month_key"],
            limitMinor: row["limit_minor"],
            isArchived: row["is_archived"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupRecurringTemplate(_ row: Row) throws -> BackupRecurringTemplate {
        BackupRecurringTemplate(
            id: UUID(uuidString: row["id"])!,
            kind: RecurringTemplateKind(rawValue: row["kind"]) ?? .expense,
            walletID: UUID(uuidString: row["wallet_id"])!,
            counterpartyWalletID: (row["counterparty_wallet_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            ruleType: RecurrenceRuleType(rawValue: row["rule_type"]) ?? .monthly,
            ruleInterval: row["rule_interval"],
            dayOfMonth: row["day_of_month"],
            weekday: row["weekday"],
            startDate: row["start_date"],
            endDate: row["end_date"],
            isActive: row["is_active"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func recurringInstance(_ row: Row) throws -> RecurringInstance {
        RecurringInstance(
            id: UUID(uuidString: row["id"])!,
            templateID: UUID(uuidString: row["template_id"])!,
            dueDate: row["due_date"],
            dayKey: row["day_key"],
            status: RecurringInstanceStatus(rawValue: row["status"]) ?? .scheduled,
            linkedTransactionID: (row["linked_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideAmountMinor: row["override_amount_minor"],
            overrideCategoryID: (row["override_category_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideNote: row["override_note"],
            overrideMerchant: row["override_merchant"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupRecurringInstance(_ row: Row) throws -> BackupRecurringInstance {
        BackupRecurringInstance(
            id: UUID(uuidString: row["id"])!,
            templateID: UUID(uuidString: row["template_id"])!,
            dueDate: row["due_date"],
            dayKey: row["day_key"],
            status: RecurringInstanceStatus(rawValue: row["status"]) ?? .scheduled,
            linkedTransactionID: (row["linked_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideAmountMinor: row["override_amount_minor"],
            overrideCategoryID: (row["override_category_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideNote: row["override_note"],
            overrideMerchant: row["override_merchant"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    static func backupImportJob(_ row: Row) throws -> BackupImportJob {
        BackupImportJob(
            id: UUID(uuidString: row["id"])!,
            sourceName: row["source_name"],
            sourceFormatID: row["source_format_id"],
            fileName: row["file_name"],
            status: ImportJobStatus(rawValue: row["status"]) ?? .created,
            totalRows: row["total_rows"],
            validRows: row["valid_rows"],
            invalidRows: row["invalid_rows"],
            startedAt: row["started_at"],
            finishedAt: row["finished_at"],
            errorSummary: row["error_summary"]
        )
    }
}
