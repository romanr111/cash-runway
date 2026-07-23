import CashRunwayCore
import CashRunwayUIVM
import Foundation
import Testing

@Suite("TimelinePresentation")
struct TimelinePresentationTests {
    private let ukrainian = Locale(identifier: "uk_UA")
    private let english = Locale(identifier: "en_US")

    private func bar(periodKey: Int, incomeMinor: Int64, expenseMinor: Int64) -> TimelineBarPoint {
        TimelineBarPoint(
            periodKey: periodKey,
            incomeMinor: incomeMinor,
            expenseMinor: expenseMinor,
            xLabel: "\(periodKey)"
        )
    }

    private func comparison(
        direction: TimelineComparison.Direction,
        currentExpenseMinor: Int64,
        baselineExpenseMinor: Int64,
        percentageChange: Double?,
        baselineStartDayKey: Int,
        baselineEndDayKey: Int
    ) -> TimelineComparison {
        TimelineComparison(
            direction: direction,
            currentExpenseMinor: currentExpenseMinor,
            baselineExpenseMinor: baselineExpenseMinor,
            percentageChange: percentageChange,
            currentStartDayKey: 20260701,
            currentEndDayKey: 20260711,
            baselineStartDayKey: baselineStartDayKey,
            baselineEndDayKey: baselineEndDayKey,
            isPartialPeriod: true
        )
    }

    private func snapshot(
        anchorMonthKey: Int = 202607,
        period: TimelinePeriod = .month,
        heroCashFlowMinor: Int64,
        bars: [TimelineBarPoint],
        comparison: TimelineComparison? = nil
    ) -> TimelineSnapshot {
        TimelineSnapshot(
            anchorMonthKey: anchorMonthKey,
            walletFilterID: nil,
            heroCashFlowMinor: heroCashFlowMinor,
            bars: bars,
            sections: [],
            period: period,
            comparison: comparison
        )
    }

    // MARK: - Amount styling

    @Test("positive net uses positive style")
    func positiveNetStyle() {
        let snapshot = snapshot(heroCashFlowMinor: 1000, bars: [bar(periodKey: 202607, incomeMinor: 2000, expenseMinor: 1000)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.netStyle == .positive)
        #expect(presentation.netText.contains("₴"))
    }

    @Test("negative net uses negative style")
    func negativeNetStyle() {
        let snapshot = snapshot(heroCashFlowMinor: -79471, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 79471)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: ukrainian
        )

        #expect(presentation.netStyle == .negative)
        #expect(presentation.netText.hasPrefix("-") || presentation.netText.hasPrefix("−"))
    }

