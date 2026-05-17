import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BankSyncSchemaTests {
    @Test func bankSyncMigrationCreatesRequiredTablesAndIndexes() throws {
        let repository = try TestSupport.makeRepository()

        let schema = try repository.databaseManager.dbQueue.read { db in
            let tables = try Set(String.fetchAll(
                db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                AND name IN ('bank_integrations', 'bank_accounts', 'bank_transaction_imports', 'bank_category_rules')
                """
            ))
            let indexes = try Set(String.fetchAll(
                db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index'
                AND name IN (
                    'idx_bank_accounts_integration',
                    'idx_bank_imports_account_time',
                    'idx_bank_imports_cash_transaction',
                    'idx_bank_category_rules_provider_type'
                )
                """
            ))
            return (tables, indexes)
        }

        #expect(schema.0 == ["bank_integrations", "bank_accounts", "bank_transaction_imports", "bank_category_rules"])
        #expect(schema.1 == [
            "idx_bank_accounts_integration",
            "idx_bank_imports_account_time",
            "idx_bank_imports_cash_transaction",
            "idx_bank_category_rules_provider_type",
        ])
    }

    @Test func bankIntegrationStoresImmutableSyncStartAt() throws {
        let repository = try TestSupport.makeRepository()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let originalSyncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let changedSyncStartAt = Date(timeIntervalSince1970: 1_750_000_000)
        let integrationID = UUID()

        try repository.saveBankIntegration(BankIntegration(
            id: integrationID,
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: originalSyncStartAt,
            tokenKeychainAccount: "mono-token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: now,
            updatedAt: now
        ))

        try repository.saveBankIntegration(BankIntegration(
            id: integrationID,
            provider: .monobank,
            displayName: "Monobank Updated",
            status: .disabled,
            syncStartAt: changedSyncStartAt,
            tokenKeychainAccount: "mono-token-updated",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: "Disabled by test",
            createdAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(1)
        ))

        let stored = try #require(try repository.bankIntegrations().first)
        #expect(stored.displayName == "Monobank Updated")
        #expect(stored.status == .disabled)
        #expect(stored.syncStartAt == originalSyncStartAt)
    }

    @Test func bankAccountsCanBeSavedAndFilteredByEnabledState() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let integrationID = UUID()
        let enabledAccountID = UUID()
        let originalSyncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let changedSyncStartAt = Date(timeIntervalSince1970: 1_750_000_000)

        try repository.saveBankIntegration(BankIntegration(
            id: integrationID,
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: now,
            tokenKeychainAccount: "mono-token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: now,
            updatedAt: now
        ))

        try repository.saveBankAccount(BankAccount(
            id: enabledAccountID,
            integrationID: integrationID,
            provider: .monobank,
            providerAccountID: "enabled-account",
            walletID: walletID,
            displayName: "Enabled Card",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "4444",
            iban: nil,
            isEnabled: true,
            syncStartAt: originalSyncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        ))
        try repository.saveBankAccount(BankAccount(
            id: UUID(),
            integrationID: integrationID,
            provider: .monobank,
            providerAccountID: "disabled-account",
            walletID: walletID,
            displayName: "Disabled Card",
            accountType: "white",
            currencyCode: 980,
            maskedPAN: "5555",
            iban: nil,
            isEnabled: false,
            syncStartAt: now,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        ))
        try repository.saveBankAccount(BankAccount(
            id: enabledAccountID,
            integrationID: integrationID,
            provider: .monobank,
            providerAccountID: "enabled-account",
            walletID: walletID,
            displayName: "Enabled Card Updated",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "4444",
            iban: nil,
            isEnabled: true,
            syncStartAt: changedSyncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(1)
        ))

        let allAccounts = try repository.bankAccounts(integrationID: integrationID)
        let enabledAccounts = try repository.enabledBankAccounts(integrationID: integrationID)

        #expect(allAccounts.count == 2)
        #expect(enabledAccounts.map(\.providerAccountID) == ["enabled-account"])
        #expect(enabledAccounts.first?.displayName == "Enabled Card Updated")
        #expect(enabledAccounts.first?.syncStartAt == originalSyncStartAt)
    }

    @Test func bankImportUniquenessPreventsDuplicateProviderStatementItems() throws {
        let repository = try TestSupport.makeRepository()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let integrationID = UUID()
        let accountID = UUID()
        let providerAccountID = "mono-account-1"
        let statementItemID = "statement-1"

        try repository.databaseManager.dbQueue.write { db in
            try insertBankTransactionImport(
                db,
                id: UUID(),
                provider: .monobank,
                integrationID: integrationID,
                bankAccountID: accountID,
                providerAccountID: providerAccountID,
                statementItemID: statementItemID,
                now: now
            )

            #expect(throws: (any Error).self) {
                try insertBankTransactionImport(
                    db,
                    id: UUID(),
                    provider: .monobank,
                    integrationID: integrationID,
                    bankAccountID: accountID,
                    providerAccountID: providerAccountID,
                    statementItemID: statementItemID,
                    now: now
                )
            }
        }

        let existing = try repository.existingBankImport(
            provider: .monobank,
            providerAccountID: providerAccountID,
            statementItemID: statementItemID
        )
        #expect(existing?.providerStatementItemID == statementItemID)
    }

    @Test func bankSchemaChangesPreserveExistingTransactionSources() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let expenseCategoryID = try #require(try repository.categories(kind: .expense).first?.id)
        let incomeCategoryID = try #require(try repository.categories(kind: .income).first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: walletID,
            amountMinor: 1_000,
            occurredAt: now,
            categoryID: expenseCategoryID,
            merchant: "Manual",
            source: .manual
        ))
        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: walletID,
            amountMinor: 2_000,
            occurredAt: now,
            categoryID: expenseCategoryID,
            merchant: "CSV",
            source: .importCSV
        ))
        try repository.saveTransaction(TransactionDraft(
            kind: .income,
            walletID: walletID,
            amountMinor: 3_000,
            occurredAt: now,
            categoryID: incomeCategoryID,
            merchant: "Recurring",
            source: .recurring
        ))

        let counts = try transactionCountsBySource(repository)
        #expect(counts["manual"] == 1)
        #expect(counts["import_csv"] == 1)
        #expect(counts["recurring"] == 1)
        #expect(counts["bank_sync"] == nil)
    }

    private func insertBankTransactionImport(
        _ db: Database,
        id: UUID,
        provider: BankProvider,
        integrationID: UUID,
        bankAccountID: UUID,
        providerAccountID: String,
        statementItemID: String,
        now: Date
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO bank_transaction_imports (
                id, provider, integration_id, bank_account_id, provider_account_id,
                provider_statement_item_id, statement_time, amount_minor_signed,
                operation_amount_minor_signed, currency_code, raw_json, import_status,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id.uuidString,
                provider.rawValue,
                integrationID.uuidString,
                bankAccountID.uuidString,
                providerAccountID,
                statementItemID,
                1_800_000_000,
                -12_345,
                nil,
                980,
                "{}",
                BankTransactionImportStatus.imported.rawValue,
                now,
                now,
            ]
        )
    }

    private func transactionCountsBySource(_ repository: CashRunwayRepository) throws -> [String: Int] {
        try repository.databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT source, COUNT(*) AS count FROM transactions GROUP BY source"
            )
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (row["source"] as String, row["count"] as Int)
            })
        }
    }
}
