import Foundation
import GRDB
import CryptoKit
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MigrationIntegrityTests {
    /// Asserts the migration identifiers in the exact order GRDB will run them.
    ///
    /// GRDB runs migrations in registration order (not name order), so the
    /// non-monotonic position of `v3_bank_sync` (registered after `v4_…`) is
    /// intentional and must not be "fixed" by reordering — existing databases
    /// would treat a reordered identifier as new and re-run it, corrupting data.
    /// New migrations append only; never rename, reorder, or delete an entry.
    @Test func migrationIdentifierSetMatchesRegistrationOrder() throws {
        let identifiers = DatabaseManager.allMigrations().map(\.0)
        #expect(identifiers == [
            "v1_schema",
            "v2_transaction_search_category_name",
            "v3_import_idempotency",
            "v4_import_job_source_format_id",
            "v3_bank_sync",
            "v5_custom_wallet_categories",
            "v6_bank_raw_json_ttl",
            "v7_monthly_category_spend_wallet_kind_income",
            "v7_monthly_label_spend_wallet",
            "v8_currency_foundation",
            "v9_masked_card_search_privacy",
        ])
    }

    @Test func currencyFoundationMigrationDefaultsLegacyLedgerToUAH() throws {
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        let key = "currency-foundation-key"
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])
        let partialMigrator = DatabaseManager.makeMigrator(upTo: "v7_monthly_label_spend_wallet")
        var fixtureManager: DatabaseManager? = try DatabaseManager(
            locationProvider: location,
            keychain: keychain,
            migrator: partialMigrator
        )
        let fixtureRepo = CashRunwayRepository(databaseManager: fixtureManager!)
        try fixtureRepo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: fixtureRepo)
        let wallet = try #require(try fixtureRepo.wallets().first)
        let category = try #require(try fixtureRepo.categories(kind: .expense).first)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try fixtureRepo.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 12_34,
            occurredAt: now,
            categoryID: category.id,
            merchant: "Legacy Currency",
            source: .manual
        ))
        try fixtureRepo.saveRecurringTemplate(RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: wallet.id,
            counterpartyWalletID: nil,
            amountMinor: 12_34,
            categoryID: category.id,
            merchant: "Legacy Currency",
            note: nil,
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 1,
            weekday: nil,
            startDate: now,
            endDate: nil,
            isActive: true,
            createdAt: now,
            updatedAt: now
        ))
        try fixtureManager?.checkpointWal()
        fixtureManager = nil

        let fullManager = try DatabaseManager(locationProvider: location, keychain: keychain)

        try fullManager.dbQueue.read { db in
            let walletCurrency = try String.fetchOne(db, sql: "SELECT currency_code FROM wallets LIMIT 1")
            let transactionCurrency = try String.fetchOne(db, sql: "SELECT currency_code FROM transactions LIMIT 1")
            let recurringTemplateCurrency = try String.fetchOne(db, sql: "SELECT currency_code FROM recurring_templates LIMIT 1")
            let preferences = try String.fetchOne(
                db,
                sql: """
                SELECT default_currency_code || ':' || reporting_currency_code
                FROM currency_preferences
                WHERE id = 'default'
                """
            )

            #expect(walletCurrency == "UAH")
            #expect(transactionCurrency == "UAH")
            #expect(recurringTemplateCurrency == "UAH")
            #expect(preferences == "UAH:UAH")
        }

        #expect(FileManager.default.fileExists(atPath: dbURL.path))
    }

    @Test func migrationFromPreviousEncryptedSchemaPreservesLedger() throws {
        let key = "aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkkllllmmmmnnnnoooopppp"
        let location = TestSupport.makeLocation()
        let dbURL = try location.databaseURL()
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])

        let partialMigrator = DatabaseManager.makeMigrator(upTo: "v3_import_idempotency")
        let fixtureManager = try DatabaseManager(locationProvider: location, keychain: keychain, migrator: partialMigrator)
        let fixtureRepo = CashRunwayRepository(databaseManager: fixtureManager)
        try fixtureRepo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: fixtureRepo)

        let walletA = try #require(try fixtureRepo.wallets().first)
        let expenseCategories = try fixtureRepo.categories(kind: .expense)
        let incomeCategories = try fixtureRepo.categories(kind: .income)
        let expenseCategoryID = try #require(expenseCategories.first?.id)
        let incomeCategoryID = try #require(incomeCategories.first?.id)

        let walletB = WalletBuilder()
            .with(name: "Savings")
            .with(kind: .account)
            .with(startingBalanceMinor: 500_000)
            .with(currentBalanceMinor: 500_000)
            .build()
        try fixtureRepo.saveWallet(walletB)

        let labelA = LabelBuilder().with(name: "Groceries").build()
        let labelB = LabelBuilder().with(name: "Utilities").build()
        try fixtureRepo.saveLabel(labelA)
        try fixtureRepo.saveLabel(labelB)

        let calendar = Calendar(identifier: .gregorian)
        let month1 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        let month2 = calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!
        let month3 = calendar.date(from: DateComponents(year: 2025, month: 3, day: 15))!

        try fixtureRepo.saveTransaction(TransactionBuilder()
            .with(walletID: walletA.id).with(amountMinor: 200_000).with(occurredAt: month1)
            .with(categoryID: expenseCategoryID).with(merchant: "Rent").with(source: .manual).build())

        try fixtureRepo.saveTransaction(TransactionBuilder()
            .with(kind: .income).with(walletID: walletB.id).with(amountMinor: 300_000)
            .with(occurredAt: month1).with(merchant: "Salary").with(categoryID: incomeCategoryID)
            .with(source: .manual).build())

        try fixtureRepo.saveTransaction(TransactionBuilder()
            .with(walletID: walletA.id).with(amountMinor: 50_000).with(occurredAt: month2)
            .with(categoryID: expenseCategoryID).with(merchant: "Utilities").with(source: .manual)
            .with(labelIDs: [labelA.id, labelB.id]).build())

        try fixtureRepo.saveTransaction(TransactionBuilder()
            .with(walletID: walletA.id).with(amountMinor: 100_000).with(occurredAt: month3)
            .with(categoryID: expenseCategoryID).with(merchant: "Transfer Out").with(source: .manual).build())

        try fixtureRepo.saveTransaction(TransactionBuilder()
            .with(kind: .transfer).with(walletID: walletA.id).with(destinationWalletID: walletB.id)
            .with(amountMinor: 75_000).with(occurredAt: month2).with(merchant: "Internal Transfer")
            .with(source: .manual).build())

        let templateID = UUID()
        let template = RecurringTemplate(
            id: templateID, kind: .expense, walletID: walletA.id,
            counterpartyWalletID: nil, amountMinor: 25_000,
            categoryID: expenseCategoryID, merchant: "Subscription", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 1,
            weekday: nil, startDate: month3, endDate: nil,
            isActive: true, createdAt: .now, updatedAt: .now
        )
        try fixtureRepo.saveRecurringTemplate(template)
        try fixtureRepo.refreshRecurringInstances()
        let instances = try fixtureRepo.recurringInstances()
        #expect(instances.count > 0)
        let fixtureInstanceIDs = Set(instances.map { $0.id })
        let fixtureTemplateIDs = Set(instances.map { $0.templateID })

        let importJob = ImportJob(
            id: UUID(), sourceName: "CSV", fileName: "test.csv",
            status: .committed, totalRows: 1, validRows: 1, invalidRows: 0,
            duplicateRows: 0, startedAt: month1, finishedAt: month1, errorSummary: nil
        )
        try fixtureRepo.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO import_jobs (id, source_name, file_name, status, total_rows, valid_rows, invalid_rows, duplicate_rows, started_at, finished_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                arguments: [importJob.id.uuidString, importJob.sourceName, importJob.fileName, importJob.status.rawValue, importJob.totalRows, importJob.validRows, importJob.invalidRows, importJob.duplicateRows, importJob.startedAt, importJob.finishedAt]
            )
        }
        try fixtureRepo.saveTransaction(TransactionBuilder()
            .with(walletID: walletA.id).with(amountMinor: 30_000).with(occurredAt: month1)
            .with(categoryID: expenseCategoryID).with(merchant: "Import Test").with(source: .importCSV)
            .with(importJobID: importJob.id).with(importFingerprint: "fp-import-001").build())

        let preMigrateTxCount = try fixtureRepo.transactions().count
        let preMigrateWallets = try fixtureRepo.wallets()
        let preMigrateWalletAMinor = try #require(preMigrateWallets.first { $0.id == walletA.id }).currentBalanceMinor
        let preMigrateWalletBMinor = try #require(preMigrateWallets.first { $0.id == walletB.id }).currentBalanceMinor
        let totalNetWorth = preMigrateWalletAMinor + preMigrateWalletBMinor

        try fixtureManager.checkpointWal()

        let fullManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repo = CashRunwayRepository(databaseManager: fullManager)
        try repo.seedIfNeeded()

        let recoveryDir = dbURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: recoveryDir.path))

        let appliedVersions = try fullManager.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        #expect(appliedVersions.contains("v3_bank_sync"))
        #expect(appliedVersions.contains("v5_custom_wallet_categories"))
        #expect(appliedVersions.contains("v7_monthly_category_spend_wallet_kind_income"))
        #expect(appliedVersions.contains("v7_monthly_label_spend_wallet"))

        let walletCategories = try repo.walletCategories()
        #expect(walletCategories.filter(\.isSystem).count == 4)

        for wallet in try repo.wallets() {
            #expect(wallet.categoryID == WalletCategory.builtIn(byKind: wallet.kind).id)
        }

        let postMigrateTxCount = try repo.transactions().count
        #expect(postMigrateTxCount == preMigrateTxCount)

        let postMigrateWallets = try repo.wallets()
        let postWalletAMinor = try #require(postMigrateWallets.first { $0.id == walletA.id }).currentBalanceMinor
        let postWalletBMinor = try #require(postMigrateWallets.first { $0.id == walletB.id }).currentBalanceMinor
        #expect(postWalletAMinor == preMigrateWalletAMinor)
        #expect(postWalletBMinor == preMigrateWalletBMinor)
        #expect(postWalletAMinor + postWalletBMinor == totalNetWorth)

        let transferOutCount = try repo.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type = 'transfer_out'") ?? 0
        }
        let transferInCount = try repo.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type = 'transfer_in'") ?? 0
        }
        #expect(transferOutCount == 1)
        #expect(transferInCount == 1)

        let transferPair = try repo.databaseManager.dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT t_out.id AS out_id, t_out.linked_transfer_id AS out_linked,
                       t_in.id AS in_id, t_in.linked_transfer_id AS in_linked
                FROM transactions t_out
                JOIN transactions t_in ON t_in.id = t_out.linked_transfer_id
                WHERE t_out.type = 'transfer_out'
            """)
        }
        #expect(transferPair != nil)
        let outLinked = transferPair?["out_linked"] as String?
        let inId = transferPair?["in_id"] as String?
        let inLinked = transferPair?["in_linked"] as String?
        let outId = transferPair?["out_id"] as String?
        #expect(outLinked == inId)
        #expect(inLinked == outId)

        let labelLinkCount = try repo.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transaction_labels") ?? 0
        }
        #expect(labelLinkCount == 2)

        let labelsAfter = try repo.labels()
        #expect(labelsAfter.contains(where: { $0.name == "Groceries" }))
        #expect(labelsAfter.contains(where: { $0.name == "Utilities" }))

        let instancesAfter = try repo.recurringInstances()
        #expect(instancesAfter.count == instances.count)
        let postInstanceIDs = Set(instancesAfter.map { $0.id })
        let postTemplateIDs = Set(instancesAfter.map { $0.templateID })
        #expect(postInstanceIDs == fixtureInstanceIDs)
        #expect(postTemplateIDs == fixtureTemplateIDs)
        #expect(postTemplateIDs == [templateID])

        let importJobCount = try repo.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM import_jobs") ?? 0
        }
        #expect(importJobCount == 1)

        let importTxnRow = try repo.databaseManager.dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT import_job_id, import_fingerprint FROM transactions
                WHERE import_fingerprint IS NOT NULL
            """)
        }
        #expect((importTxnRow?["import_job_id"] as String?) == importJob.id.uuidString)
        #expect((importTxnRow?["import_fingerprint"] as String?) == "fp-import-001")

        let ftsMatches = try repo.transactions(query: .init(searchText: "Import"))
        #expect(ftsMatches.count > 0)

        let integrityOk = try fullManager.dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check")
        }
        #expect(integrityOk == "ok")
    }

    @Test func reimportAfterMigrationDedupesNullFingerprintLegacyRows() throws {
        let key = "aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkkllllmmmmnnnnoooopppp"
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])

        let partialMigrator = DatabaseManager.makeMigrator(upTo: "v3_import_idempotency")
        let fixtureManager = try DatabaseManager(locationProvider: location, keychain: keychain, migrator: partialMigrator)
        let fixtureRepo = CashRunwayRepository(databaseManager: fixtureManager)
        try fixtureRepo.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: fixtureRepo)
        let wallet = try #require(try fixtureRepo.wallets().first)
        let expenseCategory = try #require(try fixtureRepo.categories(kind: .expense).first)
        let occurredAt = try #require(ISO8601DateFormatter().date(from: "2025-04-01T00:00:00Z"))

        let transactionID = UUID()
        try fixtureRepo.saveTransaction(TransactionDraft(
            id: transactionID,
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 4200,
            occurredAt: occurredAt,
            categoryID: expenseCategory.id,
            merchant: "Migrated Shop",
            source: .importCSV
        ))
        try fixtureManager.checkpointWal()

        let fullManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repo = CashRunwayRepository(databaseManager: fullManager)
        try repo.seedIfNeeded()

        let nullFingerprintCount = try repo.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE import_fingerprint IS NULL AND source = 'import_csv'") ?? 0
        }
        #expect(nullFingerprintCount == 1)

        let service = CSVService(repository: repo)
        let text = """
        Date,Amount,Merchant,Category,Note
        2025-04-01T00:00:00Z,-42.00,Migrated Shop,Groceries,
        """
        let mapping = CSVImportMapping(
            dateColumn: "Date",
            amountColumn: "Amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: "Merchant",
            noteColumn: "Note",
            categoryColumn: "Category",
            labelsColumn: nil,
            walletID: wallet.id,
            defaultKind: .expense
        )
        let result = try service.importStatement(
            normalizedData: Data(text.utf8),
            fileName: "post-migration.csv",
            format: .genericBankCSV,
            mapping: mapping
        )
        #expect(result.insertedTransactions == 0)
        #expect(result.duplicateRows == 1)

        let truth = try TestSupport.transactionTruth(repo)
        #expect(truth.sourceImportCount == 1)
    }
}
