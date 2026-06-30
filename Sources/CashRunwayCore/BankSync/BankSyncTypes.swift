import Foundation
import GRDB

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
    // @unchecked Sendable is justified: `base` and `gate` are immutable; the
    // actor-isolated `BankSyncSerialGate` serializes all sync calls, so there
    // is no concurrent access to shared state.
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
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let` (URL, URLSession, JSONDecoder). URLSession is thread-safe for
    // concurrent data tasks.
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL = URL(string: "https://api.monobank.ua")!,
        session: URLSession = URLSession(configuration: .ephemeral)
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
            throw BankSyncError.transient(L10n.string("Monobank API temporarily unavailable."))
        default:
            throw BankSyncError.invalidResponse
        }
    }
}

public final class MonobankPersonalAPIClient: MonobankClient, @unchecked Sendable {
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let`. URLSession is thread-safe; `BankTokenStore` is Sendable.
    private let tokenStore: any BankTokenStore
    private let tokenAccount: String
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        tokenStore: any BankTokenStore,
        tokenAccount: String,
        baseURL: URL = URL(string: "https://api.monobank.ua")!,
        session: URLSession = URLSession(configuration: .ephemeral)
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
            throw CashRunwayError.validation(L10n.string("Monobank statement window must not exceed 31 days."))
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
            throw BankSyncError.transient(L10n.string("Monobank API temporarily unavailable."))
        default:
            throw BankSyncError.invalidResponse
        }
    }
}

public final class BankSyncService: BankSyncPerforming, @unchecked Sendable {
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let`; `repository` is `any CashRunwayRepositorying` (Sendable, backed by
    // GRDB DatabaseQueue serialization); `client` is Sendable; `now` is
    // `@Sendable`.
    private let repository: any CashRunwayRepositorying
    private let client: any MonobankClient
    private let now: @Sendable () -> Date

    public init(
        repository: any CashRunwayRepositorying,
        client: any MonobankClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.client = client
        self.now = now
    }

    public func syncOnDemand() async throws -> BankSyncResult {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "syncOnDemand") else { return BankSyncResult() }
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
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "syncOnForeground") else { return BankSyncResult() }
        return try await syncOnDemand()
    }

    public func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        guard !ProtectedDataMonitor.skipIfUnavailable(work: "syncIntegration") else { return BankSyncResult() }
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
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let`; `repository`, `tokenStore`, `tokenValidator`, `syncPerformer` are
    // Sendable protocols; `now` is `@Sendable`.
    private let repository: any CashRunwayRepositorying
    private let tokenStore: any BankTokenStore
    private let tokenValidator: any MonobankTokenValidating
    private let syncPerformer: any BankSyncPerforming
    private let now: @Sendable () -> Date

    public init(
        repository: any CashRunwayRepositorying,
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
            throw CashRunwayError.validation(L10n.string("Select at least one UAH Monobank card."))
        }
        let walletIDs = Set(try repository.wallets().map(\.id))
        guard enabledSelections.allSatisfy({ walletIDs.contains($0.walletID) }) else {
            throw CashRunwayError.validation(L10n.string("Each selected Monobank account must map to an existing wallet."))
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
        let cardName = (account.type?.isEmpty == false ? account.type! : L10n.string("Card")).capitalized
        if let masked = account.maskedPan?.first, !masked.isEmpty {
            return L10n.string("%@ card %@", cardName, "****\(masked.suffix(4))")
        }
        return L10n.string("%@ card", cardName)
    }
}

