import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MonobankSyncRuleTests {

    // MARK: - CR-009/CR-010: Only selected/enabled UAH expense accounts are imported

    @Test func syncOnlyEnabledAccountsImportsFromEnabledAndSkipsDisabled() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = syncStartAt.addingTimeInterval(60 * 60)
        let walletID = try #require(try repository.wallets().first?.id)

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
        let enabledAccount = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "enabled-acc",
            walletID: walletID,
            displayName: "Enabled Card",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "1111",
            iban: nil,
            isEnabled: true,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        )
        let disabledAccount = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "disabled-acc",
            walletID: walletID,
            displayName: "Disabled Card",
            accountType: "white",
            currencyCode: 980,
            maskedPAN: "2222",
            iban: nil,
            isEnabled: false,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveBankIntegration(integration)
        try repository.saveBankAccount(enabledAccount)
        try repository.saveBankAccount(disabledAccount)

        let client = FakeMonobankClient(statementHandler: { accountID, _, _ in
            if accountID == enabledAccount.providerAccountID {
                return [monobankItem(id: "enabled-tx", time: Int(syncStartAt.addingTimeInterval(30).timeIntervalSince1970), amount: -1_000, currencyCode: 980)]
            }
            if accountID == disabledAccount.providerAccountID {
                return [monobankItem(id: "disabled-tx", time: Int(syncStartAt.addingTimeInterval(31).timeIntervalSince1970), amount: -2_000, currencyCode: 980)]
            }
            return []
        })
        let service = BankSyncService(repository: repository, client: client, now: { now })

        let result = try await service.syncIntegration(integration.id)

        let requests = client.statementRequests
        #expect(requests.count == 1)
        #expect(requests.first?.accountID == enabledAccount.providerAccountID)
        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 0)
        #expect(try bankSyncTransactionCount(repository) == 1)

        let importedIDs = try bankSyncStatementIDs(repository)
        #expect(importedIDs.contains("enabled-tx"))
        #expect(!importedIDs.contains("disabled-tx"))
    }

    // MARK: - CR-011: Overlapping sync windows are idempotent

    @Test func overlappingSyncWindowsDoNotDuplicateTransactions() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstSyncAt = syncStartAt.addingTimeInterval(60 * 60)
        let secondSyncAt = syncStartAt.addingTimeInterval(2 * 60 * 60)
        let setup = try makeBankSetup(repository: repository, syncStartAt: syncStartAt)
        let txTime = syncStartAt.addingTimeInterval(30 * 60)

        let client = FakeMonobankClient(items: [
            monobankItem(id: "overlap-tx", time: Int(txTime.timeIntervalSince1970), amount: -5_000, currencyCode: 980),
        ])
        let firstService = BankSyncService(repository: repository, client: client, now: { firstSyncAt })
        let secondService = BankSyncService(repository: repository, client: client, now: { secondSyncAt })

        let first = try await firstService.syncIntegration(setup.integration.id)
        let second = try await secondService.syncIntegration(setup.integration.id)

        #expect(first.importedCount == 1)
        #expect(first.skippedCount == 0)
        #expect(second.importedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(try bankSyncTransactionCount(repository) == 1)
        #expect(try bankImportCount(repository) == 1)
    }

    // MARK: - Helpers

    private func makeBankSetup(repository: CashRunwayRepository, syncStartAt: Date) throws -> (integration: BankIntegration, account: BankAccount) {
        let walletID = try #require(try repository.wallets().first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
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
        return (integration, account)
    }

    private func monobankItem(id: String, time: Int, amount: Int64, currencyCode: Int) -> MonobankStatementItem {
        MonobankStatementItem(
            id: id,
            time: time,
            description: "Merchant",
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
            counterName: "Merchant"
        )
    }

    private func bankSyncTransactionCount(_ repository: CashRunwayRepository) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE source = ?", arguments: [TransactionSource.bankSync.rawValue]) ?? 0
        }
    }

    private func bankImportCount(_ repository: CashRunwayRepository) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bank_transaction_imports") ?? 0
        }
    }

    private func bankSyncStatementIDs(_ repository: CashRunwayRepository) throws -> [String] {
        try repository.databaseManager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT i.provider_statement_item_id
                FROM bank_transaction_imports i
                JOIN transactions t ON t.id = i.cash_runway_transaction_id
                WHERE t.source = ?
                """,
                arguments: [TransactionSource.bankSync.rawValue]
            )
        }
    }
}

private final class FakeMonobankClient: MonobankClient, @unchecked Sendable {
    private let clientInfoHandler: () throws -> MonobankClientInfo
    private let statementHandler: (String, Date, Date) throws -> [MonobankStatementItem]
    private(set) var statementRequests: [(accountID: String, from: Date, to: Date)] = []

    init(
        items: [MonobankStatementItem] = [],
        error: Error? = nil,
        statementHandler: ((String, Date, Date) throws -> [MonobankStatementItem])? = nil,
        clientInfoHandler: (() throws -> MonobankClientInfo)? = nil
    ) {
        if let clientInfoHandler {
            self.clientInfoHandler = clientInfoHandler
        } else {
            self.clientInfoHandler = {
                if let error { throw error }
                return MonobankClientInfo(name: "Test User", accounts: [])
            }
        }
        if let statementHandler {
            self.statementHandler = statementHandler
        } else {
            self.statementHandler = { _, _, _ in
                if let error { throw error }
                return items
            }
        }
    }

    func clientInfo() async throws -> MonobankClientInfo {
        try clientInfoHandler()
    }

    func statement(accountID: String, from: Date, to: Date) async throws -> [MonobankStatementItem] {
        statementRequests.append((accountID, from, to))
        return try statementHandler(accountID, from, to)
    }
}
