import Foundation
import CryptoKit

// MARK: - Agent Access Servicing

public protocol AgentAccessServicing: Sendable {
    func createSession(_ grant: AgentConsentGrant) async throws(AgentAccessError) -> AgentSession
    func revokeSession(id: UUID) async throws(AgentAccessError)
    func activeSessions() async throws(AgentAccessError) -> [AgentSession]

    func readOverview(sessionID: UUID, request: AgentOverviewRequest) async throws(AgentAccessError) -> AgentOverviewResponse
    func readWallets(sessionID: UUID) async throws(AgentAccessError) -> AgentWalletsResponse
    func readCategories(sessionID: UUID) async throws(AgentAccessError) -> AgentCategoriesResponse
    func readTransactions(sessionID: UUID, request: AgentTransactionsRequest) async throws(AgentAccessError) -> AgentTransactionsResponse
    func readBankConnectionStatus(sessionID: UUID, provider: BankProvider) async throws(AgentAccessError) -> AgentBankConnectionStatusResponse
}

// MARK: - Concrete Service

/// The concrete agent access service.
///
/// Depends only on narrow repository protocols (`DashboardRepositorying`,
/// `BankSyncRepositorying`) plus session/audit/redaction collaborators. No
/// `DatabaseManager` or `dbQueue` access.
public final class AgentAccessService: AgentAccessServicing, Sendable {
    private let sessionStore: any AgentSessionStoring
    private let auditLog: any AgentAuditLogging
    private let redactionService: AgentRedactionService
    private let dashboardRepository: any DashboardRepositorying
    private let bankSyncRepository: any BankSyncRepositorying
    private let consentVersion: String
    private let dateProvider: @Sendable () -> Date

    public init(
        sessionStore: any AgentSessionStoring,
        auditLog: any AgentAuditLogging,
        redactionService: AgentRedactionService = .init(),
        dashboardRepository: any DashboardRepositorying,
        bankSyncRepository: any BankSyncRepositorying,
        consentVersion: String = AgentConsentConstants.consentVersion,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sessionStore = sessionStore
        self.auditLog = auditLog
        self.redactionService = redactionService
        self.dashboardRepository = dashboardRepository
        self.bankSyncRepository = bankSyncRepository
        self.consentVersion = consentVersion
        self.dateProvider = dateProvider
    }

    // MARK: - Session management

    public func createSession(_ grant: AgentConsentGrant) async throws(AgentAccessError) -> AgentSession {
        var mutableGrant = grant
        try mutableGrant.scope.validate()
        let validated = try mutableGrant.validated(currentConsentVersion: consentVersion)
        let now = dateProvider()
        let session = AgentSession(
            id: UUID(),
            createdAt: now,
            expiresAt: now.addingTimeInterval(validated.requestedTTL),
            revokedAt: nil,
            capabilities: validated.capabilities,
            scope: validated.scope,
            consentVersion: validated.consentVersion
        )
        try await saveSession(session)
        return session
    }

    public func revokeSession(id: UUID) async throws(AgentAccessError) {
        do {
            try await sessionStore.revoke(id: id, at: dateProvider())
        } catch {
            throw .redactionFailed
        }
    }

    public func activeSessions() async throws(AgentAccessError) -> [AgentSession] {
        try await loadActiveSessions()
    }

    // MARK: - Read endpoints

    public func readOverview(
        sessionID: UUID,
        request: AgentOverviewRequest
    ) async throws(AgentAccessError) -> AgentOverviewResponse {
        let session = try await validatedSession(sessionID, capability: .readOverview)
        let monthKey = try await validatedMonthKey(request.monthKey, session: session)

        let snapshot = try repository {
            try overviewSnapshotScoped(session: session, monthKey: monthKey)
        }

        let wallets = try repository { try scopedWallets(session: session) }
        let walletSummaries = wallets.map {
            AgentWalletSummaryDTO(
                handle: walletHandle($0),
                name: redactionService.redactAccountLikePatterns($0.name),
                kind: $0.kind,
                currentBalance: uahMoney($0.currentBalanceMinor)
            )
        }

        let categoryRows = snapshot.categories.map {
            AgentCategoryRowDTO(
                name: redactionService.redactAccountLikePatterns($0.name),
                kind: $0.kind,
                amount: uahMoney($0.amountMinor),
                transactionCount: $0.transactionCount
            )
        }

        let response = AgentOverviewResponse(
            totalBalance: uahMoney(snapshot.totalWealthMinor),
            monthIncome: uahMoney(snapshot.monthIncomeMinor),
            monthExpense: uahMoney(snapshot.monthExpenseMinor),
            monthNet: uahMoney(snapshot.monthCashFlowMinor),
            categoryRows: categoryRows,
            walletSummaries: walletSummaries
        )

        return try await finalizeAllowedResponse(
            response,
            session: session,
            capability: .readOverview,
            resultCount: categoryRows.count
        )
    }

