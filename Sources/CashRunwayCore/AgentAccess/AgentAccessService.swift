import Foundation

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
/// `SettingsRepositorying`, `BankSyncRepositorying`) plus session/audit/redaction
/// collaborators. No `DatabaseManager` or `dbQueue` access.
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
        let validated = try grant.validated()
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
        let monthKey = request.monthKey ?? currentMonthKey()

        let snapshot = try repository {
            try dashboardRepository.overviewSnapshot(
                monthKey: monthKey,
                walletID: selectedSingleWalletID(from: session.scope)
            )
        }

        let wallets = try repository { try scopedWallets(session: session) }
        let walletSummaries = wallets.map {
            AgentWalletSummaryDTO(
                handle: walletHandle($0),
                name: $0.name,
                kind: $0.kind,
                currentBalanceMinor: $0.currentBalanceMinor,
                currencyCode: "UAH"
            )
        }

        let categoryRows = snapshot.categories.map {
            AgentCategoryRowDTO(
                name: $0.name,
                kind: $0.kind,
                amountMinor: $0.amountMinor,
                transactionCount: $0.transactionCount
            )
        }

        let response = AgentOverviewResponse(
            totalBalanceMinor: snapshot.totalWealthMinor,
            monthIncomeMinor: snapshot.monthIncomeMinor,
            monthExpenseMinor: snapshot.monthExpenseMinor,
            monthNetMinor: snapshot.monthCashFlowMinor,
            categoryRows: categoryRows,
            walletSummaries: walletSummaries
        )

        try await auditAllow(session: session, operation: "read:overview", resultCount: categoryRows.count)
        return response
    }

    public func readWallets(sessionID: UUID) async throws(AgentAccessError) -> AgentWalletsResponse {
        let session = try await validatedSession(sessionID, capability: .readWallets)
        let wallets = try repository { try scopedWallets(session: session) }
        let dtos = wallets.map {
            AgentWalletSummaryDTO(
                handle: walletHandle($0),
                name: $0.name,
                kind: $0.kind,
                currentBalanceMinor: $0.currentBalanceMinor,
                currencyCode: "UAH"
            )
        }
        try await auditAllow(session: session, operation: "read:wallets", resultCount: dtos.count)
        return AgentWalletsResponse(wallets: dtos)
    }

    public func readCategories(sessionID: UUID) async throws(AgentAccessError) -> AgentCategoriesResponse {
        let session = try await validatedSession(sessionID, capability: .readCategories)
        let categories = try repository { try dashboardRepository.categories(kind: nil) }
        let rows = categories.map {
            AgentCategoryRowDTO(
                name: $0.name,
                kind: $0.kind,
                amountMinor: 0,
                transactionCount: 0
            )
        }
        try await auditAllow(session: session, operation: "read:categories", resultCount: rows.count)
        return AgentCategoriesResponse(categories: rows)
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
                        operation: "read:transactions",
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
            try await auditDeny(session: session, operation: "read:transactions", reason: .dateRangeOutOfScope)
            throw .dateRangeOutOfScope
        }
        if let end = request.endDate, end > scopeInterval.end {
            try await auditDeny(session: session, operation: "read:transactions", reason: .dateRangeOutOfScope)
            throw .dateRangeOutOfScope
        }

        let effectiveStart = max(request.startDate ?? scopeInterval.start, scopeInterval.start)
        let effectiveEnd = min(request.endDate ?? scopeInterval.end, scopeInterval.end)
        let walletIDs = request.walletIDs ?? session.scope.walletScope.walletIDs

        var query = TransactionQuery(
            startDate: effectiveStart,
            endDate: effectiveEnd,
            offset: 0
        )
        if let walletIDs, let first = walletIDs.first, walletIDs.count == 1 {
            query.walletID = first
        }

        let limit = session.scope.maxTransactionCount
        let items = try repository { try dashboardRepository.transactions(query: query, limit: limit) }
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
                amountMinor: item.amountMinor,
                currencyCode: "UAH",
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

        let data = try encodeForAuditCheck(response)
        guard !redactionService.containsBlockedContent(data) else {
            try await auditDeny(session: session, operation: "read:transactions", reason: .redactionFailed)
            throw .redactionFailed
        }

        try await auditAllow(session: session, operation: "read:transactions", resultCount: dtos.count)
        return response
    }

    public func readBankConnectionStatus(
        sessionID: UUID,
        provider: BankProvider
    ) async throws(AgentAccessError) -> AgentBankConnectionStatusResponse {
        let session = try await validatedSession(sessionID, capability: .readBankConnectionStatus)
        guard session.scope.includeBankSyncMetadata else {
            try await auditDeny(session: session, operation: "read:bankConnectionStatus", reason: .missingCapability)
            throw .missingCapability
        }
        let status = try repository { try bankSyncRepository.bankConnectionStatus(provider: provider) }
        let response = AgentBankConnectionStatusResponse(
            provider: provider,
            isConnected: status.integration != nil,
            enabledAccountCount: status.enabledAccountCount,
            lastSyncError: status.lastSyncError
        )
        try await auditAllow(session: session, operation: "read:bankConnectionStatus", resultCount: 1)
        return response
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
            try await auditDeny(session: session, operation: capability.auditOperation, reason: error)
            throw error
        }
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

    private func selectedSingleWalletID(from scope: AgentScope) -> UUID? {
        if case let .selectedWallets(ids) = scope.walletScope, ids.count == 1 {
            return ids.first
        }
        return nil
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

    private func encodeForAuditCheck(_ value: some Codable & Sendable) throws(AgentAccessError) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(value)
        } catch {
            throw .redactionFailed
        }
    }

    private func scopeHash(_ session: AgentSession) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session.scope),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return String(string.hash)
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

    private func auditAllow(session: AgentSession, operation: String, resultCount: Int?) async throws(AgentAccessError) {
        let entry = AgentAuditEntry(
            id: UUID(),
            sessionID: session.id,
            capability: capabilityFor(operation: operation),
            operation: operation,
            decision: .allowed,
            denialReason: nil,
            scopeHash: scopeHash(session),
            requestSummary: "allowed request",
            resultCount: resultCount,
            createdAt: dateProvider()
        )
        try await appendAudit(entry)
    }

    private func auditDeny(session: AgentSession, operation: String, reason: AgentAccessError) async throws(AgentAccessError) {
        let entry = AgentAuditEntry(
            id: UUID(),
            sessionID: session.id,
            capability: capabilityFor(operation: operation),
            operation: operation,
            decision: .denied,
            denialReason: reason,
            scopeHash: scopeHash(session),
            requestSummary: "denied request",
            resultCount: nil,
            createdAt: dateProvider()
        )
        try await appendAudit(entry)
    }

    private func capabilityFor(operation: String) -> AgentCapability {
        switch operation {
        case "read:wallets": .readWallets
        case "read:categories": .readCategories
        case "read:transactions": .readTransactions
        case "read:bankConnectionStatus": .readBankConnectionStatus
        default: .readOverview
        }
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
