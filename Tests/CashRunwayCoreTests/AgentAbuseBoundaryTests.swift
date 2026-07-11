import Foundation
import Testing
@testable import CashRunwayCore

@Suite("Agent Abuse Boundaries")
struct AgentAbuseBoundaryTests {

    // MARK: - Multi-wallet transaction scope

    @Test func multiWalletSelectedScopeExcludesUnselectedWallets() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletA = UUID()
        let walletB = UUID()
        let walletC = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletA, name: "A", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now),
            Wallet(id: walletB, name: "B", kind: .card, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 1, createdAt: clock.now, updatedAt: clock.now),
            Wallet(id: walletC, name: "C", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 2, createdAt: clock.now, updatedAt: clock.now)
        ])
        let txA = makeTransaction(walletName: "A", amountMinor: 100, clock: clock)
        let txB = makeTransaction(walletName: "B", amountMinor: 200, clock: clock)
        let txC = makeTransaction(walletName: "C", amountMinor: 300, clock: clock)
        dashboard.set(transactions: [txA, txB, txC])

        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .selectedWallets([walletA, walletB]),
                maxTransactionCount: 10
            )
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        #expect(response.transactions.count == 2)
        #expect(response.transactions.contains { $0.walletDisplayName == "A" })
        #expect(response.transactions.contains { $0.walletDisplayName == "B" })
        #expect(!response.transactions.contains { $0.walletDisplayName == "C" })

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .allowed)
        #expect(entries[0].resultCount == 2)
    }

    // MARK: - Overview scope

    @Test func overviewRespectsSelectedWalletsAndDoesNotReturnAllWalletAggregate() async throws {
        let clock = TestClock(now: Self.lastDayOfMonth(year: 2026, month: 6))
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletA = UUID()
        let walletB = UUID()
        let walletC = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletA, name: "A", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 1000, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now),
            Wallet(id: walletB, name: "B", kind: .card, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 2000, isArchived: false, sortOrder: 1, createdAt: clock.now, updatedAt: clock.now),
            Wallet(id: walletC, name: "C", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 4000, isArchived: false, sortOrder: 2, createdAt: clock.now, updatedAt: clock.now)
        ])
        // Per-wallet snapshots are needed for the fake because it returns the storedOverview verbatim for single-wallet calls.
        dashboard.set(overview: nil)

        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(walletScope: .selectedWallets([walletA, walletB]), dateScope: .lastDays(365))
        )

        let response = try await service.readOverview(sessionID: session.id, request: .init(monthKey: currentMonthKey(clock: clock)))
        // Wallet summaries should only include A and B.
        #expect(response.walletSummaries.map(\.name).sorted() == ["A", "B"])
        #expect(response.walletSummaries.count == 2)
    }

    @Test func multiWalletOverviewAggregatesCategoriesWithoutDoubleCounting() async throws {
        let clock = TestClock(now: Self.lastDayOfMonth(year: 2026, month: 6))
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletA = UUID()
        let walletB = UUID()
        let categoryFood = UUID()
        let monthKey = currentMonthKey(clock: clock)
        dashboard.set(wallets: [
            Wallet(id: walletA, name: "A", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 1000, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now),
            Wallet(id: walletB, name: "B", kind: .card, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 2000, isArchived: false, sortOrder: 1, createdAt: clock.now, updatedAt: clock.now)
        ])

        let overviewA = OverviewSnapshot(
            selectedMonthKey: monthKey,
            walletFilterID: walletA,
            months: [],
            totalWealthMinor: 1000,
            monthCashFlowMinor: 100,
            monthIncomeMinor: 0,
            monthExpenseMinor: 100,
            categories: [
                OverviewCategoryRow(id: categoryFood, name: "Food", kind: .expense, colorHex: nil, iconName: nil, amountMinor: 100, transactionCount: 1, percentage: 1.0)
            ],
            labels: []
        )
        let overviewB = OverviewSnapshot(
            selectedMonthKey: monthKey,
            walletFilterID: walletB,
            months: [],
            totalWealthMinor: 2000,
            monthCashFlowMinor: 200,
            monthIncomeMinor: 0,
            monthExpenseMinor: 200,
            categories: [
                OverviewCategoryRow(id: categoryFood, name: "Food", kind: .expense, colorHex: nil, iconName: nil, amountMinor: 200, transactionCount: 2, percentage: 1.0)
            ],
            labels: []
        )
        dashboard.set(overviewByWalletID: [walletA: overviewA, walletB: overviewB])

        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(walletScope: .selectedWallets([walletA, walletB]), dateScope: .lastDays(365))
        )

        let response = try await service.readOverview(sessionID: session.id, request: .init(monthKey: monthKey))
        let foodRow = response.categoryRows.first { $0.name == "Food" }
        #expect(foodRow != nil)
        #expect(foodRow?.amount.amountMinor == 300)
        #expect(foodRow?.transactionCount == 3)
        #expect(response.totalBalance.amountMinor == 3000)
        #expect(response.monthExpense.amountMinor == 300)
        #expect(response.walletSummaries.count == 2)
    }

    @Test func overviewRejectsMonthKeyOutsideDateScope() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(dateScope: .lastDays(7))
        )

        let oldMonthKey = priorMonthKey(monthsBack: 3, clock: clock)
        await #expect(throws: AgentAccessError.dateRangeOutOfScope) {
            try await service.readOverview(sessionID: session.id, request: .init(monthKey: oldMonthKey))
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .dateRangeOutOfScope)
    }

    @Test func overviewRejectsPartiallyCoveredMonthKey() async throws {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 5))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let clock = TestClock(now: end)
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(dateScope: .closedRange(DateInterval(start: start, end: end)))
        )

        await #expect(throws: AgentAccessError.dateRangeOutOfScope) {
            try await service.readOverview(sessionID: session.id, request: .init(monthKey: 202606))
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .dateRangeOutOfScope)
    }

    @Test func overviewRejectsCurrentMonthWhenScopeDoesNotCoverFullMonth() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(dateScope: .lastDays(7))
        )

        // .lastDays(7) from Jan 12 1970 = Dec 6 1969 – Jan 12 1970.
        // Current month (January 1970) spans Jan 1-31, which does not fit
        // entirely within the 7-day scope.
        await #expect(throws: AgentAccessError.dateRangeOutOfScope) {
            try await service.readOverview(sessionID: session.id, request: .init(monthKey: currentMonthKey(clock: clock)))
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .dateRangeOutOfScope)
    }

    @Test func overviewAllowsCurrentMonthWhenScopeCoversFullMonth() async throws {
        let clock = TestClock(now: Self.lastDayOfMonth(year: 2026, month: 6))
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        dashboard.set(overview: OverviewSnapshot(
            selectedMonthKey: currentMonthKey(clock: clock),
            walletFilterID: walletID,
            months: [],
            totalWealthMinor: 0,
            monthCashFlowMinor: 0,
            monthIncomeMinor: 0,
            monthExpenseMinor: 0,
            categories: [],
            labels: []
        ))
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(dateScope: .lastDays(365))
        )

        let response = try await service.readOverview(sessionID: session.id, request: .init(monthKey: currentMonthKey(clock: clock)))
        #expect(response.totalBalance.amountMinor == 0)
    }

    @Test func overviewPreservesWalletCurrencyInMoneyDTOs() async throws {
        let clock = TestClock(now: Self.lastDayOfMonth(year: 2026, month: 6))
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "USD Wallet", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 5000, currencyCode: .usd, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        let monthKey = currentMonthKey(clock: clock)
        dashboard.set(overview: OverviewSnapshot(
            selectedMonthKey: monthKey,
            walletFilterID: walletID,
            months: [],
            totalWealthMinor: 5000,
            monthCashFlowMinor: 0,
            monthIncomeMinor: 0,
            monthExpenseMinor: 0,
            categories: [],
            labels: []
        ))
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(walletScope: .selectedWallets([walletID]), dateScope: .lastDays(365))
        )

        let response = try await service.readOverview(sessionID: session.id, request: .init(monthKey: monthKey))
        #expect(response.totalBalance.currencyCode == "USD")
        #expect(response.totalBalance.amountMinor == 5000)
        #expect(response.walletSummaries.first?.currentBalance.currencyCode == "USD")
    }

    // MARK: - Universal egress redaction

    @Test func walletResponseWithForbiddenSubstringIsDenied() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "raw_json wallet", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets]
        )

        await #expect(throws: AgentAccessError.redactionFailed) {
            try await service.readWallets(sessionID: session.id)
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .redactionFailed)
    }

    @Test func categoryResponseWithAccountLikeNameIsRedacted() async throws {
        let clock = TestClock()
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let category = Category(id: UUID(), name: "UA12345678901234567890123456", kind: .expense, iconName: nil, colorHex: nil, parentID: nil, isSystem: false, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        dashboard.set(categories: [category])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readCategories]
        )

        let response = try await service.readCategories(sessionID: session.id)
        #expect(response.categories.first?.name.contains("[REDACTED_IBAN]") == true)
    }

    @Test func overviewResponseWithForbiddenSubstringIsDenied() async throws {
        let clock = TestClock(now: Self.lastDayOfMonth(year: 2026, month: 6))
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        dashboard.set(overview: OverviewSnapshot(
            selectedMonthKey: currentMonthKey(clock: clock),
            walletFilterID: walletID,
            months: [],
            totalWealthMinor: 0,
            monthCashFlowMinor: 0,
            monthIncomeMinor: 0,
            monthExpenseMinor: 0,
            categories: [
                OverviewCategoryRow(
                    id: UUID(),
                    name: "counter_iban",
                    kind: .expense,
                    colorHex: nil,
                    iconName: nil,
                    amountMinor: 100,
                    transactionCount: 1,
                    percentage: 1.0
                )
            ],
            labels: []
        ))
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(walletScope: .selectedWallets([walletID]), dateScope: .lastDays(365))
        )

        await #expect(throws: AgentAccessError.redactionFailed) {
            try await service.readOverview(sessionID: session.id, request: .init(monthKey: currentMonthKey(clock: clock)))
        }
    }

    // MARK: - Bank status sanitization

    @Test func bankStatusWithActiveIntegrationAndRawTokenErrorIsSanitizedToTokenInvalid() async throws {
        let clock = TestClock()
        let (service, _, _, _, bankSync) = AgentTestMocks.makeService(clock: clock)
        bankSync.setStatus(
            BankConnectionStatusSnapshot(
                integration: activeBankIntegration(status: .active, clock: clock),
                enabledAccountCount: 1,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: "Provider rejected token for account X1234: unauthorized",
                importedExpenseCount: 0
            ),
            provider: .monobank
        )
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readBankConnectionStatus],
            scope: AgentScope(includeBankSyncMetadata: true)
        )

        let response = try await service.readBankConnectionStatus(sessionID: session.id, provider: .monobank)
        #expect(response.health == .tokenInvalid)
        #expect(response.isConnected == false)
        #expect(response.sanitizedErrorHint == nil)
    }

    @Test func bankStatusWithActiveIntegrationAndKeychainPathErrorIsSanitizedToSyncFailed() async throws {
        let clock = TestClock()
        let (service, _, _, _, bankSync) = AgentTestMocks.makeService(clock: clock)
        bankSync.setStatus(
            BankConnectionStatusSnapshot(
                integration: activeBankIntegration(status: .active, clock: clock),
                enabledAccountCount: 1,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: "Could not read keychain item at file:///private/var/...",
                importedExpenseCount: 0
            ),
            provider: .monobank
        )
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readBankConnectionStatus],
            scope: AgentScope(includeBankSyncMetadata: true)
        )

        let response = try await service.readBankConnectionStatus(sessionID: session.id, provider: .monobank)
        #expect(response.health == .syncFailed)
        #expect(response.isConnected == false)
        #expect(response.sanitizedErrorHint == nil)
    }

    @Test func bankStatusWithDisabledIntegrationReportsDisconnected() async throws {
        let clock = TestClock()
        let (service, _, _, _, bankSync) = AgentTestMocks.makeService(clock: clock)
        bankSync.setStatus(
            BankConnectionStatusSnapshot(
                integration: activeBankIntegration(status: .disabled, clock: clock),
                enabledAccountCount: 0,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            ),
            provider: .monobank
        )
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readBankConnectionStatus],
            scope: AgentScope(includeBankSyncMetadata: true)
        )

        let response = try await service.readBankConnectionStatus(sessionID: session.id, provider: .monobank)
        #expect(response.health == .disconnected)
        #expect(response.isConnected == false)
    }

    @Test func bankStatusWithTokenInvalidIntegrationReportsTokenInvalid() async throws {
        let clock = TestClock()
        let (service, _, _, _, bankSync) = AgentTestMocks.makeService(clock: clock)
        bankSync.setStatus(
            BankConnectionStatusSnapshot(
                integration: activeBankIntegration(status: .tokenInvalid, clock: clock),
                enabledAccountCount: 0,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            ),
            provider: .monobank
        )
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readBankConnectionStatus],
            scope: AgentScope(includeBankSyncMetadata: true)
        )

        let response = try await service.readBankConnectionStatus(sessionID: session.id, provider: .monobank)
        #expect(response.health == .tokenInvalid)
        #expect(response.isConnected == false)
    }

    @Test func bankStatusWithActiveIntegrationAndNoErrorReportsConnected() async throws {
        let clock = TestClock()
        let (service, _, _, _, bankSync) = AgentTestMocks.makeService(clock: clock)
        bankSync.setStatus(
            BankConnectionStatusSnapshot(
                integration: activeBankIntegration(status: .active, clock: clock),
                enabledAccountCount: 2,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            ),
            provider: .monobank
        )
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readBankConnectionStatus],
            scope: AgentScope(includeBankSyncMetadata: true)
        )

        let response = try await service.readBankConnectionStatus(sessionID: session.id, provider: .monobank)
        #expect(response.health == .connected)
        #expect(response.isConnected == true)
        #expect(response.enabledAccountCount == 2)
    }

    // MARK: - Transaction display-name redaction

    @Test func transactionWalletAndCategoryNamesWithAccountLikeStringsAreRedacted() async throws {
        let clock = TestClock()
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        let category = Category(id: UUID(), name: "UA12345678901234567890123456", kind: .expense, iconName: nil, colorHex: nil, parentID: nil, isSystem: false, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Card 4141 4141 4141 4141", kind: .card, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        dashboard.set(categories: [category])
        dashboard.set(transactions: [
            TransactionListItem(
                id: UUID(),
                walletName: "Card 4141 4141 4141 4141",
                amountMinor: 100,
                occurredAt: clock.now,
                categoryName: "UA12345678901234567890123456",
                categoryColorHex: nil,
                categoryIconName: nil,
                merchant: "Merchant",
                note: "",
                kind: .expense,
                source: .manual,
                labels: [],
                dayKey: 0
            )
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(walletScope: .selectedWallets([walletID]), maxTransactionCount: 10)
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        #expect(response.transactions.count == 1)
        let tx = response.transactions[0]
        #expect(tx.walletDisplayName.contains("[REDACTED_CARD]"))
        #expect(tx.categoryName?.contains("[REDACTED_IBAN]") == true)
    }

    // MARK: - Canonical scope hash

    @Test func identicalScopesWithDifferentWalletSetOrderProduceSameAuditHash() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletA = UUID()
        let walletB = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletA, name: "A", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now),
            Wallet(id: walletB, name: "B", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 1, createdAt: clock.now, updatedAt: clock.now)
        ])

        let idsOne = Set([walletA, walletB])
        let idsTwo = Set([walletB, walletA])

        let sessionOne = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets],
            scope: AgentScope(walletScope: .selectedWallets(idsOne))
        )
        _ = try await service.readWallets(sessionID: sessionOne.id)

        let sessionTwo = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets],
            scope: AgentScope(walletScope: .selectedWallets(idsTwo))
        )
        _ = try await service.readWallets(sessionID: sessionTwo.id)

        let entriesOne = try await audit.entries(forSessionID: sessionOne.id)
        let entriesTwo = try await audit.entries(forSessionID: sessionTwo.id)
        #expect(entriesOne.count == 1)
        #expect(entriesTwo.count == 1)
        #expect(entriesOne[0].scopeHash == entriesTwo[0].scopeHash)
        #expect(!entriesOne[0].scopeHash.isEmpty)
    }

    // MARK: - Consent version

    @Test func staleConsentVersionIsRejected() async throws {
        let clock = TestClock()
        let (service, _, _, _, _) = AgentTestMocks.makeService(clock: clock)

        await #expect(throws: AgentAccessError.invalidConsentVersion) {
            _ = try await AgentTestMocks.makeSession(
                service: service,
                capabilities: [.readWallets],
                consentVersion: "v0.9"
            )
        }
    }

    @Test func explicitConsentVersionIsAccepted() async throws {
        let clock = TestClock()
        let (service, _, _, _, _) = AgentTestMocks.makeService(clock: clock)

        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets],
            consentVersion: AgentConsentConstants.consentVersion
        )
        #expect(!session.id.uuidString.isEmpty)
    }

    // MARK: - Scope upper bounds

    @Test func excessiveMaxTransactionCountIsClampedToUpperBound() async throws {
        let clock = TestClock()
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: clock.now, updatedAt: clock.now)
        ])
        let transactions = (1...120).map { index in
            TransactionListItem(
                id: UUID(),
                walletName: "Cash",
                amountMinor: Int64(index),
                occurredAt: clock.now,
                categoryName: nil,
                categoryColorHex: nil,
                categoryIconName: nil,
                merchant: "M\(index)",
                note: "",
                kind: .expense,
                source: .manual,
                labels: [],
                dayKey: 0
            )
        }
        dashboard.set(transactions: transactions)
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .selectedWallets([walletID]),
                maxTransactionCount: 500,
                includeMerchantNames: true
            )
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        #expect(response.transactions.count == 100)
    }

    // MARK: - Helpers

    private func makeTransaction(walletName: String, amountMinor: Int64, clock: TestClock) -> TransactionListItem {
        TransactionListItem(
            id: UUID(),
            walletName: walletName,
            amountMinor: amountMinor,
            occurredAt: clock.now,
            categoryName: nil,
            categoryColorHex: nil,
            categoryIconName: nil,
            merchant: "Merchant",
            note: "",
            kind: .expense,
            source: .manual,
            labels: [],
            dayKey: 0
        )
    }

    private func activeBankIntegration(status: BankIntegrationStatus, clock: TestClock) -> BankIntegration {
        BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: status,
            syncStartAt: clock.now,
            tokenKeychainAccount: "monobank-token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: clock.now,
            updatedAt: clock.now
        )
    }

    private func currentMonthKey(clock: TestClock) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: clock.now)
        let month = calendar.component(.month, from: clock.now)
        return year * 100 + month
    }

    private func priorMonthKey(monthsBack: Int, clock: TestClock) -> Int {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .month, value: -monthsBack, to: clock.now) else {
            return currentMonthKey(clock: clock)
        }
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return year * 100 + month
    }

    private static func lastDayOfMonth(year: Int, month: Int) -> Date {
        let calendar = Calendar.current
        let firstOfNextMonth = calendar.date(from: DateComponents(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1))!
        return calendar.date(byAdding: .second, value: -1, to: firstOfNextMonth)!
    }
}