    public func readWallets(sessionID: UUID) async throws(AgentAccessError) -> AgentWalletsResponse {
        let session = try await validatedSession(sessionID, capability: .readWallets)
        let wallets = try repository { try scopedWallets(session: session) }
        let dtos = wallets.map {
            AgentWalletSummaryDTO(
                handle: walletHandle($0),
                name: redactionService.redactAccountLikePatterns($0.name),
                kind: $0.kind,
                currentBalance: uahMoney($0.currentBalanceMinor)
            )
        }
        let response = AgentWalletsResponse(wallets: dtos)
        return try await finalizeAllowedResponse(
            response,
            session: session,
            capability: .readWallets,
            resultCount: dtos.count
        )
    }

    public func readCategories(sessionID: UUID) async throws(AgentAccessError) -> AgentCategoriesResponse {
        let session = try await validatedSession(sessionID, capability: .readCategories)
        let categories = try repository { try dashboardRepository.categories(kind: nil) }
        let rows = categories.map {
            AgentCategoryRowDTO(
                name: redactionService.redactAccountLikePatterns($0.name),
                kind: $0.kind,
                amount: uahMoney(0),
                transactionCount: 0
            )
        }
        let response = AgentCategoriesResponse(categories: rows)
        return try await finalizeAllowedResponse(
            response,
            session: session,
            capability: .readCategories,
            resultCount: rows.count
        )
    }

    public func readTransactions(
        sessionID: UUID,
        request: AgentTransactionsRequest
    ) async throws(AgentAccessError) -> AgentTransactionsResponse {
        let session = try await validatedSession(sessionID, capability: .readTransactions)

        // Validate requested wallets against scope.
        if let requestedWalletIDs = request.walletIDs {
            for walletID in requestedWalletIDs {
                guard session.scope.walletScope.contains(walletID) else {
                    try await auditDeny(
                        session: session,
                        capability: .readTransactions,
                        reason: .walletOutOfScope
                    )
                    throw .walletOutOfScope
                }
            }
        }

        let now = dateProvider()
        let scopeInterval = session.scope.dateScope.dateInterval(now: now)

        // Validate explicit request dates against scope.
        if let start = request.startDate, start < scopeInterval.start {
            try await auditDeny(session: session, capability: .readTransactions, reason: .dateRangeOutOfScope)
            throw .dateRangeOutOfScope
        }
        if let end = request.endDate, end > scopeInterval.end {
            try await auditDeny(session: session, capability: .readTransactions, reason: .dateRangeOutOfScope)
            throw .dateRangeOutOfScope
        }

        let effectiveStart = max(request.startDate ?? scopeInterval.start, scopeInterval.start)
        let effectiveEnd = min(request.endDate ?? scopeInterval.end, scopeInterval.end)
        let walletIDs = request.walletIDs ?? session.scope.walletScope.walletIDs

        let limit = session.scope.maxTransactionCount
        let items = try repository {
            try transactionsScoped(
                walletIDs: walletIDs,
                startDate: effectiveStart,
                endDate: effectiveEnd,
                limit: limit
            )
        }
        let truncated = items.count >= limit

        // Map to safe DTOs.
        var dtos: [AgentTransactionDTO] = []
        for (index, item) in items.enumerated() {
            let handle = transactionHandle(index: index)
            let merchant = redactionService.merchantPreview(
                item.merchant,
                include: session.scope.includeMerchantNames
            )
            let note = redactionService.notePreview(
                item.note,
                include: session.scope.includeNotes
            )
            let labels = redactionService.labels(
                item.labels.map(\.name),
                include: session.scope.includeLabels
            )

            let dto = AgentTransactionDTO(
                handle: handle,
                occurredAt: item.occurredAt,
                walletDisplayName: item.walletName,
                kind: item.kind.asTransactionKind,
                amount: uahMoney(item.amountMinor),
                categoryName: item.categoryName,
                merchantPreview: merchant,
                notePreview: note,
                labels: labels,
                source: item.source
            )
            dtos.append(dto)
        }

        let response = AgentTransactionsResponse(
            transactions: dtos,
            returnedCount: dtos.count,
            truncatedToMax: truncated
        )

        return try await finalizeAllowedResponse(
            response,
            session: session,
            capability: .readTransactions,
            resultCount: dtos.count
        )
    }

