import Foundation
import GRDB

private struct AggregateContribution {
    let walletID: UUID
    let monthKey: Int
    let dayKey: Int
    let type: TransactionKind
    let amountMinor: Int64
    let categoryID: UUID?
}

public protocol MonobankClient: Sendable {
    func clientInfo() async throws -> MonobankClientInfo
    func statement(accountID: String, from: Date, to: Date) async throws -> [MonobankStatementItem]
}

public protocol MonobankTokenValidating: Sendable {
    func clientInfo(token: String) async throws -> MonobankClientInfo
}

public protocol BankSyncPerforming: Sendable {
    func syncOnDemand() async throws -> BankSyncResult
    func syncOnForeground() async throws -> BankSyncResult
    func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult
}

public final class BankSyncSerialPerformer: BankSyncPerforming, @unchecked Sendable {
    private let base: any BankSyncPerforming
    private let gate = BankSyncSerialGate()

    public init(_ base: any BankSyncPerforming) {
        self.base = base
    }

    public func syncOnDemand() async throws -> BankSyncResult {
        try await gate.perform {
            try await self.base.syncOnDemand()
        }
    }

    public func syncOnForeground() async throws -> BankSyncResult {
        try await gate.perform {
            try await self.base.syncOnForeground()
        }
    }

    public func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        try await gate.perform {
            try await self.base.syncIntegration(integrationID)
        }
    }
}

private actor BankSyncSerialGate {
    private var tail: Task<BankSyncResult, Error>?
    private var tailID = 0

    func perform(_ operation: @escaping @Sendable () async throws -> BankSyncResult) async throws -> BankSyncResult {
        let previous = tail
        tailID += 1
        let currentID = tailID
        let task = Task {
            do {
                _ = try await previous?.value
            } catch {
                // A failed previous sync should not prevent the queued sync from trying.
            }
            return try await operation()
        }
        tail = task
        do {
            let result = try await task.value
            if tailID == currentID {
                tail = nil
            }
            return result
        } catch {
            if tailID == currentID {
                tail = nil
            }
            throw error
        }
    }
}

public func statementWindows(from: Date, to: Date) -> [DateInterval] {
    guard from < to else { return [] }
    let maxDuration = 31.0 * 24.0 * 60.0 * 60.0
    var windows: [DateInterval] = []
    var start = from
    while start < to {
        let end = min(start.addingTimeInterval(maxDuration), to)
        windows.append(DateInterval(start: start, end: end))
        start = end
    }
    return windows
}

public final class MonobankDirectTokenValidator: MonobankTokenValidating, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL = URL(string: "https://api.monobank.ua")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func clientInfo(token: String) async throws -> MonobankClientInfo {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw BankSyncError.tokenInvalid }
        var request = URLRequest(url: baseURL.appendingPathComponent("personal").appendingPathComponent("client-info"))
        request.httpMethod = "GET"
        request.setValue(trimmedToken, forHTTPHeaderField: "X-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BankSyncError.transient(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankSyncError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(MonobankClientInfo.self, from: data)
            } catch {
                throw BankSyncError.invalidResponse
            }
        case 401, 403:
            throw BankSyncError.tokenInvalid
        case 429:
            throw BankSyncError.rateLimited
        case 500..<600:
            throw BankSyncError.transient("Monobank API temporarily unavailable.")
        default:
            throw BankSyncError.invalidResponse
        }
    }
}

public final class MonobankPersonalAPIClient: MonobankClient, @unchecked Sendable {
    private let tokenStore: any BankTokenStore
    private let tokenAccount: String
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        tokenStore: any BankTokenStore,
        tokenAccount: String,
        baseURL: URL = URL(string: "https://api.monobank.ua")!,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.tokenAccount = tokenAccount
        self.baseURL = baseURL
        self.session = session
        decoder = JSONDecoder()
    }

    public func clientInfo() async throws -> MonobankClientInfo {
        try await get(baseURL.appendingPathComponent("personal").appendingPathComponent("client-info"))
    }

    public func statement(accountID: String, from: Date, to: Date) async throws -> [MonobankStatementItem] {
        guard to.timeIntervalSince(from) <= 31 * 24 * 60 * 60 else {
            throw CashRunwayError.validation("Monobank statement window must not exceed 31 days.")
        }
        let accountPath = accountID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? accountID
        let url = baseURL
            .appendingPathComponent("personal")
            .appendingPathComponent("statement")
            .appendingPathComponent(accountPath)
            .appendingPathComponent(String(Int(from.timeIntervalSince1970)))
            .appendingPathComponent(String(Int(to.timeIntervalSince1970)))
        return try await get(url)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        guard let token = try tokenStore.readToken(account: tokenAccount), !token.isEmpty else {
            throw BankSyncError.tokenInvalid
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BankSyncError.transient(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankSyncError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw BankSyncError.invalidResponse
            }
        case 401, 403:
            throw BankSyncError.tokenInvalid
        case 429:
            throw BankSyncError.rateLimited
        case 500..<600:
            throw BankSyncError.transient("Monobank API temporarily unavailable.")
        default:
            throw BankSyncError.invalidResponse
        }
    }
}

public final class BankSyncService: BankSyncPerforming, @unchecked Sendable {
    private let repository: CashRunwayRepository
    private let client: any MonobankClient
    private let now: @Sendable () -> Date

    public init(
        repository: CashRunwayRepository,
        client: any MonobankClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.client = client
        self.now = now
    }

    public func syncOnDemand() async throws -> BankSyncResult {
        var result = BankSyncResult()
        for integration in try repository.activeBankIntegrations() {
            do {
                let integrationResult = try await sync([integration])
                result.importedCount += integrationResult.importedCount
                result.skippedCount += integrationResult.skippedCount
                result.syncedAccountCount += integrationResult.syncedAccountCount
            } catch BankSyncError.tokenInvalid {
                continue
            }
        }
        return result
    }

    public func syncOnForeground() async throws -> BankSyncResult {
        try await syncOnDemand()
    }

    public func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        guard let integration = try repository.bankIntegrations().first(where: { $0.id == integrationID }) else {
            throw CashRunwayError.notFound
        }
        guard integration.status == .active else {
            return BankSyncResult()
        }
        return try await sync([integration])
    }

    private func sync(_ integrations: [BankIntegration]) async throws -> BankSyncResult {
        var result = BankSyncResult()
        for integration in integrations {
            var integrationSyncedAt: Date?
            for account in try repository.enabledBankAccounts(integrationID: integration.id) {
                guard account.currencyCode == 980 else { continue }
                let lowerBound = integration.syncStartAt
                let from = max(account.lastSuccessfulSyncAt?.addingTimeInterval(-6 * 60 * 60) ?? lowerBound, lowerBound)
                let to = now()
                integrationSyncedAt = to

                for window in statementWindows(from: from, to: to) {
                    let items: [MonobankStatementItem]
                    do {
                        items = try await client.statement(accountID: account.providerAccountID, from: window.start, to: window.end)
                    } catch BankSyncError.tokenInvalid {
                        try markTokenInvalid(integration)
                        throw BankSyncError.tokenInvalid
                    }

                    let importable = items.filter { item in
                        Date(timeIntervalSince1970: TimeInterval(item.time)) >= lowerBound
                            && item.amount < 0
                            && item.currencyCode == 980
                    }
                    result.skippedCount += items.count - importable.count
                    let importResult = try repository.importMonobankExpenseItems(importable, account: account, integration: integration)
                    result.importedCount += importResult.importedCount
                    result.skippedCount += importResult.skippedCount
                }

                try repository.markBankAccountSynced(account.id, at: to)
                result.syncedAccountCount += 1
            }
            if let integrationSyncedAt {
                try repository.markBankIntegrationSynced(integration.id, at: integrationSyncedAt)
            }
        }
        return result
    }

    private func markTokenInvalid(_ integration: BankIntegration) throws {
        var updated = integration
        updated.status = .tokenInvalid
        updated.lastSyncError = BankSyncError.tokenInvalid.localizedDescription
        updated.updatedAt = now()
        try repository.saveBankIntegration(updated)
    }
}

public final class MonobankConnectionService: @unchecked Sendable {
    private let repository: CashRunwayRepository
    private let tokenStore: any BankTokenStore
    private let tokenValidator: any MonobankTokenValidating
    private let syncPerformer: any BankSyncPerforming
    private let now: @Sendable () -> Date

    public init(
        repository: CashRunwayRepository,
        tokenStore: any BankTokenStore,
        tokenValidator: any MonobankTokenValidating,
        syncPerformer: any BankSyncPerforming,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.tokenStore = tokenStore
        self.tokenValidator = tokenValidator
        self.syncPerformer = syncPerformer
        self.now = now
    }

    public func validateToken(_ token: String) async throws -> MonobankClientInfo {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw BankSyncError.tokenInvalid }
        return try await tokenValidator.clientInfo(token: trimmedToken)
    }

    @discardableResult
    public func connectMonobank(
        token: String,
        selections: [MonobankAccountConnectionSelection]
    ) async throws -> BankIntegration {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw BankSyncError.tokenInvalid }
        let enabledSelections = selections.filter { $0.isEnabled && $0.account.currencyCode == 980 }
        guard !enabledSelections.isEmpty else {
            throw CashRunwayError.validation("Select at least one UAH Monobank card.")
        }
        let walletIDs = Set(try repository.wallets().map(\.id))
        guard enabledSelections.allSatisfy({ walletIDs.contains($0.walletID) }) else {
            throw CashRunwayError.validation("Each selected Monobank account must map to an existing wallet.")
        }

        let timestamp = now()
        let integrationID = UUID()
        let tokenAccount = "bank-token-monobank-\(integrationID.uuidString)"
        try tokenStore.writeToken(trimmedToken, account: tokenAccount)

        let integration = BankIntegration(
            id: integrationID,
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: timestamp,
            tokenKeychainAccount: tokenAccount,
            lastClientInfoSyncAt: timestamp,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let accounts = enabledSelections.map { selection in
            BankAccount(
                id: UUID(),
                integrationID: integration.id,
                provider: .monobank,
                providerAccountID: selection.account.id,
                walletID: selection.walletID,
                displayName: Self.displayName(for: selection.account),
                accountType: selection.account.type,
                currencyCode: selection.account.currencyCode,
                maskedPAN: selection.account.maskedPan?.first,
                iban: selection.account.iban,
                isEnabled: true,
                syncStartAt: timestamp,
                lastSuccessfulSyncAt: nil,
                lastStatementItemTime: nil,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        do {
            try repository.saveBankConnection(integration: integration, accounts: accounts)
        } catch {
            try tokenStore.deleteToken(account: tokenAccount)
            throw error
        }

        do {
            _ = try await syncPerformer.syncIntegration(integration.id)
        } catch {
            try repository.recordBankSyncError(integrationID: integration.id, error: error.localizedDescription, at: now())
        }
        return integration
    }

    public func disconnectIntegration(_ integrationID: UUID) throws {
        guard let integration = try repository.bankIntegrations().first(where: { $0.id == integrationID }) else {
            throw CashRunwayError.notFound
        }
        try tokenStore.deleteToken(account: integration.tokenKeychainAccount)
        try repository.disableBankIntegration(integrationID, at: now())
    }

    private static func displayName(for account: MonobankAccount) -> String {
        let cardName = (account.type?.isEmpty == false ? account.type! : "Card").capitalized
        if let masked = account.maskedPan?.first, !masked.isEmpty {
            return "\(cardName) card ****\(String(masked.suffix(4)))"
        }
        return "\(cardName) card"
    }
}

public final class BankSyncCoordinator: BankSyncPerforming, @unchecked Sendable {
    private let repository: CashRunwayRepository
    private let tokenStore: any BankTokenStore
    private let now: @Sendable () -> Date

    public init(
        repository: CashRunwayRepository,
        tokenStore: any BankTokenStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.tokenStore = tokenStore
        self.now = now
    }

    public func syncOnDemand() async throws -> BankSyncResult {
        var result = BankSyncResult()
        for integration in try repository.activeBankIntegrations() {
            do {
                let integrationResult = try await syncIntegration(integration.id)
                result.importedCount += integrationResult.importedCount
                result.skippedCount += integrationResult.skippedCount
                result.syncedAccountCount += integrationResult.syncedAccountCount
            } catch BankSyncError.tokenInvalid {
                continue
            }
        }
        return result
    }

    public func syncOnForeground() async throws -> BankSyncResult {
        try await syncOnDemand()
    }

    public func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        guard let integration = try repository.bankIntegrations().first(where: { $0.id == integrationID }) else {
            throw CashRunwayError.notFound
        }
        let client = MonobankPersonalAPIClient(tokenStore: tokenStore, tokenAccount: integration.tokenKeychainAccount)
        let service = BankSyncService(repository: repository, client: client, now: now)
        return try await service.syncIntegration(integrationID)
    }
}

public final class BankCategoryMapper: @unchecked Sendable {
    private let repository: CashRunwayRepository

    public init(repository: CashRunwayRepository) {
        self.repository = repository
    }

    public func resolve(
        merchant: String?,
        description: String,
        mcc: Int?,
        originalMcc: Int?
    ) throws -> UUID {
        try repository.databaseManager.dbQueue.read { db in
            try BankCategoryResolution.resolve(
                db,
                provider: .monobank,
                merchant: merchant,
                description: description,
                mcc: mcc,
                originalMcc: originalMcc
            )
        }
    }
}

private enum BankCategoryResolution {
    static func resolve(
        _ db: Database,
        provider: BankProvider,
        merchant: String?,
        description: String,
        mcc: Int?,
        originalMcc: Int?
    ) throws -> UUID {
        if let ruleCategoryID = try merchantRuleCategoryID(db, provider: provider, merchant: merchant, description: description) {
            return ruleCategoryID
        }
        if let ruleCategoryID = try mccRuleCategoryID(db, provider: provider, mcc: mcc, originalMcc: originalMcc) {
            return ruleCategoryID
        }
        for code in [mcc, originalMcc].compactMap({ $0 }) {
            if let categoryName = builtInCategoryName(mcc: code),
               let categoryID = try categoryID(db, named: categoryName) {
                return categoryID
            }
        }
        if let fallbackID = try categoryID(db, named: "Other Expense") {
            return fallbackID
        }
        throw CashRunwayError.notFound
    }

