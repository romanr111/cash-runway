import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct UtilityAndModelTests {
    // MARK: - MoneyFormatter

    @Test func moneyParsingRejectsOverflow() throws {
        #expect(throws: MoneyError.self) {
            try MoneyFormatter.parseMinorUnits("99999999999999999999999999999.99")
        }
    }

    @Test func moneyParsingRejectsInvalidInput() throws {
        #expect(throws: MoneyError.invalidAmount("abc")) {
            try MoneyFormatter.parseMinorUnits("abc")
        }
        #expect(throws: MoneyError.invalidAmount("")) {
            try MoneyFormatter.parseMinorUnits("")
        }
    }

    @Test func moneyParsingHandlesNormalValues() throws {
        #expect(try MoneyFormatter.parseMinorUnits("123,45") == 12_345)
        #expect(try MoneyFormatter.parseMinorUnits("-99.30") == -9_930)
        #expect(try MoneyFormatter.parseMinorUnits("0") == 0)
        #expect(try MoneyFormatter.parseMinorUnits("0.01") == 1)
    }

    @Test func moneyStringFormatting() {
        let result = MoneyFormatter.string(from: 12_345)
        #expect(result.contains("123"))
        #expect(result.contains("45"))
    }

    @Test func moneyPlainStringHandlesNormalValues() {
        #expect(MoneyFormatter.plainString(from: 12_345) == "123.45")
        #expect(MoneyFormatter.plainString(from: -9_930) == "-99.30")
        #expect(MoneyFormatter.plainString(from: 0) == "0.00")
        #expect(MoneyFormatter.plainString(from: 5) == "0.05")
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

    @Test func periodLabelForYear() {
        #expect(DateKeys.periodLabel(periodKey: 2025, period: .year) == "2025")
    }

    @Test func startOfMonthEdgeCase() {
        let date = DateKeys.startOfMonth(for: 202501)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 1)
    }

    // MARK: - Models

    @Test func transactionKindWalletDeltaSign() {
        #expect(TransactionKind.expense.walletDeltaSign == -1)
        #expect(TransactionKind.transferOut.walletDeltaSign == -1)
        #expect(TransactionKind.income.walletDeltaSign == 1)
        #expect(TransactionKind.transferIn.walletDeltaSign == 1)
    }

    @Test func transactionKindAffectsCategorySpend() {
        #expect(TransactionKind.expense.affectsCategorySpend == true)
        #expect(TransactionKind.income.affectsCategorySpend == false)
        #expect(TransactionKind.transferOut.affectsCategorySpend == false)
        #expect(TransactionKind.transferIn.affectsCategorySpend == false)
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
