import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MonobankImportRollbackTests {
    @Test func monobankBatchFailureRollsBackAllItems() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let initialBalance = wallet.currentBalanceMinor

        let otherExpenseID = UUID(uuidString: "11111111-1111-1111-1111-111111111122")!
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [otherExpenseID.uuidString])
        }

        let setup = try makeBankSetup(repository: repository)

        let succeedsFirstItem = MonobankStatementItem(
            id: "succeeds-first", time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
            description: "ATB Market", mcc: 5411, originalMcc: 5411,
            amount: -10_000, operationAmount: nil, currencyCode: 980,
            commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
            receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
            counterName: "ATB"
        )

        let failsSecondItem = MonobankStatementItem(
            id: "fails-second", time: Int(setup.syncStartAt.addingTimeInterval(120).timeIntervalSince1970),
            description: "NoMatchPossible", mcc: nil, originalMcc: nil,
            amount: -5_000, operationAmount: nil, currencyCode: 980,
            commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
            receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
            counterName: "NoMatchPossible"
        )

        do {
            _ = try repository.importMonobankExpenseItems(
                [succeedsFirstItem, failsSecondItem],
                account: setup.account, integration: setup.integration
            )
            #expect(Bool(false), "Expected throw for unresolvable category")
        } catch {
            #expect(error is CashRunwayError)
        }

        let txAfterRollback = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txAfterRollback == 0)

        let importsAfterRollback = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bank_transaction_imports") ?? 0
        }
        #expect(importsAfterRollback == 0)

        let walletAfterRollback = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfterRollback.currentBalanceMinor == initialBalance)

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO categories (id, name, kind, is_system, sort_order, created_at, updated_at) VALUES (?, ?, 'expense', 1, 0, ?, ?)",
                arguments: [otherExpenseID.uuidString, "Other Expense", Date(), Date()]
            )
        }

        let correctedItems = [
            MonobankStatementItem(
                id: "corrected-001", time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
                description: "ATB", mcc: 5411, originalMcc: 5411,
                amount: -10_000, operationAmount: nil, currencyCode: 980,
                commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
                receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
                counterName: "ATB"
            ),
            MonobankStatementItem(
                id: "corrected-002", time: Int(setup.syncStartAt.addingTimeInterval(120).timeIntervalSince1970),
                description: "Silpo", mcc: 5411, originalMcc: 5411,
                amount: -5_000, operationAmount: nil, currencyCode: 980,
                commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
                receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
                counterName: "Silpo"
            ),
        ]

        let firstResult = try repository.importMonobankExpenseItems(correctedItems, account: setup.account, integration: setup.integration)
        #expect(firstResult.importedCount == 2)
        #expect(firstResult.skippedCount == 0)

        let txAfterCorrected = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txAfterCorrected == 2)

        let importsAfterCorrected = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bank_transaction_imports") ?? 0
        }
        #expect(importsAfterCorrected == 2)

        let walletAfterCorrected = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfterCorrected.currentBalanceMinor == initialBalance - 15_000)

        let retryResult = try repository.importMonobankExpenseItems(correctedItems, account: setup.account, integration: setup.integration)
        #expect(retryResult.importedCount == 0)
        #expect(retryResult.skippedCount == 2)

        let txAfterRetry = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txAfterRetry == 2)

        let walletAfterRetry = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfterRetry.currentBalanceMinor == initialBalance - 15_000)
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
}