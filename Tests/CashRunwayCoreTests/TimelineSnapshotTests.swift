import Foundation
import Testing
@testable import CashRunwayCore

// Repository integration tests for the deterministic `timelineSnapshot(...now:)`
// overload. Each test injects a fixed `now` so month-to-date, bounded sums, and the
// expense comparison are fully reproducible.
@Suite struct TimelineSnapshotTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func dayKey(_ year: Int, _ month: Int, _ day: Int) -> Int {
        year * 10_000 + month * 100 + day
    }

    private func makeSeededRepository() throws -> (CashRunwayRepository, Wallet, CashRunwayCore.Category, CashRunwayCore.Category) {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallet = try repository.wallets().first!
        let expenseCategory = try repository.categories(kind: .expense).first!
        let incomeCategory = try repository.categories(kind: .income).first!
        return (repository, wallet, expenseCategory, incomeCategory)
    }

    // MARK: - Month-to-date current period

    @Test func currentMonthSelectedBarIsMonthToDate() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        // Current month is July 2026; "now" is July 11.
        let now = date(2026, 7, 11)
        // An expense within month-to-date (July 5).
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 4_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        // An expense AFTER the current day (July 20) must be excluded from actuals.
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 9_000).with(occurredAt: date(2026, 7, 20)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202607 }

        #expect(selectedBar?.expenseMinor == 4_000, "Future-dated expense must be excluded from current month-to-date actuals.")
        #expect(snapshot.heroCashFlowMinor == selectedBar!.incomeMinor - selectedBar!.expenseMinor)
    }

    @Test func futureDatedRecordsExcludedFromCurrentActuals() throws {
        let (repository, wallet, expenseCategory, incomeCategory) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .income).with(walletID: wallet.id).with(categoryID: incomeCategory.id).with(amountMinor: 5_000).with(occurredAt: date(2026, 7, 25)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202607 }

        #expect(selectedBar?.incomeMinor == 0, "Future-dated income must be excluded from current month-to-date actuals.")
    }

    // MARK: - Completed historical period

    @Test func completedHistoricalMonthUsesFullAggregate() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        // Completed March: both early and late-day expenses count (full month).
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 1_000).with(occurredAt: date(2026, 3, 2)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 3, 30)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202603, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202603 }

        #expect(selectedBar?.expenseMinor == 3_000, "Completed historical month must include the full month, not truncate to today's ordinal day.")
    }

    // MARK: - Comparison: excludes income and transfers

    @Test func comparisonExcludesIncomeAndBothTransferDirections() throws {
        let (repository, wallet, expenseCategory, incomeCategory) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        let secondWallet = try WalletBuilder()
            .with(currencyCode: .uah)
            .build()
        try repository.saveWallet(secondWallet)

        // Current-period expense.
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 3_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        // Current-period income must not affect the expense comparison.
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .income).with(walletID: wallet.id).with(categoryID: incomeCategory.id).with(amountMinor: 9_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        // Baseline (June) expense to compare against.
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 1_500).with(occurredAt: date(2026, 6, 5)).build()
        )
        // Baseline transfer must be excluded from expense comparison.
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .transfer).with(walletID: wallet.id).with(destinationWalletID: secondWallet.id).with(amountMinor: 99_000).with(occurredAt: date(2026, 6, 5)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let comparison = try #require(snapshot.comparison)

        #expect(comparison.currentExpenseMinor == 3_000)
        #expect(comparison.baselineExpenseMinor == 1_500)
        // 3000 vs 1500 baseline: 100% higher.
        #expect(comparison.direction == .higher)
        #expect(comparison.percentageChange == 1.0)
    }

    // MARK: - Soft-deleted rows

    @Test func softDeletedRowsExcludedFromSums() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        let draft = TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 7_000).with(occurredAt: date(2026, 7, 5)).build()
        try repository.saveTransaction(draft)

        // Soft-delete the saved transaction.
        let saved = try repository.transactions(query: .init(walletID: wallet.id)).first!
        try repository.deleteTransaction(id: saved.id)

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202607 }
        #expect(selectedBar?.expenseMinor == 0, "Soft-deleted rows must be excluded from selected-period sums.")
    }

    // MARK: - Wallet scope

    @Test func selectedWalletScopeRespectedInSums() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try repository.saveWallet(WalletBuilder().with(name: "UAH One").with(currencyCode: .uah).build())
        try repository.saveWallet(WalletBuilder().with(name: "UAH Two").with(currencyCode: .uah).build())
        let wallets = try repository.wallets().filter { !$0.isArchived }
        let expenseCategory = try repository.categories(kind: .expense).first!
        let now = date(2026, 7, 11)

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallets[0].id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallets[1].id).with(categoryID: expenseCategory.id).with(amountMinor: 8_000).with(occurredAt: date(2026, 7, 5)).build()
        )

        let scoped = try repository.timelineSnapshot(monthKey: 202607, walletID: wallets[0].id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let scopedBar = scoped.bars.first { $0.periodKey == 202607 }
        #expect(scopedBar?.expenseMinor == 2_000, "Selected wallet scope must include only that wallet's transactions.")
    }

    @Test func sameCurrencyAllWalletsAggregatesEveryActiveWallet() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try repository.saveWallet(WalletBuilder().with(name: "UAH One").with(currencyCode: .uah).build())
        try repository.saveWallet(WalletBuilder().with(name: "UAH Two").with(currencyCode: .uah).build())
        let activeWallets = try repository.wallets().filter { !$0.isArchived }
        let expenseCategory = try repository.categories(kind: .expense).first!
        let now = date(2026, 7, 11)

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: activeWallets[0].id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: activeWallets[1].id).with(categoryID: expenseCategory.id).with(amountMinor: 8_000).with(occurredAt: date(2026, 7, 5)).build()
        )

        // nil walletID => All Wallets. Both same-currency wallets must be included.
        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: nil, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202607 }
        #expect(selectedBar?.expenseMinor == 10_000, "Same-currency All Wallets must genuinely aggregate every active wallet.")
        #expect(snapshot.walletFilterID == nil, "All Wallets nil scope must be preserved, not narrowed to one wallet.")
    }

    @Test func mixedCurrencyAllWalletsIsRejected() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try repository.saveWallet(WalletBuilder().with(name: "UAH").with(currencyCode: .uah).build())
        try repository.saveWallet(WalletBuilder().with(name: "USD").with(currencyCode: .usd).build())
        let now = date(2026, 7, 11)

        #expect(throws: CashRunwayError.self) {
            _ = try repository.timelineSnapshot(monthKey: 202607, walletID: nil, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        }
    }

    // MARK: - All Wallets scope excludes archived wallets

    @Test func allWalletsScopeExcludesArchivedWalletTransactions() throws {
        // Regression: nil (All Wallets) scope must aggregate only active wallets.
        // An archived same-currency wallet's historical transactions must not leak
        // into the snapshot bars, the bounded current-period sums, the baseline
        // comparison, or the historical `allBars` chart.
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let activeWallet = WalletBuilder().with(name: "UAH Active").with(currencyCode: .uah).build()
        let archivedWallet = WalletBuilder().with(name: "UAH Archived").with(currencyCode: .uah).build()
        try repository.saveWallet(activeWallet)
        try repository.saveWallet(archivedWallet)
        let expenseCategory = try repository.categories(kind: .expense).first!
        let now = date(2026, 7, 11)

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: activeWallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: archivedWallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 8_000).with(occurredAt: date(2026, 7, 5)).build()
        )

        // Archive the second wallet by re-saving with isArchived = true. Its
        // monthly_wallet_cashflow rows persist; the nil scope must filter them out.
        var archived = archivedWallet
        archived.isArchived = true
        try repository.saveWallet(archived)
        #expect(try repository.wallets().count == 1, "Archived wallet must not appear in the active wallets list.")

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: nil, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202607 }
        #expect(selectedBar?.expenseMinor == 2_000, "All Wallets must exclude archived-wallet transactions from the current-period bar.")
        #expect(snapshot.comparison?.baselineExpenseMinor == 0, "All Wallets must exclude archived-wallet transactions from the baseline.")

        let bars = try repository.allBars(walletID: nil, period: TimelinePeriod.month)
        let julyBar = bars.first { $0.periodKey == 202607 }
        #expect(julyBar?.expenseMinor == 2_000, "All Wallets allBars must exclude archived-wallet transactions.")
    }

    @Test func allWalletsDashboardAndOverviewExcludeArchivedWalletData() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let activeWallet = WalletBuilder().with(name: "UAH Active").with(currencyCode: .uah).build()
        let archivedWallet = WalletBuilder().with(name: "UAH Archived").with(currencyCode: .uah).build()
        try repository.saveWallet(activeWallet)
        try repository.saveWallet(archivedWallet)
        let expenseCategory = try repository.categories(kind: .expense).first!

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: activeWallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: archivedWallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 8_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        var archived = archivedWallet
        archived.isArchived = true
        try repository.saveWallet(archived)

        let dashboard = try repository.dashboard(monthKey: 202607, walletID: nil)
        #expect(dashboard.monthExpenseMinor == 2_000)
        #expect(dashboard.categories.first?.amountMinor == 2_000)
        #expect(dashboard.recentTransactions.count == 1)
        #expect(dashboard.recentTransactions.allSatisfy { $0.walletName == activeWallet.name })
        #expect(dashboard.wealthHistory.last?.amountMinor == -2_000)

        let overview = try repository.overviewSnapshot(monthKey: 202607, walletID: nil)
        #expect(overview.monthExpenseMinor == 2_000)
        #expect(overview.totalWealthMinor == -2_000)
        #expect(overview.categories.first?.amountMinor == 2_000)
    }

    // MARK: - Zero baseline / safety

    @Test func zeroBaselineNeverProducesNaNOrInfinity() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        // Current expense, no baseline spending at all.
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 3_000).with(occurredAt: date(2026, 7, 5)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let comparison = try #require(snapshot.comparison)

        #expect(comparison.baselineExpenseMinor == 0)
        #expect(comparison.direction == .unavailable, "New spending with zero baseline must be unavailable, not infinity.")
        #expect(comparison.percentageChange == nil)
    }

    @Test func bothZeroIsUnchangedWithNoPercentage() throws {
        let (repository, wallet, _, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let comparison = try #require(snapshot.comparison)

        #expect(comparison.currentExpenseMinor == 0)
        #expect(comparison.baselineExpenseMinor == 0)
        #expect(comparison.direction == .unchanged)
        #expect(comparison.percentageChange == nil)
    }

    @Test func equalNonZeroExpenseIsUnchangedAtZeroPercent() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 6, 5)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let comparison = try #require(snapshot.comparison)
        #expect(comparison.direction == .unchanged)
        #expect(comparison.percentageChange == 0.0)
    }

    @Test func lowerExpenseProducesLowerDirection() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 1_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 4_000).with(occurredAt: date(2026, 6, 5)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let comparison = try #require(snapshot.comparison)
        #expect(comparison.direction == .lower)
        #expect(comparison.percentageChange == -0.75)
    }

    // MARK: - Snapshot invariants

    @Test func comparisonCurrentExpenseMirrorsSelectedBar() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 6_000).with(occurredAt: date(2026, 7, 5)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let selectedBar = snapshot.bars.first { $0.periodKey == 202607 }
        let comparison = try #require(snapshot.comparison)
        #expect(comparison.currentExpenseMinor == selectedBar?.expenseMinor, "Comparison current expense must equal the selected bar's expense (invariant 2).")
        #expect(snapshot.heroCashFlowMinor == selectedBar!.incomeMinor - selectedBar!.expenseMinor, "Hero cash flow must equal income minus expense (invariant 1).")
    }

    @Test func futureSelectedPeriodRetainsTotalsButMarksComparisonUnavailable() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        // A future-dated transaction that lives in December (future selected period).
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 5_000).with(occurredAt: date(2026, 12, 5)).build()
        )

        let snapshot = try repository.timelineSnapshot(monthKey: 202612, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        // Comparison is unavailable for a strictly future period.
        #expect(snapshot.comparison == nil)
        // Stored totals are retained for the future period.
        let selectedBar = snapshot.bars.first { $0.periodKey == 202612 }
        #expect(selectedBar?.expenseMinor == 5_000)
    }

    // MARK: - Complete-day date filtering

    @Test func dateOnlyEndDateIncludesTransactionsLateInThatLocalDay() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        // Use the repository's own calendar so stored local_day_key and the query
        // bounds agree regardless of the device timezone.
        let dayMid = { (d: Int) in DateKeys.calendar.date(from: DateComponents(year: 2026, month: 6, day: d, hour: 12))! }
        // A transaction on June 5 must be included even when endDate is June 5 at
        // midnight (the whole local day is inclusive).
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 1_500).with(occurredAt: dayMid(5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: dayMid(6)).build()
        )

        let endDateAtMidnight = DateKeys.calendar.date(from: DateComponents(year: 2026, month: 6, day: 5))!
        let query = TransactionQuery(
            walletID: wallet.id,
            startDate: DateKeys.calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
            endDate: endDateAtMidnight
        )
        let items = try repository.transactions(query: query)
        // June 5 is within the June 5 local day (inclusive); June 6 is excluded.
        // TransactionListItem.amountMinor is signed (expenses are negative).
        #expect(items.count == 1)
        #expect(items.first?.amountMinor == -1_500)
    }

    // MARK: - Regression: historical allBars availability

    @Test func historicalAllBarsRemainAvailable() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 1_000).with(occurredAt: date(2026, 1, 15)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 2_000).with(occurredAt: date(2026, 2, 15)).build()
        )

        let bars = try repository.allBars(walletID: wallet.id, period: TimelinePeriod.month)
        #expect(bars.count >= 2, "Historical allBars must remain available for Phase 2 chart navigation.")
        #expect(bars.contains { $0.periodKey == 202601 })
        #expect(bars.contains { $0.periodKey == 202602 })
    }

    // MARK: - Regression: filters and wallet/period alter summary

    @Test func searchFilterDoesNotAlterSelectedSummary() throws {
        let (repository, wallet, expenseCategory, _) = try makeSeededRepository()
        let now = date(2026, 7, 11)
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 3_000).with(merchant: "Groceries").with(occurredAt: date(2026, 7, 5)).build()
        )

        let unfiltered = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let filtered = try repository.timelineSnapshot(monthKey: 202607, walletID: wallet.id, query: TransactionQuery(searchText: "Groceries"), period: TimelinePeriod.month, now: now)

        let unfilteredBar = unfiltered.bars.first { $0.periodKey == 202607 }
        let filteredBar = filtered.bars.first { $0.periodKey == 202607 }
        // Search affects only the feed sections, not the headline selected-bar summary.
        #expect(filteredBar?.expenseMinor == unfilteredBar?.expenseMinor)
        #expect(filtered.heroCashFlowMinor == unfiltered.heroCashFlowMinor)
        #expect(filtered.comparison == unfiltered.comparison)
    }

    @Test func walletSelectionAltersSummary() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try repository.saveWallet(WalletBuilder().with(name: "UAH One").with(currencyCode: .uah).build())
        try repository.saveWallet(WalletBuilder().with(name: "UAH Two").with(currencyCode: .uah).build())
        let activeWallets = try repository.wallets().filter { !$0.isArchived }
        let expenseCategory = try repository.categories(kind: .expense).first!
        let now = date(2026, 7, 11)

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: activeWallets[0].id).with(categoryID: expenseCategory.id).with(amountMinor: 1_000).with(occurredAt: date(2026, 7, 5)).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: activeWallets[1].id).with(categoryID: expenseCategory.id).with(amountMinor: 9_000).with(occurredAt: date(2026, 7, 5)).build()
        )

        let one = try repository.timelineSnapshot(monthKey: 202607, walletID: activeWallets[0].id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)
        let two = try repository.timelineSnapshot(monthKey: 202607, walletID: activeWallets[1].id, query: TransactionQuery(), period: TimelinePeriod.month, now: now)

        let oneBar = one.bars.first { $0.periodKey == 202607 }
        let twoBar = two.bars.first { $0.periodKey == 202607 }
        #expect(oneBar?.expenseMinor != twoBar?.expenseMinor, "Changing the selected wallet must change the selected-period summary.")
        #expect(oneBar?.expenseMinor == 1_000)
        #expect(twoBar?.expenseMinor == 9_000)
    }
}
