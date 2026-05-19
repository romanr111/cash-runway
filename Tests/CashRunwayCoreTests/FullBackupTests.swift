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
        #expect(decoded.metadata.version == 1)
        #expect(decoded.transactions.count == 4)
    }

    @Test func fullBackupDoesNotExposeKeychainOrLocalPaths() throws {
        let (repository, _) = try makePopulatedRepository()
        let service = BackupService(repository: repository)

        let json = String(decoding: try service.encode(try service.exportFullBackup()), as: UTF8.self)

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

    @Test func fullBackupExportThenImportRoundTripPreservesBalances() throws {
        let source = try makePopulatedRepository().0
        let backup = try source.exportFullBackup()
        let sourceBalances = Dictionary(uniqueKeysWithValues: try source.wallets().map { ($0.id, $0.currentBalanceMinor) })
        let target = try TestSupport.makeRepository()

        try target.restoreFullBackup(backup)

        let targetBalances = Dictionary(uniqueKeysWithValues: try target.wallets().map { ($0.id, $0.currentBalanceMinor) })
        #expect(targetBalances == sourceBalances)
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

    private func rawTransactionCount(_ repository: CashRunwayRepository) throws -> Int {
        try countRows(repository, table: "transactions")
    }

    private func countRows(_ repository: CashRunwayRepository, table: String) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }
}
