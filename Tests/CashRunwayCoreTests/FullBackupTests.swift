import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct FullBackupTests {
    @Test func fullBackupIncludesWallets() throws {
        let (repository, _) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()
        let walletCount = try repository.wallets().count

        #expect(backup.wallets.count == walletCount)
        #expect(backup.wallets.contains { $0.name == "Main Wallet" })
    }

    @Test func fullBackupIncludesCategoriesAndLabels() throws {
        let (repository, fixture) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()

        #expect(backup.categories.contains { $0.id == fixture.expenseCategoryID })
        #expect(backup.labels.contains { $0.id == fixture.labelID })
    }

    @Test func fullBackupIncludesTransactions() throws {
        let (repository, _) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()

        #expect(backup.transactions.count == 4)
        #expect(backup.transactions.contains { $0.merchant == "Backup Grocery" })
    }

    @Test func fullBackupIncludesTransactionLabels() throws {
        let (repository, fixture) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()

        #expect(backup.transactionLabels.contains { $0.labelID == fixture.labelID })
    }

    @Test func fullBackupPreservesTransferRelationships() throws {
        let (repository, _) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()
        let out = try #require(backup.transactions.first { $0.type == .transferOut })
        let linked = try #require(backup.transactions.first { $0.id == out.linkedTransferID })

        #expect(linked.type == .transferIn)
        #expect(linked.linkedTransferID == out.id)
        #expect(linked.amountMinor == out.amountMinor)
        #expect(linked.walletID != out.walletID)
    }

    @Test func fullBackupIncludesBudgetsIfPresent() throws {
        let (repository, fixture) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()

        #expect(backup.budgets.contains { $0.id == fixture.budgetID })
    }

    @Test func fullBackupIncludesRecurringTemplatesAndInstances() throws {
        let (repository, fixture) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()

        #expect(backup.recurringTemplates.contains { $0.id == fixture.recurringTemplateID })
        #expect(backup.recurringInstances.contains { $0.templateID == fixture.recurringTemplateID })
    }

    @Test func fullBackupIncludesImportMetadataIfPresent() throws {
        let (repository, fixture) = try makePopulatedRepository()

        let backup = try repository.exportFullBackup()

        #expect(backup.importJobs.contains { $0.id == fixture.importJobID })
    }

    @Test func fullBackupJSONRoundTripsThroughDecoder() throws {
        let (repository, _) = try makePopulatedRepository()
        let service = BackupService(repository: repository)

        let decoded = try service.decode(data: service.encode(try service.exportFullBackup()))

        #expect(decoded.metadata.format == "cash-runway-backup")
        #expect(decoded.metadata.version == 2)
        #expect(decoded.transactions.count == 4)
    }

    @Test func fullBackupDoesNotExposeKeychainOrLocalPaths() throws {
        let (repository, _) = try makePopulatedRepository()
        let service = BackupService(repository: repository)

        let json = String(data: try service.encode(try service.exportFullBackup()), encoding: .utf8) ?? ""

        #expect(!json.localizedCaseInsensitiveContains("database-key"))
        #expect(!json.localizedCaseInsensitiveContains("keychain"))
        #expect(!json.localizedCaseInsensitiveContains("Application Support"))
        #expect(!json.localizedCaseInsensitiveContains(NSTemporaryDirectory()))
    }

    @Test func fullBackupImportRestoresWallets() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        #expect(try target.wallets().count == backup.wallets.filter { !$0.isArchived }.count)
    }

    @Test func fullBackupImportRestoresTransactions() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        #expect(try rawTransactionCount(target) == backup.transactions.count)
    }

    @Test func fullBackupImportRestoresTransactionLabels() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        #expect(try countRows(target, table: "transaction_labels") == backup.transactionLabels.count)
    }

    @Test func fullBackupImportRestoresTransferRelationships() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        try TestSupport.assertNoPartialTransfer(target)
    }

    @Test func fullBackupImportRestoresRecurringTemplatesAndInstances() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        #expect(try target.recurringTemplates().count == backup.recurringTemplates.count)
        #expect(try target.recurringInstances().count == backup.recurringInstances.count)
    }

    @Test func fullBackupImportRebuildsAggregates() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        try TestSupport.assertWalletTruth(target)
        try TestSupport.assertCategoryTruth(target)
    }

    @Test func fullBackupImportRebuildsFTS() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)
        let results = try target.transactions(query: TransactionQuery(searchText: "Backup"), limit: nil)

        #expect(results.contains { $0.merchant == "Backup Grocery" })
    }

    @Test func fullBackupImportRejectsUnsupportedFormat() throws {
        var backup = try makePopulatedRepository().0.exportFullBackup()
        backup.metadata.format = "not-cash-runway"

        #expect(throws: BackupError.unsupportedFormat) {
            try BackupService(repository: try TestSupport.makeRepository()).validate(backup)
        }
    }

    @Test func fullBackupImportRejectsBrokenReferences() throws {
        var backup = try makePopulatedRepository().0.exportFullBackup()
        backup.transactions[0].walletID = UUID()

        #expect(throws: BackupError.brokenReference("transaction \(backup.transactions[0].id) wallet \(backup.transactions[0].walletID)")) {
            try BackupService(repository: try TestSupport.makeRepository()).validate(backup)
        }
    }

    @Test func fullBackupImportRejectsInvalidTransferPairs() throws {
        var backup = try makePopulatedRepository().0.exportFullBackup()
        let index = try #require(backup.transactions.firstIndex { $0.type == .transferOut })
        backup.transactions[index].amountMinor += 1

        #expect(throws: BackupError.self) {
            try BackupService(repository: try TestSupport.makeRepository()).validate(backup)
        }
    }

    @Test func fullBackupImportFailureLeavesCurrentDataUnchanged() throws {
        let (repository, _) = try makePopulatedRepository()
        let before = try repository.exportFullBackup()
        var invalid = before
        invalid.transactions[0].categoryID = UUID()

        #expect(throws: BackupError.self) {
            try repository.restoreFullBackup(invalid)
        }

        let after = try repository.exportFullBackup()
        #expect(after.wallets == before.wallets)
        #expect(after.categories == before.categories)
        #expect(after.transactions == before.transactions)
        #expect(after.transactionLabels == before.transactionLabels)
        try TestSupport.assertWalletTruth(repository)
    }

    @Test func fullBackupImportClearsExistingBankSyncState() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try makePopulatedRepository().0
        try seedBankSyncState(in: target)

        try target.restoreFullBackup(backup)

        #expect(try countRows(target, table: "bank_transaction_imports") == 0)
        #expect(try countRows(target, table: "bank_accounts") == 0)
        #expect(try countRows(target, table: "bank_category_rules") == 0)
        #expect(try countRows(target, table: "bank_integrations") == 0)
    }

    @Test func fullBackupExportDoesNotIncludeBankTransactionImports() throws {
        let repository = try makePopulatedRepository().0
        try seedBankSyncState(in: repository)

        let service = BackupService(repository: repository)
        let backup = try service.exportFullBackup()
        let json = String(data: try service.encode(backup), encoding: .utf8) ?? ""

        // bank_transaction_imports are intentionally excluded from user-facing backups.
        #expect(!json.localizedCaseInsensitiveContains("bank_transaction_imports"))
        #expect(!json.localizedCaseInsensitiveContains("raw_json"))
    }

    @Test func invalidFullBackupImportLeavesExistingBankSyncStateUnchanged() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try makePopulatedRepository().0
        try seedBankSyncState(in: target)
        var invalid = backup
        invalid.transactions[0].categoryID = UUID()

        #expect(throws: BackupError.self) {
            try target.restoreFullBackup(invalid)
        }

        #expect(try countRows(target, table: "bank_transaction_imports") == 1)
        #expect(try countRows(target, table: "bank_accounts") == 1)
        #expect(try countRows(target, table: "bank_category_rules") == 1)
        #expect(try countRows(target, table: "bank_integrations") == 1)
    }

    @Test func fullBackupServiceDeletesClearedBankTokensAfterSuccessfulRestore() throws {
        let backup = try makePopulatedRepository().0.exportFullBackup()
        let target = try makePopulatedRepository().0
        let keychain = TestKeychainStore()
        let tokenStore = KeychainBankTokenStore(keychain: keychain)
        let tokenAccount = try seedBankSyncState(in: target)
        try tokenStore.writeToken("stale-token", account: tokenAccount)
        let service = BackupService(repository: target, bankTokenStore: tokenStore)

        try service.restore(backup)

        #expect(keychain.item(account: tokenAccount) == nil)
    }

    @Test func fullBackupExportThenImportRoundTripPreservesBalances() throws {
        let source = try makePopulatedRepository().0
        let backup = try source.exportFullBackup()
        let sourceBalances = Dictionary(uniqueKeysWithValues: try source.wallets().map { ($0.id, $0.currentBalanceMinor) })
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        let targetBalances = Dictionary(uniqueKeysWithValues: try target.wallets().map { ($0.id, $0.currentBalanceMinor) })
        #expect(targetBalances == sourceBalances)
    }

    @Test func fullBackupImportPreservesTransactionCategoryRelationships() throws {
        let source = try makePopulatedRepository().0
        let backup = try source.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        for backupTx in backup.transactions where backupTx.type == .expense || backupTx.type == .income {
            let restoredDraft = try target.transactionDraft(id: backupTx.id)
            #expect(restoredDraft.categoryID == backupTx.categoryID)
        }
    }

    @Test func fullBackupImportPreservesTransactionWalletRelationships() throws {
        let source = try makePopulatedRepository().0
        let backup = try source.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        for backupTx in backup.transactions where backupTx.type != .transferIn {
            let restoredDraft = try target.transactionDraft(id: backupTx.id)
            #expect(restoredDraft.walletID == backupTx.walletID)
        }
    }

    @Test func fullBackupImportPreservesLedgerSummary() throws {
        let source = try makePopulatedRepository().0
        let monthKey = DateKeys.monthKey(for: Date(timeIntervalSince1970: 1_768_435_200))
        let sourceOverview = try source.overviewSnapshot(monthKey: monthKey)
        let backup = try source.exportFullBackup()
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        let targetOverview = try target.overviewSnapshot(monthKey: monthKey)
        #expect(targetOverview.monthExpenseMinor == sourceOverview.monthExpenseMinor)
        #expect(targetOverview.monthIncomeMinor == sourceOverview.monthIncomeMinor)
        #expect(targetOverview.monthCashFlowMinor == sourceOverview.monthCashFlowMinor)
    }

    private struct FixtureIDs {
        var expenseCategoryID: UUID
        var labelID: UUID
        var budgetID: UUID
        var recurringTemplateID: UUID
        var importJobID: UUID
    }

    private func makePopulatedRepository() throws -> (CashRunwayRepository, FixtureIDs) {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        let now = Date(timeIntervalSince1970: 1_768_435_200)
        let label = LabelBuilder().with(name: "Backup Label").with(colorHex: "#123456").build()
        try repository.saveLabel(label)

        try repository.saveTransaction(
            TransactionBuilder()
                .with(walletID: wallets[0].id)
                .with(amountMinor: 12_345)
                .with(occurredAt: now)
                .with(categoryID: expenseCategory.id)
                .with(labelIDs: [label.id])
                .with(merchant: "Backup Grocery")
                .with(note: "Has label")
                .build()
        )
        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .income)
                .with(walletID: wallets[0].id)
                .with(amountMinor: 50_000)
                .with(occurredAt: now)
                .with(categoryID: incomeCategory.id)
                .with(merchant: "Backup Salary")
                .build()
        )
        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .transfer)
                .with(walletID: wallets[0].id)
                .with(destinationWalletID: wallets[1].id)
                .with(amountMinor: 7_500)
                .with(occurredAt: now)
                .with(labelIDs: [label.id])
                .with(merchant: "Backup Transfer")
                .build()
        )

        let budget = Budget(id: UUID(), categoryID: expenseCategory.id, monthKey: DateKeys.monthKey(for: now), limitMinor: 100_000, isArchived: false, createdAt: now, updatedAt: now)
        try repository.saveBudget(budget)

        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: wallets[0].id,
            counterpartyWalletID: nil,
            amountMinor: 9_999,
            categoryID: expenseCategory.id,
            merchant: "Backup Recurring",
            note: "",
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: DateKeys.calendar.component(.day, from: Date()),
            weekday: nil,
            startDate: Date(),
            endDate: nil,
            isActive: true,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveRecurringTemplate(template)

        let importJobID = UUID()
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO import_jobs (id, source_name, file_name, status, total_rows, valid_rows, invalid_rows, started_at, finished_at, error_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    importJobID.uuidString,
                    "CSV",
                    "backup.csv",
                    ImportJobStatus.committed.rawValue,
                    2,
                    2,
                    0,
                    now,
                    now,
                    nil,
                ]
            )
        }

        return (
            repository,
            FixtureIDs(
                expenseCategoryID: expenseCategory.id,
                labelID: label.id,
                budgetID: budget.id,
                recurringTemplateID: template.id,
                importJobID: importJobID
            )
        )
    }

    @discardableResult
    private func seedBankSyncState(in repository: CashRunwayRepository) throws -> String {
        let walletID = try #require(repository.wallets().first?.id)
        let categoryID = try #require(repository.categories(kind: .expense).first?.id)
        let now = Date(timeIntervalSince1970: 1_768_435_200)
        let integrationID = UUID()
        let accountID = UUID()
        let tokenAccount = "bank-token-monobank-\(integrationID.uuidString)"
        let integration = BankIntegration(
            id: integrationID,
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: now,
            tokenKeychainAccount: tokenAccount,
            lastClientInfoSyncAt: now,
            lastSuccessfulSyncAt: now,
            lastSyncError: nil,
            createdAt: now,
            updatedAt: now
        )
        let account = BankAccount(
            id: accountID,
            integrationID: integrationID,
            provider: .monobank,
            providerAccountID: "mono-card",
            walletID: walletID,
            displayName: "Black Card",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "4444",
            iban: nil,
            isEnabled: true,
            syncStartAt: now,
            lastSuccessfulSyncAt: now,
            lastStatementItemTime: 1_768_435_200,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveBankConnection(integration: integration, accounts: [account])

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bank_transaction_imports (
                    id, provider, integration_id, bank_account_id, provider_account_id,
                    provider_statement_item_id, statement_time, amount_minor_signed,
                    operation_amount_minor_signed, currency_code, mcc, original_mcc,
                    description, comment, counter_name, counter_iban, receipt_id, hold,
                    raw_json, raw_json_expires_at, cash_runway_transaction_id, import_status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    integrationID.uuidString,
                    accountID.uuidString,
                    "mono-card",
                    "statement-1",
                    1_768_435_200,
                    -1200,
                    -1200,
                    980,
                    5411,
                    5411,
                    "Stale grocery",
                    nil,
                    "Market",
                    nil,
                    nil,
                    false,
                    "{}",
                    now.addingTimeInterval(30 * 24 * 60 * 60),
                    nil,
                    BankTransactionImportStatus.imported.rawValue,
                    now,
                    now,
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO bank_category_rules (
                    id, provider, rule_type, merchant_pattern, mcc, category_id,
                    confidence, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    "merchant",
                    "Market",
                    nil,
                    categoryID.uuidString,
                    100,
                    now,
                    now,
                ]
            )
        }

        return tokenAccount
    }

    private func rawTransactionCount(_ repository: CashRunwayRepository) throws -> Int {
        try countRows(repository, table: "transactions")
    }

    private func countRows(_ repository: CashRunwayRepository, table: String) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }
}
