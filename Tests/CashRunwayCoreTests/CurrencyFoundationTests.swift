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

    @Test func currencyCodeCodableUsesValidatedSingleStringValue() throws {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CurrencyCode.self, from: Data(#"" usd ""#.utf8))
        #expect(decoded == .usd)

        let encoded = try JSONEncoder().encode(CurrencyCode.eur)
        #expect(String(decoding: encoded, as: UTF8.self) == #""EUR""#)

        #expect(CurrencyCode(rawValue: " usd ") == .usd)
        #expect(CurrencyCode(rawValue: "US1") == nil)
        #expect(CurrencyCode(rawValue: "USDT") == nil)
        #expect(throws: MoneyError.self) {
            _ = try CurrencyCode(validating: "US1")
        }

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(CurrencyCode.self, from: Data(#""US1""#.utf8))
        }
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(CurrencyCode.self, from: Data(#""USDT""#.utf8))
        }
    }

    @Test func repositoryRejectsTransactionCurrencyMismatch() throws {
        let repository = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(repository, currencyCode: .usd)
        let category = try saveExpenseCategory(repository)
        #expect(try repository.canChangeWalletCurrency(id: wallet.id))
        #expect(try repository.canChangeWalletCurrency(id: wallet.id))

        #expect(throws: CashRunwayError.self) {
            try repository.saveTransaction(TransactionDraft(
                kind: .expense,
                walletID: wallet.id,
                amountMinor: 1_000,
                currencyCode: .uah,
                occurredAt: .now,
                categoryID: category.id
            ))
        }
    }

    @Test func repositoryAcceptsTransactionMatchingWalletCurrency() throws {
        let repository = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(repository, currencyCode: .usd)
        let category = try saveExpenseCategory(repository)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 1_000,
            currencyCode: .usd,
            occurredAt: .now,
            categoryID: category.id
        ))

        let transaction = try #require(try repository.exportFullBackup().transactions.first)
        #expect(transaction.currencyCode == .usd)
    }

    @Test func repositoryRejectsTransferBetweenDifferentWalletCurrencies() throws {
        let repository = try makeCurrencyRepository()
        let source = try saveCurrencyWallet(repository, currencyCode: .uah)
        let destination = try saveCurrencyWallet(repository, currencyCode: .usd)

        #expect(throws: CashRunwayError.self) {
            try repository.saveTransaction(TransactionDraft(
                kind: .transfer,
                walletID: source.id,
                destinationWalletID: destination.id,
                amountMinor: 1_000,
                currencyCode: .uah,
                occurredAt: .now
            ))
        }
    }

    @Test func repositoryRejectsTransferDraftCurrencyMismatch() throws {
        let repository = try makeCurrencyRepository()
        let source = try saveCurrencyWallet(repository, currencyCode: .usd)
        let destination = try saveCurrencyWallet(repository, currencyCode: .usd)

        #expect(throws: CashRunwayError.self) {
            try repository.saveTransaction(TransactionDraft(
                kind: .transfer,
                walletID: source.id,
                destinationWalletID: destination.id,
                amountMinor: 1_000,
                currencyCode: .uah,
                occurredAt: .now
            ))
        }
    }

    @Test func repositoryRejectsRecurringTemplateCurrencyMismatch() throws {
        let repository = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(repository, currencyCode: .usd)
        let category = try saveExpenseCategory(repository)

        #expect(throws: CashRunwayError.self) {
            try repository.saveRecurringTemplate(RecurringTemplate(
                id: UUID(),
                kind: .expense,
                walletID: wallet.id,
                counterpartyWalletID: nil,
                amountMinor: 1_000,
                currencyCode: .uah,
                categoryID: category.id,
                merchant: "Rent",
                note: nil,
                ruleType: .monthly,
                ruleInterval: 1,
                dayOfMonth: 1,
                weekday: nil,
                startDate: .now,
                endDate: nil,
                isActive: true,
                createdAt: .now,
                updatedAt: .now
            ))
        }
    }

    @Test func repositoryRejectsWalletCurrencyChangeAfterTransactionsExist() throws {
        let repository = try makeCurrencyRepository()
        var wallet = try saveCurrencyWallet(repository, currencyCode: .uah)
        #expect(try repository.canChangeWalletCurrency(id: wallet.id))
        let category = try saveExpenseCategory(repository)
        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 1_000,
            currencyCode: .uah,
            occurredAt: .now,
            categoryID: category.id
        ))

        wallet.currencyCode = .usd
        #expect(!(try repository.canChangeWalletCurrency(id: wallet.id)))
        #expect(!(try repository.canChangeWalletCurrency(id: wallet.id)))

        #expect(throws: CashRunwayError.self) {
            try repository.saveWallet(wallet)
        }
    }

    @Test func repositoryRejectsWalletCurrencyChangeAfterBankAccountMappingExists() throws {
        let repository = try makeCurrencyRepository()
        var wallet = try saveCurrencyWallet(repository, currencyCode: .uah)
        let integrationID = UUID()
        try repository.saveBankConnection(
            integration: BankIntegration(
                id: integrationID,
                provider: .monobank,
                displayName: "Monobank",
                status: .active,
                syncStartAt: .now,
                tokenKeychainAccount: "token",
                lastClientInfoSyncAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                createdAt: .now,
                updatedAt: .now
            ),
            accounts: [
                BankAccount(
                    id: UUID(),
                    integrationID: integrationID,
                    provider: .monobank,
                    providerAccountID: "acc-1",
                    walletID: wallet.id,
                    displayName: "Black",
                    accountType: "black",
                    currencyCode: 980,
                    maskedPAN: "1234",
                    iban: nil,
                    isEnabled: true,
                    syncStartAt: .now,
                    lastSuccessfulSyncAt: nil,
                    lastStatementItemTime: nil,
                    createdAt: .now,
                    updatedAt: .now
                ),
            ]
        )

        wallet.currencyCode = .usd

        #expect(throws: CashRunwayError.self) {
            try repository.saveWallet(wallet)
        }
    }

    @Test func mixedCurrencyAllWalletSnapshotsAreRejected() throws {
        let repository = try makeCurrencyRepository()
        let uahWallet = try saveCurrencyWallet(repository, currencyCode: .uah)
        _ = try saveCurrencyWallet(repository, currencyCode: .usd)
        let monthKey = DateKeys.monthKey(for: .now)

        #expect(throws: CashRunwayError.self) {
            _ = try repository.dashboard(monthKey: monthKey, walletID: nil)
        }
        #expect(throws: CashRunwayError.self) {
            _ = try repository.overviewSnapshot(monthKey: monthKey, walletID: nil)
        }
        #expect(throws: CashRunwayError.self) {
            _ = try repository.timelineSnapshot(monthKey: monthKey, walletID: nil)
        }
        #expect(throws: CashRunwayError.self) {
            _ = try repository.allBars(walletID: nil)
        }

        _ = try repository.dashboard(monthKey: monthKey, walletID: uahWallet.id)
        _ = try repository.overviewSnapshot(monthKey: monthKey, walletID: uahWallet.id)
        _ = try repository.timelineSnapshot(monthKey: monthKey, walletID: uahWallet.id)
        _ = try repository.allBars(walletID: uahWallet.id)
    }

    @Test func archivedMixedCurrencyWalletDoesNotBlockActiveAllWalletSnapshots() throws {
        let repository = try makeCurrencyRepository()
        _ = try saveCurrencyWallet(repository, currencyCode: .uah)
        _ = try saveCurrencyWallet(repository, currencyCode: .usd, isArchived: true)
        let monthKey = DateKeys.monthKey(for: .now)

        #expect(throws: Never.self) {
            _ = try repository.dashboard(monthKey: monthKey, walletID: nil)
        }
    }

    @Test func archivedOnlyMixedCurrencyWalletsDoNotBlockAllWalletSnapshots() throws {
        let repository = try makeCurrencyRepository()
        _ = try saveCurrencyWallet(repository, currencyCode: .uah, isArchived: true)
        _ = try saveCurrencyWallet(repository, currencyCode: .usd, isArchived: true)
        let monthKey = DateKeys.monthKey(for: .now)

        #expect(throws: Never.self) {
            _ = try repository.dashboard(monthKey: monthKey, walletID: nil)
        }
        #expect(throws: Never.self) {
            _ = try repository.overviewSnapshot(monthKey: monthKey, walletID: nil)
        }
        #expect(throws: Never.self) {
            _ = try repository.timelineSnapshot(monthKey: monthKey, walletID: nil)
        }
        #expect(throws: Never.self) {
            _ = try repository.allBars(walletID: nil)
        }
    }

    @Test func aggregateCurrencyCodeRespectsSelectedWallet() {
        let uahWallet = Wallet(
            id: UUID(),
            name: "UAH",
            kind: .cash,
            colorHex: nil,
            iconName: nil,
            startingBalanceMinor: 0,
            currentBalanceMinor: 0,
            currencyCode: .uah,
            isArchived: false,
            sortOrder: 0,
            createdAt: .now,
            updatedAt: .now
        )
        let usdWallet = Wallet(
            id: UUID(),
            name: "USD",
            kind: .cash,
            colorHex: nil,
            iconName: nil,
            startingBalanceMinor: 0,
            currentBalanceMinor: 0,
            currencyCode: .usd,
            isArchived: false,
            sortOrder: 1,
            createdAt: .now,
            updatedAt: .now
        )

        #expect([uahWallet, usdWallet].aggregateCurrencyCode(selectedWalletID: uahWallet.id) == .uah)
        #expect([uahWallet, usdWallet].aggregateCurrencyCode(selectedWalletID: usdWallet.id) == .usd)
        #expect([uahWallet, usdWallet].aggregateCurrencyCode(selectedWalletID: nil) == nil)
    }

    @Test func repositoryUsesFreshWalletsForAggregateNormalization() throws {
        let repository = try makeCurrencyRepository()
        _ = try saveCurrencyWallet(repository, currencyCode: .uah)
        let staleWallets = try repository.wallets()
        _ = try saveCurrencyWallet(repository, currencyCode: .usd)

        #expect(staleWallets.aggregateCurrencyCode(selectedWalletID: nil) == .uah)

        let effectiveWalletID = try repository.normalizedWalletIDForAggregates(selectedWalletID: nil)
        #expect(effectiveWalletID != nil)

        let monthKey = DateKeys.monthKey(for: .now)
        #expect(throws: Never.self) {
            _ = try repository.dashboard(monthKey: monthKey, walletID: effectiveWalletID)
        }
        #expect(throws: Never.self) {
            _ = try repository.timelineSnapshot(monthKey: monthKey, walletID: effectiveWalletID, query: .init(), period: .month)
        }
        #expect(throws: Never.self) {
            _ = try repository.allBars(walletID: effectiveWalletID, period: .month)
        }
    }

    @Test func backupExportUsesV3AndStringCurrencyCodes() throws {
        let repository = try makeCurrencyRepository()
        _ = try saveCurrencyWallet(repository, currencyCode: .usd)
        let data = try JSONEncoder().encode(repository.exportFullBackup())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try #require(object["metadata"] as? [String: Any])
        let wallets = try #require(object["wallets"] as? [[String: Any]])
        let firstWallet = try #require(wallets.first)

        #expect(metadata["version"] as? Int == 3)
        #expect(firstWallet["currencyCode"] as? String == "USD")
    }

    @Test func backupExportRejectsInvalidStoredWalletCurrencyCodes() throws {
        let repository = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(repository, currencyCode: .usd)

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE wallets SET currency_code = ? WHERE id = ?",
                arguments: ["US1", wallet.id.uuidString]
            )
        }

        #expect(throws: MoneyError.self) { _ = try repository.wallets() }
        #expect(throws: MoneyError.self) { _ = try repository.exportFullBackup() }
    }

    @Test func backupExportRejectsInvalidStoredTransactionCurrencyCodes() throws {
        let repository = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(repository, currencyCode: .usd)
        let category = try saveExpenseCategory(repository)

        try repository.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 1_000,
            currencyCode: .usd,
            occurredAt: .now,
            categoryID: category.id
        ))

        let transactionID = try #require(try repository.exportFullBackup().transactions.first).id

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET currency_code = ? WHERE id = ?",
                arguments: ["US1", transactionID.uuidString]
            )
        }

        #expect(throws: MoneyError.self) { _ = try repository.transactionDraft(id: transactionID) }
        #expect(throws: MoneyError.self) { _ = try repository.exportFullBackup() }
    }

    @Test func backupExportRejectsInvalidCurrencyPreferences() throws {
        let repository = try makeCurrencyRepository()

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE currency_preferences SET default_currency_code = ?, reporting_currency_code = ? WHERE id = 'default'",
                arguments: ["US1", "USD"]
            )
        }

        #expect(throws: MoneyError.self) { _ = try repository.exportFullBackup() }
    }