    private static func merchantRuleCategoryID(_ db: Database, provider: BankProvider, merchant: String?, description: String) throws -> UUID? {
        let haystack = [merchant, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        guard !haystack.isEmpty else { return nil }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT merchant_pattern, category_id
            FROM bank_category_rules
            WHERE provider = ? AND rule_type = 'merchant' AND merchant_pattern IS NOT NULL
            ORDER BY confidence DESC, created_at
            """,
            arguments: [provider.rawValue]
        )
        for row in rows {
            let pattern = (row["merchant_pattern"] as String).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !pattern.isEmpty, haystack.contains(pattern) {
                return UUID(uuidString: row["category_id"])
            }
        }
        return nil
    }

    private static func mccRuleCategoryID(_ db: Database, provider: BankProvider, mcc: Int?, originalMcc: Int?) throws -> UUID? {
        let codes = Set([mcc, originalMcc].compactMap { $0 })
        guard !codes.isEmpty else { return nil }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT mcc, category_id
            FROM bank_category_rules
            WHERE provider = ? AND rule_type = 'mcc' AND mcc IS NOT NULL
            ORDER BY confidence DESC, created_at
            """,
            arguments: [provider.rawValue]
        )
        for row in rows where codes.contains(row["mcc"] as Int) {
            return UUID(uuidString: row["category_id"])
        }
        return nil
    }

    private static func builtInCategoryName(mcc: Int?) -> String? {
        guard let mcc else { return nil }
        return switch mcc {
        case 5411, 5422, 5441, 5451, 5462, 5499:
            "Groceries"
        case 5811, 5812, 5813, 5814:
            "Restaurants"
        case 4111, 4112, 4121, 4131, 4789:
            "Transport"
        case 5912, 8011, 8021, 8062, 8099:
            "Health"
        case 5311, 5399, 5611, 5621, 5651, 5699, 5732:
            "Shopping"
        case 7832, 7922, 7991, 7996, 7999:
            "Entertainment"
        case 3000...3299, 3500...3999, 4411, 4511, 4722, 7011:
            "Travel"
        default:
            nil
        }
    }

    private static func categoryID(_ db: Database, named name: String) throws -> UUID? {
        try String.fetchOne(
            db,
            sql: "SELECT id FROM categories WHERE kind = ? AND is_archived = 0 AND name = ?",
            arguments: [CategoryKind.expense.rawValue, name]
        ).flatMap(UUID.init(uuidString:))
    }
}

public final class CashRunwayRepository: @unchecked Sendable {
    public let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public convenience init(allowsDestructiveRecovery: Bool = false) throws {
        try self.init(databaseManager: DatabaseManager(allowsDestructiveRecovery: allowsDestructiveRecovery))
    }

