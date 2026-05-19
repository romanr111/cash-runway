import Foundation

@MainActor
struct CashRunwayAppRuntime {
    let model: CashRunwayAppModel?
    let startupError: String?
    let onboardingStore: UserDefaults
    let bypassOnboarding: Bool

    static func bootstrap() -> CashRunwayAppRuntime {
        #if DEBUG
        if let configuration = UITestLaunchConfiguration.current {
            do {
                return try configuration.makeRuntime()
            } catch {
                return CashRunwayAppRuntime(
                    model: nil,
                    startupError: error.localizedDescription,
                    onboardingStore: .standard,
                    bypassOnboarding: false
                )
            }
        }
        #endif

        do {
            let model = try CashRunwayAppModel.live()
            return CashRunwayAppRuntime(
                model: model,
                startupError: nil,
                onboardingStore: .standard,
                bypassOnboarding: false
            )
        } catch {
            return CashRunwayAppRuntime(
                model: nil,
                startupError: error.localizedDescription,
                onboardingStore: .standard,
                bypassOnboarding: false
            )
        }
    }
}

#if DEBUG
@MainActor
private struct UITestLaunchConfiguration {
    enum Scenario: String {
        case transactionCore = "transaction_core"
        case monobankFirstStart = "monobank_first_start"
    }

    static var current: UITestLaunchConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CASH_RUNWAY_UI_TEST_MODE"] == "1" else { return nil }

        let scenario = Scenario(
            rawValue: environment["CASH_RUNWAY_UI_TEST_SCENARIO"]
                ?? Scenario.transactionCore.rawValue
        )
        let databasePath = environment["CASH_RUNWAY_UI_TEST_DB_PATH"] ?? "cash-runway-ui-tests.sqlite"

        return UITestLaunchConfiguration(
            scenario: scenario,
            databaseURL: Self.resolveDatabaseURL(databasePath),
            shouldReset: environment["CASH_RUNWAY_UI_TEST_RESET"] == "1",
            monobankMode: UITestMonobankMode(
                rawValue: environment["CASH_RUNWAY_UI_TEST_MONOBANK_MODE"]
                    ?? UITestMonobankMode.happyPath.rawValue
            ) ?? .happyPath
        )
    }

    let scenario: Scenario?
    let databaseURL: URL
    let shouldReset: Bool
    let monobankMode: UITestMonobankMode

    private let defaultsSuiteName = "dev.roman.cashrunway.uitest"

    var onboardingStore: UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }

    func makeRuntime() throws -> CashRunwayAppRuntime {
        let keychain = UITestKeychainStore()
        // LEGACY_DISABLED_APP_LOCK:
        // App Lock is disabled for MVP.
        // keychain.delete(account: "app-lock-config")

        if shouldReset {
            try resetDatabaseFiles()
            keychain.delete(account: "database-key")
            onboardingStore.removePersistentDomain(forName: defaultsSuiteName)
        }

        let databaseManager = try DatabaseManager(
            locationProvider: DatabaseLocationProvider(
                appGroupIdentifier: nil,
                databaseURLOverride: databaseURL,
                directoryName: "CashRunwayUITests"
            ),
            allowsDestructiveRecovery: true,
            keychain: keychain
        )
        let repository = CashRunwayRepository(databaseManager: databaseManager)
        try repository.seedIfNeeded()
        try seedScenarioIfNeeded(using: repository)

        // LEGACY_DISABLED_APP_LOCK:
        // App Lock is disabled for MVP.
        // let lockStore = AppLockStore(keychain: keychain)
        let model: CashRunwayAppModel
        let tokenStore = KeychainBankTokenStore(keychain: keychain)
        if scenario == .monobankFirstStart {
            model = CashRunwayAppModel(
                repository: repository,
                bankTokenStore: tokenStore,
                bankSyncPerformer: UITestBankSyncPerformer(repository: repository, mode: monobankMode),
                monobankTokenValidator: UITestMonobankTokenValidator(mode: monobankMode)
            )
        } else {
            model = CashRunwayAppModel(
                repository: repository,
                bankTokenStore: tokenStore,
                bankSyncPerformer: UITestBankSyncPerformer(repository: repository, mode: monobankMode),
                monobankTokenValidator: UITestMonobankTokenValidator(mode: monobankMode)
            )
        }
        return CashRunwayAppRuntime(
            model: model,
            startupError: nil,
            onboardingStore: onboardingStore,
            bypassOnboarding: true
        )
    }

    private func seedScenarioIfNeeded(using repository: CashRunwayRepository) throws {
        guard scenario == .transactionCore else { return }
        try TransactionCoreUITestSeeder(repository: repository).seed()
    }

    private func resetDatabaseFiles() throws {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private static func resolveDatabaseURL(_ rawPath: String) -> URL {
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(rawPath)
    }
}

