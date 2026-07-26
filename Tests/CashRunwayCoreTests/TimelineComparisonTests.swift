import Foundation
import Testing
@testable import CashRunwayCore

// Pure unit tests for `TimelineComparisonWindow`. The helper takes an explicit
// `now` and `calendar`, so all date math is deterministic and timezone-independent.
@Suite struct TimelineComparisonTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dayKey(_ year: Int, _ month: Int, _ day: Int) -> Int {
        year * 10_000 + month * 100 + day
    }

    // MARK: - Month: current partial

    @Test func currentPartialMonthUsesMonthToDateWindow() throws {
        // "now" is July 11; selected month is July.
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202607,
            period: .month,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.isPartial == true)
        #expect(resolved.currentStartDayKey == dayKey(2026, 7, 1))
        #expect(resolved.currentEndDayKey == dayKey(2026, 7, 11))
        #expect(resolved.baselineStartDayKey == dayKey(2026, 6, 1))
        // Baseline clamps to the same ordinal (day 11) within June.
        #expect(resolved.baselineEndDayKey == dayKey(2026, 6, 11))
    }

    @Test func completedHistoricalMonthUsesFullMonthWindows() throws {
        // "now" is July 11; selected month is the completed March.
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202603,
            period: .month,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.isPartial == false)
        #expect(resolved.currentStartDayKey == dayKey(2026, 3, 1))
        #expect(resolved.currentEndDayKey == dayKey(2026, 3, 31))
        #expect(resolved.baselineStartDayKey == dayKey(2026, 2, 1))
        #expect(resolved.baselineEndDayKey == dayKey(2026, 2, 28))
    }

    @Test func marchCurrentDayClampsBaselineToFebruaryLength() throws {
        // Current March 30: baseline February has only 28 days.
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202603,
            period: .month,
            now: date(2026, 3, 30),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.currentEndDayKey == dayKey(2026, 3, 30))
        // Baseline clamps from day 30 down to February's 28 days.
        #expect(resolved.baselineEndDayKey == dayKey(2026, 2, 28))
    }

    @Test func marchCurrentDayClampsBaselineToLeapFebruary() throws {
        // 2024 is a leap year: current March 30 baseline is February 29.
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202403,
            period: .month,
            now: date(2024, 3, 30),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.baselineEndDayKey == dayKey(2024, 2, 29))
    }

    @Test func januaryCurrentMonthBaselineIsPreviousDecember() throws {
        // Current January: baseline is previous December (year boundary).
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202601,
            period: .month,
            now: date(2026, 1, 11),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.isPartial == true)
        #expect(resolved.currentStartDayKey == dayKey(2026, 1, 1))
        #expect(resolved.currentEndDayKey == dayKey(2026, 1, 11))
        #expect(resolved.baselineStartDayKey == dayKey(2025, 12, 1))
        #expect(resolved.baselineEndDayKey == dayKey(2025, 12, 11))
    }

    @Test func completedJanuaryUsesFullPreviousDecember() throws {
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202601,
            period: .month,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.isPartial == false)
        #expect(resolved.currentEndDayKey == dayKey(2026, 1, 31))
        #expect(resolved.baselineStartDayKey == dayKey(2025, 12, 1))
        #expect(resolved.baselineEndDayKey == dayKey(2025, 12, 31))
    }

    // MARK: - Month: future

    @Test func strictlyFutureSelectedMonthReturnsNil() {
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202612,
            period: .month,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        #expect(window == nil)
    }

    // MARK: - Year

    @Test func currentYearUsesYearToDateWindow() throws {
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202607,
            period: .year,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.isPartial == true)
        #expect(resolved.currentStartDayKey == dayKey(2026, 1, 1))
        #expect(resolved.currentEndDayKey == dayKey(2026, 7, 11))
        #expect(resolved.baselineStartDayKey == dayKey(2025, 1, 1))
        #expect(resolved.baselineEndDayKey == dayKey(2025, 7, 11))
    }

    @Test func leapDayYearToDateClampsBaselineToNonLeapYear() throws {
        // Current 2024 (leap) Feb 29: previous year 2023 has no Feb 29, clamp to Feb 28.
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202402,
            period: .year,
            now: date(2024, 2, 29),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.currentEndDayKey == dayKey(2024, 2, 29))
        #expect(resolved.baselineEndDayKey == dayKey(2023, 2, 28))
    }

    @Test func completedHistoricalYearUsesFullYearWindows() throws {
        // Selected year 2024, now is 2026: completed year vs full previous year.
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202401,
            period: .year,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        let resolved = try #require(window)
        #expect(resolved.isPartial == false)
        #expect(resolved.currentStartDayKey == dayKey(2024, 1, 1))
        #expect(resolved.currentEndDayKey == dayKey(2024, 12, 31))
        #expect(resolved.baselineStartDayKey == dayKey(2023, 1, 1))
        #expect(resolved.baselineEndDayKey == dayKey(2023, 12, 31))
    }

    @Test func strictlyFutureSelectedYearReturnsNil() {
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202701,
            period: .year,
            now: date(2026, 7, 11),
            calendar: calendar
        )
        #expect(window == nil)
    }

    // MARK: - Timezone boundary

    @Test func windowRespectsProvidedCalendarTimezone() throws {
        // Verify the window uses day keys derived from the provided calendar, so a local
        // midnight boundary is captured by the calendar's own day decomposition.
        var offsetCalendar = Calendar(identifier: .gregorian)
        offsetCalendar.timeZone = TimeZone(secondsFromGMT: -18000)! // UTC-5
        let window = TimelineComparisonWindow.comparisonWindow(
            selectedMonthKey: 202607,
            period: .month,
            now: offsetCalendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 23))!,
            calendar: offsetCalendar
        )
        let resolved = try #require(window)
        // The selected month is the current month; end is the current local day (Jul 1).
        #expect(resolved.currentStartDayKey == dayKey(2026, 7, 1))
        #expect(resolved.currentEndDayKey == dayKey(2026, 7, 1))
    }
}