    public func readBankConnectionStatus(
        sessionID: UUID,
        provider: BankProvider
    ) async throws(AgentAccessError) -> AgentBankConnectionStatusResponse {
        let session = try await validatedSession(sessionID, capability: .readBankConnectionStatus)
        guard session.scope.includeBankSyncMetadata else {
            try await auditDeny(session: session, capability: .readBankConnectionStatus, reason: .missingCapability)
            throw .missingCapability
        }
        let status = try repository { try bankSyncRepository.bankConnectionStatus(provider: provider) }
        let sanitized = sanitizedBankStatus(status)
        let response = AgentBankConnectionStatusResponse(
            provider: provider,
            isConnected: status.integration != nil,
            enabledAccountCount: status.enabledAccountCount,
            health: sanitized.health,
            sanitizedErrorHint: redactBankHint(sanitized.hint)
        )
        return try await finalizeAllowedResponse(
            response,
            session: session,
            capability: .readBankConnectionStatus,
            resultCount: 1
        )
    }

    // MARK: - Scope-aware repository reads

    /// Fetches transactions for the effective wallet selection. Multi-wallet
    /// selections are fetched per-wallet and merged so the repository's default
    /// unfiltered behavior cannot leak out-of-scope wallets.
    private func transactionsScoped(
        walletIDs: Set<UUID>?,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) throws -> [TransactionListItem] {
        switch effectiveWalletSelection(walletIDs: walletIDs) {
        case .all:
            let query = TransactionQuery(
                startDate: startDate,
                endDate: endDate,
                offset: 0
            )
            return try dashboardRepository.transactions(query: query, limit: limit)

        case .single(let walletID):
            var query = TransactionQuery(
                startDate: startDate,
                endDate: endDate,
                offset: 0
            )
            query.walletID = walletID
            return try dashboardRepository.transactions(query: query, limit: limit)

        case .multiple(let ids):
            var merged: [TransactionListItem] = []
            for walletID in ids {
                var query = TransactionQuery(
                    startDate: startDate,
                    endDate: endDate,
                    offset: 0
                )
                query.walletID = walletID
                let items = try dashboardRepository.transactions(query: query, limit: limit)
                merged.append(contentsOf: items)
            }
            // Sort using the app's primary transaction order (descending date, stable).
            merged.sort {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            return Array(merged.prefix(limit))
        }
    }

    private func overviewSnapshotScoped(session: AgentSession, monthKey: Int) throws -> OverviewSnapshot {
        switch effectiveWalletSelection(walletIDs: session.scope.walletScope.walletIDs) {
        case .all:
            return try dashboardRepository.overviewSnapshot(monthKey: monthKey, walletID: nil)
        case .single(let walletID):
            return try dashboardRepository.overviewSnapshot(monthKey: monthKey, walletID: walletID)
        case .multiple(let ids):
            // Aggregate across selected wallets by summing per-wallet snapshots.
            // This avoids relying on overviewSnapshot supporting a multi-wallet filter.
            var totalWealthMinor: Int64 = 0
            var monthCashFlowMinor: Int64 = 0
            var monthIncomeMinor: Int64 = 0
            var monthExpenseMinor: Int64 = 0
            var mergedCategories: [UUID: OverviewCategoryRow] = [:]
            for walletID in ids {
                let snapshot = try dashboardRepository.overviewSnapshot(monthKey: monthKey, walletID: walletID)
                totalWealthMinor += snapshot.totalWealthMinor
                monthCashFlowMinor += snapshot.monthCashFlowMinor
                monthIncomeMinor += snapshot.monthIncomeMinor
                monthExpenseMinor += snapshot.monthExpenseMinor
                for category in snapshot.categories {
                    var existing = mergedCategories[category.id] ?? category
                    existing.amountMinor += category.amountMinor
                    existing.transactionCount += category.transactionCount
                    mergedCategories[category.id] = existing
                }
            }
            return OverviewSnapshot(
                selectedMonthKey: monthKey,
                walletFilterID: nil,
                months: [],
                totalWealthMinor: totalWealthMinor,
                monthCashFlowMinor: monthCashFlowMinor,
                monthIncomeMinor: monthIncomeMinor,
                monthExpenseMinor: monthExpenseMinor,
                categories: Array(mergedCategories.values),
                labels: []
            )
        }
    }

    private enum EffectiveWalletSelection {
        case all
        case single(UUID)
        case multiple(Set<UUID>)
    }

    private func effectiveWalletSelection(walletIDs: Set<UUID>?) -> EffectiveWalletSelection {
        guard let ids = walletIDs else { return .all }
        if ids.count == 1, let first = ids.first {
            return .single(first)
        }
        return .multiple(ids)
    }

    // MARK: - Helpers

    private func validatedSession(_ id: UUID, capability: AgentCapability) async throws(AgentAccessError) -> AgentSession {
        guard let session = try await loadSession(id: id) else {
            let denial = AgentAuditEntry(
                id: UUID(),
                sessionID: id,
                capability: capability,
                operation: capability.auditOperation,
                decision: .denied,
                denialReason: .sessionNotFound,
                scopeHash: "",
                requestSummary: "session lookup",
                resultCount: nil,
                createdAt: dateProvider()
            )
            try? await appendAudit(denial)
            throw .sessionNotFound
        }

        do {
            try session.requireCapability(capability, now: dateProvider())
            return session
        } catch {
            try await auditDeny(session: session, capability: capability, reason: error)
            throw error
        }
    }

    private func validatedMonthKey(_ monthKey: Int?, session: AgentSession) async throws(AgentAccessError) -> Int {
        let resolved = monthKey ?? currentMonthKey()
        guard monthKeyInside(dateScope: session.scope.dateScope, monthKey: resolved) else {
            try await auditDeny(session: session, capability: .readOverview, reason: .dateRangeOutOfScope)
            throw .dateRangeOutOfScope
        }
        return resolved
    }

    private func monthKeyInside(dateScope: AgentDateScope, monthKey: Int) -> Bool {
        let now = dateProvider()
        let interval = dateScope.dateInterval(now: now)
        let calendar = Calendar.current
        guard let startComponents = monthKeyComponents(monthKey),
              let startDate = calendar.date(from: startComponents) else {
            return false
        }
        guard let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) else {
            return false
        }
        // The requested month must overlap the approved date scope.
        // This lets a "last 30 days" session ask about the current month without
        // silently broadening access to months entirely outside the scope.
        return interval.start <= endDate && startDate <= interval.end
    }