private final class UITestKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    func read(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[account]
    }

    func write(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        items[account] = data
    }

    func delete(account: String) {
        lock.lock()
        defer { lock.unlock() }
        items.removeValue(forKey: account)
    }
}

private enum UITestMonobankMode: String {
    case happyPath = "happy_path"
    case invalidToken = "invalid_token"
    case firstSyncFailsThenRecovers = "first_sync_fails_then_recovers"
    case foregroundNewExpense = "foreground_new_expense"
}

private final class UITestMonobankTokenValidator: MonobankTokenValidating, @unchecked Sendable {
    private let mode: UITestMonobankMode

    init(mode: UITestMonobankMode) {
        self.mode = mode
    }

    func clientInfo(token: String) async throws -> MonobankClientInfo {
        guard mode != .invalidToken, token == "UITEST-MONOBANK-TOKEN" else {
            throw BankSyncError.tokenInvalid
        }
        return MonobankClientInfo(
            name: "UITest Monobank User",
            accounts: [
                MonobankAccount(
                    id: "uitest-uah-card", type: "black",
                    currencyCode: 980, maskedPan: ["4444333322221111"], iban: nil
                ),
                MonobankAccount(
                    id: "uitest-usd-card", type: "white",
                    currencyCode: 840, maskedPan: ["5555666677778888"], iban: nil
                )
            ]
        )
    }
}

private final class UITestBankSyncPerformer: BankSyncPerforming, @unchecked Sendable {
    private let repository: CashRunwayRepository
    private let mode: UITestMonobankMode
    private let lock = NSLock()
    private var syncAttemptCount = 0

    init(repository: CashRunwayRepository, mode: UITestMonobankMode) {
        self.repository = repository
        self.mode = mode
    }

    func syncOnDemand() async throws -> BankSyncResult {
        try await syncActiveIntegrations()
    }

    func syncOnForeground() async throws -> BankSyncResult {
        try await syncActiveIntegrations()
    }

    func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        try await sync(integrationIDs: [integrationID])
    }

    private func syncActiveIntegrations() async throws -> BankSyncResult {
        let ids = try repository.activeBankIntegrations().map(\.id)
        return try await sync(integrationIDs: ids)
    }

    private func sync(integrationIDs: [UUID]) async throws -> BankSyncResult {
        guard !integrationIDs.isEmpty else { return BankSyncResult() }
        let attempt = nextSyncAttempt()
        if mode == .firstSyncFailsThenRecovers, attempt == 1 {
            throw BankSyncError.transient("UITEST first sync failed")
        }

        var result = BankSyncResult()
        for integrationID in integrationIDs {
            guard let integration = try repository.bankIntegrations().first(where: { $0.id == integrationID }),
                  integration.status == .active
            else { continue }

            let accounts = try repository.enabledBankAccounts(integrationID: integration.id)
            for account in accounts where account.currencyCode == 980 {
                let importResult = try repository.importMonobankExpenseItems(
                    statementItems(for: integration, attempt: attempt),
                    account: account,
                    integration: integration
                )
                result.importedCount += importResult.importedCount
                result.skippedCount += importResult.skippedCount
                result.syncedAccountCount += 1
                try repository.markBankAccountSynced(account.id, at: syncDate(for: integration, attempt: attempt))
            }

            try repository.markBankIntegrationSynced(integration.id, at: syncDate(for: integration, attempt: attempt))
        }
        return result
    }

    private func nextSyncAttempt() -> Int {
        lock.lock()
        defer { lock.unlock() }
        syncAttemptCount += 1
        return syncAttemptCount
    }

    private func statementItems(for integration: BankIntegration, attempt: Int) -> [MonobankStatementItem] {
        let startTime = Int(integration.syncStartAt.timeIntervalSince1970)
        var items = [
            statementItem(
                id: "uitest-old-history", time: startTime - 60,
                amount: -7_777, description: "UITEST old history", comment: "UITEST-MONO-OLD"
            ),
            statementItem(
                id: "uitest-income", time: startTime + 5,
                amount: 9_999, description: "UITEST income", comment: "UITEST-MONO-INCOME"
            ),
            statementItem(
                id: "uitest-new-expense", time: startTime + 30,
                amount: -1_234, description: "UITEST Monobank Merchant", comment: "UITEST-MONO-NEW"
            )
        ]
        if mode == .foregroundNewExpense || (mode == .firstSyncFailsThenRecovers && attempt > 1) {
            items.append(statementItem(
                id: "uitest-later-expense", time: startTime + 120,
                amount: -2_345, description: "UITEST Foreground Merchant", comment: "UITEST-MONO-FOREGROUND"
            ))
        }
        return items
    }

    private func syncDate(for integration: BankIntegration, attempt: Int) -> Date {
        integration.syncStartAt.addingTimeInterval(TimeInterval(180 + attempt))
    }

    private func statementItem(
        id: String,
        time: Int,
        amount: Int64,
        description: String,
        comment: String
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
            comment: comment,
            counterEdrpou: nil,
            counterIban: nil,
            counterName: description
        )
    }
}

