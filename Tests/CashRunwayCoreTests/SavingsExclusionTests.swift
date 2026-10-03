import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

/// Task 4 — separate-entity savings wallets must stay out of every shared
/// aggregate (all-wallet total, timeline scopes, bounded sums, Overview wealth,
/// mixed-currency guard) while remaining fully readable when selected explicitly.
@Suite(.serialized)
struct SavingsExclusionTests {
    private struct SeededWallets {
        let operationalA: Wallet
        let operationalB: Wallet
        let flaggedUSD: Wallet
    }

    /// Two same-currency (UAH) operational wallets + one flagged USD savings wallet.
    /// The mixed currency in the flagged wallet additionally verifies that the
    /// mixed-currency guard ignores separate entities (Task 5 seam).
    private func seedStandardScenario() throws -> (repository: CashRunwayRepository, wallets: SeededWallets) {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let operationalA = WalletBuilder()
            .with(name: "Operational A")
            .with(kind: .card)
            .with(currencyCode: .uah)
            .with(startingBalanceMinor: 100_000)
            .with(currentBalanceMinor: 100_000)
            .build()
        let operationalB = WalletBuilder()
            .with(name: "Operational B")
            .with(kind: .cash)
            .with(currencyCode: .uah)
            .with(startingBalanceMinor: 0)
            .with(currentBalanceMinor: 50_000)
            .build()
        var flaggedUSD = WalletBuilder()
            .with(name: "Flagged USD")
            .with(kind: .savings)
            .with(currencyCode: .usd)
            .with(startingBalanceMinor: 10_000_000)
            .with(currentBalanceMinor: 10_000_000)
            .build()
        flaggedUSD.isExcludedFromSummary = true
        for wallet in [operationalA, operationalB, flaggedUSD] {
            try repository.saveWallet(wallet)
        }
        return (repository, SeededWallets(
            operationalA: operationalA,
            operationalB: operationalB,
            flaggedUSD: flaggedUSD
        ))
    }

    @Test func allWalletDashboardTotalExcludesFlaggedWallets() throws {
        let (repository, wallets) = try seedStandardScenario()
        let monthKey = DateKeys.monthKey(for: .now)

        let allWallets = try repository.dashboard(monthKey: monthKey, walletID: nil)
        #expect(allWallets.totalBalanceMinor == 150_000)

        let selectedFlagged = try repository.dashboard(monthKey: monthKey, walletID: wallets.flaggedUSD.id)
        #expect(selectedFlagged.totalBalanceMinor == 10_000_000)
    }