    private func monthKeyComponents(_ monthKey: Int) -> DateComponents? {
        let year = monthKey / 100
        let month = monthKey % 100
        guard year >= 1, month >= 1, month <= 12 else { return nil }
        return DateComponents(year: year, month: month, day: 1)
    }

    private func scopedWallets(session: AgentSession) throws -> [Wallet] {
        let all = try dashboardRepository.wallets()
        switch session.scope.walletScope {
        case .allWallets:
            return all
        case let .selectedWallets(ids):
            return all.filter { ids.contains($0.id) }
        }
    }

    private func repository<T>(_ operation: () throws -> T) throws(AgentAccessError) -> T {
        do {
            return try operation()
        } catch {
            throw .redactionFailed
        }
    }

    private func currentMonthKey() -> Int {
        let now = dateProvider()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return year * 100 + month
    }

    private func walletHandle(_ wallet: Wallet) -> String {
        "wallet_\(wallet.id.uuidString.prefix(8))"
    }

    private func transactionHandle(index: Int) -> String {
        String(format: "tx_%03d", index + 1)
    }

    private func uahMoney(_ amountMinor: Int64) -> AgentMoneyDTO {
        AgentMoneyDTO(amountMinor: amountMinor, currencyCode: "UAH", scale: 2)
    }