public final class BankSyncCoordinator: BankSyncPerforming, @unchecked Sendable {
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let`; `repository`, `tokenStore` are Sendable; `now` is `@Sendable`.
    private let repository: any CashRunwayRepositorying
    private let tokenStore: any BankTokenStore
    private let now: @Sendable () -> Date

    public init(
        repository: any CashRunwayRepositorying,
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

public enum BankCategoryResolutionSource: Sendable {
    case cashRunwayWallet
    case bankStatement(BankProvider)
    case genericBankStatement
}

public struct BankCategoryResolutionResult: Sendable {
    public let categoryID: UUID
    public let categoryName: String
}

/// Loads bank-category rules and active categories once, then resolves rows
/// in-memory. This avoids a database read per imported row, which is critical
/// for large CSV/XLSX imports.
public final class BankCategoryResolver: @unchecked Sendable {
    // @unchecked Sendable is justified: all stored properties are immutable
    // `let` (rules and category entries are loaded once in init and never
    // mutated). Reads are concurrent-safe over immutable data.
    private struct Rule {
        let provider: BankProvider
        let merchantPattern: String?
        let mcc: Int?
        let categoryID: UUID
    }

    private struct CategoryEntry {
        let id: UUID
        let name: String
        let kind: CategoryKind
    }

    private var merchantRules: [Rule] = []
    private var mccRules: [Rule] = []
    private var categoriesByNormalizedName: [CategoryKind: [String: CategoryEntry]] = [:]
    private var categoriesByID: [UUID: CategoryEntry] = [:]

    // swiftlint:disable:next cyclomatic_complexity
    public init(repository: CashRunwayRepository) throws {
        try repository.databaseManager.dbQueue.read { db in
            // Load all categories (including archived) so remapped names resolve.
            let allCategoryRows = try Row.fetchAll(
                db,
                sql: "SELECT id, name, kind, is_archived FROM categories"
            )
            var allCategoriesByID: [UUID: CategoryEntry] = [:]
            for row in allCategoryRows {
                guard let id = UUID(uuidString: row["id"]) else { continue }
                guard let kind = CategoryKind(rawValue: row["kind"]) else { continue }
                let entry = CategoryEntry(id: id, name: row["name"], kind: kind)
                allCategoriesByID[id] = entry
            }

            // Build remap chain map.
            let remapRows = try Row.fetchAll(db, sql: "SELECT old_category_id, new_category_id FROM category_remaps")
            var remaps: [UUID: UUID] = [:]
            for row in remapRows {
                guard let oldID = UUID(uuidString: row["old_category_id"]),
                      let newID = UUID(uuidString: row["new_category_id"]) else { continue }
                remaps[oldID] = newID
            }

            func finalCategoryID(_ id: UUID) -> UUID {
                var visited: Set<UUID> = []
                var current = id
                while let next = remaps[current], visited.insert(current).inserted {
                    current = next
                }
                return current
            }

            // Active categories by ID, plus name lookup for active categories.
            var activeByID: [UUID: CategoryEntry] = [:]
            var byName: [CategoryKind: [String: CategoryEntry]] = [:]
            for (_, entry) in allCategoriesByID where entry.id == finalCategoryID(entry.id) {
                activeByID[entry.id] = entry
                let key = BankCategoryResolver.normalize(entry.name)
                byName[entry.kind, default: [:]][key] = entry
            }

            // Map names of archived/remapped categories to their active destination.
            for (_, entry) in allCategoriesByID {
                let finalID = finalCategoryID(entry.id)
                guard finalID != entry.id, let activeEntry = activeByID[finalID] else { continue }
                let key = BankCategoryResolver.normalize(entry.name)
                byName[entry.kind, default: [:]][key] = activeEntry
            }

            self.categoriesByID = activeByID
            self.categoriesByNormalizedName = byName

            // Load rules and point them at their final active category.
            let ruleRows = try Row.fetchAll(
                db,
                sql: """
                SELECT provider, rule_type, merchant_pattern, mcc, category_id
                FROM bank_category_rules
                ORDER BY confidence DESC, created_at
                """
            )
            var merchantRules: [Rule] = []
            var mccRules: [Rule] = []
            for row in ruleRows {
                guard let provider = BankProvider(rawValue: row["provider"]) else { continue }
                guard let rawCategoryID = UUID(uuidString: row["category_id"]),
                      activeByID[finalCategoryID(rawCategoryID)] != nil else { continue }
                let ruleType: String = row["rule_type"]
                if ruleType == "merchant" {
                    merchantRules.append(Rule(
                        provider: provider,
                        merchantPattern: row["merchant_pattern"],
                        mcc: nil,
                        categoryID: finalCategoryID(rawCategoryID)
                    ))
                } else if ruleType == "mcc" {
                    mccRules.append(Rule(
                        provider: provider,
                        merchantPattern: nil,
                        mcc: row["mcc"],
                        categoryID: finalCategoryID(rawCategoryID)
                    ))
                }
            }
            self.merchantRules = merchantRules
            self.mccRules = mccRules
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func resolve(
        source: BankCategoryResolutionSource,
        kind: TransactionDraft.Kind,
        merchant: String?,
        description: String,
        rawCategoryName: String?,
        mcc: Int?,
        originalMcc: Int?
    ) -> BankCategoryResolutionResult? {
        guard kind != .transfer else { return nil }
        let categoryKind: CategoryKind = kind == .income ? .income : .expense
        let fallbackName = kind == .income ? "Other Income" : "Other Expense"
        let allowsBankFallbacks = switch source {
        case .bankStatement, .genericBankStatement:
            true
        case .cashRunwayWallet:
            false
        }

        if case .bankStatement(let provider) = source {
            let haystack = [merchant, description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .joined(separator: " ")
            if !haystack.isEmpty {
                for rule in merchantRules where rule.provider == provider {
                    if let pattern = rule.merchantPattern, !pattern.isEmpty, haystack.contains(pattern.lowercased()) {
                        return result(for: rule.categoryID, fallbackName: fallbackName)
                    }
                }
            }

            let codes = Set([mcc, originalMcc].compactMap { $0 })
            if !codes.isEmpty {
                for rule in mccRules where rule.provider == provider {
                    guard let ruleMCC = rule.mcc, codes.contains(ruleMCC) else { continue }
                    return result(for: rule.categoryID, fallbackName: fallbackName)
                }
            }
        }

        if let rawCategoryName {
            let key = BankCategoryResolver.normalize(rawCategoryName)
            if let entry = categoriesByNormalizedName[categoryKind]?[key] {
                return BankCategoryResolutionResult(categoryID: entry.id, categoryName: entry.name)
            }
        }

        if allowsBankFallbacks {
            if let builtInCategoryName = Self.builtInMerchantCategoryName(
                merchant: merchant,
                description: description,
                kind: kind
            ), let entry = categoriesByNormalizedName[categoryKind]?[Self.normalize(builtInCategoryName)] {
                return BankCategoryResolutionResult(categoryID: entry.id, categoryName: builtInCategoryName)
            }

            if let rawCategoryName,
               let canonicalName = BankCategoryNameMapping.categoryName(for: rawCategoryName, kind: kind) {
                let key = BankCategoryResolver.normalize(canonicalName)
                if let entry = categoriesByNormalizedName[categoryKind]?[key] {
                    return BankCategoryResolutionResult(categoryID: entry.id, categoryName: canonicalName)
                }
            }

            for code in [mcc, originalMcc].compactMap({ $0 }) {
                if let canonicalName = MCCCategoryMapping.categoryName(for: code),
                   let entry = categoriesByNormalizedName[categoryKind]?[BankCategoryResolver.normalize(canonicalName)] {
                    return BankCategoryResolutionResult(categoryID: entry.id, categoryName: canonicalName)
                }
            }
        }

        if allowsBankFallbacks,
           let entry = categoriesByNormalizedName[categoryKind]?[BankCategoryResolver.normalize(fallbackName)] {
            return BankCategoryResolutionResult(categoryID: entry.id, categoryName: fallbackName)
        }
        return nil
    }

    private func result(for categoryID: UUID, fallbackName: String) -> BankCategoryResolutionResult? {
        guard let entry = categoriesByID[categoryID] else {
            return nil
        }
        return BankCategoryResolutionResult(categoryID: entry.id, categoryName: entry.name)
    }

    static func normalize(_ input: String) -> String {
        input
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased()
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: " ")
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func builtInMerchantCategoryName(
        merchant: String?,
        description: String?,
        kind: TransactionDraft.Kind
    ) -> String? {
        guard kind == .expense else { return nil }

        let haystack = [merchant, description].compactMap { $0?.lowercased() }
        guard !haystack.isEmpty else { return nil }

        if haystack.contains(where: { $0.contains("temu") }) {
            return "Shopping"
        }

        return nil
    }
}

/// Backward-compatible alias for code that previously used the per-row mapper.
public typealias BankCategoryMapper = BankCategoryResolver