    public func seedIfNeeded() throws {
        try databaseManager.dbQueue.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wallets") ?? 0
            if count == 0 {
                let now = Date()
                try db.execute(
                    sql: """
                    INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
                    """,
                    arguments: [
                        UUID(uuidString: "33333333-3333-3333-3333-333333333331")!.uuidString,
                        "Main Wallet",
                        WalletKind.card.rawValue,
                        "#60788A",
                        "wallet.pass.fill",
                        5_000_000,
                        5_000_000,
                        now,
                        now,
                    ]
                )
                try db.execute(
                    sql: """
                    INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?)
                    """,
                    arguments: [
                        UUID(uuidString: "33333333-3333-3333-3333-333333333332")!.uuidString,
                        "Savings",
                        WalletKind.account.rawValue,
                        "#1CC389",
                        "banknote.fill",
                        360_000,
                        360_000,
                        now,
                        now,
                    ]
                )
            }

            let categoryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0
            if categoryCount == 0 {
                let now = Date()
                for (index, category) in SeedCategories.all.enumerated() {
                    try db.execute(
                        sql: """
                        INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, NULL, 1, 0, ?, ?, ?)
                        """,
                        arguments: [
                            category.id.uuidString,
                            category.name,
                            category.kind.rawValue,
                            category.iconName,
                            category.colorHex,
                            index,
                            now,
                            now,
                        ]
                    )
                }
            }

            let budgetCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budgets") ?? 0
            if budgetCount == 0, let housing = SeedCategories.all.first(where: { $0.name == "Housing" }) {
                let now = Date()
                let monthKey = DateKeys.monthKey(for: .now)
                try db.execute(
                    sql: """
                    INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 0, ?, ?)
                    """,
                    arguments: [UUID().uuidString, housing.id.uuidString, monthKey, 90_000, now, now]
                )
                try recomputeBudgetSnapshots(db, monthKeys: [monthKey])
            }
        }
    }

    public func wallets() throws -> [Wallet] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM wallets WHERE is_archived = 0 ORDER BY sort_order, name").map(Self.wallet)
        }
    }

    public func categories(kind: CategoryKind? = nil) throws -> [Category] {
        try databaseManager.dbQueue.read { db in
            if let kind {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM categories WHERE is_archived = 0 AND kind = ? ORDER BY sort_order, name",
                    arguments: [kind.rawValue]
                ).map(Self.category)
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM categories WHERE is_archived = 0 ORDER BY kind, sort_order, name").map(Self.category)
        }
    }

    public func labels() throws -> [Label] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM labels ORDER BY name").map(Self.label)
        }
    }

    public func bankIntegrations() throws -> [BankIntegration] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM bank_integrations ORDER BY created_at, display_name").map(Self.bankIntegration)
        }
    }

    public func activeBankIntegrations() throws -> [BankIntegration] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM bank_integrations WHERE status = ? ORDER BY created_at, display_name",
                arguments: [BankIntegrationStatus.active.rawValue]
            ).map(Self.bankIntegration)
        }
    }

    public func bankAccounts(integrationID: UUID) throws -> [BankAccount] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM bank_accounts WHERE integration_id = ? ORDER BY display_name",
                arguments: [integrationID.uuidString]
            ).map(Self.bankAccount)
        }
    }

    public func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM bank_accounts WHERE integration_id = ? AND is_enabled = 1 ORDER BY display_name",
                arguments: [integrationID.uuidString]
            ).map(Self.bankAccount)
        }
    }

    public func saveBankIntegration(_ integration: BankIntegration) throws {
        try databaseManager.dbQueue.write { db in
            try Self.saveBankIntegration(integration, db: db)
        }
    }

    public func saveBankAccount(_ account: BankAccount) throws {
        try databaseManager.dbQueue.write { db in
            try Self.saveBankAccount(account, db: db)
        }
    }

    public func saveBankConnection(integration: BankIntegration, accounts: [BankAccount]) throws {
        try databaseManager.dbQueue.write { db in
            try Self.saveBankIntegration(integration, db: db)
            for account in accounts {
                try Self.saveBankAccount(account, db: db)
            }
        }
    }

    private static func saveBankIntegration(_ integration: BankIntegration, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO bank_integrations (
                id, provider, display_name, status, sync_start_at, token_keychain_account,
                last_client_info_sync_at, last_successful_sync_at, last_sync_error, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider = excluded.provider,
                display_name = excluded.display_name,
                status = excluded.status,
                sync_start_at = bank_integrations.sync_start_at,
                token_keychain_account = excluded.token_keychain_account,
                last_client_info_sync_at = excluded.last_client_info_sync_at,
                last_successful_sync_at = excluded.last_successful_sync_at,
                last_sync_error = excluded.last_sync_error,
                updated_at = excluded.updated_at
            """,
            arguments: [
                integration.id.uuidString,
                integration.provider.rawValue,
                integration.displayName,
                integration.status.rawValue,
                integration.syncStartAt,
                integration.tokenKeychainAccount,
                integration.lastClientInfoSyncAt,
                integration.lastSuccessfulSyncAt,
                integration.lastSyncError,
                integration.createdAt,
                integration.updatedAt,
            ]
        )
    }

    private static func saveBankAccount(_ account: BankAccount, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO bank_accounts (
                id, integration_id, provider, provider_account_id, wallet_id, display_name,
                account_type, currency_code, masked_pan, iban, is_enabled, sync_start_at,
                last_successful_sync_at, last_statement_item_time, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                integration_id = excluded.integration_id,
                provider = excluded.provider,
                provider_account_id = excluded.provider_account_id,
                wallet_id = excluded.wallet_id,
                display_name = excluded.display_name,
                account_type = excluded.account_type,
                currency_code = excluded.currency_code,
                masked_pan = excluded.masked_pan,
                iban = excluded.iban,
                is_enabled = excluded.is_enabled,
                sync_start_at = bank_accounts.sync_start_at,
                last_successful_sync_at = excluded.last_successful_sync_at,
                last_statement_item_time = excluded.last_statement_item_time,
                updated_at = excluded.updated_at
            """,
            arguments: [
                account.id.uuidString,
                account.integrationID.uuidString,
                account.provider.rawValue,
                account.providerAccountID,
                account.walletID.uuidString,
                account.displayName,
                account.accountType,
                account.currencyCode,
                account.maskedPAN,
                account.iban,
                account.isEnabled,
                account.syncStartAt,
                account.lastSuccessfulSyncAt,
                account.lastStatementItemTime,
                account.createdAt,
                account.updatedAt,
            ]
        )
    }

    public func markBankAccountSynced(_ accountID: UUID, at date: Date) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_accounts
                SET last_successful_sync_at = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [date, date, accountID.uuidString]
            )
        }
    }

    public func markBankIntegrationSynced(_ integrationID: UUID, at date: Date) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_integrations
                SET status = ?, last_successful_sync_at = ?, last_sync_error = NULL, updated_at = ?
                WHERE id = ?
                """,
                arguments: [BankIntegrationStatus.active.rawValue, date, date, integrationID.uuidString]
            )
        }
    }

    public func recordBankSyncError(integrationID: UUID, error: String, at date: Date) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_integrations
                SET last_sync_error = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [error, date, integrationID.uuidString]
            )
        }
    }

    public func disableBankIntegration(_ integrationID: UUID, at date: Date = Date()) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE bank_integrations
                SET status = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [BankIntegrationStatus.disabled.rawValue, date, integrationID.uuidString]
            )
        }
    }

    public func importedBankExpenseCount(integrationID: UUID) throws -> Int {
        try databaseManager.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM bank_transaction_imports
                WHERE integration_id = ? AND import_status = ? AND cash_runway_transaction_id IS NOT NULL
                """,
                arguments: [integrationID.uuidString, BankTransactionImportStatus.imported.rawValue]
            ) ?? 0
        }
    }

    public func bankConnectionStatus(provider: BankProvider) throws -> BankConnectionStatusSnapshot {
        let integrations = try bankIntegrations().filter { $0.provider == provider }
        guard let integration = integrations.first(where: { $0.status == .active }) ?? integrations.first else {
            return BankConnectionStatusSnapshot(
                integration: nil,
                enabledAccountCount: 0,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            )
        }
        let accounts = try bankAccounts(integrationID: integration.id)
        let enabledAccounts = accounts.filter(\.isEnabled)
        let lastAccountSync = enabledAccounts.compactMap(\.lastSuccessfulSyncAt).max()
        return BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: enabledAccounts.count,
            syncStartAt: integration.syncStartAt,
            lastSuccessfulSyncAt: integration.lastSuccessfulSyncAt ?? lastAccountSync,
            lastSyncError: integration.lastSyncError,
            importedExpenseCount: try importedBankExpenseCount(integrationID: integration.id)
        )
    }

    public func learnBankMerchantCategoryRule(transactionID: UUID, categoryID: UUID) throws {
        try databaseManager.dbQueue.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT t.merchant, t.source, i.counter_name, i.description
                FROM transactions t
                LEFT JOIN bank_transaction_imports i ON i.cash_runway_transaction_id = t.id
                WHERE t.id = ?
                """,
                arguments: [transactionID.uuidString]
            ) else {
                throw CashRunwayError.notFound
            }
            guard (row["source"] as String) == TransactionSource.bankSync.rawValue else {
                throw CashRunwayError.validation("Category learning is available only for bank sync transactions.")
            }
            let merchant = [
                row["counter_name"] as String?,
                row["merchant"] as String?,
                row["description"] as String?,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            guard let merchant else {
                throw CashRunwayError.validation("Bank merchant is required to learn a category rule.")
            }
            let now = Date()
            try db.execute(
                sql: """
                INSERT INTO bank_category_rules (
                    id, provider, rule_type, merchant_pattern, mcc, category_id, confidence, created_at, updated_at
                )
                VALUES (?, ?, 'merchant', ?, NULL, ?, 100, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    merchant,
                    categoryID.uuidString,
                    now,
                    now,
                ]
            )
        }
    }

    public func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? {
        try databaseManager.dbQueue.read { db in
            try existingBankImport(db, provider: provider, providerAccountID: providerAccountID, statementItemID: statementItemID)
        }
    }

    public func importBankExpense(
        provider: BankProvider,
        integration: BankIntegration,
        account: BankAccount,
        externalItem: BankExternalExpenseItem,
        draft: TransactionDraft
    ) throws {
        throw CashRunwayError.validation("Bank expense import is not implemented yet.")
    }

    public func importMonobankExpenseItems(
        _ items: [MonobankStatementItem],
        account: BankAccount,
        integration: BankIntegration
    ) throws -> BankSyncImportResult {
        try databaseManager.dbQueue.write { db in
            var result = BankSyncImportResult()
            let lowerBound = max(integration.syncStartAt, account.syncStartAt)

            for item in items {
                let occurredAt = Date(timeIntervalSince1970: TimeInterval(item.time))
                guard occurredAt >= lowerBound, item.amount < 0, item.currencyCode == 980 else {
                    result.skippedCount += 1
                    continue
                }
                if try existingBankImport(db, provider: .monobank, providerAccountID: account.providerAccountID, statementItemID: item.id) != nil {
                    result.skippedCount += 1
                    continue
                }

                let transactionID = UUID()
                let importID = UUID()
                let now = Date()
                let categoryID = try BankCategoryResolution.resolve(
                    db,
                    provider: .monobank,
                    merchant: item.counterName,
                    description: item.description,
                    mcc: item.mcc,
                    originalMcc: item.originalMcc
                )
                let draft = TransactionDraft(
                    id: transactionID,
                    kind: .expense,
                    walletID: account.walletID,
                    amountMinor: abs(item.amount),
                    occurredAt: occurredAt,
                    categoryID: categoryID,
                    merchant: item.counterName ?? item.description,
                    note: item.comment ?? "",
                    source: .bankSync
                )

                try validate(draft)
                try saveSingleTransaction(db, draft: draft)
                try insertBankTransactionImport(
                    db,
                    id: importID,
                    provider: .monobank,
                    integrationID: integration.id,
                    bankAccountID: account.id,
                    providerAccountID: account.providerAccountID,
                    item: item,
                    cashRunwayTransactionID: transactionID,
                    now: now
                )
                result.importedCount += 1
            }

            return result
        }
    }

    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public func budgets(monthKey: Int) throws -> [BudgetProgress] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT b.*, c.name AS category_name, c.kind AS category_kind, c.icon_name AS category_icon_name, c.color_hex AS category_color_hex,
                       c.parent_id AS category_parent_id, c.is_system AS category_is_system, c.is_archived AS category_is_archived,
                       c.sort_order AS category_sort_order, c.created_at AS category_created_at, c.updated_at AS category_updated_at,
                       COALESCE(s.spent_minor, 0) AS spent_minor,
                       COALESCE(s.remaining_minor, b.limit_minor) AS remaining_minor,
                       COALESCE(s.percent_used_bp, 0) AS percent_used_bp
                FROM budgets b
                JOIN categories c ON c.id = b.category_id
                LEFT JOIN budget_progress_snapshot s ON s.budget_id = b.id AND s.month_key = b.month_key
                WHERE b.month_key = ? AND b.is_archived = 0
                ORDER BY c.name
                """,
                arguments: [monthKey]
            ).map { row in
                BudgetProgress(
                    id: UUID(uuidString: row["id"])!,
                    budget: try Self.budget(row),
                    category: try Self.category(prefixed: "category_", row: row),
                    spentMinor: row["spent_minor"],
                    remainingMinor: row["remaining_minor"],
                    percentUsedBP: row["percent_used_bp"]
                )
            }
        }
    }

    public func recurringTemplates() throws -> [RecurringTemplate] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates ORDER BY created_at DESC").map(Self.recurringTemplate)
        }
    }

    public func recurringInstances() throws -> [RecurringInstance] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recurring_instances ORDER BY due_date").map(Self.recurringInstance)
        }
    }

    public func exportFullBackup() throws -> CashRunwayBackup {
        try databaseManager.dbQueue.read { db in
            let metadata = CashRunwayBackupMetadata(
                format: "cash-runway-backup",
                version: 1,
                createdAt: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                currency: "UAH"
            )

            return CashRunwayBackup(
                metadata: metadata,
                wallets: try Row.fetchAll(db, sql: "SELECT * FROM wallets ORDER BY sort_order, name").map(Self.backupWallet),
                categories: try Row.fetchAll(db, sql: "SELECT * FROM categories ORDER BY kind, sort_order, name").map(Self.backupCategory),
                labels: try Row.fetchAll(db, sql: "SELECT * FROM labels ORDER BY name").map(Self.backupLabel),
                transactions: try Row.fetchAll(db, sql: "SELECT * FROM transactions ORDER BY occurred_at, created_at, id").map(Self.backupTransaction),
                transactionLabels: try Row.fetchAll(db, sql: "SELECT * FROM transaction_labels ORDER BY transaction_id, label_id").map(Self.backupTransactionLabel),
                budgets: try Row.fetchAll(db, sql: "SELECT * FROM budgets ORDER BY month_key, category_id").map(Self.backupBudget),
                recurringTemplates: try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates ORDER BY created_at, id").map(Self.backupRecurringTemplate),
                recurringInstances: try Row.fetchAll(db, sql: "SELECT * FROM recurring_instances ORDER BY due_date, id").map(Self.backupRecurringInstance),
                importJobs: try Row.fetchAll(db, sql: "SELECT * FROM import_jobs ORDER BY started_at, id").map(Self.backupImportJob)
            )
        }
    }

    @discardableResult
    public func restoreFullBackup(_ backup: CashRunwayBackup) throws -> BackupRestoreResult {
        let summary = try BackupValidator.validate(backup)
        try databaseManager.dbQueue.write { db in
            try clearDerivedTables(db)
            try clearSourceTables(db)
            try insertBackupSourceData(backup, into: db)
            try db.execute(sql: "UPDATE wallets SET current_balance_minor = starting_balance_minor")
            let monthKeys = Set(backup.transactions.map(\.localMonthKey)).union(backup.budgets.map(\.monthKey))
            try rebuildMonths(db, monthKeys: monthKeys)
            try rebuildFTS(db)
        }
        return BackupRestoreResult(summary: summary)
    }

    public func latestTransactionMonthKey() throws -> Int? {
        try databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(local_month_key) FROM transactions WHERE is_deleted = 0")
        }
    }

    public func saveWallet(_ wallet: Wallet) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    kind = excluded.kind,
                    color_hex = excluded.color_hex,
                    icon_name = excluded.icon_name,
                    starting_balance_minor = excluded.starting_balance_minor,
                    current_balance_minor = excluded.current_balance_minor,
                    is_archived = excluded.is_archived,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    wallet.id.uuidString, wallet.name, wallet.kind.rawValue, wallet.colorHex, wallet.iconName,
                    wallet.startingBalanceMinor, wallet.currentBalanceMinor, wallet.isArchived, wallet.sortOrder,
                    wallet.createdAt, wallet.updatedAt,
                ]
            )
        }
    }

    public func deleteWallet(id: UUID) throws {
        let activeCount = try databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wallets WHERE is_archived = 0") ?? 0
        }
        guard activeCount > 1 else {
            throw CashRunwayError.validation("At least one active wallet must remain.")
        }

        let txIDs = try databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, linked_transfer_id FROM transactions WHERE wallet_id = ?",
                arguments: [id.uuidString]
            )
            var ids = Set<UUID>()
            for row in rows {
                if let txID = UUID(uuidString: row["id"]) {
                    ids.insert(txID)
                }
                if let linkedID = (row["linked_transfer_id"] as String?).flatMap(UUID.init) {
                    ids.insert(linkedID)
                }
            }
            return Array(ids)
        }

        for txID in txIDs {
            do {
                try deleteTransaction(id: txID)
            } catch CashRunwayError.notFound {
                // Already deleted as a linked transfer; safe to ignore.
            }
        }

        try databaseManager.dbQueue.write { db in
            let templateRows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM recurring_templates WHERE wallet_id = ? OR counterparty_wallet_id = ?",
                arguments: [id.uuidString, id.uuidString]
            )
            for row in templateRows {
                let templateID: String = row["id"]
                try db.execute(sql: "DELETE FROM recurring_instances WHERE template_id = ?", arguments: [templateID])
                try db.execute(sql: "DELETE FROM recurring_templates WHERE id = ?", arguments: [templateID])
            }

            try db.execute(sql: "DELETE FROM monthly_wallet_cashflow WHERE wallet_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM daily_wallet_balance_delta WHERE wallet_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM wallets WHERE id = ?", arguments: [id.uuidString])
            try rebuildFTS(db)
        }
    }

    public func saveCategory(_ category: Category) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    kind = excluded.kind,
                    icon_name = excluded.icon_name,
                    color_hex = excluded.color_hex,
                    parent_id = excluded.parent_id,
                    is_archived = excluded.is_archived,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    category.id.uuidString, category.name, category.kind.rawValue, category.iconName, category.colorHex,
                    category.parentID?.uuidString, category.isSystem, category.isArchived, category.sortOrder,
                    category.createdAt, category.updatedAt,
                ]
            )
        }
    }

    public func saveLabel(_ label: Label) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO labels (id, name, color_hex, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    color_hex = excluded.color_hex,
                    updated_at = excluded.updated_at
                """,
                arguments: [label.id.uuidString, label.name, label.colorHex, label.createdAt, label.updatedAt]
            )
        }
    }

    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public func saveBudget(_ budget: Budget) throws {
        guard budget.limitMinor > 0 else {
            throw CashRunwayError.validation("Budget limit must be greater than zero.")
        }

        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    category_id = excluded.category_id,
                    month_key = excluded.month_key,
                    limit_minor = excluded.limit_minor,
                    is_archived = excluded.is_archived,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    budget.id.uuidString, budget.categoryID.uuidString, budget.monthKey, budget.limitMinor,
                    budget.isArchived, budget.createdAt, budget.updatedAt,
                ]
            )
            try recomputeBudgetSnapshots(db, monthKeys: [budget.monthKey])
        }
    }

    public func saveRecurringTemplate(_ template: RecurringTemplate) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recurring_templates (id, kind, wallet_id, counterparty_wallet_id, amount_minor, category_id, merchant, note, rule_type, rule_interval, day_of_month, weekday, start_date, end_date, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    wallet_id = excluded.wallet_id,
                    counterparty_wallet_id = excluded.counterparty_wallet_id,
                    amount_minor = excluded.amount_minor,
                    category_id = excluded.category_id,
                    merchant = excluded.merchant,
                    note = excluded.note,
                    rule_type = excluded.rule_type,
                    rule_interval = excluded.rule_interval,
                    day_of_month = excluded.day_of_month,
                    weekday = excluded.weekday,
                    start_date = excluded.start_date,
                    end_date = excluded.end_date,
                    is_active = excluded.is_active,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    template.id.uuidString, template.kind.rawValue, template.walletID.uuidString,
                    template.counterpartyWalletID?.uuidString, template.amountMinor, template.categoryID?.uuidString,
                    template.merchant, template.note, template.ruleType.rawValue, template.ruleInterval,
                    template.dayOfMonth, template.weekday, template.startDate, template.endDate, template.isActive,
                    template.createdAt, template.updatedAt,
                ]
            )
            try refreshRecurringInstances(db)
        }
    }

    public func saveRecurringInstance(_ instance: RecurringInstance) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE recurring_instances
                SET due_date = ?, day_key = ?, status = ?, linked_transaction_id = ?, override_amount_minor = ?, override_category_id = ?, override_note = ?, override_merchant = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    instance.dueDate,
                    instance.dayKey,
                    instance.status.rawValue,
                    instance.linkedTransactionID?.uuidString,
                    instance.overrideAmountMinor,
                    instance.overrideCategoryID?.uuidString,
                    instance.overrideNote,
                    instance.overrideMerchant,
                    instance.updatedAt,
                    instance.id.uuidString,
                ]
            )
        }
    }

    public func dashboard(monthKey: Int, walletID: UUID? = nil) throws -> DashboardSnapshot {
        try databaseManager.dbQueue.read { db in
            let totalBalanceMinor: Int64
            if let walletID {
                totalBalanceMinor = try Int64.fetchOne(db, sql: "SELECT current_balance_minor FROM wallets WHERE id = ?", arguments: [walletID.uuidString]) ?? 0
            } else {
                totalBalanceMinor = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(current_balance_minor), 0) FROM wallets WHERE is_archived = 0") ?? 0
            }

            let monthCashflowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT income_minor, expense_minor, transfer_in_minor, transfer_out_minor
                FROM monthly_wallet_cashflow
                WHERE month_key = ?
                \(walletID == nil ? "" : "AND wallet_id = ?")
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )

            let monthIncomeMinor = monthCashflowRows.reduce(into: Int64.zero) { $0 += $1["income_minor"] }
            let monthExpenseMinor = monthCashflowRows.reduce(into: Int64.zero) { $0 += $1["expense_minor"] }
            let monthNetMinor = monthIncomeMinor - monthExpenseMinor

            let categoryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.name, c.color_hex, c.icon_name, m.expense_minor, m.txn_count
                FROM monthly_category_spend m
                JOIN categories c ON c.id = m.category_id
                WHERE m.month_key = ?
                ORDER BY m.expense_minor DESC
                LIMIT 8
                """,
                arguments: [monthKey]
            )
            let totalExpense = max(monthExpenseMinor, 1)
            let categories = categoryRows.map { row in
                let amountMinor: Int64 = row["expense_minor"]
                return DashboardCategorySlice(
                    id: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    colorHex: row["color_hex"],
                    iconName: row["icon_name"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(totalExpense)
                )
            }

            let historyRows = try Row.fetchAll(
                db,
                sql: """
                SELECT day_key, COALESCE(SUM(net_delta_minor), 0) AS total
                FROM daily_wallet_balance_delta
                WHERE day_key BETWEEN ? AND ?
                GROUP BY day_key
                ORDER BY day_key
                """,
                arguments: [monthKey * 100 + 1, monthKey * 100 + 31]
            )
            var rollingBalance = totalBalanceMinor - historyRows.reduce(into: Int64.zero) { $0 += $1["total"] }
            let wealthHistory = historyRows.map { row -> BalancePoint in
                rollingBalance += row["total"]
                return BalancePoint(dayKey: row["day_key"], amountMinor: rollingBalance)
            }

            let recentTransactions = try listTransactions(db, query: .init(walletID: walletID))

            return DashboardSnapshot(
                monthKey: monthKey,
                walletFilterID: walletID,
                totalBalanceMinor: totalBalanceMinor,
                monthIncomeMinor: monthIncomeMinor,
                monthExpenseMinor: monthExpenseMinor,
                monthNetMinor: monthNetMinor,
                wealthHistory: wealthHistory,
                categories: categories,
                recentTransactions: Array(recentTransactions.prefix(8))
            )
        }
    }

    public func timelineSnapshot(monthKey: Int, walletID: UUID? = nil, query: TransactionQuery = .init(), period: TimelinePeriod = .month) throws -> TimelineSnapshot {
        try databaseManager.dbQueue.read { db in
            let effectiveWalletID = walletID ?? query.walletID
            let bars = try Self.loadBars(db, monthKey: monthKey, walletID: effectiveWalletID, period: period)
            let anchorPeriodKey = Self.anchorPeriodKey(monthKey: monthKey, period: period)

            var scopedQuery = query
            scopedQuery.walletID = effectiveWalletID
            Self.applyPeriodScope(&scopedQuery, period: period, periodKey: anchorPeriodKey)
            let items = try listTransactions(db, query: scopedQuery, limit: nil)
            let sections = Dictionary(grouping: items, by: \.dayKey)
                .map { key, values in
                    TimelineSection(
                        periodKey: key,
                        periodLabel: DateKeys.dayLabel(for: key),
                        totalMinor: values.reduce(into: Int64.zero) { $0 += $1.amountMinor },
                        items: values
                    )
                }
                .sorted { $0.periodKey > $1.periodKey }

            let selectedBar = bars.first(where: { $0.periodKey == anchorPeriodKey }) ?? bars.last
            let heroCashFlow = selectedBar.map { $0.incomeMinor - $0.expenseMinor } ?? 0
            return TimelineSnapshot(
                anchorMonthKey: monthKey,
                walletFilterID: effectiveWalletID,
                heroCashFlowMinor: heroCashFlow,
                bars: bars,
                sections: sections,
                period: period
            )
        }
    }

    private static func anchorPeriodKey(monthKey: Int, period: TimelinePeriod) -> Int {
        let anchorDate = DateKeys.startOfMonth(for: monthKey)
        return DateKeys.periodKey(for: anchorDate, period: period)
    }

    private static func loadBars(_ db: Database, monthKey: Int, walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint] {
        switch period {
        case .month:
            return try loadMonthlyBars(db, monthKey: monthKey, walletID: walletID)
        case .year:
            return try loadYearlyBars(db, monthKey: monthKey, walletID: walletID)
        }
    }

    private static func loadMonthlyBars(_ db: Database, monthKey: Int, walletID: UUID?) throws -> [TimelineBarPoint] {
        let months = Self.monthWindow(endingAt: monthKey, count: 6)
        var conditions = ["month_key BETWEEN ? AND ?"]
        var arguments: [any DatabaseValueConvertible] = [months.first ?? monthKey, months.last ?? monthKey]
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(arguments)
        )
        let byMonth = Dictionary(uniqueKeysWithValues: rows.map { row in
            let month: Int = row["month_key"]
            return (
                month,
                TimelineBarPoint(
                    periodKey: month,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: monthLabel(for: month)
                )
            )
        })
        return months.map { month in
            byMonth[month] ?? TimelineBarPoint(periodKey: month, incomeMinor: 0, expenseMinor: 0, xLabel: monthLabel(for: month))
        }
    }

    private static func loadYearlyBars(_ db: Database, monthKey: Int, walletID: UUID?) throws -> [TimelineBarPoint] {
        let year = monthKey / 100
        let years = Self.yearWindow(endingAt: year, count: 6)
        let startMonth = (year - 5) * 100 + 1
        let endMonth = year * 100 + 12
        var conditions = ["month_key BETWEEN ? AND ?"]
        var arguments: [any DatabaseValueConvertible] = [startMonth, endMonth]
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(arguments)
        )
        var byYear: [Int: (income: Int64, expense: Int64)] = [:]
        for row in rows {
            let month: Int = row["month_key"]
            let y = month / 100
            var current = byYear[y] ?? (0, 0)
            current.income += row["income_minor"]
            current.expense += row["expense_minor"]
            byYear[y] = current
        }
        return years.map { y in
            let values = byYear[y] ?? (0, 0)
            return TimelineBarPoint(
                periodKey: y,
                incomeMinor: values.income,
                expenseMinor: values.expense,
                xLabel: "\(y)"
            )
        }
    }

    public func allBars(walletID: UUID? = nil, period: TimelinePeriod = .month) throws -> [TimelineBarPoint] {
        try databaseManager.dbQueue.read { db in
            switch period {
            case .month:
                return try Self.loadAllMonthlyBars(db, walletID: walletID)
            case .year:
                return try Self.loadAllYearlyBars(db, walletID: walletID)
            }
        }
    }

    private static func loadAllMonthlyBars(_ db: Database, walletID: UUID?) throws -> [TimelineBarPoint] {
        var conditions: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let minMaxRow = try Row.fetchOne(db, sql: """
            SELECT MIN(month_key) as min_month, MAX(month_key) as max_month
            FROM monthly_wallet_cashflow
            \(whereClause)
            """, arguments: StatementArguments(arguments))

        guard let minMonth: Int = minMaxRow?["min_month"],
              let maxMonth: Int = minMaxRow?["max_month"] else {
            return []
        }

        var months: [Int] = []
        var current = minMonth
        while current <= maxMonth {
            months.append(current)
            if let nextDate = DateKeys.calendar.date(byAdding: .month, value: 1, to: DateKeys.startOfMonth(for: current)) {
                current = DateKeys.monthKey(for: nextDate)
            } else {
                break
            }
        }

        var dataConditions = ["month_key BETWEEN ? AND ?"]
        var dataArguments: [any DatabaseValueConvertible] = [minMonth, maxMonth]
        if let walletID {
            dataConditions.append("wallet_id = ?")
            dataArguments.append(walletID.uuidString)
        }
        let dataRows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(dataConditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(dataArguments)
        )
        let byMonth = Dictionary(uniqueKeysWithValues: dataRows.map { row in
            let month: Int = row["month_key"]
            return (
                month,
                TimelineBarPoint(
                    periodKey: month,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: monthLabel(for: month)
                )
            )
        })
        return months.map { month in
            byMonth[month] ?? TimelineBarPoint(periodKey: month, incomeMinor: 0, expenseMinor: 0, xLabel: monthLabel(for: month))
        }
    }

    private static func loadAllYearlyBars(_ db: Database, walletID: UUID?) throws -> [TimelineBarPoint] {
        var conditions: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let minMaxRow = try Row.fetchOne(db, sql: """
            SELECT MIN(month_key / 100) as min_year, MAX(month_key / 100) as max_year
            FROM monthly_wallet_cashflow
            \(whereClause)
            """, arguments: StatementArguments(arguments))

        guard let minYear: Int = minMaxRow?["min_year"],
              let maxYear: Int = minMaxRow?["max_year"] else {
            return []
        }

        let years = Array(minYear...maxYear)

        var dataConditions = ["month_key / 100 BETWEEN ? AND ?"]
        var dataArguments: [any DatabaseValueConvertible] = [minYear, maxYear]
        if let walletID {
            dataConditions.append("wallet_id = ?")
            dataArguments.append(walletID.uuidString)
        }
        let dataRows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key / 100 as year,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(dataConditions.joined(separator: " AND "))
            GROUP BY year
            ORDER BY year
            """,
            arguments: StatementArguments(dataArguments)
        )
        let byYear = Dictionary(uniqueKeysWithValues: dataRows.map { row in
            let year: Int = row["year"]
            return (
                year,
                TimelineBarPoint(
                    periodKey: year,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: "\(year)"
                )
            )
        })
        return years.map { year in
            byYear[year] ?? TimelineBarPoint(periodKey: year, incomeMinor: 0, expenseMinor: 0, xLabel: "\(year)")
        }
    }

    private static func applyPeriodScope(_ query: inout TransactionQuery, period: TimelinePeriod, periodKey: Int) {
        let bounds = periodDateBounds(period: period, periodKey: periodKey)
        if let startDate = query.startDate {
            query.startDate = max(startDate, bounds.start)
        } else {
            query.startDate = bounds.start
        }
        if let endDate = query.endDate {
            query.endDate = min(endDate, bounds.end)
        } else {
            query.endDate = bounds.end
        }
    }

    private static func periodDateBounds(period: TimelinePeriod, periodKey: Int) -> (start: Date, end: Date) {
        switch period {
        case .month:
            return (DateKeys.startOfMonth(for: periodKey), endOfMonth(for: periodKey))
        case .year:
            let startMonthKey = periodKey * 100 + 1
            let endMonthKey = periodKey * 100 + 12
            return (DateKeys.startOfMonth(for: startMonthKey), endOfMonth(for: endMonthKey))
        }
    }

    private static func monthAbbreviation(for monthKey: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: DateKeys.startOfMonth(for: monthKey))
    }

    private static func monthLabel(for monthKey: Int) -> String {
        let abbreviation = monthAbbreviation(for: monthKey)
        let year = monthKey / 100
        return "\(abbreviation)\n\(year)"
    }

    public func overviewSnapshot(monthKey: Int, walletID: UUID? = nil) throws -> OverviewSnapshot {
        try databaseManager.dbQueue.read { db in
            let months = Self.monthWindow(endingAt: monthKey, count: 6)
            let cashflowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT month_key,
                       COALESCE(SUM(income_minor), 0) AS income_minor,
                       COALESCE(SUM(expense_minor), 0) AS expense_minor
                FROM monthly_wallet_cashflow
                WHERE month_key BETWEEN ? AND ?
                \(walletID == nil ? "" : "AND wallet_id = ?")
                GROUP BY month_key
                ORDER BY month_key
                """,
                arguments: walletID == nil
                    ? [months.first ?? monthKey, months.last ?? monthKey]
                    : [months.first ?? monthKey, months.last ?? monthKey, walletID!.uuidString]
            )
            let cashflowByMonth = Dictionary(uniqueKeysWithValues: cashflowRows.map { row in
                let month: Int = row["month_key"]
                return (month, (income: row["income_minor"] as Int64, expense: row["expense_minor"] as Int64))
            })

            let balances = try self.monthEndBalances(for: months + [monthKey], walletID: walletID, db: db)

            let monthPoints = months.map { month in
                let values = cashflowByMonth[month] ?? (income: Int64.zero, expense: Int64.zero)
                return OverviewMonthPoint(
                    monthKey: month,
                    totalWealthMinor: balances[month] ?? 0,
                    cashFlowMinor: values.income - values.expense,
                    incomeMinor: values.income,
                    expenseMinor: values.expense
                )
            }

            let selectedPoint: OverviewMonthPoint
            if let existingPoint = monthPoints.first(where: { $0.monthKey == monthKey }) {
                selectedPoint = existingPoint
            } else {
                selectedPoint = OverviewMonthPoint(
                    monthKey: monthKey,
                    totalWealthMinor: balances[monthKey] ?? 0,
                    cashFlowMinor: 0,
                    incomeMinor: 0,
                    expenseMinor: 0
                )
            }

            let categoryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.name, c.kind, c.color_hex, c.icon_name,
                       COALESCE(SUM(t.amount_minor), 0) AS expense_minor,
                       COUNT(t.id) AS txn_count
                FROM categories c
                LEFT JOIN transactions t
                  ON t.category_id = c.id
                 AND t.is_deleted = 0
                 AND (
                    (c.kind = 'expense' AND t.type = 'expense')
                    OR
                    (c.kind = 'income' AND t.type = 'income')
                 )
                 AND t.local_month_key = ?
                 \(walletID == nil ? "" : "AND t.wallet_id = ?")
                WHERE c.kind IN ('expense', 'income')
                GROUP BY c.id
                HAVING expense_minor > 0
                ORDER BY c.kind, expense_minor DESC, c.sort_order, c.name
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )
            let totalExpense = max(selectedPoint.expenseMinor, 1)
            let totalIncome = max(selectedPoint.incomeMinor, 1)
            let categories = categoryRows.map { row in
                let amountMinor: Int64 = row["expense_minor"]
                let kind = CategoryKind(rawValue: row["kind"]) ?? .expense
                return OverviewCategoryRow(
                    id: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    kind: kind,
                    colorHex: row["color_hex"],
                    iconName: row["icon_name"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(kind == .expense ? totalExpense : totalIncome)
                )
            }

            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT l.id, l.name, l.color_hex,
                       CASE t.type WHEN 'income' THEN 'income' ELSE 'expense' END AS kind,
                       COALESCE(SUM(t.amount_minor), 0) AS label_minor,
                       COUNT(DISTINCT t.id) AS txn_count
                FROM labels l
                JOIN transaction_labels tl ON tl.label_id = l.id
                JOIN transactions t ON t.id = tl.transaction_id
                WHERE t.is_deleted = 0
                  AND t.type IN ('expense', 'income')
                  AND t.local_month_key = ?
                  \(walletID == nil ? "" : "AND t.wallet_id = ?")
                GROUP BY l.id, kind
                HAVING label_minor > 0
                ORDER BY kind, label_minor DESC, l.name
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )
            let labels = labelRows.map { row in
                let amountMinor: Int64 = row["label_minor"]
                let kind = CategoryKind(rawValue: row["kind"]) ?? .expense
                return OverviewLabelRow(
                    labelID: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    kind: kind,
                    colorHex: row["color_hex"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(kind == .expense ? totalExpense : totalIncome)
                )
            }

            return OverviewSnapshot(
                selectedMonthKey: monthKey,
                walletFilterID: walletID,
                months: monthPoints,
                totalWealthMinor: selectedPoint.totalWealthMinor,
                monthCashFlowMinor: selectedPoint.cashFlowMinor,
                monthIncomeMinor: selectedPoint.incomeMinor,
                monthExpenseMinor: selectedPoint.expenseMinor,
                categories: categories,
                labels: labels
            )
        }
    }

    public func categoryManagementItems(kind: CategoryKind) throws -> [CategoryManagementItem] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT c.*,
                       COUNT(DISTINCT t.id) AS txn_count,
                       COUNT(DISTINCT t.wallet_id) AS wallet_count
                FROM categories c
                LEFT JOIN transactions t
                  ON t.category_id = c.id
                 AND t.is_deleted = 0
                 AND t.type != 'transfer_in'
                WHERE c.kind = ?
                GROUP BY c.id
                ORDER BY c.sort_order, c.name
                """,
                arguments: [kind.rawValue]
            ).map { row in
                let category = try Self.category(row)
                return CategoryManagementItem(
                    category: category,
                    transactionCount: row["txn_count"],
                    walletCount: row["wallet_count"],
                    isVisible: !category.isArchived
                )
            }
        }
    }

    public func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) throws {
        try databaseManager.dbQueue.write { db in
            for (index, id) in orderedCategoryIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE categories SET sort_order = ?, updated_at = ? WHERE id = ? AND kind = ?",
                    arguments: [index, Date.now, id.uuidString, kind.rawValue]
                )
            }
        }
    }

    public func transactions(query: TransactionQuery = .init(), limit: Int? = 300) throws -> [TransactionListItem] {
        try databaseManager.dbQueue.read { db in
            try listTransactions(db, query: query, limit: limit)
        }
    }

    public func transactionDraft(id: UUID) throws -> TransactionDraft {
        try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let transaction = try Self.transaction(row)
            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT label_id FROM transaction_labels WHERE transaction_id = ?
                UNION ALL
                SELECT label_id FROM transaction_labels WHERE transaction_id = ?
                """,
                arguments: [id.uuidString, transaction.linkedTransferID?.uuidString]
            )
            let labelIDs = labelRows.compactMap { UUID(uuidString: $0["label_id"]) }

            if transaction.type == .transferOut || transaction.type == .transferIn {
                guard let linkedID = transaction.linkedTransferID,
                      let linkedWalletID = try String.fetchOne(db, sql: "SELECT wallet_id FROM transactions WHERE id = ?", arguments: [linkedID.uuidString]).flatMap(UUID.init(uuidString:))
                else {
                    throw CashRunwayError.invalidState("Transfer pair is missing.")
                }
                let sourceWalletID = transaction.type == .transferOut ? transaction.walletID : linkedWalletID
                let destinationWalletID = transaction.type == .transferOut ? linkedWalletID : transaction.walletID
                return TransactionDraft(
                    id: sourceWalletID == transaction.walletID ? transaction.id : linkedID,
                    kind: .transfer,
                    walletID: sourceWalletID,
                    destinationWalletID: destinationWalletID,
                    amountMinor: transaction.amountMinor,
                    occurredAt: transaction.occurredAt,
                    labelIDs: labelIDs,
                    merchant: transaction.merchant ?? "",
                    note: transaction.note ?? "",
                    source: transaction.source,
                    recurringTemplateID: transaction.recurringTemplateID,
                    recurringInstanceID: transaction.recurringInstanceID
                )
            }

            return TransactionDraft(
                id: transaction.id,
                kind: transaction.type == .expense ? .expense : .income,
                walletID: transaction.walletID,
                amountMinor: transaction.amountMinor,
                occurredAt: transaction.occurredAt,
                categoryID: transaction.categoryID,
                labelIDs: labelIDs,
                merchant: transaction.merchant ?? "",
                note: transaction.note ?? "",
                source: transaction.source,
                recurringTemplateID: transaction.recurringTemplateID,
                recurringInstanceID: transaction.recurringInstanceID
            )
        }
    }

    public func saveTransaction(_ draft: TransactionDraft) throws {
        try validate(draft)
        try databaseManager.dbQueue.write { db in
            if draft.kind == .transfer {
                try saveTransfer(db, draft: draft)
            } else {
                try saveSingleTransaction(db, draft: draft)
            }
        }
    }

    public func deleteTransaction(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            guard let transactionRow = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let transaction = try Self.transaction(transactionRow)

            var transactionsToDelete = [transaction]
            if (transaction.type == .transferOut || transaction.type == .transferIn), let linkedID = transaction.linkedTransferID,
               let linkedRow = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [linkedID.uuidString]) {
                transactionsToDelete.append(try Self.transaction(linkedRow))
            }

            for item in transactionsToDelete {
                try applyContribution(db, old: contribution(for: item), new: nil)
                try db.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", arguments: [item.id.uuidString])
                try db.execute(sql: "DELETE FROM transaction_search WHERE transaction_id = ?", arguments: [item.id.uuidString])
                try db.execute(sql: "DELETE FROM transactions WHERE id = ?", arguments: [item.id.uuidString])
            }
        }
    }

    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) throws {
        try databaseManager.dbQueue.write { db in
            let now = Date()
            let affectedMonths = Set(try Int.fetchAll(
                db,
                sql: "SELECT DISTINCT local_month_key FROM transactions WHERE category_id = ?",
                arguments: [oldCategoryID.uuidString]
            ))
            try db.execute(
                sql: "UPDATE transactions SET category_id = ?, updated_at = ? WHERE category_id = ?",
                arguments: [newCategoryID.uuidString, now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: """
                INSERT INTO category_remaps (id, old_category_id, new_category_id, remapped_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, oldCategoryID.uuidString, newCategoryID.uuidString, now]
            )
            try db.execute(
                sql: """
                INSERT INTO audit_entries (id, entity_type, entity_id, operation, diff_json, created_at)
                VALUES (?, 'category', ?, 'remap', ?, ?)
                """,
                arguments: [UUID().uuidString, oldCategoryID.uuidString, "{\"from\":\"\(oldCategoryID.uuidString)\",\"to\":\"\(newCategoryID.uuidString)\"}", now]
            )
            try markDirtyRanges(db, monthKeys: affectedMonths)
            try processPendingAggregateRebuilds(db)
            try rebuildFTS(db)
        }
    }

    // DEPRECATED — CSV import is now atomic via commitCSVImport. Do not use.
    public func appendImportedTransactions(_ drafts: [TransactionDraft]) throws {
        guard !drafts.isEmpty else { return }
        try databaseManager.dbQueue.write { db in
            for draft in drafts {
                try validate(draft)
                if draft.kind == .transfer {
                    try saveTransfer(db, draft: draft, updateDerivedData: false)
                } else {
                    try saveSingleTransaction(db, draft: draft, updateDerivedData: false)
                }
            }
        }
    }

    // DEPRECATED — CSV import is now atomic via commitCSVImport. Do not use.
    public func finalizeImport(jobID: UUID, affectedMonths: Set<Int>, validRows: Int, invalidRows: Int, errorSummary: String?) throws {
        try databaseManager.dbQueue.write { db in
            try markDirtyRanges(db, monthKeys: affectedMonths)
            try processPendingAggregateRebuilds(db)
            try rebuildFTS(db)
            try db.execute(
                sql: """
                UPDATE import_jobs
                SET status = ?, valid_rows = ?, invalid_rows = ?, finished_at = ?, error_summary = ?
                WHERE id = ?
                """,
                arguments: [
                    ImportJobStatus.committed.rawValue,
                    validRows,
                    invalidRows,
                    Date(),
                    errorSummary,
                    jobID.uuidString,
                ]
            )
        }
    }

    public func failImport(jobID: UUID, errorSummary: String) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE import_jobs SET status = ?, finished_at = ?, error_summary = ? WHERE id = ?",
                arguments: [ImportJobStatus.failed.rawValue, Date(), errorSummary, jobID.uuidString]
            )
        }
    }

    public func commitCSVImport(
        fileName: String,
        sourceName: String,
        preparedRows: [PreparedImportRow],
        rowErrors: [CSVRowError],
        invalidRows: Int? = nil
    ) throws -> CSVImportResult {
        let now = Date()
        let jobID = UUID()
        let resolvedInvalidRows = invalidRows ?? rowErrors.count
        let totalRows = preparedRows.count + resolvedInvalidRows

        return try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO import_jobs (id, source_name, file_name, status, total_rows, valid_rows, invalid_rows, duplicate_rows, started_at, finished_at, error_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    jobID.uuidString, sourceName, fileName, ImportJobStatus.validated.rawValue, totalRows,
                    preparedRows.count, resolvedInvalidRows, 0, now, nil, resolvedInvalidRows > 0 ? "\(resolvedInvalidRows) rows failed validation." : nil,
                ]
            )

            var seenFingerprints = try existingImportFingerprints(db)
            var insertedRows = 0
            var duplicateRows = 0
            var affectedMonths = Set<Int>()

            for row in preparedRows {
                if seenFingerprints.contains(row.fingerprint) {
                    duplicateRows += 1
                    continue
                }

                let categoryID = try resolveOrCreateCategory(
                    db,
                    rawName: row.rawCategoryName,
                    kind: row.draft.kind,
                    iconName: row.categoryIconName,
                    colorHex: row.categoryColorHex
                )
                let labelIDs = try row.rawLabelNames.map { try resolveOrCreateLabel(db, name: $0) }

                var draft = row.draft
                draft.categoryID = categoryID
                draft.labelIDs = labelIDs
                draft.importJobID = jobID
                draft.importFingerprint = row.fingerprint

                try validate(draft)
                if draft.kind == .transfer {
                    try saveTransfer(db, draft: draft)
                } else {
                    try saveSingleTransaction(db, draft: draft)
                }

                seenFingerprints.insert(row.fingerprint)
                insertedRows += 1
                affectedMonths.insert(DateKeys.monthKey(for: row.draft.occurredAt))
            }

            try db.execute(
                sql: """
                UPDATE import_jobs
                SET status = ?, valid_rows = ?, invalid_rows = ?, duplicate_rows = ?, finished_at = ?, error_summary = ?
                WHERE id = ?
                """,
                arguments: [
                    ImportJobStatus.committed.rawValue,
                    insertedRows,
                    resolvedInvalidRows,
                    duplicateRows,
                    Date(),
                    resolvedInvalidRows > 0 ? "\(resolvedInvalidRows) rows failed validation." : nil,
                    jobID.uuidString,
                ]
            )

            let job = ImportJob(
                id: jobID,
                sourceName: sourceName,
                fileName: fileName,
                status: .committed,
                totalRows: totalRows,
                validRows: insertedRows,
                invalidRows: resolvedInvalidRows,
                duplicateRows: duplicateRows,
                startedAt: now,
                finishedAt: Date(),
                errorSummary: resolvedInvalidRows > 0 ? "\(resolvedInvalidRows) rows failed validation." : nil
            )

            return CSVImportResult(
                job: job,
                insertedTransactions: insertedRows,
                duplicateRows: duplicateRows,
                invalidRows: resolvedInvalidRows,
                affectedMonths: affectedMonths,
                rowErrors: rowErrors
            )
        }
    }

    private func existingImportFingerprints(_ db: Database) throws -> Set<String> {
        let rows = try String.fetchAll(db, sql: "SELECT import_fingerprint FROM transactions WHERE import_fingerprint IS NOT NULL")
        return Set(rows)
    }

    private func resolveOrCreateCategory(
        _ db: Database,
        rawName: String?,
        kind: TransactionDraft.Kind,
        iconName: String?,
        colorHex: String?
    ) throws -> UUID? {
        guard kind != .transfer else { return nil }
        let categoryKind: CategoryKind = kind == .income ? .income : .expense
        let fallbackName = kind == .income ? "Other Income" : "Other Expense"

        let allRows = try Row.fetchAll(db, sql: "SELECT * FROM categories WHERE kind = ? AND is_archived = 0", arguments: [categoryKind.rawValue])

        if let rawName {
            for row in allRows {
                let rowName: String = row["name"]
                if rowName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(rawName) == .orderedSame {
                    return UUID(uuidString: row["id"])!
                }
            }
        }

        if rawName == nil {
            if let fallbackRow = allRows.first(where: { ($0["name"] as String) == fallbackName }) {
                return UUID(uuidString: fallbackRow["id"])!
            }
            if let firstRow = allRows.first {
                return UUID(uuidString: firstRow["id"])!
            }
        }

        let fallbackRow = allRows.first(where: { ($0["name"] as String) == fallbackName }) ?? allRows.first
        let resolvedIconName = iconName ?? fallbackRow?["icon_name"]
        let resolvedColorHex = colorHex ?? fallbackRow?["color_hex"]

        let now = Date()
        let id = UUID()
        let name = rawName ?? fallbackName
        try db.execute(
            sql: """
            INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id.uuidString, name, categoryKind.rawValue, resolvedIconName, resolvedColorHex,
                nil, false, false, (allRows.map { $0["sort_order"] as Int }.max() ?? 0) + 1, now, now,
            ]
        )
        return id
    }

    private func resolveOrCreateLabel(_ db: Database, name: String) throws -> UUID {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM labels")
        for row in rows {
            let rowName: String = row["name"]
            if rowName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame {
                return UUID(uuidString: row["id"])!
            }
        }
        let now = Date()
        let id = UUID()
        try db.execute(
            sql: "INSERT INTO labels (id, name, color_hex, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            arguments: [id.uuidString, name, "#60788A", now, now]
        )
        return id
    }

    public func runMaintenance() throws {
        try databaseManager.dbQueue.write { db in
            try processPendingAggregateRebuilds(db)
        }
    }

    public func refreshRecurringInstances() throws {
        try databaseManager.dbQueue.write { db in
            try refreshRecurringInstances(db)
        }
    }

    public func postRecurringInstance(id: UUID, on date: Date = .now) throws {
        try databaseManager.dbQueue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM recurring_instances WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let instance = try Self.recurringInstance(row)
            guard let templateRow = try Row.fetchOne(db, sql: "SELECT * FROM recurring_templates WHERE id = ?", arguments: [instance.templateID.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let template = try Self.recurringTemplate(templateRow)
            let linkedTransactionID = UUID()

            let draft = TransactionDraft(
                id: linkedTransactionID,
                kind: template.kind == .transfer ? .transfer : (template.kind == .expense ? .expense : .income),
                walletID: template.walletID,
                destinationWalletID: template.counterpartyWalletID,
                amountMinor: instance.overrideAmountMinor ?? template.amountMinor,
                occurredAt: date,
                categoryID: instance.overrideCategoryID ?? template.categoryID,
                merchant: instance.overrideMerchant ?? template.merchant ?? "",
                note: instance.overrideNote ?? template.note ?? "",
                source: .recurring,
                recurringTemplateID: template.id,
                recurringInstanceID: instance.id
            )
            try draft.kind == .transfer ? saveTransfer(db, draft: draft) : saveSingleTransaction(db, draft: draft)
            try db.execute(
                sql: "UPDATE recurring_instances SET status = ?, linked_transaction_id = ?, updated_at = ? WHERE id = ?",
                arguments: [RecurringInstanceStatus.posted.rawValue, linkedTransactionID.uuidString, Date(), id.uuidString]
            )
        }
    }

    public func skipRecurringInstance(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recurring_instances SET status = ?, updated_at = ? WHERE id = ?",
                arguments: [RecurringInstanceStatus.skipped.rawValue, Date(), id.uuidString]
            )
        }
    }

    private func saveSingleTransaction(_ db: Database, draft: TransactionDraft, updateDerivedData: Bool = true) throws {
        let now = Date()
        let id = draft.id ?? UUID()
        let existing: CashRunwayTransaction? = if let draftID = draft.id {
            try existingTransaction(db, id: draftID)
        } else {
            nil
        }
        let cashRunwayType: TransactionKind = draft.kind == .expense ? .expense : .income
        let record = CashRunwayTransaction(
            id: id,
            walletID: draft.walletID,
            type: cashRunwayType,
            linkedTransferID: nil,
            amountMinor: draft.amountMinor,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: draft.categoryID,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            importJobID: draft.importJobID,
            importFingerprint: draft.importFingerprint,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        if updateDerivedData {
            try applyContribution(db, old: existing.map(contribution(for:)), new: contribution(for: record))
        }
        try upsertTransactionRow(db, transaction: record)
        try syncLabels(db, transactionID: id, labelIDs: draft.labelIDs)
        if updateDerivedData {
            try syncSearch(db, transaction: record)
        }
    }

    private func saveTransfer(_ db: Database, draft: TransactionDraft, updateDerivedData: Bool = true) throws {
        guard let destinationWalletID = draft.destinationWalletID, destinationWalletID != draft.walletID else {
            throw CashRunwayError.validation("Transfer requires two different wallets.")
        }
        let now = Date()
        let sourceID = draft.id ?? UUID()
        let sourceExisting: CashRunwayTransaction? = if let draftID = draft.id {
            try existingTransaction(db, id: draftID)
        } else {
            nil
        }
        let targetExisting: CashRunwayTransaction? = if let linkedTransferID = sourceExisting?.linkedTransferID {
            try existingTransaction(db, id: linkedTransferID)
        } else {
            nil
        }
        let targetID = sourceExisting?.linkedTransferID ?? UUID()

        let sourceRecord = CashRunwayTransaction(
            id: sourceID,
            walletID: draft.walletID,
            type: .transferOut,
            linkedTransferID: targetID,
            amountMinor: draft.amountMinor,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: nil,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            importJobID: draft.importJobID,
            importFingerprint: draft.importFingerprint,
            createdAt: sourceExisting?.createdAt ?? now,
            updatedAt: now
        )
        let targetRecord = CashRunwayTransaction(
            id: targetID,
            walletID: destinationWalletID,
            type: .transferIn,
            linkedTransferID: sourceID,
            amountMinor: draft.amountMinor,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: nil,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            importJobID: draft.importJobID,
            importFingerprint: draft.importFingerprint,
            createdAt: targetExisting?.createdAt ?? now,
            updatedAt: now
        )

        if updateDerivedData {
            try applyContribution(db, old: sourceExisting.map(contribution(for:)), new: contribution(for: sourceRecord))
            try applyContribution(db, old: targetExisting.map(contribution(for:)), new: contribution(for: targetRecord))
        }
        try upsertTransactionRow(db, transaction: sourceRecord)
        try upsertTransactionRow(db, transaction: targetRecord)
        try syncLabels(db, transactionID: sourceID, labelIDs: draft.labelIDs)
        try syncLabels(db, transactionID: targetID, labelIDs: draft.labelIDs)
        if updateDerivedData {
            try syncSearch(db, transaction: sourceRecord)
            try syncSearch(db, transaction: targetRecord)
        }
    }

    private func existingTransaction(_ db: Database, id: UUID) throws -> CashRunwayTransaction? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
            return nil
        }
        return try Self.transaction(row)
    }

    private func upsertTransactionRow(_ db: Database, transaction: CashRunwayTransaction) throws {
        try db.execute(
            sql: """
            INSERT INTO transactions (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key, category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id, import_job_id, import_fingerprint, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                wallet_id = excluded.wallet_id,
                type = excluded.type,
                linked_transfer_id = excluded.linked_transfer_id,
                amount_minor = excluded.amount_minor,
                occurred_at = excluded.occurred_at,
                local_day_key = excluded.local_day_key,
                local_month_key = excluded.local_month_key,
                category_id = excluded.category_id,
                merchant = excluded.merchant,
                note = excluded.note,
                source = excluded.source,
                recurring_template_id = excluded.recurring_template_id,
                recurring_instance_id = excluded.recurring_instance_id,
                import_job_id = excluded.import_job_id,
                import_fingerprint = excluded.import_fingerprint,
                updated_at = excluded.updated_at
            """,
            arguments: [
                transaction.id.uuidString, transaction.walletID.uuidString, transaction.type.rawValue, transaction.linkedTransferID?.uuidString,
                transaction.amountMinor, transaction.occurredAt, transaction.localDayKey, transaction.localMonthKey,
                transaction.categoryID?.uuidString, transaction.merchant, transaction.note, transaction.isDeleted,
                transaction.source.rawValue, transaction.recurringTemplateID?.uuidString, transaction.recurringInstanceID?.uuidString,
                transaction.importJobID?.uuidString, transaction.importFingerprint,
                transaction.createdAt, transaction.updatedAt,
            ]
        )
    }

    private func validate(_ draft: TransactionDraft) throws {
        guard draft.amountMinor > 0 else {
            throw CashRunwayError.validation("Amount must be greater than zero.")
        }
        if draft.kind != .transfer, draft.categoryID == nil {
            throw CashRunwayError.validation("Category is required for income and expense transactions.")
        }
    }

    private func syncLabels(_ db: Database, transactionID: UUID, labelIDs: [UUID]) throws {
        try db.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", arguments: [transactionID.uuidString])
        for labelID in Array(Set(labelIDs)) {
            try db.execute(
                sql: "INSERT INTO transaction_labels (transaction_id, label_id) VALUES (?, ?)",
                arguments: [transactionID.uuidString, labelID.uuidString]
            )
        }
    }

    private func contribution(for transaction: CashRunwayTransaction) -> AggregateContribution {
        AggregateContribution(
            walletID: transaction.walletID,
            monthKey: transaction.localMonthKey,
            dayKey: transaction.localDayKey,
            type: transaction.type,
            amountMinor: transaction.amountMinor,
            categoryID: transaction.categoryID
        )
    }

    private func applyContribution(_ db: Database, old: AggregateContribution?, new: AggregateContribution?) throws {
        if let old {
            try mutateAggregate(db, contribution: old, multiplier: -1)
        }
        if let new {
            try mutateAggregate(db, contribution: new, multiplier: 1)
        }
        let impactedMonthKeys = Set([old?.monthKey, new?.monthKey].compactMap { $0 })
        try recomputeBudgetSnapshots(db, monthKeys: impactedMonthKeys)
    }

    private func mutateAggregate(_ db: Database, contribution: AggregateContribution, multiplier: Int64) throws {
        let amount = contribution.amountMinor * multiplier
        let now = Date()
        let (income, expense, transferIn, transferOut): (Int64, Int64, Int64, Int64) = switch contribution.type {
        case .expense: (0, amount, 0, 0)
        case .income: (amount, 0, 0, 0)
        case .transferIn: (0, 0, amount, 0)
        case .transferOut: (0, 0, 0, amount)
        }

        try db.execute(
            sql: """
            INSERT INTO monthly_wallet_cashflow (wallet_id, month_key, income_minor, expense_minor, transfer_in_minor, transfer_out_minor, txn_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(wallet_id, month_key) DO UPDATE SET
                income_minor = income_minor + excluded.income_minor,
                expense_minor = expense_minor + excluded.expense_minor,
                transfer_in_minor = transfer_in_minor + excluded.transfer_in_minor,
                transfer_out_minor = transfer_out_minor + excluded.transfer_out_minor,
                txn_count = txn_count + excluded.txn_count,
                updated_at = excluded.updated_at
            """,
            arguments: [
                contribution.walletID.uuidString, contribution.monthKey, income, expense, transferIn, transferOut,
                multiplier, now,
            ]
        )

        if contribution.type == .expense, let categoryID = contribution.categoryID {
            try db.execute(
                sql: """
                INSERT INTO monthly_category_spend (category_id, month_key, expense_minor, txn_count, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(category_id, month_key) DO UPDATE SET
                    expense_minor = expense_minor + excluded.expense_minor,
                    txn_count = txn_count + excluded.txn_count,
                    updated_at = excluded.updated_at
                """,
                arguments: [categoryID.uuidString, contribution.monthKey, amount, multiplier, now]
            )
            try db.execute(
                sql: "DELETE FROM monthly_category_spend WHERE category_id = ? AND month_key = ? AND expense_minor = 0 AND txn_count <= 0",
                arguments: [categoryID.uuidString, contribution.monthKey]
            )
        }

        try db.execute(
            sql: """
            INSERT INTO daily_wallet_balance_delta (wallet_id, day_key, net_delta_minor, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(wallet_id, day_key) DO UPDATE SET
                net_delta_minor = net_delta_minor + excluded.net_delta_minor,
                updated_at = excluded.updated_at
            """,
            arguments: [contribution.walletID.uuidString, contribution.dayKey, amount * contribution.type.walletDeltaSign, now]
        )
        try db.execute(
            sql: "DELETE FROM daily_wallet_balance_delta WHERE wallet_id = ? AND day_key = ? AND net_delta_minor = 0",
            arguments: [contribution.walletID.uuidString, contribution.dayKey]
        )
        try db.execute(
            sql: "UPDATE wallets SET current_balance_minor = current_balance_minor + ?, updated_at = ? WHERE id = ?",
            arguments: [amount * contribution.type.walletDeltaSign, now, contribution.walletID.uuidString]
        )
        try db.execute(
            sql: """
            DELETE FROM monthly_wallet_cashflow
            WHERE wallet_id = ? AND month_key = ? AND income_minor = 0 AND expense_minor = 0
              AND transfer_in_minor = 0 AND transfer_out_minor = 0 AND txn_count <= 0
            """,
            arguments: [contribution.walletID.uuidString, contribution.monthKey]
        )
    }

    private func recomputeBudgetSnapshots(_ db: Database, monthKeys: Set<Int>) throws {
        guard !monthKeys.isEmpty else { return }
        let now = Date()
        for monthKey in monthKeys {
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT b.id, b.limit_minor, COALESCE(m.expense_minor, 0) AS spent_minor
                FROM budgets b
                LEFT JOIN monthly_category_spend m ON m.category_id = b.category_id AND m.month_key = b.month_key
                WHERE b.month_key = ? AND b.is_archived = 0
                """,
                arguments: [monthKey]
            )
            for row in rows {
                let budgetID: String = row["id"]
                let limitMinor: Int64 = row["limit_minor"]
                let spentMinor: Int64 = row["spent_minor"]
                let remainingMinor = limitMinor - spentMinor
                let percent = Int((spentMinor * 10_000) / max(limitMinor, 1))
                try db.execute(
                    sql: """
                    INSERT INTO budget_progress_snapshot (budget_id, month_key, spent_minor, remaining_minor, percent_used_bp, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(budget_id, month_key) DO UPDATE SET
                        spent_minor = excluded.spent_minor,
                        remaining_minor = excluded.remaining_minor,
                        percent_used_bp = excluded.percent_used_bp,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [budgetID, monthKey, spentMinor, remainingMinor, percent, now]
                )
            }
        }
    }

    private func listTransactions(_ db: Database, query: TransactionQuery, limit: Int? = 300) throws -> [TransactionListItem] {
        var conditions = ["t.is_deleted = 0", "t.type != 'transfer_in'"]
        var arguments: [String: any DatabaseValueConvertible] = [:]

        if let walletID = query.walletID {
            conditions.append("t.wallet_id = :walletID")
            arguments["walletID"] = walletID.uuidString
        }
        if let categoryID = query.categoryID {
            conditions.append("t.category_id = :categoryID")
            arguments["categoryID"] = categoryID.uuidString
        }
        if let labelID = query.labelID {
            conditions.append("EXISTS (SELECT 1 FROM transaction_labels tl WHERE tl.transaction_id = t.id AND tl.label_id = :labelID)")
            arguments["labelID"] = labelID.uuidString
        }
        if !query.searchText.isEmpty {
            conditions.append("t.id IN (SELECT transaction_id FROM transaction_search WHERE transaction_search MATCH :search)")
            arguments["search"] = query.searchText + "*"
        }
        if let startDate = query.startDate {
            conditions.append("t.occurred_at >= :startDate")
            arguments["startDate"] = startDate
        }
        if let endDate = query.endDate {
            conditions.append("t.occurred_at <= :endDate")
            arguments["endDate"] = endDate
        }

        let allowedDBKinds = query.kinds.flatMap { kind -> [String] in
            switch kind {
            case .expense: [TransactionKind.expense.rawValue]
            case .income: [TransactionKind.income.rawValue]
            case .transfer: [TransactionKind.transferOut.rawValue]
            }
        }
        if allowedDBKinds.count != TransactionDraft.Kind.allCases.count {
            conditions.append("t.type IN (\(allowedDBKinds.enumerated().map { ":kind\($0.offset)" }.joined(separator: ", ")))")
            for (index, value) in allowedDBKinds.enumerated() {
                arguments["kind\(index)"] = value
            }
        }

        let sql = """
        SELECT t.*, w.name AS wallet_name, c.name AS category_name, c.color_hex AS category_color_hex, c.icon_name AS category_icon_name
        FROM transactions t
        JOIN wallets w ON w.id = t.wallet_id
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY t.occurred_at DESC, t.created_at DESC
        \(limit.map { "LIMIT \($0)" } ?? "")
        """

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map { row in
            let transaction = try Self.transaction(row)
            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT l.* FROM labels l
                JOIN transaction_labels tl ON tl.label_id = l.id
                WHERE tl.transaction_id = ?
                ORDER BY l.name
                """,
                arguments: [transaction.id.uuidString]
            )
            let labels = try labelRows.map(Self.label)
            return TransactionListItem(
                id: transaction.id,
                walletName: row["wallet_name"],
                amountMinor: transaction.type == .expense || transaction.type == .transferOut ? -transaction.amountMinor : transaction.amountMinor,
                occurredAt: transaction.occurredAt,
                categoryName: row["category_name"],
                categoryColorHex: row["category_color_hex"],
                categoryIconName: row["category_icon_name"],
                merchant: transaction.merchant ?? "",
                note: transaction.note ?? "",
                kind: transaction.type == .expense ? .expense : (transaction.type == .income ? .income : .transfer),
                source: transaction.source,
                labels: labels,
                dayKey: transaction.localDayKey
            )
        }
    }

    private func balance(atEndOfMonth monthKey: Int, walletID: UUID?, db: Database) throws -> Int64 {
        let monthEnd = Self.endOfMonth(for: monthKey)
        let modifier = """
        CASE
            WHEN t.type IN ('expense', 'transfer_out') THEN -t.amount_minor
            ELSE t.amount_minor
        END
        """

        if let walletID {
            let startingBalance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(starting_balance_minor, 0) FROM wallets WHERE id = ?",
                arguments: [walletID.uuidString]
            ) ?? 0
            let netDelta = try Int64.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(\(modifier)), 0)
                FROM transactions t
                WHERE t.wallet_id = ?
                  AND t.is_deleted = 0
                  AND t.occurred_at <= ?
                """,
                arguments: [walletID.uuidString, monthEnd]
            ) ?? 0
            return startingBalance + netDelta
        }

        let startingBalance = try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(starting_balance_minor), 0) FROM wallets WHERE is_archived = 0"
        ) ?? 0
        let netDelta = try Int64.fetchOne(
            db,
            sql: """
            SELECT COALESCE(SUM(\(modifier)), 0)
            FROM transactions t
            WHERE t.is_deleted = 0
              AND t.occurred_at <= ?
            """,
            arguments: [monthEnd]
        ) ?? 0
        return startingBalance + netDelta
    }

    /// Computes ending balances for multiple months in a single pass using the aggregate table.
    /// This is O(1) per month after the initial query, vs. O(n) per month when summing all transactions.
    private func monthEndBalances(for months: [Int], walletID: UUID?, db: Database) throws -> [Int: Int64] {
        guard !months.isEmpty else { return [:] }
        let sortedMonths = Set(months).sorted()
        let latest = sortedMonths.last!

        let startingBalance: Int64
        if let walletID {
            startingBalance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(starting_balance_minor, 0) FROM wallets WHERE id = ?",
                arguments: [walletID.uuidString]
            ) ?? 0
        } else {
            startingBalance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(starting_balance_minor), 0) FROM wallets WHERE is_archived = 0"
            ) ?? 0
        }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor - expense_minor + transfer_in_minor - transfer_out_minor), 0) AS net_delta
            FROM monthly_wallet_cashflow
            WHERE month_key <= ?
            \(walletID == nil ? "" : "AND wallet_id = ?")
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: walletID == nil
                ? [latest]
                : [latest, walletID!.uuidString]
        )

        var cumulative = startingBalance
        var balances: [Int: Int64] = [:]
        var rowIndex = 0
        for month in sortedMonths {
            while rowIndex < rows.count, (rows[rowIndex]["month_key"] as Int) <= month {
                cumulative += rows[rowIndex]["net_delta"] as Int64
                rowIndex += 1
            }
            balances[month] = cumulative
        }
        return balances
    }

    private func syncSearch(_ db: Database, transaction: CashRunwayTransaction) throws {
        try db.execute(sql: "DELETE FROM transaction_search WHERE transaction_id = ?", arguments: [transaction.id.uuidString])
        let walletName = try String.fetchOne(db, sql: "SELECT name FROM wallets WHERE id = ?", arguments: [transaction.walletID.uuidString]) ?? ""
        let categoryName = transaction.categoryID.flatMap {
            try? String.fetchOne(db, sql: "SELECT name FROM categories WHERE id = ?", arguments: [$0.uuidString])
        } ?? ""
        let labelNames = try String.fetchAll(
            db,
            sql: """
            SELECT l.name FROM labels l
            JOIN transaction_labels tl ON tl.label_id = l.id
            WHERE tl.transaction_id = ?
            """,
            arguments: [transaction.id.uuidString]
        ).joined(separator: " ")
        try db.execute(
            sql: "INSERT INTO transaction_search (transaction_id, merchant, note, wallet_name, category_name, labels) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [transaction.id.uuidString, transaction.merchant ?? "", transaction.note ?? "", walletName, categoryName, labelNames]
        )
    }

    private func rebuildMonths(_ db: Database, monthKeys: Set<Int>) throws {
        for monthKey in monthKeys {
            try db.execute(sql: "DELETE FROM monthly_wallet_cashflow WHERE month_key = ?", arguments: [monthKey])
            try db.execute(sql: "DELETE FROM monthly_category_spend WHERE month_key = ?", arguments: [monthKey])
            try db.execute(sql: "DELETE FROM budget_progress_snapshot WHERE month_key = ?", arguments: [monthKey])

            let rows = try Row.fetchAll(db, sql: "SELECT * FROM transactions WHERE is_deleted = 0 AND local_month_key = ?", arguments: [monthKey])
            for row in rows {
                let transaction = try Self.transaction(row)
                try mutateAggregate(db, contribution: contribution(for: transaction), multiplier: 1)
            }
        }
        try recomputeBudgetSnapshots(db, monthKeys: monthKeys)
    }

    private func markDirtyRanges(_ db: Database, monthKeys: Set<Int>) throws {
        guard !monthKeys.isEmpty else { return }
        let now = Date()
        for monthKey in monthKeys {
            try db.execute(
                sql: """
                INSERT INTO aggregate_dirty_ranges (id, kind, month_key, status, created_at, updated_at)
                VALUES (?, 'month', ?, 'pending', ?, ?)
                """,
                arguments: [UUID().uuidString, monthKey, now, now]
            )
        }
    }

    private func processPendingAggregateRebuilds(_ db: Database) throws {
        let monthKeys = Set(try Int.fetchAll(
            db,
            sql: "SELECT DISTINCT month_key FROM aggregate_dirty_ranges WHERE kind = 'month' AND status = 'pending' AND month_key IS NOT NULL"
        ))
        guard !monthKeys.isEmpty else { return }
        let startedAt = Date()
        for monthKey in monthKeys {
            try db.execute(
                sql: "UPDATE aggregate_dirty_ranges SET status = 'running', updated_at = ? WHERE kind = 'month' AND month_key = ? AND status = 'pending'",
                arguments: [startedAt, monthKey]
            )
        }
        try rebuildMonths(db, monthKeys: monthKeys)
        let finishedAt = Date()
        for monthKey in monthKeys {
            try db.execute(
                sql: "UPDATE aggregate_dirty_ranges SET status = 'done', updated_at = ? WHERE kind = 'month' AND month_key = ? AND status = 'running'",
                arguments: [finishedAt, monthKey]
            )
        }
    }

    private func rebuildFTS(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM transaction_search")
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM transactions WHERE is_deleted = 0")
        for row in rows {
            try syncSearch(db, transaction: try Self.transaction(row))
        }
    }

    private func refreshRecurringInstances(_ db: Database) throws {
        let calendar = DateKeys.calendar
        let start = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let end = calendar.date(byAdding: .day, value: 60, to: .now) ?? .now
        let templates = try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates WHERE is_active = 1").map(Self.recurringTemplate)
        for template in templates {
            for dueDate in Self.generatedDates(for: template, start: start, end: end) {
                let dayKey = DateKeys.dayKey(for: dueDate)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO recurring_instances (id, template_id, due_date, day_key, status, linked_transaction_id, override_amount_minor, override_category_id, override_note, override_merchant, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?, ?)
                    """,
                    arguments: [UUID().uuidString, template.id.uuidString, dueDate, dayKey, RecurringInstanceStatus.scheduled.rawValue, Date(), Date()]
                )
            }
        }
    }

    public static func generatedDates(for template: RecurringTemplate, start: Date, end: Date) -> [Date] {
        var dates: [Date] = []
        var cursor = max(start, template.startDate)
        let calendar = DateKeys.calendar
        while cursor <= end {
            if let endDate = template.endDate, cursor > endDate { break }
            let match: Bool
            switch template.ruleType {
            case .daily:
                match = calendar.dateComponents([.day], from: template.startDate, to: cursor).day! % template.ruleInterval == 0
            case .weekly:
                match = calendar.dateComponents([.day], from: template.startDate, to: cursor).day! % (7 * template.ruleInterval) == 0
            case .monthly:
                let comps = calendar.dateComponents([.day], from: cursor)
                let monthsFromStart = calendar.dateComponents([.month], from: template.startDate, to: cursor).month ?? 0
                match = comps.day == template.dayOfMonth && monthsFromStart % template.ruleInterval == 0
            case .yearly:
                let current = calendar.dateComponents([.month, .day], from: cursor)
                let startComps = calendar.dateComponents([.month, .day], from: template.startDate)
                let yearsFromStart = calendar.dateComponents([.year], from: template.startDate, to: cursor).year ?? 0
                match = current.month == startComps.month && current.day == (template.dayOfMonth ?? startComps.day) && yearsFromStart % template.ruleInterval == 0
            }
            if match {
                dates.append(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return dates
    }

    private static func fallbackMerchant(for type: TransactionKind) -> String {
        switch type {
        case .expense: "Expense"
        case .income: "Income"
        case .transferOut: "Transfer"
        case .transferIn: "Transfer In"
        }
    }

    private func clearDerivedTables(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM transaction_search")
        try db.execute(sql: "DELETE FROM aggregate_dirty_ranges")
        try db.execute(sql: "DELETE FROM budget_progress_snapshot")
        try db.execute(sql: "DELETE FROM daily_wallet_balance_delta")
        try db.execute(sql: "DELETE FROM monthly_category_spend")
        try db.execute(sql: "DELETE FROM monthly_wallet_cashflow")
    }

    private func clearSourceTables(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM transaction_labels")
        try db.execute(sql: "DELETE FROM transactions")
        try db.execute(sql: "DELETE FROM recurring_instances")
        try db.execute(sql: "DELETE FROM recurring_templates")
        try db.execute(sql: "DELETE FROM import_jobs")
        try db.execute(sql: "DELETE FROM budgets")
        try db.execute(sql: "DELETE FROM labels")
        try db.execute(sql: "DELETE FROM categories")
        try db.execute(sql: "DELETE FROM wallets")
    }

    private func insertBackupSourceData(_ backup: CashRunwayBackup, into db: Database) throws {
        for wallet in backup.wallets {
            try db.execute(
                sql: """
                INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    wallet.id.uuidString, wallet.name, wallet.kind.rawValue, wallet.colorHex, wallet.iconName,
                    wallet.startingBalanceMinor, wallet.startingBalanceMinor, wallet.isArchived, wallet.sortOrder,
                    wallet.createdAt, wallet.updatedAt,
                ]
            )
        }

        for category in backup.categories {
            try db.execute(
                sql: """
                INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    category.id.uuidString, category.name, category.kind.rawValue, category.iconName, category.colorHex,
                    category.parentID?.uuidString, category.isSystem, category.isArchived, category.sortOrder,
                    category.createdAt, category.updatedAt,
                ]
            )
        }

        for label in backup.labels {
            try db.execute(
                sql: "INSERT INTO labels (id, name, color_hex, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [label.id.uuidString, label.name, label.colorHex, label.createdAt, label.updatedAt]
            )
        }

        for importJob in backup.importJobs {
            try db.execute(
                sql: """
                INSERT INTO import_jobs (id, source_name, file_name, status, total_rows, valid_rows, invalid_rows, started_at, finished_at, error_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    importJob.id.uuidString, importJob.sourceName, importJob.fileName, importJob.status.rawValue,
                    importJob.totalRows, importJob.validRows, importJob.invalidRows, importJob.startedAt,
                    importJob.finishedAt, importJob.errorSummary,
                ]
            )
        }

        for budget in backup.budgets {
            try db.execute(
                sql: "INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                arguments: [
                    budget.id.uuidString, budget.categoryID.uuidString, budget.monthKey, budget.limitMinor,
                    budget.isArchived, budget.createdAt, budget.updatedAt,
                ]
            )
        }

        for template in backup.recurringTemplates {
            try db.execute(
                sql: """
                INSERT INTO recurring_templates (id, kind, wallet_id, counterparty_wallet_id, amount_minor, category_id, merchant, note, rule_type, rule_interval, day_of_month, weekday, start_date, end_date, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    template.id.uuidString, template.kind.rawValue, template.walletID.uuidString,
                    template.counterpartyWalletID?.uuidString, template.amountMinor, template.categoryID?.uuidString,
                    template.merchant, template.note, template.ruleType.rawValue, template.ruleInterval,
                    template.dayOfMonth, template.weekday, template.startDate, template.endDate, template.isActive,
                    template.createdAt, template.updatedAt,
                ]
            )
        }

        for instance in backup.recurringInstances {
            try db.execute(
                sql: """
                INSERT INTO recurring_instances (id, template_id, due_date, day_key, status, linked_transaction_id, override_amount_minor, override_category_id, override_note, override_merchant, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    instance.id.uuidString, instance.templateID.uuidString, instance.dueDate, instance.dayKey,
                    instance.status.rawValue, instance.linkedTransactionID?.uuidString, instance.overrideAmountMinor,
                    instance.overrideCategoryID?.uuidString, instance.overrideNote, instance.overrideMerchant,
                    instance.createdAt, instance.updatedAt,
                ]
            )
        }

        for transaction in backup.transactions {
            try db.execute(
                sql: """
                INSERT INTO transactions (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key, category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    transaction.id.uuidString, transaction.walletID.uuidString, transaction.type.rawValue,
                    transaction.linkedTransferID?.uuidString, transaction.amountMinor, transaction.occurredAt,
                    transaction.localDayKey, transaction.localMonthKey, transaction.categoryID?.uuidString,
                    transaction.merchant, transaction.note, transaction.isDeleted, transaction.source.rawValue,
                    transaction.recurringTemplateID?.uuidString, transaction.recurringInstanceID?.uuidString,
                    transaction.createdAt, transaction.updatedAt,
                ]
            )
        }

        for row in backup.transactionLabels {
            try db.execute(
                sql: "INSERT INTO transaction_labels (transaction_id, label_id) VALUES (?, ?)",
                arguments: [row.transactionID.uuidString, row.labelID.uuidString]
            )
        }
    }

    private static func wallet(_ row: Row) throws -> Wallet {
        Wallet(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: WalletKind(rawValue: row["kind"]) ?? .other,
            colorHex: row["color_hex"],
            iconName: row["icon_name"],
            startingBalanceMinor: row["starting_balance_minor"],
            currentBalanceMinor: row["current_balance_minor"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupWallet(_ row: Row) throws -> BackupWallet {
        BackupWallet(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: WalletKind(rawValue: row["kind"]) ?? .other,
            colorHex: row["color_hex"],
            iconName: row["icon_name"],
            startingBalanceMinor: row["starting_balance_minor"],
            currentBalanceMinor: row["current_balance_minor"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func category(_ row: Row) throws -> Category {
        try category(prefixed: "", row: row)
    }

    private static func monthWindow(endingAt monthKey: Int, count: Int) -> [Int] {
        let start = DateKeys.startOfMonth(for: monthKey)
        return (0..<count).compactMap { offset in
            DateKeys.calendar.date(byAdding: .month, value: offset - (count - 1), to: start)
        }.map(DateKeys.monthKey(for:))
    }

    private static func yearWindow(endingAt year: Int, count: Int) -> [Int] {
        (0..<count).map { year + $0 - (count - 1) }
    }

    private static func endOfMonth(for monthKey: Int) -> Date {
        let start = DateKeys.startOfMonth(for: monthKey)
        let nextMonth = DateKeys.calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateKeys.calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? nextMonth
    }

    private static func category(prefixed prefix: String, row: Row) throws -> Category {
        Category(
            id: UUID(uuidString: row["\(prefix)id"])!,
            name: row["\(prefix)name"],
            kind: CategoryKind(rawValue: row["\(prefix)kind"]) ?? .expense,
            iconName: row["\(prefix)icon_name"],
            colorHex: row["\(prefix)color_hex"],
            parentID: (row["\(prefix)parent_id"] as String?).flatMap(UUID.init(uuidString:)),
            isSystem: row["\(prefix)is_system"],
            isArchived: row["\(prefix)is_archived"],
            sortOrder: row["\(prefix)sort_order"],
            createdAt: row["\(prefix)created_at"],
            updatedAt: row["\(prefix)updated_at"]
        )
    }

    private static func backupCategory(_ row: Row) throws -> BackupCategory {
        BackupCategory(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: CategoryKind(rawValue: row["kind"]) ?? .expense,
            iconName: row["icon_name"],
            colorHex: row["color_hex"],
            parentID: (row["parent_id"] as String?).flatMap(UUID.init(uuidString:)),
            isSystem: row["is_system"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func label(_ row: Row) throws -> Label {
        Label(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            colorHex: row["color_hex"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func bankIntegration(_ row: Row) throws -> BankIntegration {
        BankIntegration(
            id: UUID(uuidString: row["id"])!,
            provider: BankProvider(rawValue: row["provider"]) ?? .monobank,
            displayName: row["display_name"],
            status: BankIntegrationStatus(rawValue: row["status"]) ?? .syncFailed,
            syncStartAt: row["sync_start_at"],
            tokenKeychainAccount: row["token_keychain_account"],
            lastClientInfoSyncAt: row["last_client_info_sync_at"],
            lastSuccessfulSyncAt: row["last_successful_sync_at"],
            lastSyncError: row["last_sync_error"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func bankAccount(_ row: Row) throws -> BankAccount {
        BankAccount(
            id: UUID(uuidString: row["id"])!,
            integrationID: UUID(uuidString: row["integration_id"])!,
            provider: BankProvider(rawValue: row["provider"]) ?? .monobank,
            providerAccountID: row["provider_account_id"],
            walletID: UUID(uuidString: row["wallet_id"])!,
            displayName: row["display_name"],
            accountType: row["account_type"],
            currencyCode: row["currency_code"],
            maskedPAN: row["masked_pan"],
            iban: row["iban"],
            isEnabled: row["is_enabled"],
            syncStartAt: row["sync_start_at"],
            lastSuccessfulSyncAt: row["last_successful_sync_at"],
            lastStatementItemTime: row["last_statement_item_time"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func bankTransactionImport(_ row: Row) throws -> BankTransactionImport {
        BankTransactionImport(
            id: UUID(uuidString: row["id"])!,
            provider: BankProvider(rawValue: row["provider"]) ?? .monobank,
            integrationID: UUID(uuidString: row["integration_id"])!,
            bankAccountID: UUID(uuidString: row["bank_account_id"])!,
            providerAccountID: row["provider_account_id"],
            providerStatementItemID: row["provider_statement_item_id"],
            statementTime: row["statement_time"],
            amountMinorSigned: row["amount_minor_signed"],
            operationAmountMinorSigned: row["operation_amount_minor_signed"],
            currencyCode: row["currency_code"],
            mcc: row["mcc"],
            originalMCC: row["original_mcc"],
            description: row["description"],
            comment: row["comment"],
            counterName: row["counter_name"],
            counterIBAN: row["counter_iban"],
            receiptID: row["receipt_id"],
            hold: row["hold"],
            rawJSON: row["raw_json"],
            cashRunwayTransactionID: (row["cash_runway_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            importStatus: BankTransactionImportStatus(rawValue: row["import_status"]) ?? .failed,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func existingBankImport(_ db: Database, provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT * FROM bank_transaction_imports
            WHERE provider = ? AND provider_account_id = ? AND provider_statement_item_id = ?
            """,
            arguments: [provider.rawValue, providerAccountID, statementItemID]
        ) else {
            return nil
        }
        return try Self.bankTransactionImport(row)
    }

    private func insertBankTransactionImport(
        _ db: Database,
        id: UUID,
        provider: BankProvider,
        integrationID: UUID,
        bankAccountID: UUID,
        providerAccountID: String,
        item: MonobankStatementItem,
        cashRunwayTransactionID: UUID,
        now: Date
    ) throws {
        let rawJSON = String(data: try JSONEncoder().encode(item), encoding: .utf8) ?? "{}"
        try db.execute(
            sql: """
            INSERT INTO bank_transaction_imports (
                id, provider, integration_id, bank_account_id, provider_account_id,
                provider_statement_item_id, statement_time, amount_minor_signed,
                operation_amount_minor_signed, currency_code, mcc, original_mcc,
                description, comment, counter_name, counter_iban, receipt_id, hold,
                raw_json, cash_runway_transaction_id, import_status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id.uuidString,
                provider.rawValue,
                integrationID.uuidString,
                bankAccountID.uuidString,
                providerAccountID,
                item.id,
                item.time,
                item.amount,
                item.operationAmount,
                item.currencyCode,
                item.mcc,
                item.originalMcc,
                item.description,
                item.comment,
                item.counterName,
                item.counterIban,
                item.receiptId,
                item.hold,
                rawJSON,
                cashRunwayTransactionID.uuidString,
                BankTransactionImportStatus.imported.rawValue,
                now,
                now,
            ]
        )
    }

    private static func backupLabel(_ row: Row) throws -> BackupLabel {
        BackupLabel(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            colorHex: row["color_hex"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func transaction(_ row: Row) throws -> CashRunwayTransaction {
        CashRunwayTransaction(
            id: UUID(uuidString: row["id"])!,
            walletID: UUID(uuidString: row["wallet_id"])!,
            type: TransactionKind(rawValue: row["type"]) ?? .expense,
            linkedTransferID: (row["linked_transfer_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            occurredAt: row["occurred_at"],
            localDayKey: row["local_day_key"],
            localMonthKey: row["local_month_key"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            isDeleted: row["is_deleted"],
            source: TransactionSource(rawValue: row["source"]) ?? .manual,
            recurringTemplateID: (row["recurring_template_id"] as String?).flatMap(UUID.init(uuidString:)),
            recurringInstanceID: (row["recurring_instance_id"] as String?).flatMap(UUID.init(uuidString:)),
            importJobID: (row["import_job_id"] as String?).flatMap(UUID.init(uuidString:)),
            importFingerprint: row["import_fingerprint"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupTransaction(_ row: Row) throws -> BackupTransaction {
        BackupTransaction(
            id: UUID(uuidString: row["id"])!,
            walletID: UUID(uuidString: row["wallet_id"])!,
            type: TransactionKind(rawValue: row["type"]) ?? .expense,
            linkedTransferID: (row["linked_transfer_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            occurredAt: row["occurred_at"],
            localDayKey: row["local_day_key"],
            localMonthKey: row["local_month_key"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            isDeleted: row["is_deleted"],
            source: TransactionSource(rawValue: row["source"]) ?? .manual,
            recurringTemplateID: (row["recurring_template_id"] as String?).flatMap(UUID.init(uuidString:)),
            recurringInstanceID: (row["recurring_instance_id"] as String?).flatMap(UUID.init(uuidString:)),
            importJobID: nil,
            importFingerprint: nil,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupTransactionLabel(_ row: Row) throws -> BackupTransactionLabel {
        BackupTransactionLabel(
            transactionID: UUID(uuidString: row["transaction_id"])!,
            labelID: UUID(uuidString: row["label_id"])!
        )
    }

    private static func budget(_ row: Row) throws -> Budget {
        Budget(
            id: UUID(uuidString: row["id"])!,
            categoryID: UUID(uuidString: row["category_id"])!,
            monthKey: row["month_key"],
            limitMinor: row["limit_minor"],
            isArchived: row["is_archived"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupBudget(_ row: Row) throws -> BackupBudget {
        BackupBudget(
            id: UUID(uuidString: row["id"])!,
            categoryID: UUID(uuidString: row["category_id"])!,
            monthKey: row["month_key"],
            limitMinor: row["limit_minor"],
            isArchived: row["is_archived"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func recurringTemplate(_ row: Row) throws -> RecurringTemplate {
        RecurringTemplate(
            id: UUID(uuidString: row["id"])!,
            kind: RecurringTemplateKind(rawValue: row["kind"]) ?? .expense,
            walletID: UUID(uuidString: row["wallet_id"])!,
            counterpartyWalletID: (row["counterparty_wallet_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            ruleType: RecurrenceRuleType(rawValue: row["rule_type"]) ?? .monthly,
            ruleInterval: row["rule_interval"],
            dayOfMonth: row["day_of_month"],
            weekday: row["weekday"],
            startDate: row["start_date"],
            endDate: row["end_date"],
            isActive: row["is_active"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupRecurringTemplate(_ row: Row) throws -> BackupRecurringTemplate {
        BackupRecurringTemplate(
            id: UUID(uuidString: row["id"])!,
            kind: RecurringTemplateKind(rawValue: row["kind"]) ?? .expense,
            walletID: UUID(uuidString: row["wallet_id"])!,
            counterpartyWalletID: (row["counterparty_wallet_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            ruleType: RecurrenceRuleType(rawValue: row["rule_type"]) ?? .monthly,
            ruleInterval: row["rule_interval"],
            dayOfMonth: row["day_of_month"],
            weekday: row["weekday"],
            startDate: row["start_date"],
            endDate: row["end_date"],
            isActive: row["is_active"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func recurringInstance(_ row: Row) throws -> RecurringInstance {
        RecurringInstance(
            id: UUID(uuidString: row["id"])!,
            templateID: UUID(uuidString: row["template_id"])!,
            dueDate: row["due_date"],
            dayKey: row["day_key"],
            status: RecurringInstanceStatus(rawValue: row["status"]) ?? .scheduled,
            linkedTransactionID: (row["linked_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideAmountMinor: row["override_amount_minor"],
            overrideCategoryID: (row["override_category_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideNote: row["override_note"],
            overrideMerchant: row["override_merchant"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupRecurringInstance(_ row: Row) throws -> BackupRecurringInstance {
        BackupRecurringInstance(
            id: UUID(uuidString: row["id"])!,
            templateID: UUID(uuidString: row["template_id"])!,
            dueDate: row["due_date"],
            dayKey: row["day_key"],
            status: RecurringInstanceStatus(rawValue: row["status"]) ?? .scheduled,
            linkedTransactionID: (row["linked_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideAmountMinor: row["override_amount_minor"],
            overrideCategoryID: (row["override_category_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideNote: row["override_note"],
            overrideMerchant: row["override_merchant"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func backupImportJob(_ row: Row) throws -> BackupImportJob {
        BackupImportJob(
            id: UUID(uuidString: row["id"])!,
            sourceName: row["source_name"],
            fileName: row["file_name"],
            status: ImportJobStatus(rawValue: row["status"]) ?? .created,
            totalRows: row["total_rows"],
            validRows: row["valid_rows"],
            invalidRows: row["invalid_rows"],
            startedAt: row["started_at"],
            finishedAt: row["finished_at"],
            errorSummary: row["error_summary"]
        )
    }
}