    @Test("zero net uses zero style")
    func zeroNetStyle() {
        let snapshot = snapshot(heroCashFlowMinor: 0, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 0)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.netStyle == .zero)
    }

    // MARK: - Selected bar overrides historical bar

    @Test("selected snapshot bar overrides matching historical allBars point")
    func selectedBarOverridesHistoricalPoint() {
        let historical = bar(periodKey: 202607, incomeMinor: 5000, expenseMinor: 3000)
        let snapshotBar = bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 79471)
        let snapshot = snapshot(heroCashFlowMinor: -79471, bars: [snapshotBar])

        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [historical],
            currencyCode: .uah,
            locale: english
        )

        let selected = presentation.chartPoints.first { $0.periodKey == 202607 }
        #expect(selected?.incomeMinor == 0)
        #expect(selected?.expenseMinor == 79471)
    }

    // MARK: - Income and expense signs

    @Test("income text shows positive magnitude")
    func incomeIsPositiveMagnitude() {
        let snapshot = snapshot(heroCashFlowMinor: 1000, bars: [bar(periodKey: 202607, incomeMinor: 12345, expenseMinor: 0)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(!presentation.incomeText.hasPrefix("-"))
        #expect(presentation.incomeText.contains("123.45"))
    }

    @Test("expense text shows negative sign")
    func expenseIsNegative() {
        let snapshot = snapshot(heroCashFlowMinor: -1000, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 12345)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.expenseText.hasPrefix("-") || presentation.expenseText.hasPrefix("−"))
        #expect(presentation.expenseText.contains("123.45"))
    }

    // MARK: - Comparison copy

    @Test("higher comparison includes upward arrow and percentage")
    func higherComparison() {
        let comp = comparison(
            direction: .higher,
            currentExpenseMinor: 79471,
            baselineExpenseMinor: 67263,
            percentageChange: 0.18,
            baselineStartDayKey: 20260601,
            baselineEndDayKey: 20260611
        )
        let snapshot = snapshot(heroCashFlowMinor: -79471, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 79471)], comparison: comp)
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.comparison?.arrow == "↗")
        #expect(presentation.comparison?.percentageText == "+18%")
        #expect(presentation.comparison?.headline.contains("higher") == true)
    }

    @Test("lower comparison includes downward arrow and negative percentage")
    func lowerComparison() {
        let comp = comparison(
            direction: .lower,
            currentExpenseMinor: 5000,
            baselineExpenseMinor: 10000,
            percentageChange: -0.5,
            baselineStartDayKey: 20260601,
            baselineEndDayKey: 20260611
        )
        let snapshot = snapshot(heroCashFlowMinor: -5000, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 5000)], comparison: comp)
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.comparison?.arrow == "↘")
        #expect(presentation.comparison?.percentageText == "-50%")
        #expect(presentation.comparison?.headline.contains("lower") == true)
    }

    @Test("unchanged comparison omits percentage")
    func unchangedComparison() {
        let comp = comparison(
            direction: .unchanged,
            currentExpenseMinor: 5000,
            baselineExpenseMinor: 5000,
            percentageChange: 0.0,
            baselineStartDayKey: 20260601,
            baselineEndDayKey: 20260611
        )
        let snapshot = snapshot(heroCashFlowMinor: 0, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 5000)], comparison: comp)
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.comparison?.arrow == "→")
        #expect(presentation.comparison?.percentageText == nil)
        #expect(presentation.comparison?.headline.contains("unchanged") == true)
    }

    @Test("unavailable comparison omits arrow and percentage")
    func unavailableComparison() {
        let comp = comparison(
            direction: .unavailable,
            currentExpenseMinor: 0,
            baselineExpenseMinor: 0,
            percentageChange: nil,
            baselineStartDayKey: 20260601,
            baselineEndDayKey: 20260611
        )
        let snapshot = snapshot(heroCashFlowMinor: 0, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 0)], comparison: comp)
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: [],
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.comparison?.arrow == "")
        #expect(presentation.comparison?.percentageText == nil)
        #expect(presentation.comparison?.headline.contains("unavailable") == true)
    }

    // MARK: - Compact values

    @Test("Ukrainian compact value uses тис. suffix")
    func ukrainianCompactThousands() {
        let value = TimelinePresentation.compactValueText(minorUnits: 5_280_000, locale: ukrainian)
        #expect(value.contains("тис."))
    }

    @Test("English compact value uses k suffix")
    func englishCompactThousands() {
        let value = TimelinePresentation.compactValueText(minorUnits: 5_280_000, locale: english)
        #expect(value.hasSuffix("k"))
    }

    @Test("zero compact value is safe")
    func zeroCompactValue() {
        let value = TimelinePresentation.compactValueText(minorUnits: 0, locale: english)
        #expect(value == "0")
    }

    // MARK: - Chart window

    @Test("chart window contains exactly four points ending at selected period")
    func fourPointWindow() {
        let bars = [
            bar(periodKey: 202604, incomeMinor: 100, expenseMinor: 100),
            bar(periodKey: 202605, incomeMinor: 100, expenseMinor: 100),
            bar(periodKey: 202606, incomeMinor: 100, expenseMinor: 100),
            bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 79471)
        ]
        let snapshot = snapshot(heroCashFlowMinor: -79471, bars: [bar(periodKey: 202607, incomeMinor: 0, expenseMinor: 79471)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: bars,
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.chartPoints.count == 4)
        #expect(presentation.chartPoints.last?.periodKey == 202607)
    }

    @Test("first history edge shows available points without placeholders")
    func firstHistoryEdge() {
        let bars = [
            bar(periodKey: 202601, incomeMinor: 100, expenseMinor: 100),
            bar(periodKey: 202602, incomeMinor: 100, expenseMinor: 100)
        ]
        let snapshot = snapshot(anchorMonthKey: 202602, heroCashFlowMinor: -100, bars: [bar(periodKey: 202602, incomeMinor: 100, expenseMinor: 200)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: bars,
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.chartPoints.count == 2)
        #expect(presentation.chartPoints.last?.periodKey == 202602)
    }

    @Test("older selection shifts window to end at that selection")
    func olderSelectionShiftsWindow() {
        let bars = (1...6).map { bar(periodKey: 202600 + $0, incomeMinor: 100, expenseMinor: 100) }
        let snapshot = snapshot(anchorMonthKey: 202605, heroCashFlowMinor: -100, bars: [bar(periodKey: 202605, incomeMinor: 100, expenseMinor: 200)])
        let presentation = TimelinePresentation(
            snapshot: snapshot,
            allBars: bars,
            currencyCode: .uah,
            locale: english
        )

        #expect(presentation.chartPoints.count == 4)
        #expect(presentation.chartPoints.map(\.periodKey) == [202602, 202603, 202604, 202605])
    }
}