    // MARK: - Egress validation

    /// Mandatory egress gate: encodes the response, checks for blocked content,
    /// writes an allow audit entry, and returns the response.
    private func finalizeAllowedResponse<Response: Codable & Sendable>(
        _ response: Response,
        session: AgentSession,
        capability: AgentCapability,
        resultCount: Int?
    ) async throws(AgentAccessError) -> Response {
        let data = try encodeForAuditCheck(response)
        guard !redactionService.containsBlockedContent(data) else {
            try await auditDeny(session: session, capability: capability, reason: .redactionFailed)
            throw .redactionFailed
        }

        try await auditAllow(session: session, capability: capability, resultCount: resultCount)
        return response
    }

    private func encodeForAuditCheck(_ value: some Codable & Sendable) throws(AgentAccessError) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(value)
        } catch {
            throw .redactionFailed
        }
    }

    // MARK: - Stable scope hash

    private func scopeHash(_ session: AgentSession) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session.scope) else {
            return ""
        }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Bank status sanitization

    private struct SanitizedBankStatus {
        let health: AgentBankSyncHealth
        let hint: String?
    }

    private func sanitizedBankStatus(_ status: BankConnectionStatusSnapshot) -> SanitizedBankStatus {
        let rawError = status.lastSyncError?.lowercased() ?? ""
        if rawError.isEmpty {
            return SanitizedBankStatus(health: status.integration != nil ? .connected : .disconnected, hint: nil)
        }
        if rawError.contains("token") || rawError.contains("auth") || rawError.contains("unauthorized") {
            return SanitizedBankStatus(health: .tokenInvalid, hint: nil)
        }
        if rawError.contains("rate") || rawError.contains("429") || rawError.contains("throttle") {
            return SanitizedBankStatus(health: .rateLimited, hint: nil)
        }
        return SanitizedBankStatus(health: .syncFailed, hint: nil)
    }

    private func redactBankHint(_ hint: String?) -> String? {
        guard let hint else { return nil }
        return redactionService.redactAccountLikePatterns(hint)
    }

    // MARK: - Collaborator wrappers (typed throws)

    private func loadSession(id: UUID) async throws(AgentAccessError) -> AgentSession? {
        do {
            return try await sessionStore.session(id: id)
        } catch {
            throw .sessionNotFound
        }
    }

    private func saveSession(_ session: AgentSession) async throws(AgentAccessError) {
        do {
            try await sessionStore.save(session)
        } catch {
            throw .redactionFailed
        }
    }

    private func loadActiveSessions() async throws(AgentAccessError) -> [AgentSession] {
        do {
            return try await sessionStore.activeSessions(now: dateProvider())
        } catch {
            throw .sessionNotFound
        }
    }

    private func appendAudit(_ entry: AgentAuditEntry) async throws(AgentAccessError) {
        do {
            try await auditLog.append(entry)
        } catch {
            throw .redactionFailed
        }
    }

    private func auditAllow(session: AgentSession, capability: AgentCapability, resultCount: Int?) async throws(AgentAccessError) {
        let entry = AgentAuditEntry(
            id: UUID(),
            sessionID: session.id,
            capability: capability,
            operation: capability.auditOperation,
            decision: .allowed,
            denialReason: nil,
            scopeHash: scopeHash(session),
            requestSummary: "allowed request",
            resultCount: resultCount,
            createdAt: dateProvider()
        )
        try await appendAudit(entry)
    }

    private func auditDeny(session: AgentSession, capability: AgentCapability, reason: AgentAccessError) async throws(AgentAccessError) {
        let entry = AgentAuditEntry(
            id: UUID(),
            sessionID: session.id,
            capability: capability,
            operation: capability.auditOperation,
            decision: .denied,
            denialReason: reason,
            scopeHash: scopeHash(session),
            requestSummary: "denied request",
            resultCount: nil,
            createdAt: dateProvider()
        )
        try await appendAudit(entry)
    }
}

// MARK: - Kind mapping

private extension TransactionDraft.Kind {
    var asTransactionKind: TransactionKind {
        switch self {
        case .expense: .expense
        case .income: .income
        case .transfer: .transferOut
        }
    }
}
