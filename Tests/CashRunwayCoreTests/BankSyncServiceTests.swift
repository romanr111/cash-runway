import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BankSyncServiceTests {
    @Test func statementWindowsNeverExceedThirtyOneDays() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(70 * 24 * 60 * 60)

        let windows = statementWindows(from: start, to: end)

        #expect(windows.count == 3)
        #expect(windows.first?.start == start)
        #expect(windows.last?.end == end)
        #expect(windows.allSatisfy { $0.duration <= 31 * 24 * 60 * 60 })
    }

    @Test func syncIntegrationQueriesFromSyncStartAndImportsOnlyEligibleItems() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = syncStartAt.addingTimeInterval(60 * 60)
        let setup = try makeBankSetup(repository: repository, syncStartAt: syncStartAt)
        let client = FakeMonobankClient(items: [
            monobankItem(id: "old", time: Int(syncStartAt.addingTimeInterval(-1).timeIntervalSince1970), amount: -1_000, currencyCode: 980),
            monobankItem(id: "income", time: Int(syncStartAt.addingTimeInterval(1).timeIntervalSince1970), amount: 1_000, currencyCode: 980),
            monobankItem(id: "usd", time: Int(syncStartAt.addingTimeInterval(2).timeIntervalSince1970), amount: -1_000, currencyCode: 840),
            monobankItem(id: "valid", time: Int(syncStartAt.addingTimeInterval(3).timeIntervalSince1970), amount: -2_500, currencyCode: 980),
        ])
        let service = BankSyncService(repository: repository, client: client, now: { now })

        let result = try await service.syncIntegration(setup.integration.id)

        let requests = client.statementRequests
        let refreshedAccount = try #require(try repository.bankAccounts(integrationID: setup.integration.id).first)
        #expect(requests.count == 1)
        #expect(requests.first?.accountID == setup.account.providerAccountID)
        #expect(requests.first?.from == syncStartAt)
        #expect(requests.first?.to == now)
        #expect(result.importedCount == 1)
        #expect(result.skippedCount == 3)
        #expect(result.syncedAccountCount == 1)
        #expect(refreshedAccount.lastSuccessfulSyncAt == now)
        #expect(try bankSyncTransactionCount(repository) == 1)
    }

    @Test func invalidTokenMarksIntegrationTokenInvalid() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository, syncStartAt: Date(timeIntervalSince1970: 1_700_000_000))
        let client = FakeMonobankClient(error: BankSyncError.tokenInvalid)
        let service = BankSyncService(repository: repository, client: client, now: { Date(timeIntervalSince1970: 1_800_000_000) })

        await #expect(throws: BankSyncError.tokenInvalid) {
            try await service.syncIntegration(setup.integration.id)
        }

        let stored = try #require(try repository.bankIntegrations().first { $0.id == setup.integration.id })
        #expect(stored.status == .tokenInvalid)
    }

    @Test func syncOnDemandContinuesPastInvalidTokenIntegration() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = syncStartAt.addingTimeInterval(60 * 60)
        let invalidSetup = try makeBankSetup(
            repository: repository,
            syncStartAt: syncStartAt,
            integrationDisplayName: "Monobank One",
            providerAccountID: "mono-account-1"
        )
        let validSetup = try makeBankSetup(
            repository: repository,
            syncStartAt: syncStartAt,
            integrationDisplayName: "Monobank Two",
            providerAccountID: "mono-account-2"
        )
        let client = FakeMonobankClient(statementHandler: { accountID, _, _ in
            if accountID == invalidSetup.account.providerAccountID {
                throw BankSyncError.tokenInvalid
            }
            if accountID == validSetup.account.providerAccountID {
                return [
                    monobankItem(
                        id: "valid",
                        time: Int(syncStartAt.addingTimeInterval(3).timeIntervalSince1970),
                        amount: -2_500,
                        currencyCode: 980
                    )
                ]
            }
            return []
        })
        let service = BankSyncService(repository: repository, client: client, now: { now })

        let result = try await service.syncOnDemand()

        let integrations = try repository.bankIntegrations()
        let invalidStored = try #require(integrations.first { $0.id == invalidSetup.integration.id })
        let validAccount = try #require(try repository.bankAccounts(integrationID: validSetup.integration.id).first)

        #expect(result.importedCount == 1)
        #expect(result.syncedAccountCount == 1)
        #expect(invalidStored.status == .tokenInvalid)
        #expect(validAccount.lastSuccessfulSyncAt == now)
        #expect(try bankSyncTransactionCount(repository) == 1)
    }

    @Test func rateLimitReturnsSafeErrorWithoutDisablingIntegration() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let setup = try makeBankSetup(repository: repository, syncStartAt: Date(timeIntervalSince1970: 1_700_000_000))
        let client = FakeMonobankClient(error: BankSyncError.rateLimited)
        let service = BankSyncService(repository: repository, client: client, now: { Date(timeIntervalSince1970: 1_800_000_000) })

        await #expect(throws: BankSyncError.rateLimited) {
            try await service.syncIntegration(setup.integration.id)
        }

        let stored = try #require(try repository.bankIntegrations().first { $0.id == setup.integration.id })
        #expect(stored.status == .active)
    }

    @Test func runningSyncTwiceCreatesNoDuplicateTransactions() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = syncStartAt.addingTimeInterval(60 * 60)
        let setup = try makeBankSetup(repository: repository, syncStartAt: syncStartAt)
        let client = FakeMonobankClient(items: [
            monobankItem(id: "same-statement-id", time: Int(syncStartAt.addingTimeInterval(3).timeIntervalSince1970), amount: -2_500, currencyCode: 980),
        ])
        let service = BankSyncService(repository: repository, client: client, now: { now })

        let first = try await service.syncIntegration(setup.integration.id)
        let second = try await service.syncIntegration(setup.integration.id)

        #expect(first.importedCount == 1)
        #expect(second.importedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(try bankSyncTransactionCount(repository) == 1)
    }

    private func makeBankSetup(
        repository: CashRunwayRepository,
        syncStartAt: Date,
        integrationDisplayName: String = "Monobank",
        providerAccountID: String = "mono-account-1"
    ) throws -> (integration: BankIntegration, account: BankAccount) {
        let walletID = try #require(try repository.wallets().first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: integrationDisplayName,
            status: .active,
            syncStartAt: syncStartAt,
            tokenKeychainAccount: "mono-token-\(providerAccountID)",
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
            providerAccountID: providerAccountID,
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
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transactions WHERE source = ?",
                arguments: [TransactionSource.bankSync.rawValue]
            ) ?? 0
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
