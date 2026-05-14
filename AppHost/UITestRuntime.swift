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
                return CashRunwayAppRuntime(model: nil, startupError: error.localizedDescription, onboardingStore: .standard, bypassOnboarding: false)
            }
        }
        #endif

        do {
            let model = try CashRunwayAppModel.live()
            return CashRunwayAppRuntime(model: model, startupError: nil, onboardingStore: .standard, bypassOnboarding: false)
        } catch {
            return CashRunwayAppRuntime(model: nil, startupError: error.localizedDescription, onboardingStore: .standard, bypassOnboarding: false)
        }
    }
}

#if DEBUG
@MainActor
private struct UITestLaunchConfiguration {
    enum Scenario: String {
        case transactionCore = "transaction_core"
    }

    static var current: UITestLaunchConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CASH_RUNWAY_UI_TEST_MODE"] == "1" else { return nil }

        let scenario = Scenario(rawValue: environment["CASH_RUNWAY_UI_TEST_SCENARIO"] ?? Scenario.transactionCore.rawValue)
        let databasePath = environment["CASH_RUNWAY_UI_TEST_DB_PATH"] ?? "cash-runway-ui-tests.sqlite"

        return UITestLaunchConfiguration(
            scenario: scenario,
            databaseURL: Self.resolveDatabaseURL(databasePath),
            shouldReset: environment["CASH_RUNWAY_UI_TEST_RESET"] == "1"
        )
    }

    let scenario: Scenario?
    let databaseURL: URL
    let shouldReset: Bool

    private let keychainService = "dev.roman.cashrunway.uitest"
    private let defaultsSuiteName = "dev.roman.cashrunway.uitest"

    var onboardingStore: UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }

    func makeRuntime() throws -> CashRunwayAppRuntime {
        let keychain = KeychainStore(service: keychainService)
        // DEPRECATED — App Lock is deprecated. Remove when work resumes or feature is removed.
        keychain.delete(account: "app-lock-config")

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
            keychainService: keychainService
        )
        let repository = CashRunwayRepository(databaseManager: databaseManager)
        try repository.seedIfNeeded()
        try seedScenarioIfNeeded(using: repository)

        let lockStore = AppLockStore(keychain: keychain)
        return CashRunwayAppRuntime(
            model: CashRunwayAppModel(repository: repository, lockStore: lockStore),
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

private struct TransactionCoreUITestSeeder {
    let repository: CashRunwayRepository

    func seed() throws {
        try removeExistingUITestTransactions()

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