private struct TransactionCoreUITestSeeder {
    let repository: CashRunwayRepository

    func seed() throws {
        try removeExistingUITestTransactions()
        try FixtureGenerator.seedFixtureWalletsIfNeeded(into: repository)

        let wallets = try repository.wallets()
        guard let mainWallet = wallets.first(where: { $0.name == "Main Wallet" }),
              let savingsWallet = wallets.first(where: { $0.name == "Savings" }) else {
            throw CashRunwayError.invalidState("UI test baseline wallets are missing.")
        }

        let editLabelID = try ensureLabel(name: "UITEST-LABEL-001")
        let now = Date()
        let calendar = DateKeys.calendar
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let restaurantsID = try requireCategory(named: "Restaurants", kind: .expense)
        let groceriesID = try requireCategory(named: "Groceries", kind: .expense)
        let salaryID = try requireCategory(named: "Salary", kind: .income)

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: mainWallet.id,
                amountMinor: 4_120,
                occurredAt: threeDaysAgo,
                categoryID: restaurantsID,
                labelIDs: [editLabelID],
                merchant: "Editable baseline",
                note: "UITEST-EDIT-001",
                source: .manual
            )
        )

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: mainWallet.id,
                amountMinor: 2_350,
                occurredAt: twoDaysAgo,
                categoryID: groceriesID,
                merchant: "Delete baseline",
                note: "UITEST-DELETE-001",
                source: .manual
            )
        )

        try repository.saveTransaction(
            TransactionDraft(
                kind: .expense,
                walletID: savingsWallet.id,
                amountMinor: 1_110,
                occurredAt: yesterday,
                categoryID: groceriesID,
                merchant: "Search baseline",
                note: "UITEST-SEARCH-001",
                source: .manual
            )
        )

        try repository.saveTransaction(
            TransactionDraft(
                kind: .income,
                walletID: mainWallet.id,
                amountMinor: 50_000,
                occurredAt: now,
                categoryID: salaryID,
                merchant: "Salary baseline",
                note: "UITEST-INCOME-001",
                source: .manual
            )
        )

        try repository.saveTransaction(
            TransactionDraft(
                kind: .transfer,
                walletID: mainWallet.id,
                destinationWalletID: savingsWallet.id,
                amountMinor: 15_000,
                occurredAt: now,
                merchant: "Transfer baseline",
                note: "UITEST-TRANSFER-001",
                source: .manual
            )
        )

        try repository.runMaintenance()
        try repository.refreshRecurringInstances()
    }

    private func removeExistingUITestTransactions() throws {
        let existing = try repository.transactions(query: .init(), limit: nil)
            .filter { $0.note.hasPrefix("UITEST-") || $0.merchant.hasPrefix("UITEST-") }

        for item in existing {
            do {
                try repository.deleteTransaction(id: item.id)
            } catch CashRunwayError.notFound {
                continue
            }
        }
    }

    private func ensureLabel(name: String) throws -> UUID {
        if let existing = try repository.labels().first(where: { $0.name == name }) {
            return existing.id
        }

        let label = Label(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666001") ?? UUID(),
            name: name,
            colorHex: "#64D1D5",
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveLabel(label)
        return label.id
    }

    private func requireCategory(named name: String, kind: CategoryKind) throws -> UUID {
        if let category = try repository.categories(kind: kind).first(where: { $0.name == name }) {
            return category.id
        }
        throw CashRunwayError.invalidState("UI test category \(name) is missing.")
    }
}
#endif
