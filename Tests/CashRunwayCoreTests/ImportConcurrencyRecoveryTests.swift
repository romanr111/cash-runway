import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct ImportConcurrencyRecoveryTests {

    @Test func duplicateStatementItemIDProducesAtMostOneTransaction() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let initialBalance = wallet.currentBalanceMinor
        let setup = try makeBankSetup(repository: repository)

        let item = MonobankStatementItem(
            id: "dup-statement-001",
            time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
            description: "ATB", mcc: 5411, originalMcc: 5411,
            amount: -10_000, operationAmount: nil, currencyCode: 980,
            commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
            receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
            counterName: "ATB"
        )

        let first = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)
        let second = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)
        let third = try repository.importMonobankExpenseItems([item], account: setup.account, integration: setup.integration)

        #expect(first.importedCount == 1)
        #expect(second.importedCount == 0)
        #expect(third.importedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(third.skippedCount == 1)

        let txCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txCount == 1)

        let importRows = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bank_transaction_imports WHERE provider_statement_item_id = ?", arguments: [item.id]) ?? 0
        }
        #expect(importRows == 1)

        let walletAfter = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfter.currentBalanceMinor == initialBalance - 10_000)
    }

    @Test func overlappingSyncWindowsDoNotDuplicate() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let initialBalance = wallet.currentBalanceMinor
        let setup = try makeBankSetup(repository: repository)

        let items = (1...5).map { index in
            MonobankStatementItem(
                id: "overlap-\(index)",
                time: Int(setup.syncStartAt.addingTimeInterval(TimeInterval(index * 60)).timeIntervalSince1970),
                description: "Merchant\(index)", mcc: 5411, originalMcc: 5411,
                amount: -Int64(index * 1_000), operationAmount: nil, currencyCode: 980,
                commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
                receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
                counterName: "Merchant\(index)"
            )
        }

        let firstBatch = try repository.importMonobankExpenseItems(items, account: setup.account, integration: setup.integration)
        let overlappingBatch = try repository.importMonobankExpenseItems(items, account: setup.account, integration: setup.integration)

        #expect(firstBatch.importedCount == 5)
        #expect(overlappingBatch.importedCount == 0)
        #expect(overlappingBatch.skippedCount == 5)

        let txCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txCount == 5)

        let walletAfter = try #require(try repository.wallets().first { $0.id == wallet.id })
        let expectedTotal: Int64 = (1...5).map { Int64($0 * 1_000) }.reduce(0, +)
        #expect(walletAfter.currentBalanceMinor == initialBalance - expectedTotal)
    }

    @Test func retryAfterInterruptedImportProducesSameResult() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let initialBalance = wallet.currentBalanceMinor
        let setup = try makeBankSetup(repository: repository)

        let items = [
            MonobankStatementItem(
                id: "retry-001", time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
                description: "Shop1", mcc: 5411, originalMcc: 5411,
                amount: -5_000, operationAmount: nil, currencyCode: 980,
                commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
                receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
                counterName: "Shop1"
            ),
            MonobankStatementItem(
                id: "retry-002", time: Int(setup.syncStartAt.addingTimeInterval(120).timeIntervalSince1970),
                description: "Shop2", mcc: 5411, originalMcc: 5411,
                amount: -3_000, operationAmount: nil, currencyCode: 980,
                commissionRate: nil, cashbackAmount: nil, balance: nil, hold: nil,
                receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
                counterName: "Shop2"
            ),
        ]

        let first = try repository.importMonobankExpenseItems(items, account: setup.account, integration: setup.integration)
        #expect(first.importedCount == 2)

        let retry = try repository.importMonobankExpenseItems(items, account: setup.account, integration: setup.integration)
        #expect(retry.importedCount == 0)
        #expect(retry.skippedCount == 2)

        let txCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txCount == 2)

        let walletAfter = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfter.currentBalanceMinor == initialBalance - 8_000)
    }

    @Test func heldItemImportedOnceEvenWithSameDetails() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try #require(try repository.wallets().first)
        let initialBalance = wallet.currentBalanceMinor
        let setup = try makeBankSetup(repository: repository)

        let heldItem = MonobankStatementItem(
            id: "held-stmt-001",
            time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
            description: "Pending", mcc: 5411, originalMcc: 5411,
            amount: -2_000, operationAmount: nil, currencyCode: 980,
            commissionRate: nil, cashbackAmount: nil, balance: nil,
            hold: true,
            receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
            counterName: "Pending"
        )

        let result = try repository.importMonobankExpenseItems([heldItem], account: setup.account, integration: setup.integration)
        #expect(result.importedCount == 1)

        let finalItem = MonobankStatementItem(
            id: "held-stmt-001",
            time: Int(setup.syncStartAt.addingTimeInterval(60).timeIntervalSince1970),
            description: "Pending", mcc: 5411, originalMcc: 5411,
            amount: -2_000, operationAmount: nil, currencyCode: 980,
            commissionRate: nil, cashbackAmount: nil, balance: nil,
            hold: false,
            receiptId: nil, comment: nil, counterEdrpou: nil, counterIban: nil,
            counterName: "Pending"
        )

        let retryResult = try repository.importMonobankExpenseItems([finalItem], account: setup.account, integration: setup.integration)
        #expect(retryResult.importedCount == 0)
        #expect(retryResult.skippedCount == 1)

        let txCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
        #expect(txCount == 1)

        let walletAfter = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(walletAfter.currentBalanceMinor == initialBalance - 2_000)
    }

    private func makeBankSetup(repository: CashRunwayRepository) throws -> (integration: BankIntegration, account: BankAccount, syncStartAt: Date) {
        let walletID = try #require(try repository.wallets().first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let integration = BankIntegration(
            id: UUID(), provider: .monobank, displayName: "Monobank",
            status: .active, syncStartAt: syncStartAt,
            tokenKeychainAccount: "mono-token",
            lastClientInfoSyncAt: nil, lastSuccessfulSyncAt: nil, lastSyncError: nil,
            createdAt: now, updatedAt: now
        )
        let account = BankAccount(
            id: UUID(), integrationID: integration.id, provider: .monobank,
            providerAccountID: "mono-1", walletID: walletID,
            displayName: "Black", accountType: "black",
            currencyCode: 980, maskedPAN: "4444", iban: nil,
            isEnabled: true, syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil, lastStatementItemTime: nil,
            createdAt: now, updatedAt: now
        )
        try repository.saveBankIntegration(integration)
        try repository.saveBankAccount(account)
        return (integration, account, syncStartAt)
    }
}