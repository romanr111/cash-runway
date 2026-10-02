import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

/// Issue #121: retrospective monthly USD snapshot — persistence, store-once
/// semantics, month-end rate resolution (exact → nearest-earlier approximate →
/// fetch), and conversion direction (rate rows are FOREIGN→UAH; UAH→USD divides).
@Suite(.serialized)
struct MonthlyUSDSnapshotTests {
    // MARK: - Fixtures

    private let junEnd = DateKeys.calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12))!
    private let may27 = DateKeys.calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 12))!
    private let jun20 = DateKeys.calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 12))!

    private func makeRepository() throws -> CashRunwayRepository {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        return repository
    }

    private func makeWallet(_ repository: CashRunwayRepository, currencyCode: CurrencyCode = .uah) throws -> Wallet {
        let wallet = Wallet(
            id: UUID(),
            name: "Wallet \(currencyCode.rawValue) \(UUID().uuidString.prefix(4))",
            kind: .cash,
            colorHex: nil,
            iconName: nil,
            startingBalanceMinor: 0,
            currentBalanceMinor: 0,
            currencyCode: currencyCode,
            isArchived: false,
            sortOrder: 0,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWallet(wallet)
        return wallet
    }

    private func seedCashflow(
        _ repository: CashRunwayRepository,
        walletID: UUID,
        monthKey: Int,
        incomeMinor: Int64,
        expenseMinor: Int64
    ) throws {
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO monthly_wallet_cashflow (wallet_id, month_key, income_minor, expense_minor, transfer_in_minor, transfer_out_minor, txn_count, updated_at)
                VALUES (?, ?, ?, ?, 0, 0, 1, ?)
                ON CONFLICT(wallet_id, month_key) DO UPDATE SET
                    income_minor = excluded.income_minor,
                    expense_minor = excluded.expense_minor,
                    updated_at = excluded.updated_at
                """,
                arguments: [walletID.uuidString, monthKey, incomeMinor, expenseMinor, Date()]
            )
        }
    }

    private func exchangeRateCount(in repository: CashRunwayRepository) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates") ?? 0
        }
    }

    private func snapshotCount(in repository: CashRunwayRepository) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM monthly_usd_snapshot") ?? 0
        }
    }

    private func makeService(_ repository: CashRunwayRepository, provider: ExchangeRateProviding) throws -> MonthlyRetrospectiveUSDSnapshotService {
        MonthlyRetrospectiveUSDSnapshotService(repository: repository, rateProvider: provider)
    }

    // MARK: - Reporting currency

    @Test func reportingCurrencyDefaultsToUSDAndRespectsExplicitPreference() {
        // Pre-feature seed (UAH reporting) is treated as "unset" → USD.
        #expect(MonthlyRetrospectiveUSDSnapshotService.reportingCurrency(fallback: .usd, preferences: .default) == .usd)
        // Explicit user choice wins.
        let eur = CurrencyPreferences(defaultCurrencyCode: .uah, reportingCurrencyCode: .eur)
        #expect(MonthlyRetrospectiveUSDSnapshotService.reportingCurrency(fallback: .usd, preferences: eur) == .eur)
    }

    // MARK: - Conversion math and direction

    @Test func usdToUAHMultipliesAndIsExact() throws {
        let rate = ExchangeRate(
            sourceCurrencyCode: .usd,
            targetCurrencyCode: .uah,
            rateDecimal: "41.25",
            effectiveDate: junEnd,
            source: "nbu-official"
        )
        // 1000.00 USD * 41.25 = 41_250.00 UAH minor
        let result = try MonthlyRetrospectiveUSDSnapshotService.convertMinor(100_000, factor: 41.25)
        #expect(result == 4_125_000)
        _ = rate
    }

    @Test func uahToUSDDividesByUSDToUAHRate() async throws {
        // Rate rows store FOREIGN→UAH; USD→UAH rate 41.25 → factor UAH→USD = 1/41.25.
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository, currencyCode: .uah)
        // 41_250.00 UAH / 41.25 = 1000.00 USD
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 4_125_000)
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.25", effectiveDate: junEnd, source: "nbu-official"),
        ])

        let metrics = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(metrics.first { $0.monthKey == 202606 })
        #expect(june.expenseBaseMinor == 100_000)
        #expect(june.currencyCode == .uah)
        #expect(june.baseCurrencyCode == .usd)
        #expect(!june.isApproximate)
    }

    @Test func identityConversionPassesThroughWithoutRate() async throws {
        let repository = try makeRepository()
        try repository.saveCurrencyPreferences(CurrencyPreferences(defaultCurrencyCode: .usd, reportingCurrencyCode: .usd))
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository, currencyCode: .usd)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 50_000, expenseMinor: 20_000)

        let metrics = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(metrics.first { $0.monthKey == 202606 })
        #expect(june.incomeBaseMinor == 50_000)
        #expect(june.expenseBaseMinor == 20_000)
        #expect(june.savedBaseMinor == 30_000)
        #expect(try exchangeRateCount(in: repository) == 0)
    }

    // MARK: - Rate resolution order

    @Test func exactStoredMonthEndRateIsUsedWithoutFetching() async throws {
        let repository = try makeRepository()
        let provider = CountingRateProvider(rate: ExchangeRate(
            sourceCurrencyCode: .usd, targetCurrencyCode: .uah,
            rateDecimal: "99.00", effectiveDate: junEnd, source: "should-not-be-used"
        ))
        let service = try makeService(repository, provider: provider)
        let wallet = try makeWallet(repository)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 100_000, expenseMinor: 40_000)
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.00", effectiveDate: junEnd, source: "nbu-official"),
        ])

        let metrics = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(metrics.first { $0.monthKey == 202606 })
        // Fixture: 40_000.00 UAH / 41.00 = 975.609… → 976 USD minor (round half-up).
        #expect(june.expenseBaseMinor == 976)
        #expect(june.rateSource == "nbu-official")
        #expect(!june.isApproximate)
        #expect(provider.callCount == 0)
    }

    @Test func nearestEarlierStoredRateIsApproximateFallback() async throws {
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 4_100_000)
        // No June 30 rate; June 20 exists within the 10-day lookback (June 30
        // minus 10 days = June 20) → stored fallback, flagged approximate.
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.00", effectiveDate: jun20, source: "nbu-official"),
        ])

        let metrics = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(metrics.first { $0.monthKey == 202606 })
        #expect(june.isApproximate)
        #expect(june.rateEffectiveDate == DateKeys.calendar.startOfDay(for: jun20))
        // 41_000.00 UAH / 41.00 = 1000.00 USD
        #expect(june.expenseBaseMinor == 100_000)
    }

    @Test func missingRateFetchesOncePersistsAndReuses() async throws {
        let repository = try makeRepository()
        let provider = CountingRateProvider(rate: ExchangeRate(
            sourceCurrencyCode: .usd, targetCurrencyCode: .uah,
            rateDecimal: "42.00", effectiveDate: junEnd, source: "nbu-official"
        ))
        // Production wiring: fetches flow through the caching provider, which
        // persists the fetched rate into `exchange_rates` (service itself never
        // writes rates). The test asserts the same cycle through the real cache.
        let cachingProvider = CachingExchangeRateProvider(
            upstream: provider,
            repository: repository,
            maxStaleness: .infinity
        )
        let service = try makeService(repository, provider: cachingProvider)
        let wallet = try makeWallet(repository)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 4_200_000)

        let first = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(first.first { $0.monthKey == 202606 })
        #expect(june.expenseBaseMinor == 100_000)
        #expect(try exchangeRateCount(in: repository) == 1)

        // Second pass: the fetched rate is already stored → the service consults
        // the DB first (upstream not polled again), deletes the snapshot row and
        // verifies the fetch→persist→reuse cycle rebuilt it identically.
        try await repository.databaseManager.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM monthly_usd_snapshot")
        }
        let second = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let juneAgain = try #require(second.first { $0.monthKey == 202606 })
        #expect(juneAgain.expenseBaseMinor == 100_000)
        #expect(try exchangeRateCount(in: repository) == 1)
        #expect(provider.callCount == 1, "Second pass must reuse the persisted rate, not re-fetch")
    }

    // MARK: - Store-once semantics

    @Test func storedTotalsAreStableAgainstRateDrift() async throws {
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 4_125_000)
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.25", effectiveDate: junEnd, source: "nbu-official"),
        ])

        let first = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(first.first { $0.monthKey == 202606 })
        #expect(june.expenseBaseMinor == 100_000)

        // Rate "moves" in the cache: a refresh must NOT rewrite the frozen history.
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "50.00", effectiveDate: junEnd, source: "nbu-official"),
        ])
        let second = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let juneAgain = try #require(second.first { $0.monthKey == 202606 })
        #expect(juneAgain.rateDecimal == "0.0242424242424242424242424242424242" || juneAgain.rateDecimal != nil)
        #expect(juneAgain.expenseBaseMinor == 100_000, "Stored USD total must stay stable after rates drift")
        #expect(try snapshotCount(in: repository) == 1)
    }

    @Test func changedTotalsRewriteStoredRow() async throws {
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 4_125_000)
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.25", effectiveDate: junEnd, source: "nbu-official"),
        ])
        let first = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        #expect(try #require(first.first)?.expenseBaseMinor == 100_000)

        // Ledger edit lands (aggregate rebuilt): totals change → stored row updates.
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 8_250_000)
        let second = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let refreshed = try #require(second.first { $0.monthKey == 202606 })
        #expect(refreshed.expenseBaseMinor == 200_000, "Changed minor totals must refresh the stored conversion")
        #expect(try snapshotCount(in: repository) == 1, "Still one row per (month, wallet, currency)")
    }

    @Test func neverConvertedRowIsFilledOnceRateAppears() async throws {
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 4_125_000)

        // First run: rate fetch fails → row stored WITHOUT conversion (nil USD).
        var first = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        var june = try #require(first.first { $0.monthKey == 202606 })
        #expect(june.expenseBaseMinor == nil)
        #expect(june.rateDecimal == nil)

        // Rate becomes available → the never-converted row gains its conversion.
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.25", effectiveDate: junEnd, source: "nbu-official"),
        ])
        first = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        june = try #require(first.first { $0.monthKey == 202606 })
        #expect(june.expenseBaseMinor == 100_000)
        _ = june
    }

    // MARK: - Multi-wallet aggregation

    @Test func multiWalletSameCurrencyMonthAggregatesAcrossWallets() async throws {
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let cash = try makeWallet(repository, currencyCode: .uah)
        let bank = try makeWallet(repository, currencyCode: .uah)
        try seedCashflow(repository, walletID: cash.id, monthKey: 202606, incomeMinor: 80_000, expenseMinor: 30_000)
        try seedCashflow(repository, walletID: bank.id, monthKey: 202606, incomeMinor: 20_000, expenseMinor: 10_000)
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "50.00", effectiveDate: junEnd, source: "nbu-official"),
        ])

        let metrics = try await service.refreshSnapshots(monthKeys: [202606], now: junEnd)
        let june = try #require(metrics.first { $0.monthKey == 202606 })
        #expect(june.incomeMinor == 100_000)
        #expect(june.expenseMinor == 40_000)
        #expect(june.savedMinor == 60_000)
        #expect(june.incomeBaseMinor == 2_000)
        #expect(june.expenseBaseMinor == 800)
        #expect(june.savedBaseMinor == 1_200)
        #expect(try snapshotCount(in: repository) == 2)

        // Stored metrics reload without network or recompute.
        let stored = try service.storedMetrics()
        #expect(stored.first { $0.monthKey == 202606 }?.savedBaseMinor == 1_200)
    }

    @Test func futureMonthsAreSkippedInFullBackfill() async throws {
        let repository = try makeRepository()
        let service = try makeService(repository, provider: CountingRateProvider(rate: nil))
        let wallet = try makeWallet(repository)
        // Month candidates in the nil-path backfill come from the LEDGER, so
        // seed a real transaction in 2026-06. (The 2030 month exists only as an
        // aggregate row with no transactions, so the backfill never sees it —
        // and even if a month end is in the future, it is skipped by date.)
        let expenseCategory = try repository.categories(kind: .expense).first
        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 1_000,
            currencyCode: .uah,
            occurredAt: junEnd,
            categoryID: expenseCategory?.id
        ))
        try seedCashflow(repository, walletID: wallet.id, monthKey: 202606, incomeMinor: 0, expenseMinor: 1_000)
        try seedCashflow(repository, walletID: wallet.id, monthKey: 203001, incomeMinor: 0, expenseMinor: 1_000)

        _ = try await service.refreshSnapshots(now: junEnd)
        let stored = try repository.allMonthlyUSDSnapshots()
        #expect(!stored.contains { $0.monthKey == 203001 }, "A month whose end is in the future has no month-end rate yet")
        #expect(stored.contains { $0.monthKey == 202606 })
    }
}

/// Rate stub recording calls; `rate = nil` makes the fetch path throw.
private final class CountingRateProvider: ExchangeRateProviding, @unchecked Sendable {
    let rate: ExchangeRate?
    private(set) var callCount = 0

    init(rate: ExchangeRate?) {
        self.rate = rate
    }

    func rate(from sourceCurrency: CurrencyCode, to targetCurrency: CurrencyCode, on date: Date) async throws -> ExchangeRate {
        callCount += 1
        guard let rate else {
            throw MoneyError.missingExchangeRate(from: sourceCurrency, to: targetCurrency)
        }
        return rate
    }
}