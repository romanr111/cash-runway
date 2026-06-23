import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct RecurringCalendarBoundaryTests {

    @Test func monthlyRecurrenceDay31GeneratesOnAllMonths() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let wallet = wallets[0]
        let cats = try repository.categories(kind: .expense)
        let catID = try #require(cats.first?.id)

        var kyivCalendar = Calendar(identifier: .gregorian)
        kyivCalendar.locale = Locale(identifier: "uk_UA")
        kyivCalendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!

        let startDate = kyivCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: catID, merchant: "Day31Bill", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 31,
            weekday: nil, startDate: startDate, endDate: nil,
            isActive: true, createdAt: startDate, updatedAt: startDate
        )
        try repository.saveRecurringTemplate(template)

        let endOf2025 = kyivCalendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        let generatedDates = CashRunwayRepository.generatedDates(for: template, start: startDate, end: endOf2025, calendar: kyivCalendar)
        let monthsWith31 = [1, 3, 5, 7, 8, 10, 12]
        #expect(generatedDates.count == monthsWith31.count)
        for date in generatedDates {
            let components = kyivCalendar.dateComponents([.year, .month, .day], from: date)
            #expect(components.day == 31)
            #expect(monthsWith31.contains(components.month!))
        }
    }

    @Test func februaryNonLeapYearDoesNotExceed28() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let wallet = wallets[0]
        let cats = try repository.categories(kind: .expense)
        let catID = try #require(cats.first?.id)

        var kyivCalendar = Calendar(identifier: .gregorian)
        kyivCalendar.locale = Locale(identifier: "uk_UA")
        kyivCalendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!

        let startDate = kyivCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let febEnd = kyivCalendar.date(from: DateComponents(year: 2025, month: 3, day: 1))!

        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: catID, merchant: "Day30Bill", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 30,
            weekday: nil, startDate: startDate, endDate: nil,
            isActive: true, createdAt: startDate, updatedAt: startDate
        )
        try repository.saveRecurringTemplate(template)

        let generatedDates = CashRunwayRepository.generatedDates(for: template, start: startDate, end: febEnd, calendar: kyivCalendar)
        let febDates = generatedDates.filter { kyivCalendar.component(.month, from: $0) == 2 }
        #expect(febDates.count <= 1)
        if let febDate = febDates.first {
            let day = kyivCalendar.component(.day, from: febDate)
            #expect(day <= 28)
        }
    }

    @Test func februaryLeapYearHas29() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let wallet = wallets[0]
        let cats = try repository.categories(kind: .expense)
        let catID = try #require(cats.first?.id)

        var kyivCalendar = Calendar(identifier: .gregorian)
        kyivCalendar.locale = Locale(identifier: "uk_UA")
        kyivCalendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!

        let startDate = kyivCalendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let end = kyivCalendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!

        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: catID, merchant: "Day29Bill", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 29,
            weekday: nil, startDate: startDate, endDate: nil,
            isActive: true, createdAt: startDate, updatedAt: startDate
        )
        try repository.saveRecurringTemplate(template)

        let generatedDates = CashRunwayRepository.generatedDates(for: template, start: startDate, end: end, calendar: kyivCalendar)
        let febDates = generatedDates.filter { kyivCalendar.component(.month, from: $0) == 2 }
        #expect(febDates.count == 1)
        if let febDate = febDates.first {
            #expect(kyivCalendar.component(.day, from: febDate) == 29)
        }
    }

    @Test func transferPostFailureLeavesNoHalfTransfer() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let wallet = wallets[0]

        let template = RecurringTemplate(
            id: UUID(), kind: .transfer, walletID: wallet.id,
            counterpartyWalletID: wallet.id,
            amountMinor: 1_000,
            categoryID: nil, merchant: "SelfTransfer", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: nil, isActive: true, createdAt: .now, updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)
        try repository.refreshRecurringInstances()
        let instances = try repository.recurringInstances()
        let instance = try #require(instances.first)

        var thrownError: Error?
        do {
            try repository.postRecurringInstance(id: instance.id)
        } catch {
            thrownError = error
        }
        #expect(thrownError != nil)

        let transferOutCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type = 'transfer_out'") ?? 0
        }
        let transferInCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type = 'transfer_in'") ?? 0
        }
        #expect(transferOutCount == 0)
        #expect(transferInCount == 0)

        let instanceAfter = try repository.recurringInstances().first { $0.id == instance.id }
        #expect(instanceAfter?.status != .posted)
        #expect(instanceAfter?.linkedTransactionID == nil)
    }

    @Test func dstTransitionDoesNotDuplicateOrSkipInstances() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let wallet = wallets[0]
        let cats = try repository.categories(kind: .expense)
        let catID = try #require(cats.first?.id)

        var kyivCalendar = Calendar(identifier: .gregorian)
        kyivCalendar.locale = Locale(identifier: "uk_UA")
        kyivCalendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!

        let startDate = kyivCalendar.date(from: DateComponents(year: 2025, month: 2, day: 1))!
        let endDate = kyivCalendar.date(from: DateComponents(year: 2025, month: 5, day: 1))!

        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: catID, merchant: "DSTBill", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: startDate, endDate: nil,
            isActive: true, createdAt: startDate, updatedAt: startDate
        )
        try repository.saveRecurringTemplate(template)

        let generatedDates = CashRunwayRepository.generatedDates(for: template, start: startDate, end: endDate, calendar: kyivCalendar)
        #expect(generatedDates.count == 3)

        let months = generatedDates.map { kyivCalendar.component(.month, from: $0) }
        #expect(months == [2, 3, 4])

        for date in generatedDates {
            let day = kyivCalendar.component(.day, from: date)
            #expect(day == 15)
        }
    }

    @Test func repeatedRefreshDoesNotDuplicateInstances() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let wallet = wallets[0]
        let cats = try repository.categories(kind: .expense)
        let catID = try #require(cats.first?.id)

        let template = RecurringTemplate(
            id: UUID(), kind: .expense, walletID: wallet.id,
            counterpartyWalletID: nil, amountMinor: 1_000,
            categoryID: catID, merchant: "RepeatRefresh", note: nil,
            ruleType: .monthly, ruleInterval: 1, dayOfMonth: 15,
            weekday: nil, startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: nil, isActive: true, createdAt: .now, updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)

        try repository.refreshRecurringInstances()
        let countAfterFirst = try repository.recurringInstances().filter { $0.templateID == template.id }.count

        try repository.refreshRecurringInstances()
        try repository.refreshRecurringInstances()
        let countAfterThird = try repository.recurringInstances().filter { $0.templateID == template.id }.count

        #expect(countAfterFirst == countAfterThird)
    }
}