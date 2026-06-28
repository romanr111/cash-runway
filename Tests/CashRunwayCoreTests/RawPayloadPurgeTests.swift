import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct RawPayloadPurgeTests {
    @Test func importedRawJSONIsRedactedAuditPayload() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)

        let item = MonobankStatementItem(
            id: "statement-1",
            time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
            description: "Coffee",
            mcc: 5812,
            originalMcc: 5812,
            amount: -1_250,
            operationAmount: nil,
            currencyCode: 980,
            commissionRate: nil,
            cashbackAmount: nil,
            balance: 100_000,
            hold: false,
            receiptId: "receipt-1",
            comment: "office",
            counterEdrpou: nil,
            counterIban: "UA123456789",
            counterName: "Coffee Shop"
        )

        _ = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)

        let audit: BankTransactionImport? = try repository.databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM bank_transaction_imports WHERE provider_statement_item_id = ?", arguments: ["statement-1"]) else { return nil }
            return try CashRunwayRepository.bankTransactionImport(row)
        }
        let importRow = try #require(audit)
        let rawJSON = try #require(importRow.rawJSON)
        let payload = try JSONDecoder().decode(BankTransactionRawAuditPayload.self, from: Data(rawJSON.utf8))

        #expect(payload.redacted == true)
        #expect(payload.schemaVersion == 1)
        #expect(payload.provider == BankProvider.monobank)
        #expect(payload.providerAccountID == "mono-account-1")
        #expect(payload.statementItemID == "statement-1")
        #expect(payload.amountMinorSigned == -1_250)
        #expect(payload.currencyCode == 980)
        #expect(payload.mcc == 5812)
        #expect(payload.originalMCC == 5812)

        #expect(!rawJSON.contains("UA123456789"))
        #expect(!rawJSON.contains("Coffee Shop"))
        #expect(!rawJSON.contains("receipt-1"))
        #expect(!rawJSON.contains("office"))
        #expect(!rawJSON.contains("100000"))
    }

    @Test func migrationRedactsExistingFullRawJSONImmediately() throws {
        let key = "aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkkllllmmmmnnnnoooopppp"
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])

        let partialMigrator = DatabaseManager.makeMigrator(upTo: "v5_custom_wallet_categories")
        let fixtureManager = try DatabaseManager(locationProvider: location, keychain: keychain, migrator: partialMigrator)
        let fixtureRepo = CashRunwayRepository(databaseManager: fixtureManager)
        try fixtureRepo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: fixtureRepo)
        let wallet = try #require(try fixtureRepo.wallets().first)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let integrationID = UUID()
        let accountID = UUID()
        let importID = UUID()
        let fullRawJSON = """
        {"id":"stmt-1","time":\(Int(now.timeIntervalSince1970)),"description":"Coffee","mcc":5812,
        "amount":-1250,"currencyCode":980,"receiptId":"receipt-1","comment":"office",
        "counterIban":"UA123456789","counterName":"Coffee Shop","balance":100000}
        """

        try fixtureRepo.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bank_integrations (
                    id, provider, display_name, status, sync_start_at, token_keychain_account, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [integrationID.uuidString, "monobank", "Mono", "active", now, "mono-token", now, now]
            )
            try db.execute(
                sql: """
                INSERT INTO bank_accounts (
                    id, integration_id, provider, provider_account_id, wallet_id, display_name, account_type,
                    currency_code, is_enabled, sync_start_at, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [accountID.uuidString, integrationID.uuidString, "monobank", "mono-account-1",
                            wallet.id.uuidString, "Black Card", "black", 980, true, now, now, now]
            )
            try db.execute(
                sql: """
                INSERT INTO bank_transaction_imports (
                    id, provider, integration_id, bank_account_id, provider_account_id,
                    provider_statement_item_id, statement_time, amount_minor_signed,
                    operation_amount_minor_signed, currency_code, mcc, original_mcc,
                    description, comment, counter_name, counter_iban, receipt_id, hold,
                    raw_json, cash_runway_transaction_id, import_status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    importID.uuidString, "monobank", integrationID.uuidString, accountID.uuidString,
                    "mono-account-1", "stmt-1", Int(now.timeIntervalSince1970), -1_250,
                    nil, 980, 5812, 5812, "Coffee", "office", "Coffee Shop", "UA123456789",
                    "receipt-1", false, fullRawJSON, nil, "imported", now, now
                ]
            )
        }
        try fixtureManager.checkpointWal()

        let fullManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repo = CashRunwayRepository(databaseManager: fullManager)
        try repo.seedIfNeeded()

        let row = try #require(try repo.databaseManager.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT raw_json, raw_json_expires_at, counter_iban, receipt_id FROM bank_transaction_imports WHERE id = ?", arguments: [importID.uuidString])
        })
        #expect((row["raw_json"] as String?) == nil)
        #expect((row["counter_iban"] as String?) == nil)
        #expect((row["receipt_id"] as String?) == nil)
        #expect((row["raw_json_expires_at"] as Date?) != nil)
    }

    @Test func rawJSONExpiresAtIsSetOnInsert() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)

        let item = monobankItem(id: "expires", time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970), amount: -1_000, currencyCode: 980)
        _ = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)

        let audit: BankTransactionImport? = try repository.databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM bank_transaction_imports WHERE provider_statement_item_id = ?", arguments: ["expires"]) else { return nil }
            return try CashRunwayRepository.bankTransactionImport(row)
        }
        let importRow = try #require(audit)
        let expiresAt = try #require(importRow.rawJSONExpiresAt)
        let createdAt = importRow.createdAt
        let days = Calendar.current.dateComponents([.day], from: createdAt, to: expiresAt).day
        #expect(days == 30)
    }

    @Test func purgeExpiredRawJSONRemovesOnlyExpiredRows() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)
        let now = Date()

        let freshID = UUID()
        let expiredID = UUID()
        try repository.databaseManager.dbQueue.write { db in
            try insertRawBankImport(db, id: freshID, setup: setup, itemID: "fresh", now: now, expiresAt: now.addingTimeInterval(30 * 24 * 60 * 60))
            try insertRawBankImport(db, id: expiredID, setup: setup, itemID: "expired", now: now.addingTimeInterval(-40 * 24 * 60 * 60), expiresAt: now.addingTimeInterval(-10 * 24 * 60 * 60))
        }

        try repository.runMaintenance()

        let rows = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT provider_statement_item_id, raw_json FROM bank_transaction_imports ORDER BY provider_statement_item_id")
        }
        #expect(rows.count == 2)
        let freshRow = try #require(rows.first { ($0["provider_statement_item_id"] as String) == "fresh" })
        let expiredRow = try #require(rows.first { ($0["provider_statement_item_id"] as String) == "expired" })
        #expect(freshRow["raw_json"] as String? != nil)
        #expect(expiredRow["raw_json"] as String? == nil)
    }

    private func makeBankSetup(repository: CashRunwayRepository) throws -> (integration: BankIntegration, account: BankAccount, syncStartAt: Date) {
        let walletID = try #require(try repository.wallets().first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: syncStartAt,
            tokenKeychainAccount: "mono-token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: now,
            updatedAt: now
        )
        let account = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "mono-account-1",
            walletID: walletID,
            displayName: "Black Card",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: nil,
            iban: nil,
            isEnabled: true,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveBankIntegration(integration)
        try repository.saveBankAccount(account)
        return (integration, account, syncStartAt)
    }

    private func monobankItem(id: String, time: Int, amount: Int64, currencyCode: Int) -> MonobankStatementItem {
        MonobankStatementItem(
            id: id,
            time: time,
            description: "Test",
            mcc: nil,
            originalMcc: nil,
            amount: amount,
            operationAmount: nil,
            currencyCode: currencyCode,
            commissionRate: nil,
            cashbackAmount: nil,
            balance: nil,
            hold: nil,
            receiptId: nil,
            comment: nil,
            counterEdrpou: nil,
            counterIban: nil,
            counterName: nil
        )
    }

    private func insertRawBankImport(
        _ db: Database,
        id: UUID,
        setup: (integration: BankIntegration, account: BankAccount, syncStartAt: Date),
        itemID: String,
        now: Date,
        expiresAt: Date
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO bank_transaction_imports (
                id, provider, integration_id, bank_account_id, provider_account_id,
                provider_statement_item_id, statement_time, amount_minor_signed,
                currency_code, raw_json, raw_json_expires_at, cash_runway_transaction_id,
                import_status, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id.uuidString,
                BankProvider.monobank.rawValue,
                setup.integration.id.uuidString,
                setup.account.id.uuidString,
                setup.account.providerAccountID,
                itemID,
                Int(now.timeIntervalSince1970),
                -1_000,
                980,
                "{\"schemaVersion\":1}",
                expiresAt,
                nil,
                BankTransactionImportStatus.imported.rawValue,
                now,
                now,
            ]
        )
    }
}
