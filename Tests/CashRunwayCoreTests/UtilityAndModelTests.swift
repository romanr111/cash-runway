import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct UtilityAndModelTests {
    // MARK: - MoneyFormatter

    @Test(arguments: [
        ("123,45", 12_345),
        ("-99.30", -9_930),
        ("0", 0),
        ("0.01", 1),
        ("999999.99", 99_999_999),
        ("1", 100),
        ("-1", -100),
        ("123.45", 12_345),
        ("0.00", 0),
    ])
    func parseMinorUnitsValid(input: String, expected: Int64) throws {
        #expect(try MoneyFormatter.parseMinorUnits(input) == expected)
    }

    @Test(arguments: [
        ("99999999999999999999999999999.99", MoneyError.self),
        ("abc", MoneyError.self),
        ("", MoneyError.self),
    ])
    func parseMinorUnitsInvalid(input: String, errorType: MoneyError.Type) {
        #expect(throws: errorType) {
            try MoneyFormatter.parseMinorUnits(input)
        }
    }

    @Test(arguments: [
        (12_345, "123.45"),
        (-9_930, "-99.30"),
        (0, "0.00"),
        (5, "0.05"),
        (100, "1.00"),
        (-1, "-0.01"),
    ])
    func plainStringFormatting(value: Int64, expected: String) {
        #expect(MoneyFormatter.plainString(from: value) == expected)
    }

    @Test func moneyStringFormatting() {
        let result = MoneyFormatter.string(from: 12_345)
        #expect(result.contains("123"))
        #expect(result.contains("45"))
    }

    @Test func moneyPlainStringHandlesInt64Min() {
        let result = MoneyFormatter.plainString(from: Int64.min)
        #expect(result.hasPrefix("-"))
    }

    @Test func moneyErrorDescription() {
        let error = MoneyError.invalidAmount("bad")
        #expect(error.localizedDescription.contains("bad"))
    }

    // MARK: - DateKeys

    @Test func weekKeyAndStartOfWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 4, day: 7))!
        let weekKey = DateKeys.weekKey(for: date)
        #expect(weekKey > 0)

        let start = DateKeys.startOfWeek(for: weekKey)
        #expect(start <= date)
    }

    @Test func weekDateRange() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 4, day: 7))!
        let weekKey = DateKeys.weekKey(for: date)
        let range = DateKeys.weekDateRange(for: weekKey)
        let days = calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0
        #expect(days == 6)
    }

    @Test func dayLabelFormatting() {
        let label = DateKeys.dayLabel(for: 20250407)
        #expect(!label.isEmpty)
    }

    @Test(arguments: [
        (2025, TimelinePeriod.year, "2025"),
        (202501, TimelinePeriod.month, "January 2025"),
        (202512, TimelinePeriod.month, "December 2025"),
    ])
    func periodLabel(periodKey: Int, period: TimelinePeriod, expected: String) {
        #expect(DateKeys.periodLabel(periodKey: periodKey, period: period) == expected)
    }

    @Test func startOfMonthEdgeCase() {
        let date = DateKeys.startOfMonth(for: 202501)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 1)
    }

    @Test(arguments: [
        (2024, 2, 29),  // leap year
        (2023, 2, 28),  // non-leap year
        (2024, 12, 31), // year end
        (2024, 1, 1),   // year start
    ])
    func startOfMonthForVariousDates(year: Int, month: Int, day: Int) {
        let monthKey = year * 100 + month
        let date = DateKeys.startOfMonth(for: monthKey)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(components.year == year)
        #expect(components.month == month)
        #expect(components.day == 1)
    }

    // MARK: - Models

    @Test(arguments: [
        (TransactionKind.expense, -1),
        (TransactionKind.transferOut, -1),
        (TransactionKind.income, 1),
        (TransactionKind.transferIn, 1),
    ])
    func transactionKindWalletDeltaSign(kind: TransactionKind, expected: Int) {
        #expect(kind.walletDeltaSign == expected)
    }

    @Test(arguments: [
        (TransactionKind.expense, true),
        (TransactionKind.income, false),
        (TransactionKind.transferOut, false),
        (TransactionKind.transferIn, false),
    ])
    func transactionKindAffectsCategorySpend(kind: TransactionKind, expected: Bool) {
        #expect(kind.affectsCategorySpend == expected)
    }

    @Test func timelinePeriodDisplayName() {
        #expect(TimelinePeriod.month.displayName == "By months")
        #expect(TimelinePeriod.year.displayName == "By years")
    }

    @Test func timelineReloadStateKeepsLoadingUntilLatestReloadFinishes() {
        var state = TimelineReloadState()

        let firstReload = state.beginReload()
        let secondReload = state.beginReload()

        #expect(state.isLoading)
        #expect(!state.canApply(reloadID: firstReload))

        state.finishReload(reloadID: firstReload)
        #expect(state.isLoading)

        #expect(state.canApply(reloadID: secondReload))
        state.finishReload(reloadID: secondReload)
        #expect(!state.isLoading)
    }

    @Test func transactionListItemDisplayTitle() {
        let item1 = TransactionListItem(
            id: UUID(), walletName: "W", amountMinor: 100, occurredAt: .now,
            categoryName: "Food", categoryColorHex: nil, categoryIconName: nil,
            merchant: "Store", note: "", kind: .expense, source: .manual, labels: [], dayKey: 0
        )
        #expect(item1.displayTitle == "Food")

        let item2 = TransactionListItem(
            id: UUID(), walletName: "W", amountMinor: 100, occurredAt: .now,
            categoryName: "  ", categoryColorHex: nil, categoryIconName: nil,
            merchant: "Store", note: "", kind: .expense, source: .manual, labels: [], dayKey: 0
        )
        #expect(item2.displayTitle == "Store")

        let item3 = TransactionListItem(
            id: UUID(), walletName: "W", amountMinor: 100, occurredAt: .now,
            categoryName: nil, categoryColorHex: nil, categoryIconName: nil,
            merchant: "", note: "", kind: .income, source: .manual, labels: [], dayKey: 0
        )
        #expect(item3.displayTitle == "Income")
    }

    @Test func cashRunwayErrorDescriptions() {
        #expect(CashRunwayError.validation("bad").localizedDescription == "bad")
        #expect(CashRunwayError.notFound.localizedDescription.contains("not found"))
        #expect(CashRunwayError.invalidState("x").localizedDescription == "x")
    }
}