    @Test func timelineAllWalletsScopeExcludesFlagged() throws {
        let (repository, wallets) = try seedStandardScenario()
        let monthKey = DateKeys.monthKey(for: .now)
        let monthStart = DateKeys.startOfMonth(for: monthKey)
        let occurredAt = monthStart.addingTimeInterval(3600)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallets.operationalA.id,
            destinationWalletID: nil,
            amountMinor: 20_000,
            currencyCode: .uah,
            occurredAt: occurredAt,
            categoryID: expenseCategory.id,
            labelIDs: [],
            merchant: "Groceries",
            note: "Operational spend on the All-Wallets timeline",
            source: .manual
        ))
        try repository.saveTransaction(TransactionDraft(
            kind: .income,
            walletID: wallets.operationalA.id,
            destinationWalletID: nil,
            amountMinor: 90_000,
            currencyCode: .uah,
            occurredAt: occurredAt,
            categoryID: incomeCategory.id,
            labelIDs: [],
            merchant: "Salary",
            note: "Operational income on the All-Wallets timeline",
            source: .manual
        ))
        try repository.saveTransaction(TransactionDraft(
            kind: .income,
            walletID: wallets.flaggedUSD.id,
            destinationWalletID: nil,
            amountMinor: 500_000,
            currencyCode: .usd,
            occurredAt: occurredAt,
            categoryID: incomeCategory.id,
            labelIDs: [],
            merchant: "Investment Sale",
            note: "Savings timeline transaction",
            source: .manual
        ))
        

        let allWalletsTimeline = try repository.timelineSnapshot(monthKey: monthKey, walletID: nil)
        #expect(allWalletsTimeline.heroCashFlowMinor == 70_000)
        let allWalletsItems = allWalletsTimeline.sections.flatMap(\.items)
        #expect(!allWalletsItems.contains { $0.walletName == "Flagged USD" })
        #expect(allWalletsItems.contains { $0.walletName == "Operational A" })

        let flaggedTimeline = try repository.timelineSnapshot(monthKey: monthKey, walletID: wallets.flaggedUSD.id)
        let flaggedItems = flaggedTimeline.sections.flatMap(\.items)
        #expect(flaggedItems.contains { $0.walletName == "Flagged USD" })

        let operationalTimeline = try repository.timelineSnapshot(monthKey: monthKey, walletID: wallets.operationalA.id)
        #expect(operationalTimeline.bars.last?.expenseMinor == 20_000)
    }

    @Test func deleteGuardCountsOperationalOnly() throws {
        let (repository, wallets) = try seedStandardScenario()

        // 3 seeded: 2 operational + 1 flagged. Deleting the flagged wallet is allowed
        // while 2 operational wallets remain; then deleting an operational succeeds
        // while one operational remains; the LAST operational is refused.
        try repository.deleteWallet(id: wallets.flaggedUSD.id)
        try repository.deleteWallet(id: wallets.operationalA.id)
        do {
            try repository.deleteWallet(id: wallets.operationalB.id)
            Issue.record("Expected deleting the last operational wallet to fail")
        } catch {
            // expected: at least one operational wallet must remain
        }
        let remaining = try repository.wallets()
        #expect(!remaining.contains { $0.id == wallets.flaggedUSD.id })
        #expect(!remaining.contains { $0.id == wallets.operationalA.id })
        #expect(remaining.contains { $0.id == wallets.operationalB.id })
    }

    @Test func overviewWealthExcludesSavings() throws {
        let (repository, wallets) = try seedStandardScenario()
        let monthKey = DateKeys.monthKey(for: .now)
        let monthStart = DateKeys.startOfMonth(for: monthKey)
        let occurredAt = monthStart.addingTimeInterval(3600)

        // Pre-month income on the operational wallet: wealth history anchor.
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        try repository.saveTransaction(TransactionDraft(
            kind: .income,
            walletID: wallets.operationalA.id,
            destinationWalletID: nil,
            amountMinor: 40_000,
            currencyCode: .uah,
            occurredAt: occurredAt.addingTimeInterval(-2_592_000),
            categoryID: incomeCategory.id,
            labelIDs: [],
            merchant: "Salary",
            note: "Pre-month income for wealth history anchor",
            source: .manual
        ))

        let allWalletsOverview = try repository.overviewSnapshot(monthKey: monthKey, walletID: nil)
        #expect(allWalletsOverview.totalWealthMinor == 140_000)

        let flaggedOverview = try repository.overviewSnapshot(monthKey: monthKey, walletID: wallets.flaggedUSD.id)
        #expect(flaggedOverview.totalWealthMinor == 10_000_000)
    }

    @Test func aggregateCurrencyCodeIgnoresFlaggedWallets() throws {
        let (repository, wallets) = try seedStandardScenario()
        let walletsList = try repository.wallets()

        let uahOperational = walletsList.filter {
            $0.id == wallets.operationalA.id || $0.id == wallets.operationalB.id
        }
        #expect(uahOperational.aggregateCurrencyCode(selectedWalletID: nil) == .uah)
        #expect(walletsList.aggregateCurrencyCode(selectedWalletID: nil) == .uah)
        #expect(walletsList.aggregateCurrencyCode(selectedWalletID: nil) != nil)
        #expect(walletsList.aggregateCurrencyCode(selectedWalletID: wallets.flaggedUSD.id) == .usd)
    }

    @Test func normalizedWalletIDForAggregatesSkipsFlaggedWallets() throws {
        let (repository, wallets) = try seedStandardScenario()

        let staleID = UUID()
        let effectiveID = try #require(try repository.normalizedWalletIDForAggregates(selectedWalletID: staleID))
        #expect(effectiveID == wallets.operationalA.id || effectiveID == wallets.operationalB.id)
        #expect(effectiveID != wallets.flaggedUSD.id)

        // An explicitly selected flagged wallet remains a valid selection.
        let selectedFlagged = try repository.normalizedWalletIDForAggregates(selectedWalletID: wallets.flaggedUSD.id)
        #expect(selectedFlagged == wallets.flaggedUSD.id)
    }
}