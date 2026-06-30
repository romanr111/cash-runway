import Foundation
import Testing
@testable import CashRunwayCore

struct CurrencyFoundationTests {
    @Test func currencyPreferencesDefaultToUAH() {
        let preferences = CurrencyPreferences.default

        #expect(preferences.defaultCurrencyCode == .uah)
        #expect(preferences.reportingCurrencyCode == .uah)
    }

    @Test func moneyAmountAddsSameCurrency() throws {
        let left = MoneyAmount(minorUnits: 1_500, currencyCode: .uah)
        let right = MoneyAmount(minorUnits: 2_500, currencyCode: .uah)

        let result = try left.adding(right)

        #expect(result == MoneyAmount(minorUnits: 4_000, currencyCode: .uah))
    }

    @Test func moneyAmountRejectsMixedCurrencyAddition() {
        let left = MoneyAmount(minorUnits: 1_500, currencyCode: .uah)
        let right = MoneyAmount(minorUnits: 2_500, currencyCode: .usd)

        #expect(throws: MoneyError.currencyMismatch(lhs: .uah, rhs: .usd)) {
            try left.adding(right)
        }
    }

    @Test func noopCurrencyConverterReturnsSameCurrencyAmount() async throws {
        let converter = NoopCurrencyConverter()
        let amount = MoneyAmount(minorUnits: 1_500, currencyCode: .uah)

        let result = try await converter.convert(
            amount,
            to: .uah,
            on: Date(timeIntervalSince1970: 1_800_000_000),
            policy: .noConversion
        )

        #expect(result == amount)
    }

    @Test func noopCurrencyConverterThrowsForCrossCurrencyConversion() async {
        let converter = NoopCurrencyConverter()
        let amount = MoneyAmount(minorUnits: 1_500, currencyCode: .uah)

        await #expect(throws: MoneyError.missingExchangeRate(from: .uah, to: .usd)) {
            try await converter.convert(
                amount,
                to: .usd,
                on: Date(timeIntervalSince1970: 1_800_000_000),
                policy: .latestAvailable
            )
        }
    }

    @Test func legacyBackupEntitiesDefaultMissingCurrencyCodeToUAH() throws {
        let decoder = JSONDecoder()
        let wallet = try decoder.decode(BackupWallet.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy Wallet",
          "kind": "cash",
          "colorHex": null,
          "iconName": null,
          "startingBalanceMinor": 0,
          "currentBalanceMinor": 0,
          "isArchived": false,
          "sortOrder": 0,
          "createdAt": 1800000000,
          "updatedAt": 1800000000
        }
        """.utf8))
        let transaction = try decoder.decode(BackupTransaction.self, from: Data("""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "walletID": "11111111-1111-1111-1111-111111111111",
          "type": "expense",
          "linkedTransferID": null,
          "amountMinor": 1234,
          "occurredAt": 1800000000,
          "localDayKey": 20270115,
          "localMonthKey": 202701,
          "categoryID": null,
          "merchant": "Legacy",
          "note": null,
          "isDeleted": false,
          "source": "manual",
          "recurringTemplateID": null,
          "recurringInstanceID": null,
          "importJobID": null,
          "importFingerprint": null,
          "createdAt": 1800000000,
          "updatedAt": 1800000000
        }
        """.utf8))
        let template = try decoder.decode(BackupRecurringTemplate.self, from: Data("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "kind": "expense",
          "walletID": "11111111-1111-1111-1111-111111111111",
          "counterpartyWalletID": null,
          "amountMinor": 1234,
          "categoryID": null,
          "merchant": "Legacy",
          "note": null,
          "ruleType": "monthly",
          "ruleInterval": 1,
          "dayOfMonth": 1,
          "weekday": null,
          "startDate": 1800000000,
          "endDate": null,
          "isActive": true,
          "createdAt": 1800000000,
          "updatedAt": 1800000000
        }
        """.utf8))

        #expect(wallet.currencyCode == .uah)
        #expect(transaction.currencyCode == .uah)
        #expect(template.currencyCode == .uah)
    }

    @Test func repositoryPersistsCurrencyPreferences() throws {
        let repository = try makeCurrencyRepository()

        #expect(try repository.currencyPreferences() == .default)

        let preferences = CurrencyPreferences(defaultCurrencyCode: .usd, reportingCurrencyCode: .eur)
        try repository.saveCurrencyPreferences(preferences)

        #expect(try repository.currencyPreferences() == preferences)
    }

    @Test func repositoryCachesExchangeRatesByEffectiveDay() throws {
        let repository = try makeCurrencyRepository()
        let noon = try #require(DateKeys.calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 30,
            hour: 12,
            minute: 30
        )))
        let sameDayEvening = try #require(DateKeys.calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 30,
            hour: 18,
            minute: 45
        )))
        let nextDay = try #require(DateKeys.calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 1,
            hour: 9
        )))

        try repository.saveExchangeRates([
            ExchangeRate(
                sourceCurrencyCode: .usd,
                targetCurrencyCode: .uah,
                rateDecimal: "41.2500",
                effectiveDate: noon,
                source: "test"
            ),
        ])

        let cached = try #require(try repository.cachedExchangeRate(from: .usd, to: .uah, on: sameDayEvening))
        #expect(cached.sourceCurrencyCode == .usd)
        #expect(cached.targetCurrencyCode == .uah)
        #expect(cached.rateDecimal == "41.2500")
        #expect(cached.effectiveDate == DateKeys.calendar.startOfDay(for: noon))
        #expect(cached.source == "test")

        #expect(try repository.cachedExchangeRate(from: .usd, to: .uah, on: nextDay) == nil)
        #expect(try repository.cachedExchangeRate(from: .uah, to: .usd, on: sameDayEvening) == nil)
    }

    private func makeCurrencyRepository() throws -> CashRunwayRepository {
        let location = TestSupport.makeLocation()
        return CashRunwayRepository(
            databaseManager: try DatabaseManager(locationProvider: location, keychain: TestKeychainStore())
        )
    }
}
