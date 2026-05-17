import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BankSyncImportTests {
    @Test func importsNegativeUAHMonobankItemAfterSyncStart() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)

        let result = try repository.importMonobankExpenseItems(
            [
                monobankItem(
                    id: "statement-valid-1",
                    time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
                    amount: -12_345,
                    currencyCode: 980,
                    description: "ATB Market",
                    comment: "Weekly food",
                    counterName: "ATB"
                ),
            ],
            account: setup.account,
            integration: setup.integration
        )

        let stored = try repository.databaseManager.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT t.id, t.type, t.amount_minor, t.merchant, t.note, t.source, i.provider_statement_item_id
                FROM transactions t
                JOIN bank_transaction_imports i ON i.cash_runway_transaction_id = t.id
                WHERE t.source = ?
                """,
                arguments: [TransactionSource.bankSync.rawValue]
            )
        }

        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 0)
        #expect(stored?["type"] as String? == TransactionKind.expense.rawValue)
        #expect(stored?["amount_minor"] as Int64? == 12_345)
        #expect(stored?["merchant"] as String? == "ATB")
        #expect(stored?["note"] as String? == "Weekly food")
        #expect(stored?["source"] as String? == TransactionSource.bankSync.rawValue)
        #expect(stored?["provider_statement_item_id"] as String? == "statement-valid-1")
    }

    @Test func skipsOldPositiveZeroAndNonUAHMonobankItems() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)

        let result = try repository.importMonobankExpenseItems(
            [
                monobankItem(id: "old", time: Int(setup.syncStartAt.addingTimeInterval(-1).timeIntervalSince1970), amount: -1_000, currencyCode: 980, description: "Old"),
                monobankItem(id: "positive", time: Int(setup.syncStartAt.addingTimeInterval(1).timeIntervalSince1970), amount: 1_000, currencyCode: 980, description: "Income"),
                monobankItem(id: "zero", time: Int(setup.syncStartAt.addingTimeInterval(2).timeIntervalSince1970), amount: 0, currencyCode: 980, description: "Zero"),
                monobankItem(id: "usd", time: Int(setup.syncStartAt.addingTimeInterval(3).timeIntervalSince1970), amount: -1_000, currencyCode: 840, description: "USD"),
                monobankItem(id: "valid", time: Int(setup.syncStartAt.addingTimeInterval(4).timeIntervalSince1970), amount: -2_000, currencyCode: 980, description: "Valid"),
            ],
            account: setup.account,
            integration: setup.integration
        )

        let counts = try bankSyncCounts(repository)
        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 4)
        #expect(counts.transactions == 1)
        #expect(counts.imports == 1)
    }

    @Test func dedupesSameMonobankStatementItemID() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)
        let item = monobankItem(
            id: "duplicate-statement",
            time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
            amount: -1_500,
            currencyCode: 980,
            description: "Same Item"
        )

        let first = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)
        let second = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)

        let counts = try bankSyncCounts(repository)
        #expect(first.importedCount == 1)
        #expect(first.skippedCount == 0)
        #expect(second.importedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(counts.transactions == 1)
        #expect(counts.imports == 1)
    }

    @Test func bankImportDoesNotModifyExistingTransactionsWithSameDateAmountMerchant() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository)
        let categories = try repository.categories(kind: .expense)
        let categoryID = try #require(categories.first?.id)
        let occurredAt = setup.syncStartAt.addingTimeInterval(60)

        for source in [TransactionSource.manual, .importCSV, .recurring] {
            try repository.saveTransaction(TransactionDraft(
                kind: .expense,
                walletID: setup.account.walletID,
                amountMinor: 2_500,
                occurredAt: occurredAt,
                categoryID: categoryID,
                merchant: "Merchant",
                source: source
            ))
        }

        let result = try repository.importMonobankExpenseItems(
            [
                monobankItem(
                    id: "same-visible-details",
                    time: Int(occurredAt.timeIntervalSince1970),
                    amount: -2_500,
                    currencyCode: 980,
                    description: "Merchant",
                    counterName: "Merchant"
                ),
            ],
            account: setup.account,
            integration: setup.integration
        )

        let counts = try transactionCountsBySource(repository)
        #expect(result.importedCount == 1)
        #expect(counts[TransactionSource.manual.rawValue] == 1)
        #expect(counts[TransactionSource.importCSV.rawValue] == 1)
        #expect(counts[TransactionSource.recurring.rawValue] == 1)
        #expect(counts[TransactionSource.bankSync.rawValue] == 1)
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
            maskedPAN: "4444",
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

    private func monobankItem(
        id: String,
        time: Int,
        amount: Int64,
        currencyCode: Int,
        description: String,
        comment: String? = nil,
        counterName: String? = nil
    ) -> MonobankStatementItem {
        MonobankStatementItem(
            id: id,
            time: time,
            description: description,
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
            comment: comment,
            counterEdrpou: nil,
            counterIban: nil,
            counterName: counterName
        )
    }

    private func bankSyncCounts(_ repository: CashRunwayRepository) throws -> (transactions: Int, imports: Int) {
        try repository.databaseManager.dbQueue.read { db in
            let transactions = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transactions WHERE source = ?",
                arguments: [TransactionSource.bankSync.rawValue]
            ) ?? 0
            let imports = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bank_transaction_imports") ?? 0
            return (transactions, imports)
        }
    }

    private func transactionCountsBySource(_ repository: CashRunwayRepository) throws -> [String: Int] {
        try repository.databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT source, COUNT(*) AS count FROM transactions GROUP BY source")
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (row["source"] as String, row["count"] as Int)
            })
        }
    }
}
