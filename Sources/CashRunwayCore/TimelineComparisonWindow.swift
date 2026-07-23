import Foundation

/// Pure, calendar-driven date window for the Timeline expense comparison.
///
/// Computes the bounded current and baseline day-key ranges used by the
/// selected-period comparison. All bounds are inclusive local day keys
/// (`YYYYMMDD`), matching the `transactions.local_day_key` column and
/// `DateKeys.dayKey(for:)`.
///
/// - Current partial month/year: month-to-date / year-to-date through `now`.
/// - Completed historical period: full period vs full immediately preceding period.
/// - Strictly future selected period: returns `nil` (comparison is unavailable).
struct TimelineComparisonWindow: Equatable, Sendable {
    let currentStartDayKey: Int
    let currentEndDayKey: Int
    let baselineStartDayKey: Int
    let baselineEndDayKey: Int
    let isPartial: Bool

    /// Returns the comparison window for the selected period, or `nil` when the
    /// selected period is strictly in the future (no current actuals through `now`).
    static func comparisonWindow(
        selectedMonthKey: Int,
        period: TimelinePeriod,
        now: Date,
        calendar: Calendar
    ) -> TimelineComparisonWindow? {
        let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let nowYear = nowComponents.year ?? 0
        let nowMonth = nowComponents.month ?? 0
        let nowDay = nowComponents.day ?? 0

        switch period {
        case .month:
            return monthWindow(
                selectedMonthKey: selectedMonthKey,
                nowYear: nowYear,
                nowMonth: nowMonth,
                nowDay: nowDay,
                calendar: calendar
            )
        case .year:
            return yearWindow(
                selectedYear: selectedMonthKey / 100,
                nowYear: nowYear,
                nowMonth: nowMonth,
                nowDay: nowDay,
                calendar: calendar
            )
        }
    }

    // MARK: - Month

    private static func monthWindow(
        selectedMonthKey: Int,
        nowYear: Int,
        nowMonth: Int,
        nowDay: Int,
        calendar: Calendar
    ) -> TimelineComparisonWindow? {
        let selectedYear = selectedMonthKey / 100
        let selectedMonth = selectedMonthKey % 100
        let nowMonthKey = nowYear * 100 + nowMonth

        // Strictly future selected month: no current actuals through now.
        guard selectedMonthKey <= nowMonthKey else { return nil }

        let currentStart = dayKey(year: selectedYear, month: selectedMonth, day: 1)
        let (prevYear, prevMonth) = previousMonth(year: selectedYear, month: selectedMonth)
        let baselineStart = dayKey(year: prevYear, month: prevMonth, day: 1)

        if selectedMonthKey == nowMonthKey {
            // Current month: month-to-date through today.
            let currentEnd = dayKey(year: selectedYear, month: selectedMonth, day: nowDay)
            // Clamp the baseline end for months shorter than the current ordinal
            // (e.g. current Mar 30/31 vs February's 28/29 days).
            let baselineDays = daysInMonth(year: prevYear, month: prevMonth, calendar: calendar)
            let baselineEnd = dayKey(year: prevYear, month: prevMonth, day: min(nowDay, baselineDays))
            return TimelineComparisonWindow(
                currentStartDayKey: currentStart,
                currentEndDayKey: currentEnd,
                baselineStartDayKey: baselineStart,
                baselineEndDayKey: baselineEnd,
                isPartial: true
            )
        }

        // Completed historical month: full month vs full previous month.
        let selectedDays = daysInMonth(year: selectedYear, month: selectedMonth, calendar: calendar)
        let currentEnd = dayKey(year: selectedYear, month: selectedMonth, day: selectedDays)
        let prevDays = daysInMonth(year: prevYear, month: prevMonth, calendar: calendar)
        let baselineEnd = dayKey(year: prevYear, month: prevMonth, day: prevDays)
        return TimelineComparisonWindow(
            currentStartDayKey: currentStart,
            currentEndDayKey: currentEnd,
            baselineStartDayKey: baselineStart,
            baselineEndDayKey: baselineEnd,
            isPartial: false
        )
    }

    // MARK: - Year

    private static func yearWindow(
        selectedYear: Int,
        nowYear: Int,
        nowMonth: Int,
        nowDay: Int,
        calendar: Calendar
    ) -> TimelineComparisonWindow? {
        // Strictly future selected year.
        guard selectedYear <= nowYear else { return nil }

        let currentStart = dayKey(year: selectedYear, month: 1, day: 1)
        let baselineYear = selectedYear - 1
        let baselineStart = dayKey(year: baselineYear, month: 1, day: 1)

        if selectedYear == nowYear {
            // Current year: year-to-date through today.
            let currentEnd = dayKey(year: selectedYear, month: nowMonth, day: nowDay)
            // Clamp for months without the equivalent day (e.g. now is Feb 29 in a
            // leap year; the previous non-leap year has no Feb 29).
            let baselineEndMonthDays = daysInMonth(year: baselineYear, month: nowMonth, calendar: calendar)
            let baselineEnd = dayKey(year: baselineYear, month: nowMonth, day: min(nowDay, baselineEndMonthDays))
            return TimelineComparisonWindow(
                currentStartDayKey: currentStart,
                currentEndDayKey: currentEnd,
                baselineStartDayKey: baselineStart,
                baselineEndDayKey: baselineEnd,
                isPartial: true
            )
        }

        // Completed historical year: full year vs full previous year.
        let currentEnd = dayKey(year: selectedYear, month: 12, day: 31)
        let baselineEnd = dayKey(year: baselineYear, month: 12, day: 31)
        return TimelineComparisonWindow(
            currentStartDayKey: currentStart,
            currentEndDayKey: currentEnd,
            baselineStartDayKey: baselineStart,
            baselineEndDayKey: baselineEnd,
            isPartial: false
        )
    }

    // MARK: - Calendar helpers

    private static func dayKey(year: Int, month: Int, day: Int) -> Int {
        year * 10_000 + month * 100 + day
    }

    private static func previousMonth(year: Int, month: Int) -> (year: Int, month: Int) {
        month == 1 ? (year - 1, 12) : (year, month - 1)
    }

    private static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        guard let date = calendar.date(from: DateComponents(year: year, month: month)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }
}
