import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BankConnectionServiceTests {
    @Test func tokenValidationCallsClientInfoOnly() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let validator = FakeMonobankTokenValidator(
            info: MonobankClientInfo(name: "Test User", accounts: [Self.uahAccount(id: "account-1")])
        )
        let service = MonobankConnectionService(
            repository: repository,
            tokenStore: KeychainBankTokenStore(keychain: TestKeychainStore()),
            tokenValidator: validator,
            syncPerformer: RecordingBankSyncPerformer()
        )

        let info = try await service.validateToken("personal-token")

        #expect(info.accounts.map(\.id) == ["account-1"])
        #expect(validator.validatedTokens == ["personal-token"])
        #expect(try repository.bankIntegrations().isEmpty)
    }

    @Test func finalConfirmationCreatesActiveIntegrationAndSelectedUAHAccounts() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let keychain = TestKeychainStore()
        let tokenStore = KeychainBankTokenStore(keychain: keychain)
        let syncStartAt = Date(timeIntervalSince1970: 1_800_000_000)
        let walletID = try #require(try repository.wallets().first?.id)
        let syncPerformer = RecordingBankSyncPerformer()
        let service = MonobankConnectionService(
            repository: repository,
            tokenStore: tokenStore,
            tokenValidator: FakeMonobankTokenValidator(info: MonobankClientInfo(name: "Test User", accounts: [])),
            syncPerformer: syncPerformer,
            now: { syncStartAt }
        )

        let integration = try await service.connectMonobank(
            token: "personal-token",
            selections: [
                MonobankAccountConnectionSelection(account: Self.uahAccount(id: "uah-1", name: "Black", maskedPAN: ["1234"]), walletID: walletID, isEnabled: true),
                MonobankAccountConnectionSelection(account: Self.uahAccount(id: "uah-2", name: "White", maskedPAN: ["5678"]), walletID: walletID, isEnabled: false),
                MonobankAccountConnectionSelection(account: Self.usdAccount(id: "usd-1"), walletID: walletID, isEnabled: true),
            ]
        )

        let storedIntegration = try #require(try repository.bankIntegrations().first)
        let storedAccounts = try repository.bankAccounts(integrationID: integration.id)

        #expect(storedIntegration.status == .active)
        #expect(storedIntegration.provider == .monobank)
        #expect(storedIntegration.syncStartAt == syncStartAt)
        #expect(storedIntegration.tokenKeychainAccount.hasPrefix("bank-token-monobank-"))
        #expect(String(data: keychain.item(account: storedIntegration.tokenKeychainAccount) ?? Data(), encoding: .utf8) == "personal-token")
        #expect(storedAccounts.map(\.providerAccountID) == ["uah-1"])
        #expect(storedAccounts.first?.syncStartAt == syncStartAt)
        #expect(syncPerformer.syncedIntegrationIDs == [integration.id])
    }

    @Test func connectionFailureRollsBackRowsAndDeletesStoredToken() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let keychain = TestKeychainStore()
        let walletID = try #require(try repository.wallets().first?.id)
        let service = MonobankConnectionService(
            repository: repository,
            tokenStore: KeychainBankTokenStore(keychain: keychain),
            tokenValidator: FakeMonobankTokenValidator(info: MonobankClientInfo(name: "Test User", accounts: [])),
            syncPerformer: RecordingBankSyncPerformer()
        )

        await #expect(throws: Error.self) {
            _ = try await service.connectMonobank(
                token: "personal-token",
                selections: [
                    MonobankAccountConnectionSelection(account: Self.uahAccount(id: "duplicate"), walletID: walletID, isEnabled: true),
                    MonobankAccountConnectionSelection(account: Self.uahAccount(id: "duplicate"), walletID: walletID, isEnabled: true),
                ]
            )
        }

        let writtenAccount = try #require(keychain.writeHistory.first?.account)
        #expect(keychain.item(account: writtenAccount) == nil)
        #expect(keychain.deleteCount == 1)
        #expect(try repository.bankIntegrations().isEmpty)
    }

    @Test func enabledAccountRequiresExistingWalletMapping() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let service = MonobankConnectionService(
            repository: repository,
            tokenStore: KeychainBankTokenStore(keychain: TestKeychainStore()),
            tokenValidator: FakeMonobankTokenValidator(info: MonobankClientInfo(name: "Test User", accounts: [])),
            syncPerformer: RecordingBankSyncPerformer()
        )

        await #expect(throws: CashRunwayError.self) {
            _ = try await service.connectMonobank(
                token: "personal-token",
                selections: [
                    MonobankAccountConnectionSelection(account: Self.uahAccount(id: "uah-1"), walletID: UUID(), isEnabled: true),
                ]
            )
        }

        #expect(try repository.bankIntegrations().isEmpty)
    }

    @Test func successfulSyncClearsPreviousErrorAndUpdatesIntegrationStatus() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = syncStartAt.addingTimeInterval(60)
        let walletID = try #require(try repository.wallets().first?.id)
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: syncStartAt,
            tokenKeychainAccount: "token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: "Previous sync failed",
            createdAt: syncStartAt,
            updatedAt: syncStartAt
        )
        let account = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "account-1",
            walletID: walletID,
            displayName: "Black",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "1234",
            iban: nil,
            isEnabled: true,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: syncStartAt,
            updatedAt: syncStartAt
        )
        try repository.saveBankIntegration(integration)
        try repository.saveBankAccount(account)
        let client = FakeMonobankClient(items: [
            monobankItem(id: "statement-1", time: Int(syncStartAt.addingTimeInterval(1).timeIntervalSince1970), amount: -2_500),
        ])
        let service = BankSyncService(repository: repository, client: client, now: { now })

        _ = try await service.syncIntegration(integration.id)

        let stored = try #require(try repository.bankIntegrations().first { $0.id == integration.id })
        #expect(stored.status == .active)
        #expect(stored.lastSuccessfulSyncAt == now)
        #expect(stored.lastSyncError == nil)
    }

    @Test func serializedPerformerDoesNotRunManualAndForegroundSyncInParallel() async throws {
        let base = BlockingBankSyncPerformer()
        let performer = BankSyncSerialPerformer(base)

        let manualTask = Task {
            try await performer.syncOnDemand()
        }
        let foregroundTask = Task {
            try await performer.syncOnForeground()
        }

        await base.waitUntilCallCount(1)
        #expect(await base.callCount == 1)
        #expect(await base.maxActiveCount == 1)

        await base.releaseNext()
        _ = try await manualTask.value
        await base.waitUntilCallCount(2)
        #expect(await base.maxActiveCount == 1)

        await base.releaseNext()
        _ = try await foregroundTask.value
        #expect(await base.callCount == 2)
    }

    @Test func disconnectDisablesIntegrationAndKeepsImportedTransactions() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let keychain = TestKeychainStore()
        let tokenStore = KeychainBankTokenStore(keychain: keychain)
        let syncStartAt = Date(timeIntervalSince1970: 1_800_000_000)
        let walletID = try #require(try repository.wallets().first?.id)
        let service = MonobankConnectionService(
            repository: repository,
            tokenStore: tokenStore,
            tokenValidator: FakeMonobankTokenValidator(info: MonobankClientInfo(name: "Test User", accounts: [])),
            syncPerformer: RecordingBankSyncPerformer(),
            now: { syncStartAt }
        )
        let integration = try await service.connectMonobank(
            token: "personal-token",
            selections: [
                MonobankAccountConnectionSelection(account: Self.uahAccount(id: "uah-1"), walletID: walletID, isEnabled: true),
            ]
        )
        let account = try #require(try repository.bankAccounts(integrationID: integration.id).first)
        _ = try repository.importMonobankExpenseItems(
            [monobankItem(id: "statement-1", time: Int(syncStartAt.timeIntervalSince1970) + 1, amount: -2_500)],
            account: account,
            integration: integration
        )

        try service.disconnectIntegration(integration.id)

        let disabled = try #require(try repository.bankIntegrations().first)
        #expect(disabled.status == .disabled)
        #expect(keychain.item(account: disabled.tokenKeychainAccount) == nil)
        #expect(try bankSyncTransactionCount(repository) == 1)
        #expect(try bankImportCount(repository) == 1)
    }

    @Test func learningMerchantCategoryRuleAffectsFutureImports() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let syncStartAt = Date(timeIntervalSince1970: 1_800_000_000)
        let walletID = try #require(try repository.wallets().first?.id)
        let groceries = try #require(try repository.categories(kind: .expense).first { $0.name == "Groceries" })
        let other = try #require(try repository.categories(kind: .expense).first { $0.name == "Other Expense" })
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: syncStartAt,
            tokenKeychainAccount: "token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: syncStartAt,
            updatedAt: syncStartAt
        )
        let account = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "account-1",
            walletID: walletID,
            displayName: "Black",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: "1234",
            iban: nil,
            isEnabled: true,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: syncStartAt,
            updatedAt: syncStartAt
        )
        try repository.saveBankIntegration(integration)
        try repository.saveBankAccount(account)
        let first = try repository.importMonobankExpenseItems(
            [monobankItem(id: "statement-1", time: Int(syncStartAt.timeIntervalSince1970) + 1, amount: -2_500, description: "SILPO")],
            account: account,
            integration: integration
        )
        #expect(first.importedCount == 1)
        let firstTransactionID = try #require(try bankSyncTransactionIDs(repository).first)
        #expect(try repository.transactionDraft(id: firstTransactionID).categoryID == other.id)
        try repository.saveTransaction(TransactionDraft(
            id: firstTransactionID,
            kind: .expense,
            walletID: walletID,
            amountMinor: 2_500,
            occurredAt: syncStartAt.addingTimeInterval(1),
            categoryID: groceries.id,
            merchant: "SILPO",
            note: "",
            source: .bankSync
        ))

        try repository.learnBankMerchantCategoryRule(transactionID: firstTransactionID, categoryID: groceries.id)
        _ = try repository.importMonobankExpenseItems(
            [monobankItem(id: "statement-2", time: Int(syncStartAt.timeIntervalSince1970) + 2, amount: -3_000, description: "SILPO")],
            account: account,
            integration: integration
        )

        let drafts = try bankSyncTransactionIDs(repository).map { try repository.transactionDraft(id: $0) }
        #expect(drafts.count == 2)
        #expect(drafts.first?.categoryID == groceries.id)
        #expect(drafts.last?.categoryID == groceries.id)
    }

    private static func uahAccount(id: String, name: String = "Black", maskedPAN: [String] = ["1234"]) -> MonobankAccount {
        MonobankAccount(id: id, type: name.lowercased(), currencyCode: 980, maskedPan: maskedPAN, iban: nil)
    }

    private static func usdAccount(id: String) -> MonobankAccount {
        MonobankAccount(id: id, type: "white", currencyCode: 840, maskedPan: ["9999"], iban: nil)
    }

    private func monobankItem(
        id: String,
        time: Int,
        amount: Int64,
        description: String = "Merchant"
    ) -> MonobankStatementItem {
        MonobankStatementItem(
            id: id,
            time: time,
            description: description,
            mcc: nil,
            originalMcc: nil,
            amount: amount,
            operationAmount: nil,
            currencyCode: 980,
            commissionRate: nil,
            cashbackAmount: nil,
            balance: nil,
            hold: nil,
            receiptId: nil,
            comment: nil,
            counterEdrpou: nil,
            counterIban: nil,
            counterName: description
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

    private func bankSyncTransactionIDs(_ repository: CashRunwayRepository) throws -> [UUID] {
        try repository.databaseManager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT id FROM transactions WHERE source = ? ORDER BY occurred_at",
                arguments: [TransactionSource.bankSync.rawValue]
            ).compactMap(UUID.init(uuidString:))
        }
    }
}