@Test func backupV3RestoresCurrencyPreferencesAndEntityCurrencyCodes() throws {
        let source = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(source, currencyCode: .usd)
        let category = try saveExpenseCategory(source)
        try source.saveCurrencyPreferences(CurrencyPreferences(defaultCurrencyCode: .usd, reportingCurrencyCode: .eur))
        try source.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 1_000,
            currencyCode: .usd,
            occurredAt: .now,
            categoryID: category.id
        ))
        try source.saveRecurringTemplate(RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: wallet.id,
            counterpartyWalletID: nil,
            amountMinor: 2_000,
            currencyCode: .usd,
            categoryID: category.id,
            merchant: "Subscription",
            note: nil,
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 1,
            weekday: nil,
            startDate: .now,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        ))

        let backup = try source.exportFullBackup()
        let target = try makeCurrencyRepository()
        _ = try BackupService(repository: target).restore(backup)

        #expect(try target.currencyPreferences() == CurrencyPreferences(defaultCurrencyCode: .usd, reportingCurrencyCode: .eur))
        #expect(try target.wallets().first?.currencyCode == .usd)
        #expect(try target.exportFullBackup().transactions.first?.currencyCode == .usd)
        #expect(try target.recurringTemplates().first?.currencyCode == .usd)
    }

    @Test func backupRestoreRejectsTransactionCurrencyMismatch() throws {
        let source = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(source, currencyCode: .usd)
        let category = try saveExpenseCategory(source)
        try source.saveTransaction(TransactionDraft(
            kind: .expense,
            walletID: wallet.id,
            amountMinor: 1_000,
            currencyCode: .usd,
            occurredAt: .now,
            categoryID: category.id
        ))

        var backup = try source.exportFullBackup()
        backup.transactions[0].currencyCode = .uah
        let target = try makeCurrencyRepository()

        #expect(throws: BackupError.self) {
            _ = try BackupService(repository: target).restore(backup)
        }
    }

    @Test func backupRestoreRejectsRecurringCounterpartyCurrencyMismatch() throws {
        let source = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(source, currencyCode: .usd)
        let counterparty = try saveCurrencyWallet(source, currencyCode: .usd)
        try source.saveRecurringTemplate(RecurringTemplate(
            id: UUID(),
            kind: .transfer,
            walletID: wallet.id,
            counterpartyWalletID: counterparty.id,
            amountMinor: 2_000,
            currencyCode: .usd,
            categoryID: nil,
            merchant: "Savings",
            note: nil,
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 1,
            weekday: nil,
            startDate: .now,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        ))

        var backup = try source.exportFullBackup()
        let counterpartyIndex = try #require(backup.wallets.firstIndex { $0.id == counterparty.id })
        backup.wallets[counterpartyIndex].currencyCode = .eur
        let target = try makeCurrencyRepository()

        #expect(throws: BackupError.self) {
            _ = try BackupService(repository: target).restore(backup)
        }
    }

    @Test func monobankImportRejectsUAHAccountMappedToNonUAHWallet() throws {
        let repository = try makeCurrencyRepository()
        let wallet = try saveCurrencyWallet(repository, currencyCode: .usd)
        let integrationID = UUID()
        let account = BankAccount(
            id: UUID(),
            integrationID: integrationID,
            provider: .monobank,
            providerAccountID: "uah-account",
            walletID: wallet.id,
            displayName: "Black",
            accountType: "black",
            currencyCode: ISO4217NumericCurrencyCode.uah,
            maskedPAN: "1234",
            iban: nil,
            isEnabled: true,
            syncStartAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: .now,
            updatedAt: .now
        )
        let integration = BankIntegration(
            id: integrationID,
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: Date(timeIntervalSince1970: 1_800_000_000),
            tokenKeychainAccount: "token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveBankConnection(integration: integration, accounts: [account])

        let item = MonobankStatementItem(
            id: "uah-item",
            time: Int(Date(timeIntervalSince1970: 1_800_000_100).timeIntervalSince1970),
            description: "Shop",
            mcc: 5411,
            originalMcc: 5411,
            amount: -1_000,
            operationAmount: nil,
            currencyCode: ISO4217NumericCurrencyCode.uah,
            commissionRate: nil,
            cashbackAmount: nil,
            balance: nil,
            hold: nil,
            receiptId: nil,
            comment: nil,
            counterEdrpou: nil,
            counterIban: nil,
            counterName: "Shop"
        )

        #expect(throws: CashRunwayError.self) {
            _ = try repository.importMonobankExpenseItems([item], account: account, integration: integration)
        }
    }

    @Test func repositoryCachesExchangeRatesByRequestedSource() throws {
        let repository = try makeCurrencyRepository()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try repository.saveExchangeRates([
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "41.2500", effectiveDate: date, source: "nbu"),
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "40.9000", effectiveDate: date, source: "ecb"),
        ])

        let nbu = try #require(try repository.cachedExchangeRate(from: .usd, to: .uah, on: date, source: "nbu"))
        let ecb = try #require(try repository.cachedExchangeRate(from: .usd, to: .uah, on: date, source: "ecb"))

        #expect(nbu.rateDecimal == "41.2500")
        #expect(ecb.rateDecimal == "40.9000")
        #expect(try repository.cachedExchangeRate(from: .usd, to: .uah, on: date, source: "manual") == nil)
    }

    @Test func repositoryRejectsInvalidExchangeRateDecimalStrings() throws {
        let repository = try makeCurrencyRepository()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        for invalid in ["", "0", "-1", "41,2500", "abc", " 41.25 "] {
            #expect(throws: CashRunwayError.self) {
                try repository.saveExchangeRates([
                    ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: invalid, effectiveDate: date, source: "test"),
                ])
            }
        }
    }

    private func makeCurrencyRepository() throws -> CashRunwayRepository {
        let location = TestSupport.makeLocation()
        return CashRunwayRepository(
            databaseManager: try DatabaseManager(locationProvider: location, keychain: TestKeychainStore())
        )
    }

    @discardableResult
    private func saveCurrencyWallet(
        _ repository: CashRunwayRepository,
        currencyCode: CurrencyCode,
        startingBalanceMinor: Int64 = 0,
        currentBalanceMinor: Int64 = 0,
        isArchived: Bool = false
    ) throws -> Wallet {
        let wallet = Wallet(
            id: UUID(),
            name: "Wallet \(currencyCode.rawValue) \(UUID().uuidString.prefix(4))",
            kind: .cash,
            colorHex: nil,
            iconName: nil,
            startingBalanceMinor: startingBalanceMinor,
            currentBalanceMinor: currentBalanceMinor,
            currencyCode: currencyCode,
            isArchived: isArchived,
            sortOrder: 0,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWallet(wallet)
        return wallet
    }

    @discardableResult
    private func saveExpenseCategory(_ repository: CashRunwayRepository) throws -> CashRunwayCore.Category {
        let category = CashRunwayCore.Category(
            id: UUID(),
            name: "Category \(UUID().uuidString.prefix(4))",
            kind: .expense,
            iconName: nil,
            colorHex: nil,
            parentID: nil,
            isSystem: false,
            isArchived: false,
            sortOrder: 0,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveCategory(category)
        return category
    }
}