private final class FakeMonobankTokenValidator: MonobankTokenValidating, @unchecked Sendable {
    private let info: MonobankClientInfo
    private(set) var validatedTokens: [String] = []

    init(info: MonobankClientInfo) {
        self.info = info
    }

    func clientInfo(token: String) async throws -> MonobankClientInfo {
        validatedTokens.append(token)
        return info
    }
}

private final class FakeMonobankClient: MonobankClient, @unchecked Sendable {
    private let items: [MonobankStatementItem]

    init(items: [MonobankStatementItem]) {
        self.items = items
    }

    func clientInfo() async throws -> MonobankClientInfo {
        MonobankClientInfo(name: "Test User", accounts: [])
    }

    func statement(accountID: String, from: Date, to: Date) async throws -> [MonobankStatementItem] {
        items
    }
}

private final class RecordingBankSyncPerformer: BankSyncPerforming, @unchecked Sendable {
    private(set) var syncedIntegrationIDs: [UUID] = []

    func syncOnDemand() async throws -> BankSyncResult {
        BankSyncResult()
    }

    func syncOnForeground() async throws -> BankSyncResult {
        BankSyncResult()
    }

    func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        syncedIntegrationIDs.append(integrationID)
        return BankSyncResult()
    }
}

private actor BlockingBankSyncPerformer: BankSyncPerforming {
    private var activeCount = 0
    private(set) var maxActiveCount = 0
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func syncOnDemand() async throws -> BankSyncResult {
        await block()
    }

    func syncOnForeground() async throws -> BankSyncResult {
        await block()
    }

    func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        await block()
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        while callCount < expectedCount {
            await Task.yield()
        }
    }

    func releaseNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    private func block() async -> BankSyncResult {
        activeCount += 1
        callCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        activeCount -= 1
        return BankSyncResult()
    }
}
